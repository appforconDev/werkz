#!/usr/bin/env python3
# Task 22b: tests for the parts-clean/ hand-clean override convention in
# cut-hires.py. Runs against a SANDBOX tree (module ROOT is repointed to a temp
# dir with a small synthetic master + the real 7a19 manifest), so the real
# parts-hires outputs are never touched and the whole suite runs in <1s.
#
#   1. override picked up — parts-clean/leg-lower.png replaces the machine cut
#      VERBATIM, and the far-side duplicate derives from it (byte-equal pixels)
#   2. far ARM derives from the override THROUGH strip_prop (prop removal runs
#      on the hand-cleaned near arm, not the machine cut)
#   3. dimension mismatch FAILS LOUDLY with both sizes in the message
#   4. missing alpha channel FAILS LOUDLY
#   5. cut-log.json records master source + overridden part list
import importlib.util, json, os, shutil, sys, tempfile
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location("cut_hires", f"{HERE}/cut-hires.py")
cut = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cut)

P = "7a19"
failures = []

def check(name, cond, detail=""):
    print(("  PASS " if cond else "  FAIL ") + name + (f" — {detail}" if detail and not cond else ""))
    if not cond:
        failures.append(name)

with tempfile.TemporaryDirectory() as sandbox:
    cut.ROOT = sandbox
    os.makedirs(f"{sandbox}/sprites/parts/{P}")
    os.makedirs(f"{sandbox}/sprites/hires-candidates/{P}")
    shutil.copy(f"{HERE}/sprites/parts/{P}/rig-manifest.json", f"{sandbox}/sprites/parts/{P}/")

    # Synthetic hand-clean master: opaque grey body inset on a transparent
    # canvas, so load_master's defringe + bbox-crop have real edges to work on.
    m = Image.new("RGBA", (240, 480), (0, 0, 0, 0))
    body = Image.new("RGBA", (200, 440), (120, 122, 125, 255))
    m.paste(body, (20, 20))
    m.save(f"{sandbox}/sprites/hires-candidates/{P}/master-clean.png")

    outdir = f"{sandbox}/sprites/parts-hires/{P}"
    partsclean = f"{sandbox}/sprites/hires-candidates/{P}/parts-clean"
    os.makedirs(partsclean)

    # --- baseline: no overrides ---
    cut.cut_persona(P)
    log = json.load(open(f"{outdir}/cut-log.json"))
    check("baseline: cut-log has no overrides", log["overriddenParts"] == [] and log["master"] == "master-clean", str(log))
    leg_size = Image.open(f"{outdir}/leg-lower.png").size
    arm_size = Image.open(f"{outdir}/arm-lower.png").size

    # --- 1+2: overrides picked up, far side derives from them ---
    leg_ov = Image.new("RGBA", leg_size, (255, 0, 255, 255))      # magenta: unmistakable
    leg_ov.save(f"{partsclean}/leg-lower.png")
    arm_ov = Image.new("RGBA", arm_size, (90, 95, 100, 255))      # grey metal base...
    for y in range(int(arm_size[1] * 0.30), arm_size[1]):         # ...with a warm "pouch"
        for x in range(0, int(arm_size[0] * 0.40)):               #    in the strip_prop quadrant
            arm_ov.putpixel((x, y), (200, 120, 40, 255))
    arm_ov.save(f"{partsclean}/arm-lower.png")
    cut.cut_persona(P)

    check("override used VERBATIM for leg-lower",
          list(Image.open(f"{outdir}/leg-lower.png").getdata()) == list(leg_ov.getdata()))
    check("far LEG derives from the override (plain duplicate)",
          list(Image.open(f"{outdir}/leg-lower-far.png").getdata()) == list(leg_ov.getdata()))
    check("override used VERBATIM for arm-lower",
          list(Image.open(f"{outdir}/arm-lower.png").getdata()) == list(arm_ov.getdata()))
    expected_far_arm = cut.strip_prop(arm_ov.copy())
    far_arm = Image.open(f"{outdir}/arm-lower-far.png")
    check("far ARM derives from the override THROUGH strip_prop",
          list(far_arm.getdata()) == list(expected_far_arm.getdata())
          and list(far_arm.getdata()) != list(arm_ov.getdata()))
    log = json.load(open(f"{outdir}/cut-log.json"))
    check("cut-log records the overridden parts", sorted(log["overriddenParts"]) == ["arm-lower", "leg-lower"], str(log))

    # --- 3: dimension mismatch fails loudly, both sizes in the message ---
    bad = Image.new("RGBA", (leg_size[0] + 7, leg_size[1] - 3), (255, 0, 255, 255))
    bad.save(f"{partsclean}/leg-lower.png")
    try:
        cut.cut_persona(P)
        check("dimension mismatch fails loudly", False, "cut_persona did not raise")
    except SystemExit as e:
        msg = str(e)
        check("dimension mismatch fails loudly, both sizes in message",
              f"{bad.size[0]}x{bad.size[1]}" in msg and f"{leg_size[0]}x{leg_size[1]}" in msg, msg)
    leg_ov.save(f"{partsclean}/leg-lower.png")  # restore the good one

    # --- 4: missing alpha channel fails loudly ---
    Image.new("RGB", arm_size, (90, 95, 100)).save(f"{partsclean}/arm-lower.png")
    try:
        cut.cut_persona(P)
        check("missing alpha fails loudly", False, "cut_persona did not raise")
    except SystemExit as e:
        check("missing alpha fails loudly", "ALPHA" in str(e), str(e))

print()
if failures:
    sys.exit(f"{len(failures)} FAILED: {failures}")
print("all override tests passed")
