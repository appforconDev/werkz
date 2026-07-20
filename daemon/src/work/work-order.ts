// Work-order dispatch (task 11 C — the initiate-loop, GDD daily loop "set the
// day's mission"). ONE directive → ONE headless agent job, run in the project
// root. The job is a `claude -p` invocation on the USER's own key/subscription
// (BYOK, their machine); because our PreToolUse hook is installed in that
// project, every tool call the job makes flows through the SAME decision
// pipeline (destructive rules, holds, phone approval) — proven headless in
// task 4. Cap: 1 concurrent job in v1.
//
// TERMINAL-EVENT RULE (task 13 A): every dispatched job MUST emit exactly one
// terminal event — job.completed{ok:true} on clean exit, or job.failed{reason,
// detail} on spawn error / non-zero exit. A job that vanishes is a bug of the
// same tier as a silent hang. We spawn an ABSOLUTE claude path (resolved once,
// no PATH surprise), capture stderr + exit code always, and guarantee one of the
// two events fires — including a watchdog if neither exit nor error arrives.

import { spawn, type ChildProcess } from 'node:child_process';
import type { EventBus } from '../events/bus.ts';
import { buildEvent } from '../adapter/cc/index.ts';
import { detectDirty, summarizeDiff, approveFiling, realGit, type GitRunner, type ApproveResult } from './completion-filing.ts';

export interface DispatchResult {
  ok: boolean;
  error?: string;
}

// Device-zone only (§4.3): a short, length-capped stderr tail for the on-phone
// incident feed. Never shared, never templated into a share card.
const DETAIL_CAP = 160;
function gameSafeDetail(stderr: string): string {
  const line = stderr.split('\n').map((s) => s.trim()).filter(Boolean).pop() ?? '';
  return line.length > DETAIL_CAP ? line.slice(0, DETAIL_CAP - 1) + '…' : line;
}

// Task 23B: the job's RESULT REPORT — the final assistant text from
// `claude -p --output-format json` (its `result` field: the closing summary,
// not the transcript). Device-zone like diffCore (§4.3): delivered to the phone
// for the completion report view, never into narration facts (the Haiku
// allowlist doesn't include it) and never onto a share surface. Capped so one
// chatty job can't bloat the event log; truncation is LOUD, never silent.
export const REPORT_CAP = 16 * 1024;
export const REPORT_TRUNCATION_MARKER = '\n\n[— REPORT TRUNCATED AT 16KB — full output remains in the terminal —]';
export function capReport(text: string): string {
  if (text.length <= REPORT_CAP) return text;
  return text.slice(0, REPORT_CAP - REPORT_TRUNCATION_MARKER.length) + REPORT_TRUNCATION_MARKER;
}

export class WorkOrderManager {
  #projectDir: string;
  #bus: EventBus;
  #projectId: string;
  #claudePath: string | null;
  #child: ChildProcess | null = null;
  #settled = false; // guards the terminal-event-once invariant
  #log: (m: string) => void;
  #git: GitRunner;
  // Form 22-C (task 38): the last completed job's filing summary, used as the
  // commit message when the operator right-swipes APPROVE. Null when the tree was
  // clean or nothing is pending.
  #pendingFiling: { summary: string | null } | null = null;
  #quietFilingLogged = false;

  constructor(
    projectDir: string,
    projectId: string,
    bus: EventBus,
    log: (m: string) => void = () => {},
    claudePath: string | null = null,
    git: GitRunner = realGit,
  ) {
    this.#projectDir = projectDir;
    this.#projectId = projectId;
    this.#bus = bus;
    this.#log = log;
    this.#claudePath = claudePath;
    this.#git = git;
  }

  get busy(): boolean {
    return this.#child !== null;
  }

  /** Update the resolved claude path (e.g. after `werkz config claude-path`). */
  setClaudePath(path: string | null): void {
    this.#claudePath = path;
  }

  /** Dispatch one directive as a headless job. Rejects if one is already running. */
  dispatch(directive: string): DispatchResult {
    if (this.#child) return { ok: false, error: 'a work order is already in progress (one at a time in v1)' };
    const text = directive.trim();
    if (!text) return { ok: false, error: 'empty directive' };

    // No runnable claude → fail LOUDLY and terminally, before spawning anything.
    if (!this.#claudePath) {
      this.#emit('worker.dispatched', 'info', { room: 'workshop-floor', source: 'work-order' });
      this.#settled = false;
      this.#fail('agent-unavailable', 'Claude Code not found — set it with `werkz config claude-path`.');
      return { ok: true }; // accepted then failed; the phone sees FILED → FAILED, never a vanish
    }

    this.#emit('worker.dispatched', 'info', { room: 'workshop-floor', source: 'work-order' });
    this.#log(`work order dispatched: ${text.length} chars via ${this.#claudePath}`);
    this.#settled = false;

    // Default permission mode → tool calls hit our hook and are decided from the
    // phone. Never acceptEdits (that would bypass the workshop).
    const child = spawn(this.#claudePath, ['-p', text, '--output-format', 'json'], {
      cwd: this.#projectDir,
      stdio: ['ignore', 'pipe', 'pipe'], // capture stdout (json) AND stderr (diagnostics) ALWAYS
      env: process.env,
    });
    this.#child = child;

    let out = '';
    let err = '';
    child.stdout?.on('data', (c) => { out += c; });
    child.stderr?.on('data', (c) => { err += c; });

    child.on('error', (e) => {
      // e.g. spawn failed (ENOENT/EACCES) — report a failed job, never crash.
      this.#fail('agent-unavailable', gameSafeDetail((e as Error).message));
    });

    child.on('exit', (code) => {
      if (code === 0) {
        let turns: number | undefined;
        let report: string | undefined;
        try {
          const parsed = JSON.parse(out) as { num_turns?: number; result?: string };
          turns = parsed.num_turns;
          // Task 23B: capture the final assistant text as the completion report
          // (device-zone, see capReport) — before this, the answer to "give me
          // an audit of root" lived only in the terminal and the phone got a
          // toast with nothing to read.
          if (typeof parsed.result === 'string' && parsed.result.trim()) {
            report = capReport(parsed.result.trim());
          }
        } catch { /* not json */ }
        // Form 22-C (task 38): if the job left uncommitted changes, the filing
        // (files + --stat) rides on job.completed INSTANTLY (git is sync); the
        // dry Haiku diff summary follows async as `filing.summary` so completion
        // is never delayed by the spawn. Both survive replay.
        this.#pendingFiling = null;
        let filing: object | undefined;
        let jobEventId: string | undefined;
        try {
          const dirty = detectDirty(this.#projectDir, this.#git);
          if (dirty) {
            filing = { files: dirty.files, fileCount: dirty.fileCount, stat: dirty.stat };
            this.#pendingFiling = { summary: null };
          }
        } catch { /* git unavailable → no card, never blocks the filing */ }
        jobEventId = this.#settle('job.completed', 'info', {
          source: 'work-order', ok: true,
          ...(turns !== undefined ? { turns } : {}),
          ...(report !== undefined ? { report } : {}),
          ...(filing ? { filing } : {}),
        });
        this.#log(`work order finished (exit 0${report ? `, report ${report.length} chars` : ', no report text'}${filing ? ', 22-C: uncommitted changes' : ''})`);
        if (filing && jobEventId) void this.#summarizeFiling(jobEventId);
      } else {
        this.#fail('nonzero-exit', gameSafeDetail(err) || `exited with code ${code ?? 'unknown'}`, code ?? undefined);
        this.#log(`work order FAILED (exit ${code ?? '?'})`);
      }
    });

    return { ok: true };
  }

  stop(): void {
    this.#child?.kill('SIGTERM');
    this.#child = null;
    this.#settled = true; // an operator stop is a terminal state; no event owed
  }

  #fail(reason: string, detail: string, code?: number): void {
    this.#settle('job.failed', 'attention', {
      source: 'work-order', ok: false, reason, ...(detail ? { detail } : {}), ...(code !== undefined ? { code } : {}),
    });
  }

  // Emit the ONE terminal event for this job and release the slot. Idempotent:
  // if both 'error' and 'exit' somehow fire, only the first is honored. Returns
  // the emitted event's id (or undefined if already settled) so the async filing
  // summary can reference it.
  #settle(eventType: string, severity: 'info' | 'attention', payload: object): string | undefined {
    if (this.#settled) return undefined;
    this.#settled = true;
    this.#child = null;
    return this.#emit(eventType, severity, payload);
  }

  #emit(eventType: string, severity: 'info' | 'attention', payload: object): string {
    const ev = buildEvent({
      sessionId: 'work-order', projectId: this.#projectId, workerId: 'WX-9B72',
      eventType, severity, payload,
    });
    this.#bus.emit(ev);
    return ev.eventId;
  }

  // Async: the dry Haiku diff summary → `filing.summary` (referencing the job's
  // completion event). Graceful: no claude / plan limit / timeout ⇒ no event, the
  // card keeps its raw --stat, logged ONCE dry. Never blocks the filing.
  async #summarizeFiling(jobEventId: string): Promise<void> {
    let summary: string | null = null;
    try {
      summary = await summarizeDiff(this.#projectDir, this.#git, this.#claudePath);
    } catch { summary = null; }
    if (this.#pendingFiling) this.#pendingFiling.summary = summary; // used as the commit message
    if (summary) {
      this.#emit('filing.summary', 'info', { refEventId: jobEventId, text: summary });
    } else if (!this.#quietFilingLogged) {
      this.#quietFilingLogged = true;
      this.#log('22-C: no diff summary (claude quiet) — card shows the raw --stat');
    }
  }

  /**
   * APPROVE FILING (task 38, right swipe): commit + push the uncommitted changes,
   * with the pending Haiku summary as the (Werkz-prefixed) commit message. Push
   * happens ONLY here — never auto, never on trust. Returns a loud reason on any
   * failure; the changes stay put. .werkz/ is excluded by its own .gitignore
   * (task 37 A), so credentials never ride along.
   */
  approveFiling(): ApproveResult {
    const res = approveFiling(this.#projectDir, this.#pendingFiling?.summary ?? null, this.#git);
    if (res.ok) this.#pendingFiling = null;
    return res;
  }
}
