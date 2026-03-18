#!/bin/bash
# 35-generate-slsa-provenance.sh
#
# Purpose: Write the SLSA Provenance v1 (in-toto Statement) predicate for the
# container image.  This receipt captures HOW the image was built: which base
# image was used (with its digest), when the build ran, and the invocation ID
# so the build can be traced back to a specific workflow run.
#
# The output (container-receipt.json) is stored in OUTPUT_DIR alongside the
# other provenance receipts and later uploaded to GitHub as an attestation
# artefact.
#
# Required environment variables:
#   IMAGE_NAME – local name of the Docker image
#   VERSION    – version tag
#   BUILD_DATE – ISO-8601 UTC timestamp of the build
#   BASE_IMAGE – Debian image used as the base for this container
# Optional environment variables:
#   OUTPUT_DIR – directory in which to write container-receipt.json
#                default: ./build-provenance
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:?IMAGE_NAME must be set}"
VERSION="${VERSION:?VERSION must be set}"
BUILD_DATE="${BUILD_DATE:?BUILD_DATE must be set}"
BASE_IMAGE="${BASE_IMAGE:?BASE_IMAGE must be set}"
OUTPUT_DIR="${OUTPUT_DIR:-./build-provenance}"

# Derive the image digest from the locally built image.
IMAGE_DIGEST_RAW=$(docker inspect --format='{{.Id}}' "${IMAGE_NAME}:${VERSION}")
IMAGE_DIGEST="${IMAGE_DIGEST_RAW#sha256:}"

# Derive the base image digest from what docker pulled.
BASE_DIGEST_RAW=$(docker inspect --format='{{index .RepoDigests 0}}' "${BASE_IMAGE}" 2>/dev/null || true)
if [ -z "${BASE_DIGEST_RAW}" ]; then
  BASE_DIGEST_RAW=$(docker inspect --format='{{.Id}}' "${BASE_IMAGE}")
fi
BASE_DIGEST=$(echo "${BASE_DIGEST_RAW}" | grep -o 'sha256:.*')

echo "==> [35] Writing SLSA provenance receipt for ${IMAGE_NAME}:${VERSION}..."
mkdir -p "${OUTPUT_DIR}"

cat > "${OUTPUT_DIR}/container-receipt.json" << EOF
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

echo "==> [35] SLSA provenance written to ${OUTPUT_DIR}/container-receipt.json"
