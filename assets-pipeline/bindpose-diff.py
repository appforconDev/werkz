#!/usr/bin/env python3
# Task 19h/19i: compose the bind-pose verification panel for a persona.
# Left = isolated master (bind reference), middle = the ACTUAL SkeletalWorker
# rendered in bind pose (produced by app/test/world/bindpose_render_test.dart,
# so it shares the real Flame assembly math), right = a silhouette OVERLAY
# (green = master, magenta = render) with an IoU number. Run the Flutter render
# test FIRST to refresh _bindpose-render.png, then this.
import json, os, sys
from PIL import Image, ImageDraw, ImageFont

PERSONA = sys.argv[1] if len(sys.argv) > 1 else "7a19"
BASE = f"sprites/parts-hires/{PERSONA}"

master = Image.open(f"{BASE}/master-idle.png").convert("RGBA")
render = Image.open(f"{BASE}/_bindpose-render.png").convert("RGBA")

# Cut provenance (task 22b): which layers are Rickard's hand-cleans vs machine
# cuts — stamped on the panel so it's always visible what the render is built of.
cutlog = {"master": "?", "overriddenParts": []}
if os.path.exists(f"{BASE}/cut-log.json"):
    cutlog = json.load(open(f"{BASE}/cut-log.json"))
prov = f"master: {cutlog['master']}   hand-cleaned parts: " + \
       (", ".join(cutlog["overriddenParts"]) if cutlog["overriddenParts"] else "none")

# Scale both to a common height for the panel + overlay.
Hp = 460
def fit(im):
    w = int(im.width * Hp / im.height)
    return im.resize((w, Hp))
m, r = fit(master), fit(render)

# Silhouette overlay: put master alpha in green, render alpha in magenta, on a
# common canvas aligned bottom-center (feet), the way they mount.
W = max(m.width, r.width)
def sil(im, rgb):
    a = im.split()[3].point(lambda v: 255 if v > 40 else 0)
    layer = Image.new("RGBA", (W, Hp), (0, 0, 0, 0))
    layer.paste(Image.merge("RGBA", (
        a.point(lambda v: rgb[0] if v else 0),
        a.point(lambda v: rgb[1] if v else 0),
        a.point(lambda v: rgb[2] if v else 0),
        a.point(lambda v: 150 if v else 0))),
        ((W - im.width) // 2, 0))
    return layer, a

mg, ma = sil(m, (60, 220, 90))
rg, ra = sil(r, (220, 60, 200))
overlay = Image.new("RGBA", (W, Hp), (30, 32, 34, 255))
overlay.alpha_composite(mg)
overlay.alpha_composite(rg)

# IoU on the aligned silhouettes.
mp = Image.new("L", (W, Hp), 0); mp.paste(ma, ((W - m.width) // 2, 0))
rp = Image.new("L", (W, Hp), 0); rp.paste(ra, ((W - r.width) // 2, 0))
mpx, rpx = mp.load(), rp.load()
inter = union = 0
for y in range(Hp):
    for x in range(W):
        a = mpx[x, y] > 0; b = rpx[x, y] > 0
        if a or b: union += 1
        if a and b: inter += 1
iou = inter / union if union else 0.0

# 3-panel board (+18px footer for the cut-provenance line).
gap = 14
board = Image.new("RGBA", (m.width + r.width + W + gap * 2, Hp + 26 + 18), (24, 25, 27, 255))
board.paste(m, (0, 26))
board.paste(r, (m.width + gap, 26))
board.alpha_composite(overlay, (m.width + r.width + gap * 2, 26))
d = ImageDraw.Draw(board)
try:
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 13)
except Exception:
    font = ImageFont.load_default()
d.text((4, 6), "MASTER (bind ref)", fill=(210, 210, 210), font=font)
d.text((m.width + gap + 4, 6), "BIND-POSE RENDER (real assembly)", fill=(210, 210, 210), font=font)
d.text((m.width + r.width + gap * 2 + 4, 6),
       f"OVERLAY  green=master magenta=render  IoU={iou:.3f}", fill=(210, 210, 210), font=font)
d.text((4, Hp + 28), prov, fill=(190, 170, 120), font=font)
board.convert("RGB").save(f"{BASE}/bindpose-diff.png")
print(f"{PERSONA}: IoU={iou:.3f} [{prov}] -> {BASE}/bindpose-diff.png")
