import { test } from 'node:test';
import assert from 'node:assert/strict';
import { classify, route, estimateDiffLines } from './index.ts';
import { defaultConfig } from '../config.ts';

const cfg = defaultConfig;

test('classify: read tools', () => {
  assert.equal(classify({ toolName: 'Read', toolInput: { file_path: 'a.ts' } }, cfg).decisionClass, 'read');
  assert.equal(classify({ toolName: 'Grep', toolInput: {} }, cfg).decisionClass, 'read');
  assert.equal(classify({ toolName: 'Bash', toolInput: { command: 'git status' } }, cfg).decisionClass, 'read');
});

test('classify: routine bash', () => {
  assert.equal(classify({ toolName: 'Bash', toolInput: { command: 'npm test' } }, cfg).decisionClass, 'routine');
  assert.equal(classify({ toolName: 'Bash', toolInput: { command: 'pnpm install' } }, cfg).decisionClass, 'routine');
});

test('classify: destructive beats everything', () => {
  const c = classify({ toolName: 'Bash', toolInput: { command: 'rm -rf build' } }, cfg);
  assert.equal(c.decisionClass, 'destructive');
  assert.equal(c.destructiveCategory, 'file-deletion');
});

test('classify: small vs large diff', () => {
  const small = classify({ toolName: 'Write', toolInput: { file_path: 'src/a.ts', content: 'a\nb\nc' } }, cfg);
  assert.equal(small.decisionClass, 'small-diff');
  const bigContent = Array.from({ length: 25 }, (_, i) => `line ${i}`).join('\n');
  const large = classify({ toolName: 'Write', toolInput: { file_path: 'src/a.ts', content: bigContent } }, cfg);
  assert.equal(large.decisionClass, 'large-diff');
});

test('classify: critical file forces large-diff even when tiny', () => {
  const c = classify({ toolName: 'Write', toolInput: { file_path: '.github/workflows/ci.yml', content: 'x' } }, cfg);
  // .env-like/secrets are destructive; CI config is critical → large-diff.
  assert.equal(c.decisionClass, 'large-diff');
});

test('classify: writing .env is destructive (secrets)', () => {
  const c = classify({ toolName: 'Write', toolInput: { file_path: '/p/.env', content: 'K=1' } }, cfg);
  assert.equal(c.decisionClass, 'destructive');
});

test('route: destructive always holds regardless of trust', () => {
  const cls = classify({ toolName: 'Bash', toolInput: { command: 'git push --force' } }, cfg);
  assert.equal(route(cls, 100, cfg).action, 'hold');
});

test('route: trust thresholds gate auto-allow; below-threshold HOLDS, never ask/deny (task 27)', () => {
  // Fresh-workshop policy: reads are side-effect-free → auto-allow from trust 0.
  const readCls = classify({ toolName: 'Read', toolInput: {} }, cfg);
  assert.equal(route(readCls, 0, cfg).action, 'allow');
  assert.equal(route(readCls, 100, cfg).action, 'allow');

  // Below threshold = a HUMAN question on the phone (hold) — 'ask' passed to a
  // headless CC was an instant silent deny (the task-27 bug).
  const routineCls = classify({ toolName: 'Bash', toolInput: { command: 'npm test' } }, cfg);
  assert.equal(route(routineCls, 49, cfg).action, 'hold');
  assert.equal(route(routineCls, 50, cfg).action, 'allow');

  const smallCls = classify({ toolName: 'Write', toolInput: { file_path: 'a.ts', content: 'x' } }, cfg);
  assert.equal(route(smallCls, 74, cfg).action, 'hold');
  assert.equal(route(smallCls, 75, cfg).action, 'allow');
});

test('route: no class at any trust ever yields a non-hold non-allow outcome (task 27)', () => {
  const calls = [
    { toolName: 'Read', toolInput: {} },
    { toolName: 'Bash', toolInput: { command: 'pwd' } },
    { toolName: 'Bash', toolInput: { command: 'npm test' } },
    { toolName: 'Write', toolInput: { file_path: 'a.ts', content: 'x' } },
    { toolName: 'Write', toolInput: { file_path: 'a.ts', content: 'x\n'.repeat(50) } },
    { toolName: 'Bash', toolInput: { command: 'git push --force' } },
  ];
  for (const call of calls) {
    for (const trust of [0, 24, 25, 49, 50, 74, 75, 100]) {
      const r = route(classify(call, cfg), trust, cfg);
      assert.ok(r.action === 'allow' || r.action === 'hold',
        `${call.toolName}@trust${trust} routed ${r.action} — silent outcomes are forbidden`);
    }
  }
});

test('route: large-diff always holds', () => {
  const big = Array.from({ length: 30 }, () => 'x').join('\n');
  const cls = classify({ toolName: 'Write', toolInput: { file_path: 'a.ts', content: big } }, cfg);
  assert.equal(route(cls, 100, cfg).action, 'hold');
});

test('estimateDiffLines', () => {
  assert.equal(estimateDiffLines('Write', { content: 'a\nb' }), 2);
  assert.equal(estimateDiffLines('Edit', { old_string: 'a', new_string: 'a\nb\nc' }), 3);
});

test('LATENCY BUDGET (§3.5): classify+route p99 < 50ms over 10k calls', () => {
  const samples: number[] = [];
  const calls = [
    { toolName: 'Read', toolInput: { file_path: 'a.ts' } },
    { toolName: 'Bash', toolInput: { command: 'npm test && npm run build' } },
    { toolName: 'Bash', toolInput: { command: 'rm -rf node_modules' } },
    { toolName: 'Write', toolInput: { file_path: 'src/a.ts', content: 'a\nb\nc\nd' } },
  ];
  for (let i = 0; i < 10_000; i++) {
    const call = calls[i % calls.length];
    const t = performance.now();
    route(classify(call, cfg), 50, cfg);
    samples.push(performance.now() - t);
  }
  samples.sort((a, b) => a - b);
  const p99 = samples[Math.floor(samples.length * 0.99)];
  assert.ok(p99 < cfg.routingLatencyBudgetMs, `p99 ${p99.toFixed(3)}ms exceeds ${cfg.routingLatencyBudgetMs}ms budget`);
});
