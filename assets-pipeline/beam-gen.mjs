#!/usr/bin/env node
// Task 35: generate the full-width steel-beam element for the intro card — a
// standalone horizontal riveted girder with a central aged-brass plate, in the
// SAME rendered-metal 1955 material as the room art. Anchored (edit endpoint)
// on a crop of the Workshop ceiling beam so the material/palette match the world
// rather than reading like a flat UI widget. Candidates → sprites/beam/<i>.png.
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { execFileSync } from 'node:child_process';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const MODEL = 'fal-ai/gpt-image-1/edit-image';
const QUEUE = 'https://queue.fal.run';
const POLL_MS = 4000;
const TIMEOUT_MS = 6 * 60 * 1000;
const REF = path.join(ROOT, 'sprites', 'beam', '_ref.png'); // written by beam-crop step

const PROMPT =
  'A SINGLE horizontal industrial STEEL I-BEAM / structural girder spanning the ' +
  'full width, seen straight on, centered, filling the frame edge to edge. ' +
  'Rendered three-dimensional brushed gunmetal steel with realistic soft shadows, ' +
  'top highlight, scratches, grime and wear — a real forged beam, NOT a flat grey ' +
  'bar. A row of evenly spaced DOMED steel RIVETS runs along it, each a real rivet ' +
  'with its own highlight and cast shadow. Bolted at the center is a rectangular ' +
  'AGED BRASS nameplate with a subtle patina, its text ENGRAVED/embossed into the ' +
  'metal: a bold "W" emblem, then "WERKZ" large, and a smaller line "FACILITY ' +
  'OPERATIONS · DEPT. 7A". Warm tungsten rim light from the upper left against ' +
  'cool steel shadow. Flat painterly 1955 industrial-bureaucracy game-art, the ' +
  'exact material and palette of a riveted-steel workshop — warm brass, gunmetal, ' +
  'steel-grey. NO neon, no glow, no bright colors. Plain dark background above and ' +
  'below the beam.';

async function loadKey() {
  const env = await readFile(path.join(ROOT, '.env'), 'utf8');
  const m = env.match(/^FAL_KEY=(.+)$/m);
  if (!m) throw new Error('FAL_KEY not in .env');
  return m[1].trim();
}
async function falJson(url, key, init = {}) {
  const res = await fetch(url, { ...init, headers: { Authorization: `Key ${key}`, 'Content-Type': 'application/json', ...init.headers } });
  if (!res.ok) throw new Error(`${init.method ?? 'GET'} ${url} → ${res.status}: ${await res.text()}`);
  return res.json();
}

const key = await loadKey();
const b64 = (await readFile(REF)).toString('base64');
const body = {
  prompt: PROMPT,
  image_urls: [`data:image/png;base64,${b64}`],
  image_size: '1536x1024', // landscape → wide beam; crop to a strip after
  quality: 'high',
  input_fidelity: 'high',
  num_images: 3,
  output_format: 'png',
};
console.log('beam: submitting edit (1536x1024, high)');
const sub = await falJson(`${QUEUE}/${MODEL}`, key, { method: 'POST', body: JSON.stringify(body) });
const statusUrl = sub.status_url ?? `${QUEUE}/${MODEL}/requests/${sub.request_id}/status`;
const respUrl = sub.response_url ?? `${QUEUE}/${MODEL}/requests/${sub.request_id}`;
const deadline = Date.now() + TIMEOUT_MS;
for (;;) {
  const st = await falJson(statusUrl, key);
  if (st.status === 'COMPLETED') break;
  if (st.status === 'FAILED' || st.status === 'ERROR') throw new Error(JSON.stringify(st));
  if (Date.now() > deadline) throw new Error('timed out');
  await new Promise((r) => setTimeout(r, POLL_MS));
}
const result = await falJson(respUrl, key);
const dir = path.join(ROOT, 'sprites', 'beam');
await mkdir(dir, { recursive: true });
for (const [i, img] of (result.images ?? []).entries()) {
  const file = path.join(dir, `attempt-${i + 1}.png`);
  const data = await fetch(img.url);
  await writeFile(file, Buffer.from(await data.arrayBuffer()));
  console.log(`saved ${path.relative(ROOT, file)} (${img.width}x${img.height})`);
}

// Isolate the CHOSEN attempt to alpha as PART of this pipeline (task 35) — so the
// transparent strip regenerates every run, never a manual step that gets
// overwritten. Chosen = attempt-1 (Rickard-approved); override via CHOSEN env.
const chosen = process.env.CHOSEN ? Number(process.env.CHOSEN) : 1;
const chosenPath = path.join(dir, `attempt-${chosen}.png`);
const stripPath = path.join(dir, '_beam-strip.png');
execFileSync('python3', [path.join(ROOT, 'beam-cut.py'), chosenPath, stripPath], { stdio: 'inherit' });
console.log('done.');
