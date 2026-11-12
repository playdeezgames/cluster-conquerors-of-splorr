#!/usr/bin/env bash
# The balance simulator: the computer plays every side for GAMES games of up to TURNS turns and reports
# when contact, battles, meetings, captures, the moth's end, a President and eliminations first happen.
# Usage: tools/sim.sh [GAMES] [TURNS]   (defaults 40 and 200)
set -euo pipefail
cd "$(dirname "$0")/.."
odin test src/game -collection:tggd=src -define:ODIN_TEST_THREADS=1 -o:speed \
	-define:SIM_GAMES="${1:-40}" -define:SIM_TURNS="${2:-200}" -define:ODIN_TEST_NAMES=game.test_simulate 2>&1 \
	| sed -n '/^SIM/,/colonies at the end/p'
