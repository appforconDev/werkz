#!/usr/bin/env node
// Task 19l: generate WX-3C57 Checkwell's inspector clipboard as a standalone prop
// via the gpt-image EDIT endpoint, anchored on the clipboard cropped from the
// APPROVED pose sheet (sprites/clipboard-candidates/3c57/ref.png) so it matches
// the approved design. Checkwell's hi-res idle master lacks the clipboard, so it
// is a separate near-arm-attached part (manifest already declares it). The far
// arm stays prop-less (a distinct part is never duplicated onto the far side).
//
// Usage: node clipboard.mjs --attempt N
// Candidates → sprites/clipboard-candidates/3c57/attempt<N>-<i>.png (≤3 attempts,
// then stop + report per the task).

import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const MODEL = 'fal-ai/gpt-image-1/edit-image';
const QUEUE = 'https://queue.fal.run';
const POLL_MS = 4000;
const TIMEOUT_MS = 6 * 60 * 1000;
const DIR = path.join(ROOT, 'sprites', 'clipboard-candidates', '3c57');

const PROMPT =
  "Redraw ONLY the inspector's CLIPBOARD prop shown in the reference image as a " +
  'SINGLE isolated object, large and centered, filling most of the frame, on a ' +
  'plain flat warm manila-paper background with NOTHING else in frame (no robot, ' +
  'no hands, no arms). It is a 1955 industrial quality-inspector clipboard: a dark ' +
  'brushed-steel board with a metal spring clip across the top holding a pale sheet ' +
  'of paper stamped with a small dark "W" logo, held at a slight three-quarter ' +
  'tilt. Keep it IDENTICAL in design to the reference — same board, same clip, same ' +
  'stamped sheet, same worn steel + manila tones. Flat painterly 1955 industrial-' +
  'bureaucracy game-art, NOT photorealistic, warm tungsten rim light from the upper ' +
  'left against cool shadow, crisp readable silhouette, sharp clean edges.';

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

async function run(key, attempt) {
  const b64 = (await readFile(path.join(DIR, 'ref.png'))).toString('base64');
  const body = {
    prompt: PROMPT,
    image_urls: [`data:image/png;base64,${b64}`],
    image_size: '1024x1024',
    quality: 'high',
    input_fidelity: 'high',
    num_images: 3,
    output_format: 'png',
  };
  console.log(`clipboard attempt ${attempt}: submitting edit (1024x1024, high, fidelity high)`);
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
  await mkdir(DIR, { recursive: true });
  for (const [i, img] of (result.images ?? []).entries()) {
    const file = path.join(DIR, `attempt${attempt}-${i + 1}.png`);
    const data = await fetch(img.url);
    await writeFile(file, Buffer.from(await data.arrayBuffer()));
    console.log(`saved ${path.relative(ROOT, file)} (${img.width}x${img.height})`);
  }
}

const raw = process.argv.slice(2);
const ai = raw.indexOf('--attempt');
const attempt = ai !== -1 ? raw[ai + 1] : '1';
const key = await loadKey();
await run(key, attempt);
console.log('done.');
