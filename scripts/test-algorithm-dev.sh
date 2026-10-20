#!/usr/bin/env bash
set -euo pipefail
export cjHeapSize=${cjHeapSize:-64MB}
cd "$(dirname "$0")/.."
bash scripts/algorithm-dev.sh --build-only
bash scripts/cj.sh exec cjc -p src/agent --test \
  --import-path target/release/huaiwei --import-path target/release/stdx \
  -L target/release/huaiwei -L target/release/stdx \
  -lhuaiwei.model -lhuaiwei.platform -lstdx.net.http -lstdx.net.tls \
  -lstdx.encoding.json -lstdx.encoding.url -lstdx.crypto.crypto -lstdx.crypto.digest -lstdx.log -lcrypto \
  -o target/algorithm-dev/agent-tests
bash scripts/cj.sh exec target/algorithm-dev/agent-tests
python3 tests/meal-metadata-test.py
python3 tests/algorithm-dev-smoke.py
