#!/bin/bash
# 10-setup-app.sh
#
# Purpose: Bootstrap the application directory, initialise a fresh package.json,
# install all runtime AND development npm dependencies, run `npm audit fix` to
# patch vulnerable transitive packages, and then record every resolved package
# (with its integrity hash) in an in-toto / SLSA provenance receipt.
#
# NOTE: dev dependencies (typescript, @types/*) are installed here so that the
# TypeScript compilation step (scripts/20-build-app.sh) can run.  Before the
# final runtime image is assembled the Dockerfile prunes them with
# `npm prune --production`, so they never reach the runtime layer.
#
# Required environment variables: (none – all have safe defaults)
# Optional environment variables:
#   APP_DIR          – absolute path where the application will live
#                      default: /app
#   PROVENANCE_DIR   – directory in which to write npm-receipt.json
#                      default: /etc/provenance
#   NPM_RUNTIME_DEPS – space-separated runtime npm packages to install
#                      default: "ink react ink-text-input"
#   NPM_DEV_DEPS     – space-separated dev npm packages to install
#                      default: "typescript @types/react @types/node"
set -euo pipefail

APP_DIR="${APP_DIR:-/app}"
PROVENANCE_DIR="${PROVENANCE_DIR:-/etc/provenance}"
NPM_RUNTIME_DEPS="${NPM_RUNTIME_DEPS:-ink react ink-text-input}"
NPM_DEV_DEPS="${NPM_DEV_DEPS:-typescript @types/react @types/node}"

echo "==> [10] Creating application directory structure at ${APP_DIR}..."
mkdir -p "${APP_DIR}/src"
cd "${APP_DIR}"

echo "==> [10] Initialising package.json..."
npm init -y
npm pkg set type="module"

echo "==> [10] Installing runtime dependencies: ${NPM_RUNTIME_DEPS}..."
# Remove any stale lockfile that could pin old, vulnerable package versions.
rm -f package-lock.json
# shellcheck disable=SC2086  # intentional word-splitting on dep lists
npm install ${NPM_RUNTIME_DEPS}

echo "==> [10] Installing development dependencies: ${NPM_DEV_DEPS}..."
# shellcheck disable=SC2086
npm install --save-dev ${NPM_DEV_DEPS}

echo "==> [10] Patching vulnerable transitive dependencies..."
# Fix any remaining vulnerabilities within the semver ranges allowed by direct
# dependencies.
npm audit fix || true

echo "==> [10] Generating npm provenance receipt..."
mkdir -p "${PROVENANCE_DIR}"
node -e '
const fs = require("fs");
const path = require("path");
const lock = JSON.parse(fs.readFileSync("package-lock.json"));
const deps = [];
for (const [pkgPath, pkg] of Object.entries(lock.packages || {})) {
  if (pkgPath === "") continue;
  if (pkg.resolved && pkg.integrity) {
    const parts = pkg.integrity.split("-");
    const algo = parts[0] === "sha512" ? "sha512" : "sha256";
    const hash = Buffer.from(parts[1], "base64").toString("hex");
    const name = pkgPath.replace(/.*node_modules\//, "");
    deps.push({
      uri: `pkg:npm/${name}@${pkg.version}`,
      digest: { [algo]: hash }
    });
  }
}
const statement = {
  _type: "https://in-toto.io/Statement/v1",
  subject: [{ name: "app-node-modules", digest: { sha256: "0000000000000000000000000000000000000000000000000000000000000000" } }],
  predicateType: "https://slsa.dev/provenance/v1",
  predicate: { resolvedDependencies: deps }
};
fs.writeFileSync(path.join(process.env.PROVENANCE_DIR, "npm-receipt.json"), JSON.stringify(statement, null, 2));
'

echo "==> [10] npm setup complete; receipt written to ${PROVENANCE_DIR}/npm-receipt.json"
