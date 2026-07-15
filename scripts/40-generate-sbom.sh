#!/bin/bash
# 40-generate-sbom.sh
#
# Purpose: Produce a full Software Bill of Materials (SBOM) for the RUNTIME
# container image using Syft in SPDX-JSON format.  Because this scans only the
# runtime image (not the builder stage), every package in the SBOM is a
# RUNTIME dependency; build-only tools (curl, xz-utils, gcc, typescript, etc.)
# are naturally excluded.  This is the SPDX equivalent of annotating packages
# as runtime vs build-time.
#
# After generation the script:
#   1. Normalises PURL version encoding (fix-purl-encoding.py) so that the
#      spdx-dependency-submission-action accepts all packages.
#   2. Wraps the raw SPDX JSON inside an in-toto Statement envelope and saves
#      it as sbom-receipt.json for GitHub Dependency Graph submission.
#
# Required environment variables:
#   IMAGE_NAME – local name of the Docker image to scan
#   VERSION    – version tag
# Optional environment variables:
#   OUTPUT_DIR – directory in which to write raw-spdx-sbom.json and
#                sbom-receipt.json
#                default: ./build-provenance
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:?IMAGE_NAME must be set}"
VERSION="${VERSION:?VERSION must be set}"
OUTPUT_DIR="${OUTPUT_DIR:-./build-provenance}"

IMAGE_DIGEST_RAW=$(docker inspect --format='{{.Id}}' "${IMAGE_NAME}:${VERSION}")
IMAGE_DIGEST="${IMAGE_DIGEST_RAW#sha256:}"

echo "==> [40] Generating SPDX SBOM for runtime image ${IMAGE_NAME}:${VERSION}..."
mkdir -p "${OUTPUT_DIR}"

# Run syft via docker to inspect the image we just built, outputting standard
# SPDX JSON.  Mounting the Docker socket lets Syft read the local image without
# pushing it to a registry first.
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock anchore/syft:latest \
  packages "docker:${IMAGE_NAME}:${VERSION}" -o spdx-json \
  > "${OUTPUT_DIR}/raw-spdx-sbom.json"

echo "==> [40] Normalising PURL version encoding in SBOM..."
# fix-purl-encoding.py lives at the root of the repository.  It must be run
# from the repository root so that the relative path resolves correctly.
# It decodes %3A (':') and %2B ('+') in PURL version segments so that the
# spdx-dependency-submission-action validator accepts all packages; also strips
# Debian epoch and revision from CPE version fields.
python3 fix-purl-encoding.py "${OUTPUT_DIR}/raw-spdx-sbom.json"

echo "==> [40] Wrapping SBOM in in-toto Statement envelope..."
# Use jq to embed the raw SPDX document inside the standard in-toto Statement
# structure for GitHub Dependency Graph and attestation upload.
jq --arg img "docker://${IMAGE_NAME}:${VERSION}" --arg digest "${IMAGE_DIGEST}" '{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [{"name": $img, "digest": {"sha256": $digest}}],
  "predicateType": "https://spdx.dev/Document",
  "predicate": .
}' "${OUTPUT_DIR}/raw-spdx-sbom.json" > "${OUTPUT_DIR}/sbom-receipt.json"

echo "==> [40] SBOM written to ${OUTPUT_DIR}/raw-spdx-sbom.json and ${OUTPUT_DIR}/sbom-receipt.json"
