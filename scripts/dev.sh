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
printf '%s\n' 'Platform frontend host: business services require teammate adapters wired through createDiningServer. Use --component-demo only for explicit component review.'
exec bash scripts/cj.sh exec target/release/bin/huaiwei
