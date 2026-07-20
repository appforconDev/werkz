#!/usr/bin/env node
// Task 31 D: generate a FRONT-FACING (facing the camera) full-body portrait of
// each persona for the intro "personnel register" crew photo. Uses the gpt-image
// EDIT endpoint anchored on the APPROVED pose sheet so identity/colors stay
// on-model (the game sprites are all side-profile; a straight-on pose is new art
// but must be the SAME robot). Candidates → sprites/crew-front/<persona>-<i>.png.
//
// Usage: node crew-front.mjs [7a19 3c57 9b72] [--attempt N]
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const MODEL = 'fal-ai/gpt-image-1/edit-image';
const QUEUE = 'https://queue.fal.run';
const POLL_MS = 4000;
const TIMEOUT_MS = 6 * 60 * 1000;

const TRAITS = {
  '7a19': "This is the ROUND generalist WX-7A19 'Bolt K. Fixit': a compact round riveted barrel body, short stubby arms and legs, a domed head with a single round glass lens eye, a dented gray hard hat on top, and a tool belt with a wrench and pouches around its middle.",
  '3c57': "This is the TALL-THIN inspector WX-3C57 'P. Checkwell': a tall slender robot with long narrow limbs, a narrow rectangular head with a green clerk's visor, a slim necktie on its chest, and a clipboard held in one hand.",
  '9b72': "This is the SQUAT brute WX-9B72 'G. Sparkhand': a squat wide heavy robot with broad hulking shoulders and a low centre of gravity, heavily riveted armor, big blocky hands in heavy leather gloves, a scarred leather apron, and welding goggles pushed up on top of its head.",
};

function prompt(key) {
  return (
    "Redraw the SAME robot character shown in the reference sheet as a SINGLE full-body figure in a STRAIGHT-ON FRONT VIEW, facing the viewer directly (front-facing, symmetrical, looking at the camera — NOT a side profile, NOT three-quarter). A calm, upright 'staff photograph' standing pose, arms relaxed at the sides, feet together. Show the WHOLE body from the top of the head to the feet, large and centered, on a plain warm manila-paper background. Keep the character identity IDENTICAL to the reference — same proportions, same parts, same colors, same head and hat/visor/goggles. " +
    TRAITS[key] + ' ' +
    "Flat, painterly 1955 industrial-bureaucracy game-art, NOT photorealistic: brushed gunmetal and steel-gray panels with warm brass rivets, warm tungsten rim light from the upper left against cool shadow. Crisp, readable silhouette, high detail, sharp clean edges."
  );
}

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

const idOf = { '7a19': 'WX-7A19', '3c57': 'WX-3C57', '9b72': 'WX-9B72' };

async function run(key, attempt, personas) {
  for (const persona of personas) {
    const refPath = path.join(ROOT, 'approved', 'sprites', `${idOf[persona]}-poses.png`);
    const b64 = (await readFile(refPath)).toString('base64');
    const body = {
      prompt: prompt(persona),
      image_urls: [`data:image/png;base64,${b64}`],
      image_size: '1024x1536',
      quality: 'high',
      input_fidelity: 'high',
      num_images: 2,
      output_format: 'png',
    };
    console.log(`[${persona}] attempt ${attempt}: submitting FRONT-view edit`);
    const sub = await falJson(`${QUEUE}/${MODEL}`, key, { method: 'POST', body: JSON.stringify(body) });
    const statusUrl = sub.status_url ?? `${QUEUE}/${MODEL}/requests/${sub.request_id}/status`;
    const respUrl = sub.response_url ?? `${QUEUE}/${MODEL}/requests/${sub.request_id}`;
    const deadline = Date.now() + TIMEOUT_MS;
    for (;;) {
      const st = await falJson(statusUrl, key);
      if (st.status === 'COMPLETED') break;
      if (st.status === 'FAILED' || st.status === 'ERROR') throw new Error(`[${persona}] ${JSON.stringify(st)}`);
      if (Date.now() > deadline) throw new Error(`[${persona}] timed out`);
      await new Promise((r) => setTimeout(r, POLL_MS));
    }
    const result = await falJson(respUrl, key);
    const dir = path.join(ROOT, 'sprites', 'crew-front', persona);
    await mkdir(dir, { recursive: true });
    for (const [i, img] of (result.images ?? []).entries()) {
      const file = path.join(dir, `attempt${attempt}-${i + 1}.png`);
      const data = await fetch(img.url);
      await writeFile(file, Buffer.from(await data.arrayBuffer()));
      console.log(`[${persona}] saved ${path.relative(ROOT, file)} (${img.width}x${img.height})`);
    }
  }
}

const raw = process.argv.slice(2);
const ai = raw.indexOf('--attempt');
const attempt = ai !== -1 ? raw.splice(ai, 2)[1] : '1';
const personas = raw.length ? raw : ['7a19', '3c57', '9b72'];
const key = await loadKey();
await run(key, attempt, personas);
console.log('done.');
