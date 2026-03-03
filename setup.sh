#!/bin/bash
set -e

echo "==> Updating apt and installing base system dependencies..."
apt-get update
apt-get install -y curl git gnupg xz-utils

echo "==> Installing Node.js via official release tarball with hash verification..."
NODE_VERSION="20.18.0"
NODE_ARCH="linux-x64"
NODE_TAR="node-v${NODE_VERSION}-${NODE_ARCH}.tar.xz"

cd /tmp
curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/${NODE_TAR}"
curl -fsSLO "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt"

echo "==> Verifying SHA256 hash (Industry Standard Provenance)..."
# Extract only the line for our specific tarball to prevent output clutter, then verify
grep " ${NODE_TAR}\$" SHASUMS256.txt > SHASUM_CHECK.txt
sha256sum -c SHASUM_CHECK.txt

echo "==> Extracting Node.js..."
tar -xJf "${NODE_TAR}" -C /usr/local --strip-components=1
rm "${NODE_TAR}" SHASUMS256.txt SHASUM_CHECK.txt

echo "==> Creating application directory structure..."
mkdir -p /app/src
cd /app

echo "==> Initializing package.json..."
npm init -y
npm pkg set type="module"

echo "==> Installing runtime and development dependencies..."
npm install ink react ink-text-input
npm install --save-dev typescript @types/react @types/node

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
