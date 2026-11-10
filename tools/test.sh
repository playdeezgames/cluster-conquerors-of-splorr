#!/usr/bin/env bash
# Native tests, then an odin check of every package for js_wasm32 (catches stray core:os), then the real
# wasm build (catches 32-bit int overflow the native tests cannot see).
set -euo pipefail
cd "$(dirname "$0")/.."
odin test src/game -collection:tggd=src -define:ODIN_TEST_THREADS=1 -vet -o:speed
odin check src/game -no-entry-point -vet -target:js_wasm32 -collection:tggd=src
odin check src/web -vet -target:js_wasm32 -collection:tggd=src
tools/build.sh >/dev/null
echo "tests ok"
