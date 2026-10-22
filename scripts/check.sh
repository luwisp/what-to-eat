#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
python3 -m unittest discover -s tests -p 'test_build_compat.py'
python3 scripts/generate-models.py
python3 scripts/generate-ingredients.py
# Vite clears web/. Restore the local menu images even if a later check fails.
restore_assets() {
  if [ -f "${JUXIAOBAO_DB_PATH:-data/runtime/juxiaobao.sqlite}" ]; then
    python3 scripts/restore-menu-assets.py --db "${JUXIAOBAO_DB_PATH:-data/runtime/juxiaobao.sqlite}"
  fi
}
trap restore_assets EXIT
npm --prefix frontend run build
restore_assets
bash scripts/cj.sh test
bash scripts/build-integration-server.sh
npm run test:platform
node --test tests/room-integration.mjs
node --test tests/auth-integration.mjs
npm --prefix frontend run test -- --run
npm --prefix frontend run test:e2e
npm --prefix frontend run test:e2e:full
python3 -m unittest discover -s tests -p 'test_menu_import.py'
python3 tests/meal-metadata-test.py
python3 -m unittest discover -s tests -p 'test_app_migration.py'
git diff --check -- . ":(exclude)README.md" ":(exclude)docs/**"
