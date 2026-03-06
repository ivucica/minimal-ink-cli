#!/bin/bash
set -e

echo "==> Updating apt and installing base system dependencies..."
apt-get update
# full-upgrade (rather than upgrade) allows installing new packages and removing
# obsolete ones, which is required for some security fixes that change dependency
# graphs (apt-get upgrade silently skips those transitions).
apt-get full-upgrade -y
DEB_PACKAGES="curl git gnupg xz-utils"
apt-get install -y $DEB_PACKAGES

echo "==> Generating deb packages provenance receipt..."
mkdir -p /etc/provenance
DEB_DEPS=$(dpkg-query -W -f='{"uri": "pkg:deb/debian/${Package}@${Version}?arch=${Architecture}"},\n' $DEB_PACKAGES | sed '$ s/,$//')
cat << EOF > /etc/provenance/deb-receipt.json
{
  "_type": "https://in-toto.io/Statement/v1",
  "subject": [{"name": "debian-base-setup", "digest": {"sha256": "0000000000000000000000000000000000000000000000000000000000000000"}}],
  "predicateType": "https://slsa.dev/provenance/v1",
  "predicate": {
    "resolvedDependencies": [
      $DEB_DEPS
    ]
  }
}
EOF

echo "==> Installing Node.js via official release tarball with hash verification..."
NODE_VERSION="22.14.0"
NODE_ARCH="linux-x64"
NODE_TAR="node-v${NODE_VERSION}-${NODE_ARCH}.tar.xz"

cd /tmp
curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TAR}"
curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt"

echo "==> Verifying SHA256 hash and recording provenance..."
grep " ${NODE_TAR}\$" SHASUMS256.txt > SHASUM_CHECK.txt
sha256sum -c SHASUM_CHECK.txt

echo "==> Generating in-toto / SLSA compliant provenance receipt..."
NODE_HASH=$(awk '{print $1}' SHASUM_CHECK.txt)
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

cat << EOF > /etc/provenance/nodejs-receipt.json
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

echo "==> Extracting Node.js..."
tar -xJf "${NODE_TAR}" -C /usr/local --strip-components=1
rm "${NODE_TAR}" SHASUMS256.txt SHASUM_CHECK.txt

echo "==> Upgrading npm to latest to patch vendored dependency vulnerabilities..."
# The npm bundled with Node.js ships its own node_modules (cross-spawn, semver,
# ws, etc.) that Trivy/Syft surfaces as individual CVEs. Upgrading npm replaces
# those vendored copies with the latest fixed versions.
npm install -g npm@latest

echo "==> Creating application directory structure..."
mkdir -p /app/src
cd /app

echo "==> Initializing package.json..."
npm init -y
npm pkg set type="module"

echo "==> Installing runtime and development dependencies..."
# Remove any stale lockfile that could pin old, vulnerable package versions.
# The container always builds fresh, but a leftover lockfile (e.g. if this
# script is re-run) could otherwise cause npm to skip newer fixed versions.
rm -f package-lock.json
npm install ink react ink-text-input
npm install --save-dev typescript @types/react @types/node

echo "==> Patching vulnerable transitive dependencies..."
# Fix any remaining vulnerabilities in the dependency tree that fall within
# the semver ranges allowed by the direct dependencies.
npm audit fix || true

echo "==> Generating npm provenance receipt..."
node -e '
const fs = require("fs");
const lock = JSON.parse(fs.readFileSync("package-lock.json"));
const deps = [];
for (const [path, pkg] of Object.entries(lock.packages || {})) {
  if (path === "") continue;
  if (pkg.resolved && pkg.integrity) {
    const parts = pkg.integrity.split("-");
    const algo = parts[0] === "sha512" ? "sha512" : "sha256";
    const hash = Buffer.from(parts[1], "base64").toString("hex");
    const name = path.replace(/.*node_modules\//, "");
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
fs.writeFileSync("/etc/provenance/npm-receipt.json", JSON.stringify(statement, null, 2));
'

echo "==> Configuring TypeScript..."
cat << 'EOF' > tsconfig.json
{
  "compilerOptions": {
    "target": "es2022",
    "module": "NodeNext",
    "moduleResolution": "NodeNext",
    "jsx": "react",
    "outDir": "./dist",
    "rootDir": "./src",
    "esModuleInterop": true,
    "strict": true,
    "skipLibCheck": true
  },
  "include": ["src/**/*"]
}
EOF
