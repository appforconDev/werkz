#!/usr/bin/env python3
# Task 19e: cut the APPROVED hi-res masters (attempt1-1) into rig parts per each
# persona's rig-manifest, generate far-side limb DUPLICATES, and a debug overlay.
# Output → sprites/parts-hires/<persona>/. The low-res parts/ stay as reference.
#
# HONEST LIMITS (reported, not hidden):
#  - Occlusion inpaint is MINIMAL: in the idle-stand side profile the near arm
#    hangs mostly beside the body, so torso-behind-arm bleed is small at render
#    size. We do a light edge-feather, not content-aware fill (no numpy here).
#  - Far-side limbs are plain DUPLICATES of the near-side (task 19k: NOT flipped —
#    in profile both feet point the same way). Depth is sold at render time by a
#    tint + a small attach offset + z-order behind the torso, not baked here.
#  - The manifest fractions were tuned to the low-res masters; on the hi-res
#    edit outputs they land APPROXIMATELY (arms differ slightly; 3C57 has no
#    clipboard in the master). Good enough for the mechanical scaffold; pivots
#    are the rotation origins and approximate pivots give approximate-but-
#    readable motion. No manifest edits here — the 19c contract is preserved.
import json, os
from PIL import Image, ImageFilter, ImageDraw
from collections import deque

ROOT = os.path.dirname(os.path.abspath(__file__))
FAR = {"arm-upper", "arm-lower", "leg-upper", "leg-lower"}  # limbs that get a far-side DUPLICATE
ARM_FAR = {"arm-upper", "arm-lower"}  # far arm must be prop-less (task 19k)
COLORS = {"head":(255,80,80),"torso":(80,180,255),"arm-upper":(80,255,120),"arm-lower":(40,200,90),
          "leg-upper":(255,200,60),"leg-lower":(220,160,40),"tool-belt":(200,120,255),
          "clipboard":(200,120,255),"apron":(200,120,255)}

def defringe(a, decontam_rgba=None):
    # Edge decontamination (task 19i halo fix). CLOSE the matte (dilate→erode) to
    # fill anti-alias pinholes, then ERODE 1px to pull the edge INSIDE the bright
    # fringe ring that a plain threshold leaves — that ring was the halo. A hair of
    # feather restores clean AA. Previously we DILATED (MaxFilter 5), which did the
    # opposite: it grew the matte over background pixels and MADE the halo.
    a = a.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))  # close
    a = a.filter(ImageFilter.MinFilter(3))  # erode 1px → drop the fringe
    a = a.filter(ImageFilter.GaussianBlur(0.6))
    if decontam_rgba is not None:  # zero RGB where fully transparent → no bright bleed on scale
        ap = a.load(); px = decontam_rgba.load(); W, H = decontam_rgba.size
        for y in range(H):
            for x in range(W):
                if ap[x, y] == 0 and px[x, y][3] != 0:
                    px[x, y] = (0, 0, 0, 0)
    return a

def isolate(src, thr=175):
    im = Image.open(src).convert("RGB"); W,H = im.size; px = im.load()
    fg = [[(0.299*px[x,y][0]+0.587*px[x,y][1]+0.114*px[x,y][2]) < thr for x in range(W)] for y in range(H)]
    seen = [[False]*W for _ in range(H)]; best=[]; bestn=0
    for yy in range(H):
        for xx in range(W):
            if fg[yy][xx] and not seen[yy][xx]:
                q=deque([(xx,yy)]); seen[yy][xx]=True; comp=[]
                while q:
                    cx,cy=q.popleft(); comp.append((cx,cy))
                    for dx,dy in ((1,0),(-1,0),(0,1),(0,-1)):
                        nx,ny=cx+dx,cy+dy
                        if 0<=nx<W and 0<=ny<H and fg[ny][nx] and not seen[ny][nx]:
                            seen[ny][nx]=True; q.append((nx,ny))
                if len(comp)>bestn: bestn=len(comp); best=comp
    a=Image.new("L",(W,H),0); ap=a.load()
    for c in best: ap[c[0],c[1]]=255
    res=Image.open(src).convert("RGBA")
    a=defringe(a, decontam_rgba=res)
    res.putalpha(a); bb=a.getbbox()
    return res.crop(bb) if bb else res

def strip_prop(crop):
    # Remove the arm-mounted tool/binder prop from the far-arm DUPLICATE (task
    # 19k): only the near arm carries it. The prop is the warm leather pouch in
    # the lower-left of the forearm crop; the arm metal is desaturated. So inside
    # that quadrant we clear saturated warm pixels (spares the grey arm), leaving
    # the far arm prop-less. Behind the torso this reveals torso, which is fine.
    im = crop.convert("RGBA"); W, H = im.size; px = im.load()
    for y in range(H):
        for x in range(W):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            if x < 0.42 * W and y > 0.24 * H:  # lower-left prop quadrant
                mx = max(r, g, b); mn = min(r, g, b)
                s = 0 if mx == 0 else (mx - mn) / mx
                if s > 0.30 and r > b:  # saturated + warm → the pouch, not the metal
                    px[x, y] = (0, 0, 0, 0)
    return im

def isolate_clipboard(src, region, masterW, masterH):
    # Isolate the GENERATED clipboard prop (task 19l): flood the LIGHT manila
    # background inward from the edges — the dark clipboard frame blocks the flood,
    # so the enclosed pale inspection sheet stays foreground (a plain dark-CC cut
    # would punch out the paper). Then fit to the manifest region aspect so the
    # sprite isn't stretched when placed.
    im = Image.open(src).convert("RGB"); W, H = im.size; px = im.load()
    lum = lambda p: 0.299 * p[0] + 0.587 * p[1] + 0.114 * p[2]
    THR = 165
    bg = [[False] * W for _ in range(H)]; q = deque()
    for x in range(W):
        for y in (0, H - 1):
            if lum(px[x, y]) > THR and not bg[y][x]: bg[y][x] = True; q.append((x, y))
    for y in range(H):
        for x in (0, W - 1):
            if lum(px[x, y]) > THR and not bg[y][x]: bg[y][x] = True; q.append((x, y))
    while q:
        cx, cy = q.popleft()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, ny = cx + dx, cy + dy
            if 0 <= nx < W and 0 <= ny < H and not bg[ny][nx] and lum(px[nx, ny]) > THR:
                bg[ny][nx] = True; q.append((nx, ny))
    a = Image.new("L", (W, H), 0); ap = a.load()
    for y in range(H):
        for x in range(W):
            if not bg[y][x]: ap[x, y] = 255
    a = a.filter(ImageFilter.MaxFilter(3)).filter(ImageFilter.MinFilter(3))  # close pinholes
    a = a.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(0.6))  # defringe
    res = Image.open(src).convert("RGBA"); res.putalpha(a); bb = a.getbbox()
    clip = res.crop(bb) if bb else res
    # Region aspect in PIXELS = the component bbox aspect Flame builds (region
    # fractions × master pixel dims), so the sprite fills without stretching.
    r = region
    target = ((r["x1"] - r["x0"]) * masterW) / ((r["y1"] - r["y0"]) * masterH)
    cw, ch = clip.size
    if cw / ch < target:
        nw = int(ch * target); canvas = Image.new("RGBA", (nw, ch), (0, 0, 0, 0)); canvas.paste(clip, ((nw - cw) // 2, 0))
    else:
        nh = int(cw / target); canvas = Image.new("RGBA", (cw, nh), (0, 0, 0, 0)); canvas.paste(clip, (0, (nh - ch) // 2))
    return canvas

def load_master(persona):
    # Prefer Rickard's hand-cleaned transparent cutout when it exists (task 19i);
    # only decontaminate its edge. Otherwise threshold-isolate attempt1-1.
    clean = f"{ROOT}/sprites/hires-candidates/{persona}/master-clean.png"
    if os.path.exists(clean):
        res = Image.open(clean).convert("RGBA")
        a = defringe(res.split()[3], decontam_rgba=res)
        res.putalpha(a); bb = a.getbbox()
        print(persona, "using hand-cleaned master-clean.png")
        return res.crop(bb) if bb else res
    return isolate(f"{ROOT}/sprites/hires-candidates/{persona}/attempt1-1.png")

for p in ["7a19","3c57","9b72"]:
    m = json.load(open(f"{ROOT}/sprites/parts/{p}/rig-manifest.json"))
    outdir = f"{ROOT}/sprites/parts-hires/{p}"; os.makedirs(outdir, exist_ok=True)
    master = load_master(p)
    master.save(f"{outdir}/master-idle.png")
    W,H = master.size
    for part in m["parts"]:
        r = part["masterRegion"]
        box = (int(r["x0"]*W), int(r["y0"]*H), int(r["x1"]*W), int(r["y1"]*H))
        crop = master.crop(box)
        crop.save(f"{outdir}/{part['name']}.png")
        if part["name"] in FAR:
            # Far side is a plain DUPLICATE — NOT flipped (task 19k): in profile
            # both feet point the same way. Depth tint is applied at RENDER time
            # (tunable), so the PNG stays a byte-identical copy (legs) except for
            # the arm's prop removal.
            far = crop.copy()
            if part["name"] in ARM_FAR:
                far = strip_prop(far)
            far.save(f"{outdir}/{part['name']}-far.png")
    # 3C57's inspector clipboard is a GENERATED prop (task 19l): the idle master
    # lacks it, so its region-cut is empty. If a chosen candidate exists, isolate
    # it and overwrite clipboard.png. Reproducible; regenerate the candidate with
    # clipboard.mjs. It's a distinct near-arm part → never duplicated to the far arm.
    chosen = f"{ROOT}/sprites/clipboard-candidates/{p}/chosen.png"
    clip_part = next((x for x in m["parts"] if x["name"] == "clipboard"), None)
    if clip_part and os.path.exists(chosen):
        isolate_clipboard(chosen, clip_part["masterRegion"], W, H).save(f"{outdir}/clipboard.png")
        print(p, "clipboard from generated prop")
    # debug overlay (manifest regions + pivots on the isolated hi-res master)
    ov = master.copy(); d = ImageDraw.Draw(ov)
    for part in m["parts"]:
        r=part["masterRegion"]; c=COLORS.get(part["name"],(255,255,255))
        d.rectangle((r["x0"]*W,r["y0"]*H,r["x1"]*W,r["y1"]*H), outline=c, width=4)
        px_=r["x0"]*W+part["pivot"]["x"]*(r["x1"]-r["x0"])*W
        py_=r["y0"]*H+part["pivot"]["y"]*(r["y1"]-r["y0"])*H
        d.ellipse((px_-6,py_-6,px_+6,py_+6), fill=c)
    bg=Image.new("RGBA",ov.size,(52,55,58,255)); bg.alpha_composite(ov)
    bg.convert("RGB").save(f"{outdir}/debug-overlay.png")
    print(p, "master", master.size, "->", outdir)
