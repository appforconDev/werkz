#!/usr/bin/env node
// Silhouette test (task 18 B): threshold a sprite/pose sheet to a pure-black
// shape on white, so the persona reads as a shadow. No regeneration — this is a
// pipeline step over an already-generated image. Uses only Node + a tiny PNG
// decode via the system `sips` is avoided; we shell to Python/PIL which is
// already used elsewhere in this repo for image work.
//
// Usage: node silhouette.mjs <input.png> <output.png> [threshold=205]
import { execFileSync } from 'node:child_process';

const [input, output, thr = '205'] = process.argv.slice(2);
if (!input || !output) {
  console.error('usage: node silhouette.mjs <input.png> <output.png> [threshold]');
  process.exit(1);
}

// The sheets sit on warm manila paper (light). Pixels darker than the threshold
// become black (the robot), everything lighter becomes white (paper) — so the
// silhouette is the robot's shadow. `L` luminance threshold.
const py = `
from PIL import Image
im = Image.open(${JSON.stringify(input)}).convert('L')
bw = im.point(lambda p: 0 if p < ${Number(thr)} else 255, mode='1')
bw.convert('L').save(${JSON.stringify(output)})
print('silhouette', bw.size)
`;
execFileSync('python3', ['-c', py], { stdio: 'inherit' });
