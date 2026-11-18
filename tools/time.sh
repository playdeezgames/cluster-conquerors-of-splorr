#!/usr/bin/env bash
# How long a turn and a map frame take natively at huge with five rivals, over 5 games of TURNS turns.
# Usage: tools/time.sh [TURNS]   (default 200). The browser runs the same code as wasm, roughly 1.5 to 3 times slower.
set -euo pipefail
cd "$(dirname "$0")/.."
odin test src/game -collection:tggd=src -define:ODIN_TEST_THREADS=1 -o:speed \
	-define:TIME_TURNS="${1:-200}" -define:ODIN_TEST_NAMES=game.test_time_turns 2>&1 | grep -E "^TIME|Error"
