#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ -f .env ]; then set -a; source .env; set +a; fi
npm --prefix frontend run build
if [ "${1:-}" = --component-demo ]; then
  bash scripts/build-integration-server.sh
  export HUAIWEI_PORT=${HUAIWEI_PORT:-8080}
  export HUAIWEI_PUBLIC_BASE_URL=${HUAIWEI_PUBLIC_BASE_URL:-http://127.0.0.1:$HUAIWEI_PORT}
  printf '%s\n' 'Component demo: TEST restaurant, real room/WS/rules, test-only memory/visitor adapters. Restart clears rooms. Account/catalog writes are not supplied.'
  exec bash scripts/cj.sh exec target/integration/dining-server
fi
bash scripts/cj.sh build -j 4
export HUAIWEI_DB_PATH=${HUAIWEI_DB_PATH:-data/runtime/huaiwei.sqlite}
if [ ! -f "$HUAIWEI_DB_PATH" ]; then python3 scripts/import-menu.py --db "$HUAIWEI_DB_PATH"; fi
python3 scripts/migrate-meal-metadata.py --db "$HUAIWEI_DB_PATH"
python3 scripts/restore-menu-assets.py --db "$HUAIWEI_DB_PATH"
printf '%s\n' 'Dining app: SQLite accounts, menus, rooms and v3 meal recommendations. Restaurant code: LAOXIANGJI.'
exec bash scripts/cj.sh exec target/release/bin/huaiwei
