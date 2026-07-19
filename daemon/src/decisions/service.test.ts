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

test('read at trust 0 auto-allows — a fresh workshop can look around (task 27)', async () => {
  const { service, events } = svc(0);
  const r = await service.handlePreToolUse({
    hook_event_name: 'PreToolUse', session_id: 's1', tool_name: 'Bash', tool_input: { command: 'pwd' },
  });
  assert.equal(r.response.hookSpecificOutput.permissionDecision, 'allow');
  assert.equal(r.route.decisionClass, 'read');
  assert.equal(events.at(-1)?.eventType, 'task.started');
});

test('low trust routine HOLDS: the requisition reaches the phone, never a silent outcome (task 27)', async () => {
  const { service, events } = svc(0);
  const p = service.handlePreToolUse({
    hook_event_name: 'PreToolUse', session_id: 's1', tool_name: 'Bash', tool_input: { command: 'npm test' },
  });
  await new Promise((r) => setTimeout(r, 20));
  // The core product promise: an unclear decision is VISIBLE on the phone.
  assert.equal(service.listPending().length, 1, 'a requisition must be raised');
  const req = events.find((e) => e.eventType === 'decision.requested');
  assert.ok(req, 'decision.requested emitted for a below-threshold routine call');

  service.release(service.listPending()[0].decisionId, 'allow');
  const r = await p;
  assert.equal(r.response.hookSpecificOutput.permissionDecision, 'allow');
  assert.match(r.response.hookSpecificOutput.permissionDecisionReason, /APPROVED by the operator/);
});

test('no phone connected: the hold waits its window, then tells the agent it is AWAITING approval — never a refusal (task 27)', async () => {
  const events: WerkzEvent[] = [];
  const bus = new EventBus();
  bus.subscribe((e) => events.push(e));
  const trust = new TrustStore(); // fresh workshop, trust 0
  const cfg = { ...defaultConfig, keyboardHoldSeconds: 0.05, awayHoldSeconds: 0.05 };
  const service = new DecisionService(cfg, bus, trust);
  const r = await service.handlePreToolUse({
    hook_event_name: 'PreToolUse', session_id: 's1', tool_name: 'Bash', tool_input: { command: 'npm test' },
  });
  // The ceiling elapsed unanswered → CC's own dialog is the fallback ('ask'),
  // and the reason tells the agent this is a wait, not a block.
  assert.equal(r.response.hookSpecificOutput.permissionDecision, 'ask');
  assert.match(r.response.hookSpecificOutput.permissionDecisionReason, /NOT a refusal/);
  assert.match(r.response.hookSpecificOutput.permissionDecisionReason, /awaiting operator approval/);
  assert.ok(events.some((e) => e.eventType === 'decision.requested'), 'the requisition was raised while holding');
  assert.ok(events.some((e) => e.eventType === 'decision.superseded'), 'the elapsed hold superseded loudly');
});

test('phone-approved decision raises trust by 1 (GDD §4.1 immediate credit)', async () => {
  const events: WerkzEvent[] = [];
  const bus = new EventBus();
  bus.subscribe((e) => events.push(e));
  const trust = new TrustStore();
  trust.set('WX-7A19', 10);
  const service = new DecisionService(defaultConfig, bus, trust);
  const p = service.handlePreToolUse({
    hook_event_name: 'PreToolUse', session_id: 's1', tool_name: 'Bash', tool_input: { command: 'npm test' },
  });
  await new Promise((r) => setTimeout(r, 20));
  service.release(service.listPending()[0].decisionId, 'allow');
  await p;
  assert.equal(trust.get('WX-7A19'), 11, '+1 on approve');
  const approved = events.find((e) => e.eventType === 'decision.approved');
  assert.equal((approved!.payload as { trust?: number }).trust, 11, 'new trust rides the event');
});

test('phone-DENIED decision tells the agent not to retry, and trust is unchanged', async () => {
  const { service } = svc(10);
  const p = service.handlePreToolUse({
    hook_event_name: 'PreToolUse', session_id: 's1', tool_name: 'Bash', tool_input: { command: 'npm test' },
  });
  await new Promise((r) => setTimeout(r, 20));
  service.release(service.listPending()[0].decisionId, 'deny');
  const r = await p;
  assert.equal(r.response.hookSpecificOutput.permissionDecision, 'deny');
  assert.match(r.response.hookSpecificOutput.permissionDecisionReason, /DENIED by the operator/);
  assert.match(r.response.hookSpecificOutput.permissionDecisionReason, /note the denial in your report/);
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
