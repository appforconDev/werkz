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
  type DiffLine,
  preToolUseEvent,
  buildEvent,
  buildDiffCore,
  roomForTool,
} from '../adapter/cc/index.ts';
import { deriveProjectIdentity } from '../adapter/cc/project.ts';
import { decisionKey, uuidv7 } from '../util/id.ts';
import { loadJson, saveJson } from '../state/store.ts';

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

// Liveness of the CC hook connection holding a decision open (task 17 A). The
// http layer wires this to the request socket; a decision whose socket is gone
// can never be answered and must be superseded, not left as a zombie.
export interface HoldConnection {
  onClose(cb: () => void): void;
  isClosed(): boolean;
}

// View of a pending decision for the app. Categories/counts are game-safe;
// `diffCore` is device-zone only (§4.3) — shown in the overlay, never
// persisted to disk, never shared.
export interface PendingSummary {
  decisionId: string;
  decisionClass: string;
  room: string;
  toolCategory: string;
  destructiveCategory?: string;
  diffLines?: number;
  diffCore?: DiffLine[];
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
  // decisionId → the hook connection holding it (when opened via http).
  #connections = new Map<string, HoldConnection>();
  #pendingStatePath: string | null;
  #lastPermissionMode: string | null = null;

  constructor(config: DaemonConfig, bus: EventBus, trust = new TrustStore(), pendingStatePath: string | null = null) {
    this.#config = config;
    this.#bus = bus;
    this.#trust = trust;
    this.#dedup = new DedupStore(config.decisionDedupWindowSeconds);
    this.#pendingStatePath = pendingStatePath;
  }

  #persistPending(): void {
    if (!this.#pendingStatePath) return;
    // Strip diffCore before writing to disk — it is device-zone only (§4.3)
    // and recovery/supersede never needs it.
    const safe = [...this.#pendingSummaries.values()].map(({ diffCore: _d, ...rest }) => rest);
    saveJson(this.#pendingStatePath, safe);
  }

  /**
   * Recover after a restart (task 7 §4). Any decision that was open when the
   * daemon died belonged to a CC hook whose connection is now dead (the CLI
   * fell back the moment we dropped) — it can never be answered. So we emit
   * `decision.superseded` for each and clear: expired cleanly, never silently
   * lost. Returns the count recovered. Call once at startup, after subscribers
   * are attached.
   */
  recoverPending(): number {
    if (!this.#pendingStatePath) return 0;
    const leftover = loadJson<PendingSummary[]>(this.#pendingStatePath, []);
    for (const s of leftover) {
      this.#bus.emit(
        buildEvent({
          sessionId: 'recovered',
          projectId: 'recovered',
          workerId: null,
          eventType: 'decision.superseded',
          severity: 'info',
          payload: { decisionId: s.decisionId, decisionClass: s.decisionClass, reason: 'daemon-restart' },
        }),
      );
    }
    this.#pendingSummaries.clear();
    this.#persistPending();
    return leftover.length;
  }

  get pendingCount(): number {
    return this.#pending.size;
  }

  /**
   * Only decisions with a LIVE held connection (task 17 A3). A summary whose
   * hold is gone, or whose hook socket has closed, is a zombie — it is
   * superseded on sight and never reaches a snapshot. Holds opened without
   * connection info (direct calls in tests) count as live while held.
   */
  listPending(): PendingSummary[] {
    const live: PendingSummary[] = [];
    for (const s of this.#pendingSummaries.values()) {
      if (!this.#pending.has(s.decisionId)) continue; // settling — not live
      const conn = this.#connections.get(s.decisionId);
      if (conn?.isClosed()) {
        this.supersede(s.decisionId, 'session-ended'); // missed close event
        continue;
      }
      live.push(s);
    }
    return live;
  }

  release(decisionId: string, decision: 'allow' | 'deny'): boolean {
    return this.#pending.release(decisionId, decision);
  }

  /** Supersede an open hold early (session died, TTL sweep). */
  supersede(decisionId: string, reason: string): boolean {
    return this.#pending.supersede(decisionId, reason);
  }

  /**
   * TTL sweep (task 17 A2), run on a timer — not just at boot. Supersedes any
   * open hold whose hook socket has closed (missed close event), and any hold
   * older than the pending TTL: no legitimate ceiling reaches that age, so it
   * is a zombie by definition. Returns the number superseded.
   */
  sweepStale(now: number = Date.now()): number {
    const ttlMs = this.#config.pendingTtlHours * 3_600_000;
    let n = 0;
    for (const h of [...this.#pending.handles()]) {
      const conn = this.#connections.get(h.decisionId);
      if (conn?.isClosed()) {
        if (this.supersede(h.decisionId, 'session-ended')) n++;
      } else if (now - h.openedAt > ttlMs) {
        if (this.supersede(h.decisionId, 'stale-ttl')) n++;
      }
    }
    return n;
  }

  /** Dev/testing + P2 calibration: seed a worker's trust directly. */
  setTrust(workerId: string, value: number): void {
    this.#trust.set(workerId, value);
  }

  /**
   * Latest CC permission mode seen, and whether it's permissive (autopilot).
   * Permissive modes decide without the user — the app warns when the daemon
   * would be bypassed. default/plan are NOT permissive.
   */
  permissionModeSummary(): { mode: string | null; autopilot: boolean } {
    const mode = this.#lastPermissionMode;
    const permissive = new Set(['acceptEdits', 'auto', 'dontAsk', 'bypassPermissions']);
    return { mode, autopilot: mode ? permissive.has(mode) : false };
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

  /**
   * Non-decision replies synchronously; decision replies await the phone.
   * `connection` (when opened via http) is the CC hook socket: if it closes
   * mid-hold the session is dead and the decision is superseded IMMEDIATELY
   * (task 17 A1) — never left for restart recovery to find.
   */
  async handlePreToolUse(
    payload: CcHookPayload,
    now: number = Date.now(),
    connection?: HoldConnection,
  ): Promise<HandleResult> {
    const t0 = performance.now();
    if (typeof payload.permission_mode === 'string' && payload.permission_mode !== this.#lastPermissionMode) {
      this.#lastPermissionMode = payload.permission_mode;
      // Tell connected clients so the autopilot banner updates live.
      const summary = this.permissionModeSummary();
      this.#bus.emit(
        buildEvent({
          sessionId: 'building', projectId: 'building', workerId: null,
          eventType: 'session.mode', severity: 'info',
          payload: { mode: summary.mode, autopilot: summary.autopilot },
        }),
      );
    }
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

    // Raise the requisition and hold. diffCore is device-zone only (§4.3).
    const decisionId = uuidv7(now);
    const diffCore = buildDiffCore(toolName, toolInput);
    this.#bus.emit(
      preToolUseEvent(ctx, toolName, cls.decisionClass, true, {
        diffLines: cls.diffLines,
        destructiveCategory: cls.destructiveCategory,
        command,
        decisionId,
        diffCore,
      }),
    );
    this.#pendingSummaries.set(decisionId, {
      decisionId,
      decisionClass: cls.decisionClass,
      room: roomForTool(toolName, command),
      toolCategory: toolName,
      ...(cls.destructiveCategory ? { destructiveCategory: cls.destructiveCategory } : {}),
      ...(cls.diffLines !== undefined ? { diffLines: cls.diffLines } : {}),
      diffCore,
      openedAt: new Date(now).toISOString(),
    });
    this.#persistPending();
    const ceiling = this.#holdCeilingSeconds(ctx.sessionId, now);
    const handle = this.#pending.open(decisionId, key, ceiling, now);
    if (connection) {
      this.#connections.set(decisionId, connection);
      connection.onClose(() => this.supersede(decisionId, 'session-ended'));
    }
    const outcome = await handle.promise;
    this.#pendingSummaries.delete(decisionId);
    this.#connections.delete(decisionId);
    this.#persistPending();

    if (typeof outcome !== 'string') {
      // decisionId rides the event so the app can drop exactly this requisition.
      this.#bus.emit(
        buildEvent({
          sessionId: ctx.sessionId,
          projectId: ctx.projectId,
          workerId: ctx.workerId,
          eventType: 'decision.superseded',
          severity: 'info',
          payload: { decisionId, decisionClass: cls.decisionClass, reason: outcome.superseded, ceilingSeconds: ceiling },
        }),
      );
      return { response: reply('ask', `superseded: ${outcome.superseded}`), routingLatencyMs, route: r, decisionId };
    }

    this.#dedup.record(key, outcome, Date.now());
    this.#bus.emit(
      buildEvent({
        sessionId: ctx.sessionId,
        projectId: ctx.projectId,
        workerId: ctx.workerId,
        eventType: outcome === 'allow' ? 'decision.approved' : 'decision.denied',
        severity: 'info',
        payload: { decisionId, decisionClass: cls.decisionClass },
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
