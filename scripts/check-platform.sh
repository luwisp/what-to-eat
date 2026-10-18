#!/usr/bin/env bash
set -euo pipefail
project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
bash scripts/cj.sh build -j 4
bash scripts/cj.sh test --filter 'PlatformTests.*,CryptoTests.*'
npm run test:platform
probe_dir=$(mktemp -d "${TMPDIR:-/tmp}/huaiwei-probes.XXXXXX")
trap 'rm -rf "$probe_dir"' EXIT
bash scripts/cj.sh exec cjc tests/platform-probe.cj --import-path target/release/stdx \
  -L target/release/stdx -lstdx.encoding.json -lstdx.crypto.crypto -lstdx.net.http -lstdx.net.tls -o "$probe_dir/platform"
bash scripts/cj.sh exec "$probe_dir/platform"
bash scripts/cj.sh exec bash -c 'cd .deps/sqlite4cj && cjpm build -j 4'
bash scripts/cj.sh exec cjc tests/sqlite-probe.cj --import-path .deps/sqlite4cj/target/release/sqlite4cj \
  -L .deps/sqlite4cj/target/release/sqlite4cj -L .deps/sqlite4cj/lib/linux-x64 \
  -lsqlite4cj -lsqlite3 -o "$probe_dir/sqlite"
HUAIWEI_SQLITE_PROBE_PATH="$probe_dir/probe.db" HUAIWEI_SQLITE_PROBE_WRITE=true bash scripts/cj.sh exec "$probe_dir/sqlite"
HUAIWEI_SQLITE_PROBE_PATH="$probe_dir/probe.db" bash scripts/cj.sh exec "$probe_dir/sqlite"
