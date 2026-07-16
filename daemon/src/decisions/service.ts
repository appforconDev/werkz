// Decision service — the vertical slice's core. Ties classify → route → dedup
// → (instant reply | hold) → emit WerkzEvents. event-model.md §3.
//
// Non-decision path is synchronous and must stay under the latency budget
// (§3.5): no I/O, no await before replying. Decision path awaits the phone.

import type { DaemonConfig } from '../config.ts';
import { EventBus } from '../events/bus.ts';
import { classify, route, type RouteResult } from '../router/index.ts';
import { DedupStore } from '../router/dedup.ts';
import { PendingDecisions } from './pending.ts';
import { TrustStore } from './trust.ts';
import {
  type CcHookPayload,
  preToolUseEvent,
  buildEvent,
  roomForTool,
} from '../adapter/cc/index.ts';
import { deriveProjectIdentity } from '../adapter/cc/project.ts';
import { decisionKey, uuidv7 } from '../util/id.ts';

export interface HookResponse {
  hookSpecificOutput: {
    hookEventName: 'PreToolUse';
    permissionDecision: 'allow' | 'deny' | 'ask';
    permissionDecisionReason: string;
  };
}

export interface HandleResult {
  response: HookResponse;
  routingLatencyMs: number; // time to CLASSIFY+ROUTE (the budgeted part), not the hold
  route: RouteResult;
  decisionId?: string;      // present when the call is held
  deduped?: boolean;
}

// Game-safe view of a pending decision (no raw command/content — §4.3).
export interface PendingSummary {
  decisionId: string;
  decisionClass: string;
  room: string;
  toolCategory: string;
  destructiveCategory?: string;
  diffLines?: number;
  openedAt: string;
}

function reply(decision: 'allow' | 'deny' | 'ask', reason: string): HookResponse {
  return {
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: decision,
      permissionDecisionReason: reason,
    },
  };
}

export class DecisionService {
  #config: DaemonConfig;
  #bus: EventBus;
  #dedup: DedupStore;
  #pending = new PendingDecisions();
  #trust: TrustStore;
  // CC session_id → internal { sessionId, workerId, projectId (cached) }
  #sessions = new Map<string, { sessionId: string; workerId: string; projectId: string }>();
  #lastActivity = new Map<string, number>(); // internal sessionId → ms of last interactive signal
  // Game-safe summaries of open decisions, for the phone to GET /pending.
  #pendingSummaries = new Map<string, PendingSummary>();

  constructor(config: DaemonConfig, bus: EventBus, trust = new TrustStore()) {
    this.#config = config;
    this.#bus = bus;
    this.#trust = trust;
    this.#dedup = new DedupStore(config.decisionDedupWindowSeconds);
  }

  get pendingCount(): number {
    return this.#pending.size;
  }

  listPending(): PendingSummary[] {
    return [...this.#pendingSummaries.values()];
  }

  release(decisionId: string, decision: 'allow' | 'deny'): boolean {
    return this.#pending.release(decisionId, decision);
  }

  /** Dev/testing + P2 calibration: seed a worker's trust directly. */
  setTrust(workerId: string, value: number): void {
    this.#trust.set(workerId, value);
  }

  #sessionCtx(payload: CcHookPayload): { sessionId: string; workerId: string; projectId: string } {
    const ccId = payload.session_id ?? 'unknown';
    let mapped = this.#sessions.get(ccId);
    if (!mapped) {
      // Deterministic primary persona per session for this slice. projectId is
      // derived from git identity ONCE here (subprocess) and cached — never on
      // the per-call latency path (§3.5).
      mapped = {
        sessionId: uuidv7(),
        workerId: 'WX-7A19',
        projectId: deriveProjectIdentity(payload.cwd ?? process.cwd()).projectId,
      };
      this.#sessions.set(ccId, mapped);
    }
    return mapped;
  }

  /** Chooses the hold ceiling once, at hook open (§3.4). */
  #holdCeilingSeconds(sessionId: string, now: number): number {
    const last = this.#lastActivity.get(sessionId) ?? 0;
    const atKeyboard = now - last <= this.#config.terminalActivityWindowMinutes * 60_000;
    return atKeyboard ? this.#config.keyboardHoldSeconds : this.#config.awayHoldSeconds;
  }

  /** Non-decision replies synchronously; decision replies await the phone. */
  async handlePreToolUse(payload: CcHookPayload, now: number = Date.now()): Promise<HandleResult> {
    const t0 = performance.now();
    const ctx = this.#sessionCtx(payload);
    const toolName = payload.tool_name ?? 'Unknown';
    const toolInput = payload.tool_input ?? {};
    const command = typeof toolInput.command === 'string' ? toolInput.command : undefined;

    const cls = classify({ toolName, toolInput }, this.#config);
    const trust = this.#trust.get(ctx.workerId);
    const r = route(cls, trust, this.#config);
    const routingLatencyMs = performance.now() - t0;

    // Non-decision path: reply immediately (budget-critical).
    if (r.action !== 'hold') {
      this.#bus.emit(
        preToolUseEvent(ctx, toolName, cls.decisionClass, false, {
          diffLines: cls.diffLines,
          destructiveCategory: cls.destructiveCategory,
          command,
        }),
      );
      return { response: reply(r.action, r.reason), routingLatencyMs, route: r };
    }

    // Decision path. Dedup first (§3.6): a retry within the window reuses the
    // prior outcome instead of raising a second requisition.
    const key = decisionKey(ctx.sessionId, toolName, toolInput);
    const prior = this.#dedup.lookup(key, now);
    if (prior) {
      return {
        response: reply(prior, `deduped: prior ${prior} within window`),
        routingLatencyMs,
        route: r,
        deduped: true,
      };
    }

    // Raise the requisition and hold.
    const decisionId = uuidv7(now);
    this.#bus.emit(
      preToolUseEvent(ctx, toolName, cls.decisionClass, true, {
        diffLines: cls.diffLines,
        destructiveCategory: cls.destructiveCategory,
        command,
        decisionId,
      }),
    );
    this.#pendingSummaries.set(decisionId, {
      decisionId,
      decisionClass: cls.decisionClass,
      room: roomForTool(toolName, command),
      toolCategory: toolName,
      ...(cls.destructiveCategory ? { destructiveCategory: cls.destructiveCategory } : {}),
      ...(cls.diffLines !== undefined ? { diffLines: cls.diffLines } : {}),
      openedAt: new Date(now).toISOString(),
    });
    const ceiling = this.#holdCeilingSeconds(ctx.sessionId, now);
    const handle = this.#pending.open(decisionId, key, ceiling, now);
    const outcome = await handle.promise;
    this.#pendingSummaries.delete(decisionId);

    if (outcome === 'superseded') {
      this.#bus.emit(
        buildEvent({
          sessionId: ctx.sessionId,
          projectId: ctx.projectId,
          workerId: ctx.workerId,
          eventType: 'decision.superseded',
          severity: 'info',
          payload: { decisionClass: cls.decisionClass, ceilingSeconds: ceiling },
        }),
      );
      return { response: reply('ask', 'hold ceiling reached — superseded'), routingLatencyMs, route: r, decisionId };
    }

    this.#dedup.record(key, outcome, Date.now());
    this.#bus.emit(
      buildEvent({
        sessionId: ctx.sessionId,
        projectId: ctx.projectId,
        workerId: ctx.workerId,
        eventType: outcome === 'allow' ? 'decision.approved' : 'decision.denied',
        severity: 'info',
        payload: { decisionClass: cls.decisionClass },
      }),
    );
    return { response: reply(outcome, `phone released: ${outcome}`), routingLatencyMs, route: r, decisionId };
  }

  /** Record an interactive signal (UserPromptSubmit etc.) for §3.4 timing. */
  noteActivity(payload: CcHookPayload, now: number = Date.now()): void {
    const ctx = this.#sessionCtx(payload);
    this.#lastActivity.set(ctx.sessionId, now);
  }
}
