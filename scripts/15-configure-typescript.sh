#!/bin/bash
# 15-configure-typescript.sh
#
# Purpose: Write the TypeScript compiler configuration (tsconfig.json) into
# the application directory.  The configuration targets modern ES2022 modules,
# uses NodeNext module resolution (required for ESM with Node.js 22+), and
# outputs compiled JavaScript into the `dist/` subdirectory.
#
# This step is intentionally separate from dependency installation so that
# tsconfig changes can be iterated without re-running the heavier npm install.
#
# Required environment variables: (none – all have safe defaults)
# Optional environment variables:
#   APP_DIR – absolute path to the application directory containing src/
#             default: /app
set -euo pipefail

APP_DIR="${APP_DIR:-/app}"

echo "==> [15] Writing tsconfig.json to ${APP_DIR}..."
cat > "${APP_DIR}/tsconfig.json" << 'EOF'
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

echo "==> [15] tsconfig.json written to ${APP_DIR}/tsconfig.json"
