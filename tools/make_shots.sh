#!/usr/bin/env bash
# Renders real frames natively and writes assets/screenshots/01-map.png, 02-colony.png, 03-battle.png
# and 04-council.png (the 480x270 screen at 3x) and assets/portal.png (480x360: a 240x180 window of
# the star map around home, doubled, for the oeuvre-of-splorr portal). Needs Pillow.
set -euo pipefail
cd "$(dirname "$0")/.."
D="$(mktemp -d)"
odin test src/game -collection:tggd=src -define:ODIN_TEST_THREADS=1 -define:DUMP_PLAY="$D" \
	-define:ODIN_TEST_NAMES=game.test_dump_play >/dev/null
rm -f assets/screenshots/01-cluster.png
python3 -I - "$D" <<'PY'
import sys
from PIL import Image
d = sys.argv[1]
for i, name in enumerate(["map", "colony", "battle", "council"], 1):
    im = Image.open(f"{d}/{name}.ppm")
    im.resize((480 * 3, 270 * 3), Image.NEAREST).save(f"assets/screenshots/{i:02d}-{name}.png")
im = Image.open(f"{d}/map.ppm")
# The star map is 360x240 at the top left; take a 4:3 240x180 window from its middle, doubled.
im.crop((60, 30, 300, 210)).resize((480, 360), Image.NEAREST).save("assets/portal.png")
print("assets/screenshots/01-04, assets/portal.png")
PY
rm -rf "$D"
