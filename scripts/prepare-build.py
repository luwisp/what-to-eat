#!/usr/bin/env python3
"""Apply the pinned stdx native-build fixes without installing Python packages.

Called both after bootstrap and before cjpm builds. Only vendored build inputs
and disposable stdx CMake caches are modified; application data is never touched.
"""
import argparse
from pathlib import Path
import re
import shutil
import subprocess
import sys

MARKER = '# BEGIN JUXIAOBAO NATIVE COMPAT v1'
TOOLCHAIN_FIX = r'''
# BEGIN JUXIAOBAO NATIVE COMPAT v1
# Keep diagnostics and -Werror for stdx itself, but separate C/C++ warnings.
foreach(flag -Wnon-virtual-dtor -Wdelete-non-virtual-dtor -Woverloaded-virtual)
    string(REPLACE " ${flag}" "" CMAKE_C_FLAGS "${CMAKE_C_FLAGS}")
endforeach()
foreach(flag -Wstrict-prototypes -Wno-implicit-function-declaration)
    string(REPLACE " ${flag}" "" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
endforeach()
# Toolchain files run before compiler identification; CC is set by cjpm_build.py.
set(JUXIAOBAO_NATIVE_CC "${CMAKE_C_COMPILER}")
if(NOT JUXIAOBAO_NATIVE_CC)
    set(JUXIAOBAO_NATIVE_CC "$ENV{CC}")
endif()
if(NOT JUXIAOBAO_NATIVE_CC)
    set(JUXIAOBAO_NATIVE_CC cc)
endif()
execute_process(COMMAND "${JUXIAOBAO_NATIVE_CC}" --version
    OUTPUT_VARIABLE JUXIAOBAO_NATIVE_CC_VERSION ERROR_QUIET)
if(JUXIAOBAO_NATIVE_CC_VERSION MATCHES "gcc|GCC|Free Software Foundation")
    foreach(flag -Wno-shorten-64-to-32 -Wno-implicit-int-conversion -Wno-string-conversion)
        string(REPLACE " ${flag}" "" CMAKE_C_FLAGS "${CMAKE_C_FLAGS}")
        string(REPLACE " ${flag}" "" CMAKE_CXX_FLAGS "${CMAKE_CXX_FLAGS}")
    endforeach()
    string(REPLACE " -fstandalone-debug" "" CMAKE_CXX_FLAGS_DEBUG "${CMAKE_CXX_FLAGS_DEBUG}")
endif()
# END JUXIAOBAO NATIVE COMPAT v1
'''
ZLIB_FIX = r'''
# BEGIN JUXIAOBAO NATIVE COMPAT v1
# libz.a is linked into stdx's shared library, so its objects must also be PIC.
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
# Older third-party zlib triggers conversion diagnostics on newer GCC/Clang.
# Keep the warning visible, without making this vendored dependency fail.
if(CMAKE_C_COMPILER_ID MATCHES "GNU|Clang")
    add_compile_options(-Wno-error=conversion)
endif()
# END JUXIAOBAO NATIVE COMPAT v1
'''


def insert_before(text, anchor, block, path):
    if MARKER in text:
        return text
    if text.count(anchor) != 1:
        raise RuntimeError(f'Unsupported stdx build configuration: {path}; expected the pinned dependency version')
    return text.replace(anchor, block + '\n' + anchor, 1)


def prepare(project):
    stdx = project / '.deps/stdx'
    toolchain = stdx / 'build/common/linux_toolchain.cmake'
    zlib = stdx / 'third_party/zlib/CMakeLists.txt'
    hook = stdx / 'build.cj'
    missing = [str(path) for path in (toolchain, zlib, hook) if not path.is_file()]
    if missing:
        raise RuntimeError('Missing dependency sources; run bash scripts/bootstrap-deps.sh first.\n' + '\n'.join(missing))
    # Validate all expected anchors before writing any source.
    old_toolchain, old_zlib, old_hook = [p.read_text() for p in (toolchain, zlib, hook)]
    new_toolchain = insert_before(old_toolchain, 'if(CMAKE_BUILD_TYPE MATCHES Release)', TOOLCHAIN_FIX, toolchain)
    new_zlib = old_zlib
    if MARKER not in new_zlib:
        # Replace our older standalone PIC fix with the complete compatibility block.
        new_zlib = new_zlib.removeprefix('set(CMAKE_POSITION_INDEPENDENT_CODE ON)\n')
        anchor = re.search(r'^project\(zlib C\)\s*$', new_zlib, re.MULTILINE)
        if not anchor:
            raise RuntimeError(f'Unsupported zlib build configuration: {zlib}')
        new_zlib = new_zlib[:anchor.end()] + '\n' + ZLIB_FIX + new_zlib[anchor.end():]
    new_hook = old_hook
    hook_marker = '// JUXIAOBAO: psutil is only used by the Windows cwd probe.'
    if hook_marker not in old_hook:
        # The Linux implementation in cjpm_build.py uses /proc, and macOS uses
        # lsof. Do not let the upstream convenience probe run global pip on Linux.
        pattern = r'(?m)^([ \t]*)ensurePsutilInstalled\(pyCommand\)[ \t]*$'
        matches = list(re.finditer(pattern, old_hook))
        if len(matches) != 1:
            raise RuntimeError(f'Unsupported stdx build hook: {hook}')
        new_hook = re.sub(pattern, lambda m: m[1] + hook_marker + '\n' + m[1] +
                          'if (isWin) { ensurePsutilInstalled(pyCommand) }', old_hook)
    changes = [(p, after) for p, before, after in (
        (toolchain, old_toolchain, new_toolchain), (zlib, old_zlib, new_zlib), (hook, old_hook, new_hook)
    ) if before != after]
    for path, content in changes:
        path.write_text(content)
    # Clear only generated native build directories when changing their inputs,
    # or when a checkout/cache was moved. Cangjie targets and DBs stay intact.
    cleared = []
    for cache in sorted((stdx / 'build_temp').glob('build*')):
        if not cache.is_dir() or cache.is_symlink():
            continue
        cache_file = cache / 'CMakeCache.txt'
        stale = False
        if cache_file.is_file():
            content = cache_file.read_text(errors='replace')
            home = re.search(r'^CMAKE_HOME_DIRECTORY:INTERNAL=(.*)$', content, re.MULTILINE)
            stale = bool(home and Path(home[1]).resolve() != stdx.resolve())
        if changes or stale:
            shutil.rmtree(cache)
            cleared.append(cache.name)
    if changes:
        print('Native compatibility prepared: C/C++ flags, zlib conversion/PIC, Linux Python hook.')
    if cleared:
        print('Removed obsolete stdx CMake cache: ' + ', '.join(cleared))
    return len(changes)


def check_tools():
    missing = [name for name in ('cmake', 'ninja') if not shutil.which(name)]
    pairs = [(shutil.which(c), shutil.which(cxx)) for c, cxx in (('clang', 'clang++'), ('gcc', 'g++'), ('cc', 'c++'))]
    cc, cxx = next(((c, cpp) for c, cpp in pairs if c and cpp), (None, None))
    if not cc:
        missing.append('C compiler (gcc or clang)')
    if not cxx:
        missing.append('C++ compiler (g++ or clang++)')
    if missing:
        raise RuntimeError('Missing build tools: ' + ', '.join(missing) + '\nUbuntu 24.04: sudo apt install build-essential cmake ninja-build libssl-dev python3')
    probe = subprocess.run([cc, '-x', 'c', '-E', '-'], input='#include <openssl/evp.h>\n#include <openssl/ssl.h>\n',
                           text=True, stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    if probe.returncode:
        raise RuntimeError('C compiler/OpenSSL header check failed. Ubuntu: sudo apt install libssl-dev\n' + probe.stderr)


def main():
    cli = argparse.ArgumentParser(description=__doc__)
    cli.add_argument('--project-root', type=Path, default=Path(__file__).resolve().parents[1])
    cli.add_argument('--check-tools', action='store_true')
    args = cli.parse_args()
    try:
        prepare(args.project_root)
        if args.check_tools:
            check_tools()
    except (OSError, RuntimeError) as error:
        print(f'Build preparation failed: {error}', file=sys.stderr)
        return 2
    return 0


if __name__ == '__main__':
    sys.exit(main())
