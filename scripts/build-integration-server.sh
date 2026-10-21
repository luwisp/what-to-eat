#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/cj.sh build -j 4
mkdir -p target/integration
bash scripts/cj.sh exec cjc tests/support/dining-server.cj \
  --import-path target/release/juxiaobao --import-path target/release/stdx --import-path target/release/sqlite4cj \
  -L target/release/juxiaobao -L target/release/stdx -L target/release/sqlite4cj -L .deps/sqlite4cj/lib/linux-x64 \
  -ljuxiaobao.app -ljuxiaobao.auth -ljuxiaobao.catalog -ljuxiaobao.room -ljuxiaobao.agent -ljuxiaobao.model -ljuxiaobao.platform -ljuxiaobao.store -lsqlite4cj -lsqlite3 \
  -lstdx.net.http -lstdx.net.tls -lstdx.encoding.url -lstdx.encoding.json -lstdx.encoding.base64 -lstdx.crypto.crypto -lstdx.crypto.digest -lstdx.log -lcrypto \
  -o target/integration/dining-server
