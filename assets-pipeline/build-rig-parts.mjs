#!/usr/bin/env node
// Rig-part cutter (task 19). From each persona's isolated idle-stand master pose
// (sprites/parts/<persona>/master-idle.png), produce best-effort part PNGs plus
// a rig-manifest.json that makes Rickard's Rive editor session mechanical:
// part list, master region (so world position is known), pivot (joint), z-order,
// attach parent.
//
// HONEST LIMIT: cutting a FLAT painterly render leaves occlusion holes — the
// torso behind an arm isn't in the pixels. These crops are a SCAFFOLD + a cut
// plan; the actual part separation + occlusion inpainting happens in the editor.
// The manifest is the real deliverable; the PNGs are a visual starting point.
//
// Pure PIL via python3 (no numpy in this env). Regions/pivots are fractions of
// the master bbox so they are resolution-independent.
import { execFileSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

// part = [name, x0,y0,x1,y1 (master fractions), pivotX,pivotY (fraction of PART),
//         z, attachParent]. Side-view near-side limbs; the far-side arm/leg are
// mirror duplicates created in the editor (z below the torso).
const PERSONAS = {
  '7a19': {
    name: 'Bolt K. Fixit', id: 'WX-7A19', body: 'round generalist',
    parts: [
      ['torso',      0.05,0.18, 0.95,0.72,  0.50,0.20, 0, null],
      ['head',       0.18,0.00, 0.98,0.34,  0.50,0.92, 5, 'torso'],
      ['tool-belt',  0.05,0.55, 0.95,0.70,  0.50,0.50, 2, 'torso'],
      ['arm-upper',  0.50,0.30, 0.84,0.52,  0.50,0.12, 3, 'torso'],
      ['arm-lower',  0.42,0.48, 0.80,0.74,  0.58,0.12, 4, 'arm-upper'],
      ['leg-upper',  0.28,0.62, 0.62,0.82,  0.50,0.12, 1, 'torso'],
      ['leg-lower',  0.26,0.80, 0.64,1.00,  0.50,0.12, 1, 'leg-upper'],
    ],
  },
  '3c57': {
    name: 'P. Checkwell', id: 'WX-3C57', body: 'tall-thin inspector',
    parts: [
      ['torso',      0.14,0.12, 0.88,0.52,  0.50,0.20, 0, null],
      ['head',       0.22,0.00, 0.82,0.17,  0.50,0.90, 5, 'torso'],
      ['arm-upper',  0.44,0.22, 0.76,0.44,  0.50,0.12, 3, 'torso'],
      ['arm-lower',  0.36,0.42, 0.72,0.70,  0.58,0.12, 4, 'arm-upper'],
      ['clipboard',  0.04,0.40, 0.46,0.66,  0.50,0.50, 6, 'arm-lower'],
      ['leg-upper',  0.30,0.50, 0.64,0.76,  0.50,0.12, 1, 'torso'],
      ['leg-lower',  0.26,0.74, 0.66,1.00,  0.50,0.12, 1, 'leg-upper'],
    ],
  },
  '9b72': {
    name: 'G. Sparkhand', id: 'WX-9B72', body: 'squat brute',
    parts: [
      ['torso',      0.05,0.20, 0.95,0.66,  0.50,0.20, 0, null],
      ['head',       0.18,0.00, 0.78,0.32,  0.50,0.94, 5, 'torso'],   // goggles on top
      ['apron',      0.02,0.40, 0.56,0.82,  0.30,0.50, 2, 'torso'],
      ['arm-upper',  0.54,0.30, 0.92,0.52,  0.50,0.12, 3, 'torso'],
      ['arm-lower',  0.54,0.48, 0.98,0.76,  0.50,0.12, 4, 'arm-upper'], // big glove
      ['leg-upper',  0.28,0.60, 0.62,0.82,  0.50,0.12, 1, 'torso'],
      ['leg-lower',  0.26,0.80, 0.66,1.00,  0.50,0.12, 1, 'leg-upper'],
    ],
  },
};

for (const [key, p] of Object.entries(PERSONAS)) {
  const dir = `sprites/parts/${key}`;
  const master = `${dir}/master-idle.png`;
  // Crop each part from the master (alpha preserved), save PNG.
  const cropSpec = p.parts.map((pt) => ({ name: pt[0], box: pt.slice(1, 5) }));
  const py = `
from PIL import Image
im = Image.open(${JSON.stringify(master)}).convert("RGBA")
W,H = im.size
import json
for spec in json.loads(${JSON.stringify(JSON.stringify(cropSpec))}):
    x0,y0,x1,y1 = spec["box"]
    box = (int(x0*W), int(y0*H), int(x1*W), int(y1*H))
    part = im.crop(box)
    part.save(${JSON.stringify(dir)} + "/" + spec["name"] + ".png")
print("cut", ${JSON.stringify(key)}, len(json.loads(${JSON.stringify(JSON.stringify(cropSpec))})), "parts")
`;
  execFileSync('python3', ['-c', py], { stdio: 'inherit' });

  const manifest = {
    persona: p.id,
    name: p.name,
    body: p.body,
    master: 'master-idle.png',
    note: 'Regions/pivots are fractions of the master bbox (resolution-independent). '
      + 'Part PNGs are a flat-cut SCAFFOLD — occlusion (torso behind arms/legs) must be '
      + 'inpainted in the editor, and far-side arm/leg are mirror duplicates added there.',
    parts: p.parts.map((pt) => ({
      name: pt[0],
      masterRegion: { x0: pt[1], y0: pt[2], x1: pt[3], y1: pt[4] },
      pivot: { x: pt[5], y: pt[6] }, // joint origin, fraction of the part
      z: pt[7],
      attachParent: pt[8],
    })),
    animationsV1: {
      idle: 'weight shift + slow head look (reference: idle-stand)',
      walk: 'contact + passing keys drive the cycle (reference: walk-contact, walk-passing)',
      'work-typing': 'looped forearm tap at desk height (reference: work-typing)',
      'carry-walk': 'walk with both arms forward holding a crate (reference: work-carry)',
      'coffee-idle': 'relaxed idle, one hand holding a mug (reference: maintenance-coffee)',
    },
    stateMachineInputs: {
      speed: 'number 0..1 — 0 idle, >0 blends toward the walk cycle (tempo data-driven later)',
      mood: 'number 0/1/2 — 0 routine, 1 busy, 2 maintenance (Rive has NO string/enum input; task 19c)',
      carrying: 'bool — swaps walk for carry-walk',
    },
  };
  writeFileSync(`${dir}/rig-manifest.json`, JSON.stringify(manifest, null, 2) + '\n');
  console.log(`wrote ${dir}/rig-manifest.json`);
}
