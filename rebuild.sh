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

echo "==> Extracting provenance files from container..."
# Create a dummy container (does not start it) to copy files out
CONTAINER_ID=$(docker create ${IMAGE_NAME}:${VERSION})
rm -rf ./build-provenance
docker cp $CONTAINER_ID:/etc/provenance ./build-provenance
docker rm $CONTAINER_ID

echo "==> Generating final container provenance statement..."
# Local images without a registry push only have an ID digest
IMAGE_DIGEST_RAW=$(docker inspect --format='{{.Id}}' ${IMAGE_NAME}:${VERSION})
IMAGE_DIGEST=${IMAGE_DIGEST_RAW#sha256:}

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

echo "==> Build complete."
echo "==> Provenance for deb, nodejs, npm, and the container itself saved to ./build-provenance/"
