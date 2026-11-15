#!/usr/bin/env bash
# Renders real frames natively and writes assets/screenshots/01-map.png, 02-colony.png, 03-battle.png,
# 04-council.png and 05-watch.png (the 480x270 screen at 3x) and assets/portal.png (480x360: a 240x180 window of
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

# Scales up by whole pixels. An affine transform, not resize: this machine's Pillow 12.1.1 began
# failing to enlarge with resize ("returned NULL without setting an exception") on November 15, 2026.
def scale(im, k):
    return im.transform((im.width * k, im.height * k), Image.AFFINE, (1 / k, 0, 0, 0, 1 / k, 0), Image.NEAREST)

for i, name in enumerate(["map", "colony", "battle", "council", "watch"], 1):
    im = Image.open(f"{d}/{name}.ppm")
    scale(im, 3).save(f"assets/screenshots/{i:02d}-{name}.png")
im = Image.open(f"{d}/map.ppm")
# The star map is 360x240 at the top left; take a 4:3 240x180 window from its middle, doubled.
scale(im.crop((60, 30, 300, 210)), 2).save("assets/portal.png")
print("assets/screenshots/01-05, assets/portal.png")
PY
rm -rf "$D"
