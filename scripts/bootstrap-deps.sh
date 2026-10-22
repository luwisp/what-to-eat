#!/usr/bin/env bash
set -euo pipefail
project_dir=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
cd "$project_dir"
mkdir -p .deps

fetch_archive() {
  local url=$1 archive=$2 expected=$3 destination=$4
  if [ ! -f "$archive" ]; then
    curl --fail --location --retry 2 "$url" --output "$archive.part"
    mv "$archive.part" "$archive"
  fi
  printf '%s  %s\n' "$expected" "$archive" | sha256sum --check --status
  if [ ! -d "$destination" ]; then
    mkdir -p "$destination"
    tar -xzf "$archive" --strip-components=1 -C "$destination"
  fi
}

fetch_archive https://api.github.com/repos/cangjielanguage/cangjie_stdx/tarball/89035c96e3fdb18aa43b1800fffe3763e66a810d \
  .deps/stdx-1.2.0.1.tar.gz 9e1fb15110631e83f19ef3501e67a1fe569e180e73c28c23abc612e6cd3914e3 .deps/stdx
fetch_archive https://api.github.com/repos/openharmony/third_party_zlib/tarball/OpenHarmony-v6.0-Release \
  .deps/zlib-source.tar.gz d49025d1d2f22f0229250cf7e2b5b81b502a86aa93c7a510cb50d117bbadeaef .deps/stdx/third_party/zlib
fetch_archive https://api.github.com/repos/openharmony/third_party_bounds_checking_function/tarball/OpenHarmony-v6.0-Release \
  .deps/boundscheck-source.tar.gz 0d26f38eeae9cfcda43691e72b5801048527b07c82185c0a03b1c217a007cb60 .deps/stdx/third_party/boundscheck-v1.1.16


if [ ! -d .deps/sqlite4cj ]; then
  git clone https://gitcode.com/skay_caomao/sqlite4cj.git .deps/sqlite4cj
  git -C .deps/sqlite4cj checkout --detach 70971c0b639ea55dcd8cfc2fc0ee03a017c38845
fi
test "$(git -C .deps/sqlite4cj rev-parse HEAD)" = 70971c0b639ea55dcd8cfc2fc0ee03a017c38845

if [ "${1:-}" = --local-tools ]; then
  if [ -d .deps/build-tools/conda-meta ]; then
    conda install --prefix "$project_dir/.deps/build-tools" -c conda-forge --yes 'clang=15' 'clangxx=15' 'openssl=3.5'
  else
    conda create --prefix "$project_dir/.deps/build-tools" -c conda-forge --no-default-packages --yes 'clang=15' 'clangxx=15' 'openssl=3.5'
  fi
fi
python3 scripts/prepare-build.py
printf '%s\n' 'Sources ready. GCC/g++ or Clang, CMake, Ninja and complete OpenSSL headers are required.'
printf '%s\n' 'Ubuntu 24.04: sudo apt install build-essential cmake ninja-build libssl-dev python3'
