#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/cj.sh build -j 4
mkdir -p target/integration
bash scripts/cj.sh exec cjc tests/support/dining-server.cj \
  --import-path target/release/huaiwei --import-path target/release/stdx \
  -L target/release/huaiwei -L target/release/stdx \
  -lhuaiwei.app -lhuaiwei.room -lhuaiwei.agent -lhuaiwei.model -lhuaiwei.platform -lhuaiwei.store \
  -lstdx.net.http -lstdx.net.tls -lstdx.encoding.url -lstdx.encoding.json -lstdx.crypto.crypto -lstdx.log -lcrypto \
  -o target/integration/dining-server
