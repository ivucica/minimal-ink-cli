#!/bin/bash
# 20-build-app.sh
#
# Purpose: Compile the TypeScript/JSX source files in `src/` into plain
# JavaScript using the TypeScript compiler (tsc).  The compiled output is
# written to `dist/` as configured in tsconfig.json.  A successful tsc run
# also acts as a lightweight type-check / quality gate.
#
# Required environment variables: (none – all have safe defaults)
# Optional environment variables:
#   APP_DIR – absolute path to the application directory where tsconfig.json
#             and the src/ tree live
#             default: /app
set -euo pipefail

APP_DIR="${APP_DIR:-/app}"

echo "==> [20] Compiling TypeScript source in ${APP_DIR}/src → ${APP_DIR}/dist..."
cd "${APP_DIR}"
npx tsc

echo "==> [20] TypeScript compilation complete."
