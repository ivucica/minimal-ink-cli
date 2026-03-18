# =============================================================================
# STAGE 1 – builder
# =============================================================================
# Use a pinned Debian Trixie (13) slim image as the build base.  Pinning to a
# specific release tag (rather than "stable") ensures this layer is reusable
# across projects and won't silently upgrade to Debian 14 when it becomes
# stable.  All build-time tools (curl, xz-utils, Node.js, npm, TypeScript,
# @types/*) live only in this stage and are never copied to the runtime image.
FROM debian:trixie-slim AS builder

# Copy the setup entry-point and all numbered build scripts.
COPY setup.sh /build/setup.sh
COPY scripts/ /build/scripts/

# scripts/00-install-system-deps.sh – update apt, install build-time packages
#   (curl, xz-utils), write /etc/provenance/deb-receipt.json.
# scripts/05-install-nodejs.sh      – download and SHA-256-verify the official
#   Node.js tarball, extract to /usr/local, upgrade npm, write
#   /etc/provenance/nodejs-receipt.json.
# scripts/10-setup-app.sh           – create /app, npm init, install runtime
#   AND dev npm dependencies, npm audit fix, write
#   /etc/provenance/npm-receipt.json.
# scripts/15-configure-typescript.sh – write /app/tsconfig.json.
RUN chmod +x /build/setup.sh /build/scripts/*.sh && /build/setup.sh

# Set the working directory before copying source so Docker cache is
# invalidated only when source files change (not when deps change).
WORKDIR /app

# Copy the application source into the builder.
COPY app.tsx ./src/app.tsx

# scripts/20-build-app.sh – compile TypeScript/JSX in src/ into JavaScript
#   in dist/ using the tsc compiler.  A successful tsc run also type-checks
#   the source, acting as a lightweight quality gate.
RUN /build/scripts/20-build-app.sh

# Remove devDependencies from node_modules so only runtime packages are
# carried forward into the runtime image.
RUN npm prune --production

# =============================================================================
# STAGE 2 – runtime
# =============================================================================
# Start from the same pinned Debian Trixie slim image for a reproducible,
# minimal runtime layer.  Only the node binary (copied from the builder stage)
# and libstdc++6 (a small shared library required by the node binary) are
# added on top of the base image.  No npm, no curl, no build tools.
FROM debian:trixie-slim AS runtime

LABEL org.opencontainers.image.description="A minimal CLI example using Ink and React for building interactive terminal UIs"

# Install the only Debian package needed to run the node binary on a slim
# image: libstdc++6 (the Node.js binary links against it dynamically).
# Run full-upgrade first so the base layer receives all available security
# patches before we add our one additional package.
RUN apt-get update \
 && apt-get full-upgrade -y --no-install-recommends \
 && apt-get install -y --no-install-recommends libstdc++6 \
 && rm -rf /var/lib/apt/lists/*

# Copy only the node binary – npm, npx and the rest of the Node.js toolchain
# are not needed at runtime and are intentionally excluded.
COPY --from=builder /usr/local/bin/node /usr/local/bin/node

# Copy the compiled application, pruned runtime node_modules, and package.json
# (needed for Node.js ESM module-type resolution).
COPY --from=builder /app/dist          /app/dist
COPY --from=builder /app/node_modules  /app/node_modules
COPY --from=builder /app/package.json  /app/package.json

# Copy the provenance receipts written during the build stage so they are
# available in the runtime image and can be extracted by rebuild.sh for the
# host-side provenance artefacts.
COPY --from=builder /etc/provenance /etc/provenance

WORKDIR /app

# Set the default command to run the compiled CLI tool.
CMD ["node", "dist/app.js"]
