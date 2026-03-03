#!/bin/bash
set -e

IMAGE_NAME="minimal-ink-cli"
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
  -t ${IMAGE_NAME}:${VERSION} \
  -t ${IMAGE_NAME}:latest \
  .

echo "==> Generating final container provenance statement..."
# Local images without a registry push only have an ID digest
IMAGE_DIGEST_RAW=$(docker inspect --format='{{.Id}}' ${IMAGE_NAME}:${VERSION})
IMAGE_DIGEST=${IMAGE_DIGEST_RAW#sha256:}

mkdir -p ./build-provenance

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

echo "==> Generating deb packages provenance receipt from built image..."
DEB_DEPS=$(docker run --rm --entrypoint dpkg-query ${IMAGE_NAME}:${VERSION} -W -f='        {"uri": "pkg:deb/debian/${Package}@${Version}?arch=${Architecture}"},\n' | sed '$ s/,$//')

cat << EOF > ./build-provenance/deb-receipt.json
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [{"name": "docker://${IMAGE_NAME}:${VERSION}", "digest": {"sha256": "${IMAGE_DIGEST}"}}],
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": {
    "resolvedDependencies": [
$DEB_DEPS
    ]
  }
}
EOF

echo "==> Generating npm packages provenance receipt from built image..."
docker run --rm -w /app --entrypoint node ${IMAGE_NAME}:${VERSION} -e '
const fs = require("fs");
let lock;
try {
  lock = JSON.parse(fs.readFileSync("package-lock.json"));
} catch (e) {
  console.error("No package-lock.json found.");
  process.exit(0);
}
const deps = [];
for (const [path, pkg] of Object.entries(lock.packages || {})) {
  if (path === "") continue;
  if (pkg.resolved && pkg.integrity) {
    const parts = pkg.integrity.split("-");
    const algo = parts[0] === "sha512" ? "sha512" : "sha256";
    const hash = Buffer.from(parts[1], "base64").toString("hex");
    const name = path.replace(/.*node_modules\//, "");
    deps.push({
      uri: `pkg:npm/${name}@${pkg.version}`,
      digest: { [algo]: hash }
    });
  }
}
const statement = {
  _type: "https://in-toto.io/Statement/v1",
  subject: [{ name: "docker://'"${IMAGE_NAME}"':'"${VERSION}"'", digest: { sha256: "'"${IMAGE_DIGEST}"'" } }],
  predicateType: "https://slsa.dev/provenance/v1",
  predicate: { resolvedDependencies: deps }
};
console.log(JSON.stringify(statement, null, 2));
' > ./build-provenance/npm-receipt.json

echo "==> Build complete."
echo "==> Provenance for deb, npm, and the container itself saved to ./build-provenance/"
