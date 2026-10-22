#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
env_file=${JUXIAOBAO_ENV_FILE:-.env}
if [ -f "$env_file" ]; then set -a; source "$env_file"; set +a; fi
export JUXIAOBAO_PORT=${JUXIAOBAO_PORT:-8080}
export JUXIAOBAO_PUBLIC_BASE_URL=${JUXIAOBAO_PUBLIC_BASE_URL:-http://127.0.0.1:$JUXIAOBAO_PORT}
# Keep the Cangjie macro runtime below the physical-memory limit on small
# development machines. Use project-scoped settings instead of inheriting a
# potentially invalid global cjHeapSize value from the login shell.
export cjHeapSize=${JUXIAOBAO_CJ_HEAP_SIZE:-64MB}
build_jobs=${JUXIAOBAO_BUILD_JOBS:-1}
# Fail early on missing native tools, and repair existing stdx sources/caches
# before spending time building the frontend. No system pip installs are used.
bash scripts/cj.sh prepare
npm --prefix frontend run build
if [ "${1:-}" = --component-demo ]; then
  bash scripts/build-integration-server.sh
  printf '%s\n' 'Component demo: TEST restaurant, real room/WS/rules, test-only memory/visitor adapters. Restart clears rooms. Account/catalog writes are not supplied.'
  exec bash scripts/cj.sh exec target/integration/dining-server
fi
bash scripts/cj.sh build -j "$build_jobs"
export JUXIAOBAO_DB_PATH=${JUXIAOBAO_DB_PATH:-data/runtime/juxiaobao.sqlite}
python3 scripts/migrate-app-data.py --db "$JUXIAOBAO_DB_PATH"
if [ ! -f "$JUXIAOBAO_DB_PATH" ]; then python3 scripts/import-menu.py --db "$JUXIAOBAO_DB_PATH"; fi
python3 scripts/migrate-meal-metadata.py --db "$JUXIAOBAO_DB_PATH"
python3 scripts/restore-menu-assets.py --db "$JUXIAOBAO_DB_PATH"
printf '%s\n' "Dining app: $JUXIAOBAO_PUBLIC_BASE_URL/" "Consumer account: $JUXIAOBAO_PUBLIC_BASE_URL/account" "Merchant: $JUXIAOBAO_PUBLIC_BASE_URL/admin/" "Example restaurant: $JUXIAOBAO_PUBLIC_BASE_URL/r/LAOXIANGJI"
exec bash scripts/cj.sh exec target/release/bin/juxiaobao
