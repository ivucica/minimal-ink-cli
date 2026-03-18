#!/bin/bash
# 45-generate-receipts.sh
#
# Purpose: Generate the remaining provenance receipts that are produced on the
# HOST after the Docker image has been built and the build-stage receipts have
# been extracted:
#
#   test-receipt.json – records the outcome of the TypeScript compilation
#     quality gate (tsc) that ran during the Docker build.  In a project with
#     a proper test suite this would capture the test runner result instead.
#
# The deb-receipt.json, nodejs-receipt.json, and npm-receipt.json were already
# produced inside the builder stage and extracted by 30-extract-provenance.sh,
# so this script does not regenerate them.
#
# Required environment variables:
#   IMAGE_NAME – local name of the Docker image
#   VERSION    – version tag
#   BUILD_DATE – ISO-8601 UTC timestamp of the build
# Optional environment variables:
#   OUTPUT_DIR – directory in which to write test-receipt.json
#                default: ./build-provenance
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:?IMAGE_NAME must be set}"
VERSION="${VERSION:?VERSION must be set}"
BUILD_DATE="${BUILD_DATE:?BUILD_DATE must be set}"
OUTPUT_DIR="${OUTPUT_DIR:-./build-provenance}"

IMAGE_DIGEST_RAW=$(docker inspect --format='{{.Id}}' "${IMAGE_NAME}:${VERSION}")
IMAGE_DIGEST="${IMAGE_DIGEST_RAW#sha256:}"

echo "==> [45] Writing test-receipt.json..."
mkdir -p "${OUTPUT_DIR}"

# In a real project this would parse test-runner output (jest, vitest, etc.).
# Currently TypeScript compilation (tsc) is the only quality gate; a successful
# Docker build implies it passed.
cat > "${OUTPUT_DIR}/test-receipt.json" << EOF
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

echo "==> [45] test-receipt.json written to ${OUTPUT_DIR}/test-receipt.json"
