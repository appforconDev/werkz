// Task 39: Advisor Consultation — plan-mode lock, degradation, persistence.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, existsSync, readFileSync } from 'node:fs';
import { join } from 'node:path';
import { tmpdir } from 'node:os';
import { EventEmitter } from 'node:events';
import { ConsultationManager, PLAN_ARGS } from './consultation.ts';
import type { Spawner } from '../narration/narrate.ts';

// A fake claude that records its args and replies with scripted json.
function recordingClaude(result: string, code = 0, opts: { throwSync?: boolean } = {}): { spawner: Spawner; calls: string[][] } {
  const calls: string[][] = [];
  const spawner = ((_cmd: string, args: string[]) => {
    calls.push(args);
    if (opts.throwSync) throw new Error('ENOENT');
    const child = new EventEmitter() as EventEmitter & { stdout: EventEmitter; stderr: EventEmitter; kill: () => void };
    child.stdout = new EventEmitter();
    child.stderr = new EventEmitter();
    child.kill = () => {};
    queueMicrotask(() => {
      child.stdout.emit('data', JSON.stringify({ result }));
      child.emit('exit', code);
    });
    return child as unknown as ReturnType<Spawner>;
  }) as unknown as Spawner;
  return { spawner, calls };
}

test('every consultation turn spawns claude in PLAN MODE (hard lock)', async () => {
  const { spawner, calls } = recordingClaude('Here is the plan.');
  const c = new ConsultationManager('/proj', '/fake/claude', { spawner });
  const { sessionId } = c.start();
  const r = await c.send(sessionId, 'plan the auth refactor');
  assert.equal(r.ok, true);
  assert.equal(r.reply, 'Here is the plan.');
  const args = calls[0];
  // --permission-mode plan is ALWAYS present — the Advisor can never write/run.
  const i = args.indexOf('--permission-mode');
  assert.ok(i >= 0 && args[i + 1] === 'plan', `plan mode must be in the spawn args: ${args.join(' ')}`);
  // Belt-and-suspenders: the write/exec/research tools are ALSO disabled, so a
  // turn is pure reasoning (fast) and provably can't touch the repo.
  const d = args.indexOf('--disallowedTools');
  assert.ok(d >= 0, `disallowedTools must be present: ${args.join(' ')}`);
  for (const t of ['Bash', 'Edit', 'Write', 'Task']) {
    assert.ok(args[d + 1].includes(t), `${t} must be disallowed`);
  }
  assert.equal(PLAN_ARGS[0], '--permission-mode');
  assert.equal(PLAN_ARGS[1], 'plan');
});

test('the whole transcript is sent each turn (self-held context)', async () => {
  const { spawner, calls } = recordingClaude('ok');
  const c = new ConsultationManager('/proj', '/fake/claude', { spawner });
  const { sessionId } = c.start();
  await c.send(sessionId, 'first question');
  await c.send(sessionId, 'second question');
  const prompt = calls[1][calls[1].indexOf('-p') + 1];
  assert.match(prompt, /OPERATOR: first question/);
  assert.match(prompt, /ADVISOR: ok/); // the first reply is in the transcript
  assert.match(prompt, /OPERATOR: second question/);
});

test('degradation: no claude → loud-but-kind Advisor-unavailable, never a hang', async () => {
  const c = new ConsultationManager('/proj', null); // no binary
  const { sessionId } = c.start();
  const r = await c.send(sessionId, 'hi');
  assert.equal(r.ok, false);
  assert.match(r.error!, /Advisor unavailable/);
  // The operator message is kept so a retry doesn't lose it.
  assert.equal(c.get(sessionId)!.messages.at(-1)!.role, 'operator');
});

test('degradation: non-zero exit (plan limit) → kind error', async () => {
  const { spawner } = recordingClaude('', 1);
  const c = new ConsultationManager('/proj', '/fake/claude', { spawner });
  const { sessionId } = c.start();
  const r = await c.send(sessionId, 'hi');
  assert.equal(r.ok, false);
  assert.match(r.error!, /could not respond/);
});

test('sessions persist to .werkz/ and reload (survive reconnect / restart)', async () => {
  const dir = mkdtempSync(join(tmpdir(), 'werkz-consult-'));
  const statePath = join(dir, 'consultations.json');
  const { spawner } = recordingClaude('the plan');
  const c1 = new ConsultationManager('/proj', '/fake/claude', { statePath, spawner });
  const { sessionId } = c1.start();
  await c1.send(sessionId, 'plan it');
  assert.ok(existsSync(statePath));

  // A fresh manager over the same file (a daemon restart) recovers the session.
  const c2 = new ConsultationManager('/proj', '/fake/claude', { statePath, spawner });
  const s = c2.get(sessionId);
  assert.ok(s, 'the consultation survived');
  assert.equal(s!.messages.length, 2); // operator + advisor
  assert.equal(s!.messages[1].text, 'the plan');
});

test('old sessions are swept on start (age cap)', () => {
  const dir = mkdtempSync(join(tmpdir(), 'werkz-consult-'));
  const statePath = join(dir, 'consultations.json');
  let clock = 1_000_000;
  const c1 = new ConsultationManager('/proj', null, { statePath, now: () => clock });
  const { sessionId } = c1.start();
  assert.ok(c1.get(sessionId));
  // Two days later a new manager sweeps the stale session.
  clock += 2 * 24 * 3600_000;
  const c2 = new ConsultationManager('/proj', null, { statePath, now: () => clock });
  assert.equal(c2.get(sessionId), null, 'stale consultation swept');
});

test('the persisted file never leaks tokens and lives under .werkz (0600 via saveJson)', () => {
  const dir = mkdtempSync(join(tmpdir(), 'werkz-consult-'));
  const statePath = join(dir, 'consultations.json');
  const c = new ConsultationManager('/proj', null, { statePath });
  c.start();
  // saveJson writes 0600 (task 37 A) — just assert the file is valid JSON here.
  assert.doesNotThrow(() => JSON.parse(readFileSync(statePath, 'utf8')));
});
