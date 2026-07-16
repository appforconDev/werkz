import { test } from 'node:test';
import assert from 'node:assert/strict';
import { DecisionService } from './service.ts';
import { EventBus } from '../events/bus.ts';
import { defaultConfig } from '../config.ts';
import { TrustStore } from './trust.ts';
import type { WerkzEvent } from '../events/types.ts';

function svc(trustValue = 100) {
  const events: WerkzEvent[] = [];
  const bus = new EventBus();
  bus.subscribe((e) => events.push(e));
  const trust = new TrustStore();
  trust.set('WX-7A19', trustValue);
  return { service: new DecisionService(defaultConfig, bus, trust), events };
}

test('non-decision call replies allow instantly and emits task.started', async () => {
  const { service, events } = svc(100);
  const r = await service.handlePreToolUse({
    hook_event_name: 'PreToolUse', session_id: 's1', tool_name: 'Read', tool_input: { file_path: 'a.ts' },
  });
  assert.equal(r.response.hookSpecificOutput.permissionDecision, 'allow');
  assert.equal(r.route.decisionClass, 'read');
  assert.ok(r.routingLatencyMs < 50);
  assert.equal(events.at(-1)?.eventType, 'task.started');
});

test('low trust routine replies ask (no hold)', async () => {
  const { service } = svc(0);
  const r = await service.handlePreToolUse({
    hook_event_name: 'PreToolUse', session_id: 's1', tool_name: 'Bash', tool_input: { command: 'npm test' },
  });
  assert.equal(r.response.hookSpecificOutput.permissionDecision, 'ask');
});

// Read the decisionId the service put in the emitted decision.requested event.
function pendingDecisionId(events: WerkzEvent[]): string {
  const req = events.find((e) => e.eventType === 'decision.requested');
  assert.ok(req, 'decision.requested emitted');
  const id = (req!.payload as { decisionId?: string }).decisionId;
  assert.ok(id, 'decisionId present in payload');
  return id!;
}

test('destructive holds, then phone release=deny blocks and emits decision.requested+denied', async () => {
  const { service, events } = svc(100);
  const p = service.handlePreToolUse({
    hook_event_name: 'PreToolUse', session_id: 's1', tool_name: 'Bash', tool_input: { command: 'rm -rf build' },
  });
  await new Promise((r) => setTimeout(r, 20));
  assert.equal(service.pendingCount, 1);
  service.release(pendingDecisionId(events), 'deny');
  const result = await p;
  assert.equal(result.response.hookSpecificOutput.permissionDecision, 'deny');
  assert.ok(events.some((e) => e.eventType === 'decision.denied'));
});

test('dedup: retry-after-deny within window reuses prior outcome, no second hold', async () => {
  const { service, events } = svc(100);
  const input = { command: 'git push --force' };
  const p1 = service.handlePreToolUse({ hook_event_name: 'PreToolUse', session_id: 's1', tool_name: 'Bash', tool_input: input });
  await new Promise((r) => setTimeout(r, 20));
  service.release(pendingDecisionId(events), 'deny');
  await p1;

  const before = events.filter((e) => e.eventType === 'decision.requested').length;
  const r2 = await service.handlePreToolUse({ hook_event_name: 'PreToolUse', session_id: 's1', tool_name: 'Bash', tool_input: input });
  const after = events.filter((e) => e.eventType === 'decision.requested').length;

  assert.equal(r2.deduped, true);
  assert.equal(r2.response.hookSpecificOutput.permissionDecision, 'deny');
  assert.equal(after, before, 'no second requisition raised for the retry');
});
