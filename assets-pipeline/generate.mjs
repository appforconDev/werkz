#!/usr/bin/env node
// Generate concept art via Fal's queue API (openai/gpt-image-2).
//
// Usage:
//   node generate.mjs                 run every job in manifest.json
//   node generate.mjs 05 07           run only jobs whose id starts with these prefixes
//   node generate.mjs --quality low   override quality for this run (smoke tests)
//
// Every prompt is prefixed with anchors/style-anchor.txt so all assets share
// the same style DNA. Images land in output/<job-id>[-n].png (gitignored).

import { readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.dirname(fileURLToPath(import.meta.url));
const QUEUE_BASE = 'https://queue.fal.run';
const POLL_INTERVAL_MS = 3000;
const JOB_TIMEOUT_MS = 5 * 60 * 1000;

async function loadFalKey() {
  const env = await readFile(path.join(ROOT, '.env'), 'utf8');
  const match = env.match(/^FAL_KEY=(.+)$/m);
  if (!match) throw new Error('FAL_KEY not found in assets-pipeline/.env');
  return match[1].trim();
}

async function falJson(url, key, init = {}) {
  const res = await fetch(url, {
    ...init,
    headers: { Authorization: `Key ${key}`, 'Content-Type': 'application/json', ...init.headers },
  });
  if (!res.ok) throw new Error(`${init.method ?? 'GET'} ${url} → ${res.status}: ${await res.text()}`);
  return res.json();
}

async function runJob(job, { model, key, anchor, defaults, qualityOverride }) {
  const promptText = (await readFile(path.join(ROOT, job.prompt), 'utf8')).trim();
  const body = {
    prompt: job.anchor === false ? promptText : anchor + '\n\n' + promptText,
    image_size: job.image_size,
    quality: qualityOverride ?? job.quality ?? defaults.quality,
    output_format: job.output_format ?? defaults.output_format,
    num_images: job.num_images ?? defaults.num_images,
  };

  console.log(`[${job.id}] submitting (${body.image_size}, ${body.quality})`);
  const submitted = await falJson(`${QUEUE_BASE}/${model}`, key, {
    method: 'POST',
    body: JSON.stringify(body),
  });

  const statusUrl = submitted.status_url ?? `${QUEUE_BASE}/${model}/requests/${submitted.request_id}/status`;
  const responseUrl = submitted.response_url ?? `${QUEUE_BASE}/${model}/requests/${submitted.request_id}`;

  const deadline = Date.now() + JOB_TIMEOUT_MS;
  while (true) {
    const status = await falJson(statusUrl, key);
    if (status.status === 'COMPLETED') break;
    if (status.status === 'FAILED' || status.status === 'ERROR') {
      throw new Error(`[${job.id}] generation failed: ${JSON.stringify(status)}`);
    }
    if (Date.now() > deadline) throw new Error(`[${job.id}] timed out after ${JOB_TIMEOUT_MS / 1000}s`);
    await new Promise((r) => setTimeout(r, POLL_INTERVAL_MS));
  }

  const result = await falJson(responseUrl, key);
  const images = result.images ?? [];
  if (!images.length) throw new Error(`[${job.id}] completed but returned no images`);

  const saved = [];
  for (const [i, image] of images.entries()) {
    const ext = (image.content_type ?? 'image/png').split('/')[1];
    const suffix = images.length > 1 ? `-${i + 1}` : '';
    const file = path.join(ROOT, 'output', `${job.id}${suffix}.${ext}`);
    const data = await fetch(image.url);
    if (!data.ok) throw new Error(`[${job.id}] download failed: ${data.status}`);
    await writeFile(file, Buffer.from(await data.arrayBuffer()));
    saved.push(file);
    console.log(`[${job.id}] saved ${path.relative(ROOT, file)} (${image.width}x${image.height})`);
  }
  return saved;
}

const args = process.argv.slice(2);
const qualityFlag = args.indexOf('--quality');
const qualityOverride = qualityFlag !== -1 ? args.splice(qualityFlag, 2)[1] : undefined;

const key = await loadFalKey();
const anchor = (await readFile(path.join(ROOT, 'anchors', 'style-anchor.txt'), 'utf8')).trim();
const manifest = JSON.parse(await readFile(path.join(ROOT, 'manifest.json'), 'utf8'));

const jobs = args.length
  ? manifest.jobs.filter((j) => args.some((prefix) => j.id.startsWith(prefix)))
  : manifest.jobs;
if (!jobs.length) {
  console.error(`No jobs match: ${args.join(', ')}`);
  process.exit(1);
}

let failures = 0;
for (const job of jobs) {
  try {
    await runJob(job, { model: manifest.model, key, anchor, defaults: manifest.defaults, qualityOverride });
  } catch (err) {
    failures++;
    console.error(String(err));
  }
}
console.log(`Done: ${jobs.length - failures}/${jobs.length} jobs succeeded.`);
process.exit(failures ? 1 : 0);
