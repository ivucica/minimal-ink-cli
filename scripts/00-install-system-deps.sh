#!/bin/bash
# 00-install-system-deps.sh
#
# Purpose: Update the Debian package index, apply all available upgrades, and
# install the minimal set of Debian packages required at BUILD TIME only.
# These packages (curl, xz-utils) are used in subsequent build steps to
# download and extract the Node.js tarball.  They are NOT copied into the
# runtime image, so they contribute zero attack surface to the final container.
#
# After installing, the script records every explicitly requested package and
# its exact Debian version in an in-toto / SLSA provenance receipt so that
# downstream tools (Trivy, dependency graph) can correlate build-time packages.
#
# Required environment variables: (none – all have safe defaults)
# Optional environment variables:
#   DEB_PACKAGES   – space-separated list of packages to install
#                    default: "curl xz-utils"
#   PROVENANCE_DIR – directory in which to write deb-receipt.json
#                    default: /etc/provenance
set -euo pipefail

DEB_PACKAGES="${DEB_PACKAGES:-curl xz-utils}"
PROVENANCE_DIR="${PROVENANCE_DIR:-/etc/provenance}"

echo "==> [00] Updating apt index and applying full-upgrade..."
apt-get update
# full-upgrade (rather than upgrade) allows installing new packages and removing
# obsolete ones, which is required for some security fixes that change dependency
# graphs (apt-get upgrade silently skips those transitions).  --no-install-recommends
# avoids pulling in unnecessary recommended packages during the upgrade.
apt-get full-upgrade -y --no-install-recommends

echo "==> [00] Installing build-time system dependencies: ${DEB_PACKAGES}..."
# shellcheck disable=SC2086  # intentional word-splitting on DEB_PACKAGES
apt-get install -y --no-install-recommends ${DEB_PACKAGES}

echo "==> [00] Generating deb packages provenance receipt..."
mkdir -p "${PROVENANCE_DIR}"
# Build a JSON array of PURL entries for every explicitly installed package.
DEB_DEPS=$(dpkg-query -W -f='{"uri": "pkg:deb/debian/${Package}@${Version}?arch=${Architecture}"},\n' \
    ${DEB_PACKAGES} | sed '$ s/,$//')
cat > "${PROVENANCE_DIR}/deb-receipt.json" << EOF
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [{"name": "debian-base-setup", "digest": {"sha256": "0000000000000000000000000000000000000000000000000000000000000000"}}],
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": {
    "resolvedDependencies": [
      ${DEB_DEPS}
    ]
  }
}
EOF

echo "==> [00] System dependencies installed and receipt written to ${PROVENANCE_DIR}/deb-receipt.json"
