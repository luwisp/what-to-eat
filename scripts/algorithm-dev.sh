#!/usr/bin/env bash
set -euo pipefail
project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
if [ ! -f "${HUAIWEI_DEV_DB:-data/runtime/huaiwei.sqlite}" ]; then
  python3 scripts/import-menu.py --db "${HUAIWEI_DEV_DB:-data/runtime/huaiwei.sqlite}"
fi
export cjHeapSize=${cjHeapSize:-64MB}
if [ "${HUAIWEI_DEV_SKIP_BUILD:-false}" != true ]; then bash scripts/cj.sh build -j 1; fi
python3 scripts/prepare-meal-metadata.py --db "${HUAIWEI_DEV_DB:-data/runtime/huaiwei.sqlite}" --output "${HUAIWEI_DEV_METADATA:-data/runtime/meal-metadata.json}" --restaurant-code "${HUAIWEI_DEV_RESTAURANT:-LAOXIANGJI}"
mkdir -p target/algorithm-dev/agent
bash scripts/cj.sh exec cjc -p src/agent --output-type=staticlib \
  --import-path target/release/huaiwei --import-path target/release/stdx \
  -L target/release/huaiwei -L target/release/stdx -lhuaiwei.model -lhuaiwei.platform \
  -lstdx.net.http -lstdx.net.tls -lstdx.encoding.json -lstdx.encoding.url \
  -lstdx.crypto.crypto -lstdx.crypto.digest -lstdx.log -lcrypto \
  -o target/algorithm-dev/agent/libhuaiwei.agent.a
case "$(uname -m)" in
  x86_64) sqlite_native=.deps/sqlite4cj/lib/linux-x64 ;;
  aarch64) sqlite_native=.deps/sqlite4cj/lib/linux-arm64 ;;
  *) printf '%s\n' 'This dev launcher currently supports Linux x86_64 / aarch64.' >&2; exit 2 ;;
esac
bash scripts/cj.sh exec cjc dev/algorithm/server.cj \
  --import-path target/algorithm-dev/agent --import-path target/release/huaiwei --import-path target/release/stdx --import-path target/release/sqlite4cj \
  -L target/algorithm-dev/agent -L target/release/huaiwei -L target/release/stdx -L target/release/sqlite4cj -L "$sqlite_native" \
  -lhuaiwei.agent -lhuaiwei.room -lhuaiwei.model -lhuaiwei.platform -lhuaiwei.store \
  -lsqlite4cj -lsqlite3 -lstdx.net.http -lstdx.net.tls -lstdx.encoding.url \
  -lstdx.encoding.json -lstdx.crypto.crypto -lstdx.crypto.digest -lstdx.log -lcrypto \
  -o target/algorithm-dev/server
if [ "${1:-}" = --build-only ]; then exit 0; fi
exec bash scripts/cj.sh exec target/algorithm-dev/server
