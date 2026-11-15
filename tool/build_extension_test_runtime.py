#!/usr/bin/env python3
"""Build the installed flutter_qjs_next core for native Flutter regression tests.
Requires flutter pub get, GCC/G++, Linux; no package downloads or SDK mutation.
The plugin's actual Android/Linux builds still use its upstream build files.
"""
import json
from pathlib import Path
import subprocess
from urllib.parse import unquote, urlparse

project = Path(__file__).resolve().parents[1]
config = project / '.dart_tool/package_config.json'
packages = json.loads(config.read_text())['packages']
package = next(p for p in packages if p['name'] == 'flutter_qjs_next')
uri = package['rootUri']
package_root = Path(unquote(urlparse(uri).path)) if uri.startswith('file:') else (config.parent / uri).resolve()
source = package_root / 'cxx'
output = project / 'build/native_extensions'
output.mkdir(parents=True, exist_ok=True)
version = (source / 'quickjs/VERSION.txt').read_text().strip()
names = ['cutils', 'libregexp', 'libunicode', 'quickjs', 'dtoa']
for name in names:
    subprocess.run(['gcc', '-O2', '-fPIC', '-D_GNU_SOURCE', f'-DCONFIG_VERSION="{version}"', f'-I{source / "quickjs"}', '-c', str(source / 'quickjs' / f'{name}.c'), '-o', str(output / f'{name}.o')], check=True)
subprocess.run(['g++', '-std=c++17', '-O2', '-fPIC', '-shared', str(source / 'ffi.cpp'), *[str(output / f'{name}.o') for name in names], '-lm', '-ldl', '-pthread', '-o', str(output / 'libflutter_qjs_next_plugin.so')], check=True)
print(output / 'libflutter_qjs_next_plugin.so')
