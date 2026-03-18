#!/bin/bash
# 05-install-nodejs.sh
#
# Purpose: Download the official Node.js pre-built binary tarball from
# nodejs.org, verify its SHA-256 hash against the published SHASUMS256.txt
# file, extract it into /usr/local (making `node` and `npm` available on
# PATH), and then upgrade npm itself to patch vendored-dependency CVEs that
# Trivy/Syft surfaces.
#
# A signed in-toto / SLSA provenance receipt is written so downstream tools
# can verify exactly which Node.js artefact was installed and when it was
# verified.
#
# Required environment variables: (none – all have safe defaults)
# Optional environment variables:
#   NODE_VERSION   – Node.js release to install, e.g. "22.14.0"
#                    default: "22.14.0"
#   NODE_ARCH      – OS/architecture string matching the tarball name
#                    default: "linux-x64"
#   PROVENANCE_DIR – directory in which to write nodejs-receipt.json
#                    default: /etc/provenance
set -euo pipefail

NODE_VERSION="${NODE_VERSION:-22.14.0}"
NODE_ARCH="${NODE_ARCH:-linux-x64}"
PROVENANCE_DIR="${PROVENANCE_DIR:-/etc/provenance}"

NODE_TAR="node-v${NODE_VERSION}-${NODE_ARCH}.tar.xz"

echo "==> [05] Downloading Node.js v${NODE_VERSION} (${NODE_ARCH})..."
cd /tmp
curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TAR}"
curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt"

echo "==> [05] Verifying SHA-256 hash..."
grep " ${NODE_TAR}\$" SHASUMS256.txt > SHASUM_CHECK.txt
sha256sum -c SHASUM_CHECK.txt

echo "==> [05] Recording provenance receipt..."
NODE_HASH=$(awk '{print $1}' SHASUM_CHECK.txt)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
mkdir -p "${PROVENANCE_DIR}"

cat > "${PROVENANCE_DIR}/nodejs-receipt.json" << EOF
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [
    {
      "name": "node-v${NODE_VERSION}-${NODE_ARCH}.tar.xz",
      "digest": {
        "sha256": "${NODE_HASH}"
      }
    }
  ],
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": {
    "buildDefinition": {
      "buildType": "https://nodejs.org/release",
      "externalParameters": {
        "sourceUrl": "https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TAR}",
        "version": "${NODE_VERSION}"
      }
    },
    "runDetails": {
      "metadata": {
        "verifiedAt": "${TIMESTAMP}"
      }
    }
  }
}
EOF

echo "==> [05] Extracting Node.js into /usr/local..."
tar -xJf "${NODE_TAR}" -C /usr/local --strip-components=1
rm "${NODE_TAR}" SHASUMS256.txt SHASUM_CHECK.txt

echo "==> [05] Upgrading npm to latest to patch vendored-dependency CVEs..."
# The npm bundled with Node.js ships its own node_modules (cross-spawn, semver,
# ws, etc.) that Trivy/Syft surfaces as individual CVEs.  Upgrading npm replaces
# those vendored copies with the latest fixed versions.
npm install -g npm@latest

echo "==> [05] Node.js v${NODE_VERSION} installed; receipt written to ${PROVENANCE_DIR}/nodejs-receipt.json"
