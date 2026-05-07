#!/bin/bash
# rebuild.sh
#
# Purpose: Orchestrate the full local / CI build pipeline.  This script
# exports shared environment variables and then delegates each distinct phase
# to a numbered sub-script in the scripts/ directory so that every step is
# self-contained, independently documented, and can be re-run in isolation.
#
# Sub-scripts called (in order):
#   scripts/25-docker-build.sh             – pull base image, build the
#                                            multi-stage Docker image with OCI
#                                            annotation labels
#   scripts/30-extract-provenance.sh       – create a temporary container,
#                                            copy provenance receipts and npm
#                                            manifests to the host, remove the
#                                            container
#   scripts/35-generate-slsa-provenance.sh – write the SLSA Provenance v1
#                                            container receipt
#   scripts/40-generate-sbom.sh            – run Syft against the runtime
#                                            image, normalise PURL encoding,
#                                            wrap in an in-toto envelope
#   scripts/45-generate-receipts.sh        – write the test-result receipt
set -euo pipefail

# Resolve the directory that contains this script so sub-scripts can be
# found regardless of the working directory from which rebuild.sh is called.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Make all sub-scripts executable (idempotent; safe to run on every build).
chmod +x "${SCRIPT_DIR}/scripts/"*.sh

# ---------------------------------------------------------------------------
# Shared build metadata – exported so every sub-script can read them.
# ---------------------------------------------------------------------------
export IMAGE_NAME="${IMAGE_NAME:-minimal-ink-cli}"
# Attempt to get the short git hash; fall back to v1.0.0 if not in a git repo.
export VERSION="${VERSION:-$(git rev-parse --short HEAD 2>/dev/null || echo "v1.0.0")}"
export BUILD_DATE="${BUILD_DATE:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
export BASE_IMAGE="${BASE_IMAGE:-debian:trixie-slim}"
export OUTPUT_DIR="${OUTPUT_DIR:-${SCRIPT_DIR}/build-provenance}"

echo "==> [rebuild.sh] Build: ${IMAGE_NAME}:${VERSION}  base: ${BASE_IMAGE}"

# Step 1: Pull the Debian base image and build the multi-stage Docker image.
"${SCRIPT_DIR}/scripts/25-docker-build.sh"

# Step 2: Extract provenance receipts and npm manifests from the built image.
"${SCRIPT_DIR}/scripts/30-extract-provenance.sh"

# Step 3: Generate the SLSA Provenance receipt for the container image.
"${SCRIPT_DIR}/scripts/35-generate-slsa-provenance.sh"

# Step 4: Generate the SPDX SBOM for the runtime image using Syft.
"${SCRIPT_DIR}/scripts/40-generate-sbom.sh"

# Step 5: Generate the remaining receipts (test results).
"${SCRIPT_DIR}/scripts/45-generate-receipts.sh"

echo "==> [rebuild.sh] Build complete."
echo "==> Provenance receipts saved to ${OUTPUT_DIR}/"
