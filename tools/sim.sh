#!/usr/bin/env bash
# The balance simulator: the computer plays every side for GAMES games of up to TURNS turns and reports
# when contact, battles, meetings, captures, the moth's end, a President and eliminations first happen.
# Usage: tools/sim.sh [GAMES] [TURNS] [SIZE] [RIVALS] [DIFFICULTY]   (defaults 40, 200, 0, 0 and 0; SIZE 0 small, 1 medium, 2 large, 3 huge; RIVALS 0 for the size's default; DIFFICULTY -2 to 2)
set -euo pipefail
cd "$(dirname "$0")/.."
odin test src/game -collection:tggd=src -define:ODIN_TEST_THREADS=1 -o:speed \
	-define:SIM_GAMES="${1:-40}" -define:SIM_TURNS="${2:-200}" -define:SIM_SIZE="${3:-0}" -define:SIM_RIVALS="${4:-0}" -define:SIM_DIFFICULTY="${5:-0}" -define:ODIN_TEST_NAMES=game.test_simulate 2>&1 \
	| sed -n '/^SIM/,/colonies at the end/p'
