#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 scripts/generate-models.py
python3 scripts/generate-ingredients.py
npm --prefix frontend run build
bash scripts/cj.sh test
bash scripts/build-integration-server.sh
npm run test:platform
node --test tests/room-integration.mjs
npm --prefix frontend run test -- --run
npm --prefix frontend run test:e2e
git diff --check -- . ":(exclude)README.md" ":(exclude)docs/**"
