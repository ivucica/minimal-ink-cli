#!/bin/bash
# setup.sh
#
# Purpose: Entry-point script that the Dockerfile builder stage executes to
# prepare the build environment.  It delegates each distinct concern to a
# numbered sub-script in the scripts/ directory so that every step is
# self-contained, independently documented, and can be re-run in isolation.
#
# Sub-scripts called (in order):
#   scripts/00-install-system-deps.sh  – update apt, install build-time packages,
#                                        write deb-receipt.json
#   scripts/05-install-nodejs.sh       – download and verify Node.js tarball,
#                                        install to /usr/local, upgrade npm,
#                                        write nodejs-receipt.json
#   scripts/10-setup-app.sh            – create /app, npm init, install runtime
#                                        and dev npm dependencies, npm audit fix,
#                                        write npm-receipt.json
#   scripts/15-configure-typescript.sh – write tsconfig.json
#
# The compilation step (scripts/20-build-app.sh) is intentionally NOT called
# here; the Dockerfile invokes it in a separate RUN layer so that source-code
# changes do not invalidate the expensive npm install layer above.
set -euo pipefail

# Resolve the directory that contains this script so sub-scripts can be
# found regardless of the working directory from which setup.sh is called.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "==> [setup.sh] Starting build environment setup..."

# Install build-time system dependencies and record deb provenance.
"${SCRIPT_DIR}/scripts/00-install-system-deps.sh"

# Download, verify, and install Node.js; record nodejs provenance.
"${SCRIPT_DIR}/scripts/05-install-nodejs.sh"

# Bootstrap the application directory and install npm dependencies.
"${SCRIPT_DIR}/scripts/10-setup-app.sh"

# Write tsconfig.json for the TypeScript compiler.
"${SCRIPT_DIR}/scripts/15-configure-typescript.sh"

echo "==> [setup.sh] Build environment setup complete."
