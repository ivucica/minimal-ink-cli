#!/bin/bash
set -e

echo "==> Updating apt and installing base system dependencies..."
apt-get update
apt-get install -y curl git gnupg

echo "==> Installing Node.js (v20)..."
curl -fsSL https://deb.nodesource.com/setup_20.x | bash -
apt-get install -y nodejs

echo "==> Creating application directory structure..."
mkdir -p /app/src
cd /app

echo "==> Initializing package.json..."
npm init -y

echo "==> Installing runtime and development dependencies..."
npm install ink react ink-text-input
npm install --save-dev typescript @types/react @types/node

echo "==> Configuring TypeScript..."
cat << 'EOF' > tsconfig.json
{
  "compilerOptions": {
    "target": "es2022",
    "module": "commonjs",
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
