#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
test_dir=$(mktemp -d /tmp/huaiwei-app-test.XXXXXX)
app_pid=''
cleanup() { if [ -n "$app_pid" ]; then kill "$app_pid" 2>/dev/null || true; wait "$app_pid" 2>/dev/null || true; fi; rm -rf "$test_dir"; }
trap cleanup EXIT
trap 'exit 0' INT TERM
python3 scripts/import-menu.py --db "$test_dir/app.sqlite" --assets-dir web/menu-images
HUAIWEI_DB_PATH="$test_dir/app.sqlite" HUAIWEI_PORT=8095 HUAIWEI_PUBLIC_BASE_URL=http://127.0.0.1:4175 bash scripts/cj.sh exec target/release/bin/huaiwei &
app_pid=$!
wait "$app_pid"
