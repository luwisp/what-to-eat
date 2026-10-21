#!/usr/bin/env bash
set -euo pipefail
export cjHeapSize=${cjHeapSize:-64MB}
cd "$(dirname "$0")/.."
bash scripts/algorithm-dev.sh --build-only
bash scripts/cj.sh exec cjc -p src/agent --test \
  --import-path target/release/juxiaobao --import-path target/release/stdx \
  -L target/release/juxiaobao -L target/release/stdx \
  -ljuxiaobao.model -ljuxiaobao.platform -lstdx.net.http -lstdx.net.tls \
  -lstdx.encoding.json -lstdx.encoding.url -lstdx.crypto.crypto -lstdx.crypto.digest -lstdx.log -lcrypto \
  -o target/algorithm-dev/agent-tests
bash scripts/cj.sh exec target/algorithm-dev/agent-tests
python3 tests/meal-metadata-test.py
python3 tests/algorithm-dev-smoke.py
