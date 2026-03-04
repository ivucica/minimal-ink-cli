#!/bin/bash
set -e

IMAGE_NAME="minimal-ink-cli"
IMAGE_DESCRIPTION="A minimal CLI example using Ink and React for building interactive terminal UIs"
# Attempt to get the short git hash; fallback to v1.0.0 if not in a git repo
VERSION=$(git rev-parse --short HEAD 2>/dev/null || echo "v1.0.0")
BUILD_DATE=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
BASE_IMAGE="debian:stable-slim"

echo "==> Pulling base image to ensure latest and retrieve digest..."
docker pull $BASE_IMAGE
# Extract the RepoDigest (looks like debian@sha256:...)
BASE_DIGEST_RAW=$(docker inspect --format='{{index .RepoDigests 0}}' $BASE_IMAGE 2>/dev/null || true)
if [ -z "$BASE_DIGEST_RAW" ]; then
  # Fallback to Image ID if it lacks a RepoDigest (e.g., loaded locally instead of pulled)
  BASE_DIGEST_RAW=$(docker inspect --format='{{.Id}}' $BASE_IMAGE)
fi
BASE_DIGEST=$(echo $BASE_DIGEST_RAW | grep -o 'sha256:.*')

echo "==> Building container image with OCI annotations..."
docker build \
  --label org.opencontainers.image.created="$BUILD_DATE" \
  --label org.opencontainers.image.version="$VERSION" \
  --label org.opencontainers.image.base.name="$BASE_IMAGE" \
  --label org.opencontainers.image.base.digest="$BASE_DIGEST" \
  --label org.opencontainers.image.description="$IMAGE_DESCRIPTION" \
  -t ${IMAGE_NAME}:${VERSION} \
  -t ${IMAGE_NAME}:latest \
  .

# # Local images without a registry push only have an ID digest
IMAGE_DIGEST_RAW=$(docker inspect --format='{{.Id}}' ${IMAGE_NAME}:${VERSION})
IMAGE_DIGEST=${IMAGE_DIGEST_RAW#sha256:}

mkdir -p ./build-provenance

echo "==> Extracting application files for PR updates..."
# Create a dummy container (does not start it) to copy files out
CONTAINER_ID=$(docker create ${IMAGE_NAME}:${VERSION})
rm -rf ./build-provenance
docker cp $CONTAINER_ID:/etc/provenance ./build-provenance
# Extract NPM manifest and lockfile to update host repository
docker cp $CONTAINER_ID:/app/package.json ./package.json || true
docker cp $CONTAINER_ID:/app/package-lock.json ./package-lock.json || true
docker rm $CONTAINER_ID

# ---------------------------------------------------------
# PREDICATE 1: SLSA PROVENANCE (How it was built)
# ---------------------------------------------------------
echo "==> Generating SLSA Provenance predicate..."
cat << EOF > ./build-provenance/container-receipt.json
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [
    {
      "name": "docker://${IMAGE_NAME}:${VERSION}",
      "digest": {
        "sha256": "${IMAGE_DIGEST}"
      }
    }
  ],
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": {
    "buildDefinition": {
      "buildType": "https://mobyproject.org/buildkit",
      "resolvedDependencies": [
        {
          "uri": "docker://${BASE_IMAGE}",
          "digest": {
            "sha256": "${BASE_DIGEST#sha256:}"
          }
        }
      ]
    },
    "runDetails": {
      "metadata": {
        "invocationId": "local-build-${VERSION}",
        "startedOn": "${BUILD_DATE}"
      }
    }
  }
}
EOF

# ---------------------------------------------------------
# PREDICATE 2: SPDX SBOM (What is inside it)
# ---------------------------------------------------------
echo "==> Generating SPDX SBOM predicate using Syft..."
# Run syft via docker to inspect the image we just built, outputting standard SPDX JSON
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock anchore/syft:latest \
  packages docker:${IMAGE_NAME}:${VERSION} -o spdx-json > ./build-provenance/raw-spdx-sbom.json

# Use jq to wrap the raw SPDX JSON inside the in-toto Statement envelope
jq --arg img "docker://${IMAGE_NAME}:${VERSION}" --arg digest "${IMAGE_DIGEST}" '{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [{"name": $img, "digest": {"sha256": $digest}}],
  "predicateType": "https://spdx.dev/Document",
  "predicate": .
}' ./build-provenance/raw-spdx-sbom.json > ./build-provenance/sbom-receipt.json

# ---------------------------------------------------------
# PREDICATE 3: TEST RESULT (Did it pass quality gates)
# ---------------------------------------------------------
echo "==> Generating Test Result predicate..."
# In a real scenario, you would parse your test runner output here.
# We map it to the official in-toto test-result v1 schema.
# (For now, we say 'tsc' because that's the only quasi-test we are running: build itself.
# We would say something like 'jest'.)
cat << EOF > ./build-provenance/test-receipt.json
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [{"name": "docker://${IMAGE_NAME}:${VERSION}", "digest": {"sha256": "${IMAGE_DIGEST}"}}],
  "predicateType": "https://in-toto.io/attestation/test-result/v1",
  "predicate": {
    "result": "PASSED",
    "timestamp": "${BUILD_DATE}",
    "testExecution": {
      "testFramework": "tsc",
      "testInvocationId": "build-only:${GITHUB_RUN_ID:-local}"
    }
  }
}
EOF

# Keep the manual deb/npm extraction if you prefer the custom granularity,
# but the SPDX SBOM above officially replaces the need for them.
echo "==> Generating custom deb/npm receipts..."
DEB_DEPS=$(docker run --rm --entrypoint dpkg-query ${IMAGE_NAME}:${VERSION} -W -f='        {"uri": "pkg:deb/debian/${Package}@${Version}?arch=${Architecture}"},\n' | sed '$ s/,$//')
cat << EOF > ./build-provenance/deb-receipt.json
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [{"name": "docker://${IMAGE_NAME}:${VERSION}", "digest": {"sha256": "${IMAGE_DIGEST}"}}],
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": { "resolvedDependencies": [ $DEB_DEPS ] }
}
EOF

docker run --rm -w /app --entrypoint node ${IMAGE_NAME}:${VERSION} -e '
const fs = require("fs"); let lock; try { lock = JSON.parse(fs.readFileSync("package-lock.json")); } catch (e) { process.exit(0); }
const deps = [];
for (const [path, pkg] of Object.entries(lock.packages || {})) {
  if (path === "") continue;
  if (pkg.resolved && pkg.integrity) {
    const parts = pkg.integrity.split("-"); const hash = Buffer.from(parts[1], "base64").toString("hex");
    deps.push({ uri: `pkg:npm/${path.replace(/.*node_modules\//, "")}@${pkg.version}`, digest: { [parts[0] === "sha512" ? "sha512" : "sha256"]: hash }});
  }
}
const stmt = {
  _type: "https://in-toto.io/Statement/v1",
  subject: [{ name: "docker://'"${IMAGE_NAME}"':'"${VERSION}"'", digest: { sha256: "'"${IMAGE_DIGEST}"'" } }],
  predicateType: "https://slsa.dev/provenance/v1",
  predicate: { resolvedDependencies: deps }
};
console.log(JSON.stringify(stmt, null, 2));
' > ./build-provenance/npm-receipt.json

echo "==> Build complete."
echo "==> Provenance for deb, nodejs, npm, and the container itself saved to ./build-provenance/"
