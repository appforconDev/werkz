#!/usr/bin/env python3
# Task 36: resolve the FINAL intro-card beam → sprites/beam/crew-beam.png.
#
# AUTO-PICKUP CONVENTION (mirrors master-clean.png for sprites): if Rickard's
# HAND-CLEANED beam_clean.png is present it is used VERBATIM, ALWAYS, ahead of any
# generated output — no isolate, no defringe, no processing on top. This script
# and beam-gen.mjs NEVER write beam_clean.png; they only read it. When it is
# absent the beam is isolated from the chosen gpt-image attempt as a fallback.
#
# NEVER-RESIZE GUARD: a hand-clean whose canvas differs from the expected size,
# or that has no alpha channel, FAILS LOUDLY — the bake rejects it rather than
# silently scaling (the card layout uses the source aspect; a resized file would
# distort the art). Same spirit as the parts-clean dimension guard.
#
# Pixel cutouts are RICKARD's job going forward (CLAUDE.md rule 8) — this script
# does NOT re-isolate over a hand-clean.
import sys, importlib.util, os
from PIL import Image
from collections import deque

ROOT = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location('cut', os.path.join(ROOT, 'cut-hires.py'))
cut = importlib.util.module_from_spec(spec); spec.loader.exec_module(cut)

BEAM = os.path.join(ROOT, 'sprites', 'beam')
CLEAN = os.path.join(BEAM, 'beam_clean.png')  # Rickard's hand-clean (protected input)
OUT = os.path.join(BEAM, 'crew-beam.png')     # resolved final (this script's own output)
EXPECTED = (1161, 215)  # the hand-clean's agreed canvas; a mismatch fails loud

def resolve():
    if os.path.exists(CLEAN):
        im = Image.open(CLEAN)
        if 'A' not in im.getbands() and 'transparency' not in im.info:
            raise SystemExit(f"BEAM_CLEAN REJECTED: {CLEAN} has NO ALPHA CHANNEL (mode {im.mode}). "
                             f"Export the hand-cleaned beam as a transparent PNG.")
        if im.size != EXPECTED:
            raise SystemExit(f"BEAM_CLEAN REJECTED: canvas {im.size[0]}x{im.size[1]} != expected "
                             f"{EXPECTED[0]}x{EXPECTED[1]} ({CLEAN}). The bake NEVER resizes a hand-clean "
                             f"(the card layout uses the source aspect). Re-export at the expected size, "
                             f"or update EXPECTED in beam-cut.py as a deliberate change.")
        im.convert('RGBA').save(OUT)  # verbatim, no processing
        print(f"beam: using Rickard's hand-cleaned beam_clean.png (verbatim) -> {os.path.relpath(OUT, ROOT)} {im.size}")
        return
    _isolate_fallback()

def _isolate_fallback():
    # Fallback ONLY when there is no hand-clean: per-column silhouette isolate of
    # the chosen generated attempt (kept for reproducibility, not the shipping path).
    src = sys.argv[1] if len(sys.argv) > 1 else os.path.join(BEAM, 'attempt-1.png')
    if not os.path.exists(src):
        raise SystemExit(f"beam: no beam_clean.png and no generated attempt ({src}) — nothing to resolve.")
    im = Image.open(src).convert('RGB'); W, H = im.size; px = im.load()
    lum = lambda p: 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]
    rowmean = [sum(lum(px[x, y]) for x in range(0, W, 8)) / (W // 8) for y in range(H)]
    base = min(rowmean); band = [y for y, m in enumerate(rowmean) if m > base + 12]
    if band:
        pad = int((max(band) - min(band)) * 0.12)
        im = im.crop((0, max(0, min(band) - pad), W, min(H, max(band) + pad))); px = im.load(); W, H = im.size
    EDGE = 42
    a = Image.new('L', (W, H), 0); ap = a.load()
    for x in range(W):
        top_y = bot_y = -1
        for y in range(H):
            if lum(px[x, y]) > EDGE:
                if top_y < 0: top_y = y
                bot_y = y
        if top_y >= 0:
            for y in range(top_y, bot_y + 1): ap[x, y] = 255
    res = im.convert('RGBA')
    a = cut.defringe(a, decontam_rgba=res)
    res.putalpha(a); bb = a.getbbox()
    (res.crop(bb) if bb else res).save(OUT)
    print(f"beam: no hand-clean — isolated fallback from {os.path.basename(src)} -> {os.path.relpath(OUT, ROOT)} {res.size}")

if __name__ == '__main__':
    resolve()
