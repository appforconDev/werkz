#!/usr/bin/env python3
# Task 35: isolate the generated steel beam to ALPHA — part of the beam-gen
# pipeline (invoked by beam-gen.mjs), NOT a manual step, so the strip regenerates
# transparent every run. The beam is a bright-ish metal SUBJECT on a near-BLACK
# background (the inverse of the sprite cut's dark-on-light), so the matte is
# "everything NOT reachable as near-black from the image edges" — a flood from
# all four edges removes the surrounding black band while the beam's own interior
# shadows (enclosed by brighter metal) stay opaque. Then the SAME defringe as the
# sprite cut (close → erode 1px → feather → RGB decontaminate) pulls the matte
# INSIDE the dark fringe ring so there is no black halo around the rivets/plate.
import sys, importlib.util, os
from PIL import Image, ImageFilter
from collections import deque

ROOT = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('cut', os.path.join(ROOT, 'cut-hires.py'))
cut = importlib.util.module_from_spec(spec); spec.loader.exec_module(cut)

src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(ROOT, 'sprites', 'beam', 'attempt-1.png')
out = sys.argv[2] if len(sys.argv) > 2 else os.path.join(ROOT, 'sprites', 'beam', '_beam-strip.png')
BG_THR = 30  # only the TRUE near-black bg (dark gunmetal steel is brighter)

im = Image.open(src).convert('RGB')
W, H = im.size
px = im.load()
lum = lambda p: 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]

# 1) Crop to the beam band: rows whose mean brightness rises clearly above the
#    darkest (background) row, plus a small pad.
rowmean = [sum(lum(px[x, y]) for x in range(0, W, 8)) / (W // 8) for y in range(H)]
base = min(rowmean)
band = [y for y, m in enumerate(rowmean) if m > base + 12]
if band:
    pad = int((max(band) - min(band)) * 0.12)
    top = max(0, min(band) - pad); bot = min(H, max(band) + pad)
    im = im.crop((0, top, W, bot)); px = im.load(); W, H = im.size

# 2) PER-COLUMN silhouette fill. The beam metal is genuinely dark (near the bg
#    luminance), so a flood eats through it. Instead, for each column find the
#    TOPMOST and BOTTOMMOST metal pixel (lum > EDGE) and fill everything BETWEEN
#    them opaque — the beam is one solid vertical span per column (plate taller,
#    rivets domed, interior grooves all enclosed), so this can never punch an
#    interior hole or leave a rivet floating. Columns with no metal → transparent.
EDGE = 42  # outer metal edge sits above the near-black bg
a = Image.new('L', (W, H), 0); ap = a.load()
for x in range(W):
    top_y = bot_y = -1
    for y in range(H):
        if lum(px[x, y]) > EDGE:
            if top_y < 0:
                top_y = y
            bot_y = y
    if top_y >= 0:
        for y in range(top_y, bot_y + 1):
            ap[x, y] = 255

# 3) SAME defringe as the sprite cut — drops the dark fringe ring + decontaminates
#    RGB under the matte so scaling never bleeds a black halo.
res = im.convert('RGBA')
a = cut.defringe(a, decontam_rgba=res)
res.putalpha(a)
bb = a.getbbox()
res = res.crop(bb) if bb else res
res.save(out)
print(f'beam isolated → {os.path.relpath(out, ROOT)} {res.size}')
