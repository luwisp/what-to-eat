import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location('build_compat', ROOT / 'scripts/prepare-build.py')
compat = importlib.util.module_from_spec(spec)
spec.loader.exec_module(compat)

TOOLCHAIN = '''set(CMAKE_SYSTEM_NAME Linux)
set(CMAKE_POSITION_INDEPENDENT_CODE ON)
set(CMAKE_C_FLAGS "-Wall -Wextra -Werror -Wconversion -Wstrict-prototypes -Wno-implicit-function-declaration -Wnon-virtual-dtor -Wdelete-non-virtual-dtor -Woverloaded-virtual -Wno-shorten-64-to-32 -Wno-implicit-int-conversion -Wno-string-conversion")
set(CMAKE_CXX_FLAGS "-Wall -Wextra -Werror -Wconversion -Wstrict-prototypes -Wno-implicit-function-declaration -Wnon-virtual-dtor -Woverloaded-virtual -Wno-shorten-64-to-32 -Wno-implicit-int-conversion -Wno-string-conversion")
set(CMAKE_CXX_FLAGS_DEBUG "-O0 -g -fstandalone-debug")
if(CMAKE_BUILD_TYPE MATCHES Release)
    set(CMAKE_C_FLAGS_RELEASE "-O2")
endif()
'''
HOOK = '''func ensurePsutilInstalled(pyCommand: String): Unit { }
main(): Int64 {
    match (getCommandLine()[1]) {
        case "pre-build" =>
            ensurePsutilInstalled(pyCommand)
            stagePreBuild(pyCommand)
        case _ => 0
    }
}
'''


def fixture(root):
    stdx = root / '.deps/stdx'
    toolchain = stdx / 'build/common/linux_toolchain.cmake'
    toolchain.parent.mkdir(parents=True)
    toolchain.write_text(TOOLCHAIN)
    zlib = stdx / 'third_party/zlib'
    zlib.mkdir(parents=True)
    (zlib / 'CMakeLists.txt').write_text('cmake_minimum_required(VERSION 3.16)\nproject(zlib C)\n')
    (stdx / 'build.cj').write_text(HOOK)
    return stdx, toolchain, zlib


class NativeBuildCompatibilityTests(unittest.TestCase):
    def test_missing_sources_fail_with_bootstrap_instruction(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(RuntimeError, 'bootstrap-deps.sh'):
                compat.prepare(Path(temp))

    def test_patch_is_idempotent_and_only_discards_native_cache(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            stdx, toolchain, zlib = fixture(root)
            cache = stdx / 'build_temp/build'
            cache.mkdir(parents=True)
            (cache / 'CMakeCache.txt').write_text('failed cache')
            data = root / 'data/runtime/app.sqlite'
            data.parent.mkdir(parents=True)
            data.write_bytes(b'existing application data')
            self.assertEqual(compat.prepare(root), 3)
            self.assertFalse(cache.exists())
            self.assertEqual(data.read_bytes(), b'existing application data')
            paths = [toolchain, zlib / 'CMakeLists.txt', stdx / 'build.cj']
            before = [(p.read_bytes(), p.stat().st_mtime_ns) for p in paths]
            cache.mkdir()
            (cache / 'CMakeCache.txt').write_text(f'CMAKE_HOME_DIRECTORY:INTERNAL={stdx}\n')
            self.assertEqual(compat.prepare(root), 0)
            self.assertEqual(before, [(p.read_bytes(), p.stat().st_mtime_ns) for p in paths])
            self.assertTrue(cache.exists())
            self.assertIn('if (isWin) { ensurePsutilInstalled(pyCommand) }', paths[2].read_text())

    def test_moved_checkout_cmake_cache_is_removed_without_repatching(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            stdx, _, _ = fixture(root)
            compat.prepare(root)
            cache = stdx / 'build_temp/build'
            cache.mkdir(parents=True)
            (cache / 'CMakeCache.txt').write_text('CMAKE_HOME_DIRECTORY:INTERNAL=/previous/location/.deps/stdx\n')
            self.assertEqual(compat.prepare(root), 0)
            self.assertFalse(cache.exists())

    def test_unknown_dependency_version_fails_before_any_write(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            stdx, toolchain, _ = fixture(root)
            original = toolchain.read_text()
            (stdx / 'build.cj').write_text('changed upstream build hook')
            with self.assertRaisesRegex(RuntimeError, 'Unsupported stdx build hook'):
                compat.prepare(root)
            self.assertEqual(toolchain.read_text(), original)

    def test_native_cache_symlink_is_never_followed(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            stdx, _, _ = fixture(root)
            external = root / 'unrelated'
            external.mkdir()
            (external / 'important').write_text('keep')
            cache = stdx / 'build_temp'
            cache.mkdir()
            (cache / 'build').symlink_to(external, target_is_directory=True)
            compat.prepare(root)
            self.assertEqual((external / 'important').read_text(), 'keep')

    @unittest.skipUnless(shutil.which('gcc') and shutil.which('g++') and shutil.which('cmake') and shutil.which('ninja'), 'native GCC/CMake/Ninja required')
    def test_gcc_builds_c_and_cpp_and_keeps_conversion_diagnostics(self):
        with tempfile.TemporaryDirectory(prefix='juxiaobao compat ') as temp:
            root = Path(temp)
            _, toolchain, zlib = fixture(root)
            # This is the actual failure class: narrowing conversion in third-party
            # C code, plus language-specific flags mixed into the other language.
            (zlib / 'smoke.c').write_text('unsigned char narrow(unsigned long n) { return n; }\nint main(void) { return narrow(0); }\n')
            (zlib / 'smoke.cpp').write_text('int main() { return 0; }\n')
            with (zlib / 'CMakeLists.txt').open('a') as cmake:
                cmake.write('enable_language(CXX)\nadd_library(c_smoke STATIC smoke.c)\nadd_executable(cpp_smoke smoke.cpp)\n')
            compat.prepare(root)
            build = root / 'native-build'
            env = {**os.environ, 'CC': shutil.which('gcc'), 'CXX': shutil.which('g++')}
            args = ['cmake', '-S', str(zlib), '-B', str(build), '-G', 'Ninja', f'-DCMAKE_TOOLCHAIN_FILE={toolchain}', '-DCMAKE_BUILD_TYPE=Release', '-DCMAKE_EXPORT_COMPILE_COMMANDS=ON']
            configured = subprocess.run(args, env=env, capture_output=True, text=True)
            self.assertEqual(configured.returncode, 0, configured.stdout + configured.stderr)
            compiled = subprocess.run(['cmake', '--build', str(build)], env=env, capture_output=True, text=True)
            self.assertEqual(compiled.returncode, 0, compiled.stdout + compiled.stderr)
            self.assertIn('conversion', compiled.stdout + compiled.stderr)
            commands = json.loads((build / 'compile_commands.json').read_text())
            c = next(c['command'] for c in commands if c['file'].endswith('smoke.c'))
            cpp = next(c['command'] for c in commands if c['file'].endswith('smoke.cpp'))
            self.assertNotIn('-Wnon-virtual-dtor', c)
            self.assertNotIn('-Woverloaded-virtual', c)
            self.assertNotIn('-Wstrict-prototypes', cpp)
            self.assertNotIn('-Wno-shorten-64-to-32', c)
            self.assertIn('-Werror', c)
            self.assertIn('-Wno-error=conversion', c)
            self.assertIn('-fPIC', c)


if __name__ == '__main__':
    unittest.main()
