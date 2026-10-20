#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/cj.sh build -j 4
mkdir -p target/integration
bash scripts/cj.sh exec cjc tests/support/dining-server.cj \
  --import-path target/release/huaiwei --import-path target/release/stdx --import-path target/release/sqlite4cj \
  -L target/release/huaiwei -L target/release/stdx -L target/release/sqlite4cj -L .deps/sqlite4cj/lib/linux-x64 \
  -lhuaiwei.app -lhuaiwei.auth -lhuaiwei.catalog -lhuaiwei.room -lhuaiwei.agent -lhuaiwei.model -lhuaiwei.platform -lhuaiwei.store -lsqlite4cj -lsqlite3 \
  -lstdx.net.http -lstdx.net.tls -lstdx.encoding.url -lstdx.encoding.json -lstdx.crypto.crypto -lstdx.crypto.digest -lstdx.log -lcrypto \
  -o target/integration/dining-server
