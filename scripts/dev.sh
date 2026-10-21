#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
env_file=${HUAIWEI_ENV_FILE:-.env}
if [ -f "$env_file" ]; then set -a; source "$env_file"; set +a; fi
export HUAIWEI_PORT=${HUAIWEI_PORT:-8080}
export HUAIWEI_PUBLIC_BASE_URL=${HUAIWEI_PUBLIC_BASE_URL:-http://127.0.0.1:$HUAIWEI_PORT}
npm --prefix frontend run build
if [ "${1:-}" = --component-demo ]; then
  bash scripts/build-integration-server.sh
  printf '%s\n' 'Component demo: TEST restaurant, real room/WS/rules, test-only memory/visitor adapters. Restart clears rooms. Account/catalog writes are not supplied.'
  exec bash scripts/cj.sh exec target/integration/dining-server
fi
bash scripts/cj.sh build -j 4
export HUAIWEI_DB_PATH=${HUAIWEI_DB_PATH:-data/runtime/huaiwei.sqlite}
if [ ! -f "$HUAIWEI_DB_PATH" ]; then python3 scripts/import-menu.py --db "$HUAIWEI_DB_PATH"; fi
python3 scripts/migrate-meal-metadata.py --db "$HUAIWEI_DB_PATH"
python3 scripts/restore-menu-assets.py --db "$HUAIWEI_DB_PATH"
printf '%s\n' "Dining app: $HUAIWEI_PUBLIC_BASE_URL/" "Consumer account: $HUAIWEI_PUBLIC_BASE_URL/account" "Merchant: $HUAIWEI_PUBLIC_BASE_URL/admin/" "Example restaurant: $HUAIWEI_PUBLIC_BASE_URL/r/LAOXIANGJI"
exec bash scripts/cj.sh exec target/release/bin/huaiwei
