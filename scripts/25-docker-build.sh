#!/bin/bash
# 25-docker-build.sh
#
# Purpose: Pull the Debian base image (to ensure it is current and to capture
# its immutable digest for provenance), then build the Docker image with a full
# set of OCI image-spec annotation labels.  This script produces the tagged
# image that all subsequent scripts operate on.
#
# The base-image digest is captured HERE because docker pull guarantees we have
# the latest manifest, whereas `docker inspect` after `docker build` may reflect
# a cached layer that pre-dates the current base push.
#
# Required environment variables: (none – all have safe defaults)
# Optional environment variables:
#   IMAGE_NAME        – local name to tag the built image
#                       default: "minimal-ink-cli"
#   VERSION           – version tag (e.g. a git short-SHA)
#                       default: short git HEAD SHA, or "v1.0.0" if not in a repo
#   BUILD_DATE        – ISO-8601 timestamp to embed in OCI labels
#                       default: current UTC time
#   BASE_IMAGE        – Debian image used for both builder and runtime stages
#                       default: "debian:trixie-slim"
#   IMAGE_DESCRIPTION – human-readable description for the OCI label
#                       default: the standard project description
set -euo pipefail

IMAGE_NAME="${IMAGE_NAME:-minimal-ink-cli}"
VERSION="${VERSION:-$(git rev-parse --short HEAD 2>/dev/null || echo "v1.0.0")}"
BUILD_DATE="${BUILD_DATE:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"
BASE_IMAGE="${BASE_IMAGE:-debian:trixie-slim}"
IMAGE_DESCRIPTION="${IMAGE_DESCRIPTION:-A minimal CLI example using Ink and React for building interactive terminal UIs}"

echo "==> [25] Pulling base image ${BASE_IMAGE} to get latest digest..."
docker pull "${BASE_IMAGE}"

# Extract the RepoDigest (looks like debian@sha256:...).  Fall back to the
# image ID if the image was loaded locally instead of pulled.
BASE_DIGEST_RAW=$(docker inspect --format='{{index .RepoDigests 0}}' "${BASE_IMAGE}" 2>/dev/null || true)
if [ -z "${BASE_DIGEST_RAW}" ]; then
  BASE_DIGEST_RAW=$(docker inspect --format='{{.Id}}' "${BASE_IMAGE}")
fi
BASE_DIGEST=$(echo "${BASE_DIGEST_RAW}" | grep -o 'sha256:.*')

echo "==> [25] Building Docker image ${IMAGE_NAME}:${VERSION} with OCI labels..."
docker build \
  --label org.opencontainers.image.created="${BUILD_DATE}" \
  --label org.opencontainers.image.version="${VERSION}" \
  --label org.opencontainers.image.base.name="${BASE_IMAGE}" \
  --label org.opencontainers.image.base.digest="${BASE_DIGEST}" \
  --label org.opencontainers.image.description="${IMAGE_DESCRIPTION}" \
  -t "${IMAGE_NAME}:${VERSION}" \
  -t "${IMAGE_NAME}:latest" \
  .

echo "==> [25] Image ${IMAGE_NAME}:${VERSION} built successfully."
echo "    Base image digest: ${BASE_DIGEST}"
