#!/usr/bin/env bash
set -e
project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
sdk_dir=${JUXIAOBAO_CANGJIE_SDK:-${CANGJIE_HOME:-$HOME/.local/opt/cangjie-1.2.0/cangjie}}
if [ ! -f "$sdk_dir/envsetup.sh" ]; then
  printf '%s\n' 'Set JUXIAOBAO_CANGJIE_SDK to your Cangjie SDK directory.' >&2
  exit 2
fi
source "$sdk_dir/envsetup.sh"
if [ -d "$project_dir/.deps/build-tools/bin" ]; then
  export PATH="$project_dir/.deps/build-tools/bin:$PATH"
fi
if [ -d "$project_dir/.deps/build-tools/include/openssl" ]; then
  export OPENSSL_ROOT_DIR="$project_dir/.deps/build-tools"
  export CPATH="$project_dir/.deps/build-tools/include:${CPATH:-}"
fi
export LD_LIBRARY_PATH="$project_dir/target/release/stdx:$project_dir/.deps/build-tools/lib:$project_dir/.deps/stdx/target/release/stdx:${LD_LIBRARY_PATH:-}"
cd "$project_dir"
case "${1:-}" in
  prepare)
    exec python3 scripts/prepare-build.py --check-tools
    ;;
  build|test|run|bench)
    python3 scripts/prepare-build.py --check-tools
    ;;
esac
if [ "${1:-}" = exec ]; then
  shift
  exec "$@"
fi
exec cjpm "$@"
