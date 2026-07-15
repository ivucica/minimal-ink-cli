#!/bin/bash
# 30-extract-provenance.sh
#
# Purpose: Create a temporary (non-running) container from the built image,
# copy out the provenance receipts that were generated during the Docker build
# stage (deb-receipt.json, nodejs-receipt.json, npm-receipt.json), and also
# copy out the resolved package.json and package-lock.json so that the host
# repository can be updated via a PR.  The temporary container is removed
# immediately after extraction.
#
# The provenance files extracted here were written to /etc/provenance/ inside
# the builder stage and then COPY'd into the runtime image.  They reflect the
# exact packages and versions installed during the build.
#
# Required environment variables:
#   IMAGE_NAME – local name of the Docker image to inspect
#   VERSION    – version tag of the image
# Optional environment variables:
#   OUTPUT_DIR – host directory to extract provenance files into
#                default: ./build-provenance
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:?IMAGE_NAME must be set}"
VERSION="${VERSION:?VERSION must be set}"
OUTPUT_DIR="${OUTPUT_DIR:-./build-provenance}"

echo "==> [30] Extracting provenance and package manifests from ${IMAGE_NAME}:${VERSION}..."

# Create a dummy (non-running) container solely to copy files out of it.
CONTAINER_ID=$(docker create "${IMAGE_NAME}:${VERSION}")

# Remove any stale output directory before extracting fresh files.
rm -rf "${OUTPUT_DIR}"

# Copy the provenance receipts written during the Docker build stage.
docker cp "${CONTAINER_ID}:/etc/provenance" "${OUTPUT_DIR}"

# Copy the resolved npm manifests so the host repo can be updated.
docker cp "${CONTAINER_ID}:/app/package.json" ./package.json || true
docker cp "${CONTAINER_ID}:/app/package-lock.json" ./package-lock.json || true

docker rm "${CONTAINER_ID}"

echo "==> [30] Provenance extracted to ${OUTPUT_DIR}/"
echo "    Files: $(ls "${OUTPUT_DIR}/")"
