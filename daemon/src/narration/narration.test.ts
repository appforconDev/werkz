// Task 30 E: zero-key narration — the engine spawns the user's own `claude`
// (Haiku print mode). No API key store anymore. Tests use an injected fake
// spawner so nothing real is launched.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { EventEmitter } from 'node:events';
import { NarrationEngine } from './engine.ts';
import { narrateWithClaude, type Spawner } from './narrate.ts';
import { EventBus } from '../events/bus.ts';
import { buildEvent } from '../adapter/cc/index.ts';
import type { WerkzEvent } from '../events/types.ts';

// A fake child process: emits `out` on stdout then exits with `code`.
function fakeSpawner(out: string, code = 0, opts: { throwSync?: boolean; errorAsync?: boolean } = {}): Spawner {
  return ((/* cmd, args, spawnOpts */) => {
    if (opts.throwSync) throw new Error('ENOENT');
    const child = new EventEmitter() as EventEmitter & { stdout: EventEmitter; kill: () => void };
    child.stdout = new EventEmitter();
    child.kill = () => {};
    queueMicrotask(() => {
      if (opts.errorAsync) { child.emit('error', new Error('spawn failed')); return; }
      if (out) child.stdout.emit('data', out);
      child.emit('exit', code);
    });
    return child as unknown as ReturnType<Spawner>;
  }) as unknown as Spawner;
}

function decisionEvent(): WerkzEvent {
  return buildEvent({
    sessionId: 's', projectId: 'p', workerId: 'WX-7A19',
    eventType: 'decision.requested', severity: 'decision',
    payload: { decisionClass: 'destructive', destructiveCategory: 'redirect-overwrite', room: 'workshop-floor', toolCategory: 'Bash' },
  });
}

test('narrateWithClaude: spawns claude and returns the trimmed line', async () => {
  const line = await narrateWithClaude(
    { event: decisionEvent(), narrationClass: 'situational' },
    '/fake/claude',
    fakeSpawner('  Requisition 47-B filed. Awaiting stamp.\n'),
  );
  assert.equal(line, 'Requisition 47-B filed. Awaiting stamp.');
});

test('narrateWithClaude: null claude path → null (no binary, quiet)', async () => {
  const line = await narrateWithClaude({ event: decisionEvent(), narrationClass: 'situational' }, null, fakeSpawner('x'));
  assert.equal(line, null);
});

test('narrateWithClaude: non-zero exit (plan limit / refusal) → null', async () => {
  const line = await narrateWithClaude(
    { event: decisionEvent(), narrationClass: 'situational' }, '/fake/claude', fakeSpawner('nope', 1));
  assert.equal(line, null);
});

test('narrateWithClaude: spawn throws / errors → null (graceful)', async () => {
  const sync = await narrateWithClaude(
    { event: decisionEvent(), narrationClass: 'situational' }, '/fake/claude', fakeSpawner('', 0, { throwSync: true }));
  assert.equal(sync, null);
  const asyncErr = await narrateWithClaude(
    { event: decisionEvent(), narrationClass: 'situational' }, '/fake/claude', fakeSpawner('', 0, { errorAsync: true }));
  assert.equal(asyncErr, null);
});

test('engine: no claude path → no narration.ready (absence path)', async () => {
  const events: WerkzEvent[] = [];
  const bus = new EventBus();
  bus.subscribe((e) => events.push(e));
  const logs: string[] = [];
  new NarrationEngine(bus, null, { log: (m) => logs.push(m) });

  bus.emit(decisionEvent());
  bus.emit(decisionEvent()); // twice — the quiet notice logs only ONCE
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(events.filter((e) => e.eventType === 'narration.ready').length, 0);
  assert.equal(logs.filter((l) => l.includes('quiet')).length, 1, 'logged once, dry');
});

test('engine: with claude → emits narration.ready referencing the source event', async () => {
  const events: WerkzEvent[] = [];
  const bus = new EventBus();
  bus.subscribe((e) => events.push(e));
  new NarrationEngine(bus, '/fake/claude', { spawner: fakeSpawner('Requisition 47-B filed.') });

  const src = decisionEvent();
  bus.emit(src);
  for (let i = 0; i < 30 && !events.some((e) => e.eventType === 'narration.ready'); i++) {
    await new Promise((r) => setTimeout(r, 10));
  }
  const narration = events.find((e) => e.eventType === 'narration.ready');
  assert.ok(narration, 'narration.ready emitted');
  const payload = narration!.payload as { refEventId: string; text: string; source: string };
  assert.equal(payload.refEventId, src.eventId);
  assert.equal(payload.source, 'claude');
  assert.match(payload.text, /Requisition/);
});

test('engine: routine events are not narrated (keeps LLM cost down, §4.1)', async () => {
  const events: WerkzEvent[] = [];
  const bus = new EventBus();
  bus.subscribe((e) => events.push(e));
  new NarrationEngine(bus, '/fake/claude', { spawner: fakeSpawner('should not fire') });

  bus.emit(buildEvent({
    sessionId: 's', projectId: 'p', workerId: 'WX-7A19',
    eventType: 'task.started', severity: 'info', payload: { room: 'archive', toolCategory: 'Read' },
  }));
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(events.filter((e) => e.eventType === 'narration.ready').length, 0);
});
