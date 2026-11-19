#!/usr/bin/env python3
"""Draws the itch.io cover, assets/cover.png (630x500), from the Urizen tiles and the DINOBYTE font the
game uses, in the game's Sweetie-16 colours: the title, and a corner of the cluster where yer green
Golf Carts head for a rival's star past the very large space moth at the Clubhouse's porch light.
Run: python3 -I tools/make_cover.py"""
import os
import random
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
sheet = Image.open(os.path.join(ROOT, 'tools/data/urizen_onebit_tileset__v2d0.png')).convert('RGB')
font = Image.open(os.path.join(ROOT, 'tools/data/dbyte_1x.png')).convert('RGBA')

P = [0x1A1C2C, 0x5D275D, 0xB13E53, 0xEF7D57, 0xFFCD75, 0xA7F070, 0x38B764, 0x257179,
     0x29366F, 0x3B5DC9, 0x41A6F6, 0x73EFF7, 0xF4F4F4, 0x94B0C2, 0x566C86, 0x333C57]
C = [((v >> 16) & 255, (v >> 8) & 255, v & 255) for v in P]
BLACK, PURPLE, RED, ORANGE, YELLOW, LIME, GREEN = C[0], C[1], C[2], C[3], C[4], C[5], C[6]
NAVY, CYAN, WHITE, LIGHT, MID, DARK = C[8], C[11], C[12], C[13], C[14], C[15]

TILES = {'star': (79, 21), 'dim': (78, 21), 'planet': (78, 19), 'van': (52, 7), 'wormhole': (28, 13),
         'car': (59, 7), 'truck': (54, 7), 'bus': (64, 7), 'tank': (68, 7), 'scooter': (73, 7),
         'moth_tl': (40, 48), 'moth_tr': (41, 48), 'moth_bl': (40, 49), 'moth_br': (41, 49)}

W, H = 630, 500
img = Image.new('RGB', (W, H), BLACK)


def put(x, y, color, s=1):
    for sy in range(s):
        for sx in range(s):
            if 0 <= x + sx < W and 0 <= y + sy < H:
                img.putpixel((x + sx, y + sy), color)


def tile(name, x, y, scale, color):
    col, row = TILES[name]
    for ty in range(12):
        for tx in range(12):
            if max(sheet.getpixel((13 * col + 1 + tx, 13 * row + 1 + ty))) > 0:
                put(x + tx * scale, y + ty * scale, color, scale)


def text(s, y, scale, color, shadow=None, x0=None):
    if x0 is None:
        x0 = (W - len(s) * 6 * scale) // 2
    for i, ch in enumerate(s.encode('cp437')):
        cx, cy = (ch % 16) * 6, (ch // 16) * 8
        for gy in range(8):
            for gx in range(6):
                if font.getpixel((cx + gx, cy + gy))[3] > 0:
                    x, yy = x0 + (i * 6 + gx) * scale, y + gy * scale
                    if shadow:
                        put(x + scale // 2 + 1, yy + scale // 2 + 1, shadow, scale)
                    put(x, yy, color, scale)


def dots(x0, y0, x1, y1, color, step=12, s=3):
    n = max(abs(x1 - x0), abs(y1 - y0)) // step
    for i in range(n + 1):
        put(x0 + (x1 - x0) * i // n, y0 + (y1 - y0) * i // n, color, s)


# Far stars, fixed by a seed so the cover can be drawn again the same.
rng = random.Random(20261119)
for _ in range(170):
    x, y = rng.randrange(W), rng.randrange(H)
    put(x, y, rng.choice([DARK, DARK, MID, NAVY, LIGHT]), rng.choice([1, 2, 2, 3]))

# The title.
text("CLUSTER", 22, 8, CYAN, NAVY)
text("CONQUERORS", 100, 7, CYAN, NAVY)
text("of SPLORR!!", 172, 4, WHITE, DARK)

# The scene: yer home world bottom left, a rival's star right, the moth at the porch light top right.
SC = 4  # tiles at 48 by 48
tile('planet', 34, 380, SC, GREEN)                 # yer home
tile('dim', 150, 260, 3, PURPLE)                   # unsurveyed
tile('wormhole', 250, 410, 3, PURPLE)              # a wormhole
tile('planet', 360, 300, 3, ORANGE)                # someone else's
tile('star', 470, 352, SC, YELLOW)                 # the rival's star
tile('tank', 550, 318, SC, RED)                    # its Monster Truck
tile('truck', 550, 376, SC, RED)                   # and Pickup
tile('star', 430, 230, 3, YELLOW)                  # the Clubhouse porch light
for name, dx, dy in (('moth_tl', 0, 0), ('moth_tr', 1, 0), ('moth_bl', 0, 1), ('moth_br', 1, 1)):
    tile(name, 492 + dx * 36, 214 + dy * 36, 3, LIGHT)

# Yer fleet on its way, a dotted route behind it.
dots(84, 392, 470, 380, GREEN)
tile('car', 196, 352, SC, GREEN)
tile('car', 252, 364, SC, GREEN)
tile('bus', 308, 352, SC, LIME)
tile('van', 120, 430, 3, WHITE)                    # a Moving Van, off somewhere else
dots(150, 446, 250, 430, DARK, 10, 2)

text("Everybody hates you.", 468, 2, LIGHT)
img.save(os.path.join(ROOT, 'assets/cover.png'))
print("assets/cover.png", img.size)
