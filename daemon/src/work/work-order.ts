// Work-order dispatch (task 11 C — the initiate-loop, GDD daily loop "set the
// day's mission"). ONE directive → ONE headless agent job, run in the project
// root. The job is a `claude -p` invocation on the USER's own key/subscription
// (BYOK, their machine); because our PreToolUse hook is installed in that
// project, every tool call the job makes flows through the SAME decision
// pipeline (destructive rules, holds, phone approval) — proven headless in
// task 4. Cap: 1 concurrent job in v1.

import { spawn, type ChildProcess } from 'node:child_process';
import type { EventBus } from '../events/bus.ts';
import { buildEvent } from '../adapter/cc/index.ts';

export interface DispatchResult {
  ok: boolean;
  error?: string;
}

export class WorkOrderManager {
  #projectDir: string;
  #bus: EventBus;
  #projectId: string;
  #child: ChildProcess | null = null;
  #log: (m: string) => void;

  constructor(projectDir: string, projectId: string, bus: EventBus, log: (m: string) => void = () => {}) {
    this.#projectDir = projectDir;
    this.#projectId = projectId;
    this.#bus = bus;
    this.#log = log;
  }

  get busy(): boolean {
    return this.#child !== null;
  }

  /** Dispatch one directive as a headless job. Rejects if one is already running. */
  dispatch(directive: string): DispatchResult {
    if (this.#child) return { ok: false, error: 'a work order is already in progress (one at a time in v1)' };
    const text = directive.trim();
    if (!text) return { ok: false, error: 'empty directive' };

    this.#emit('worker.dispatched', 'info', { room: 'workshop-floor', source: 'work-order' });
    this.#log(`work order dispatched: ${text.length} chars`);

    // Default permission mode → tool calls hit our hook and are decided from the
    // phone. Never acceptEdits (that would bypass the workshop).
    const child = spawn('claude', ['-p', text, '--output-format', 'json'], {
      cwd: this.#projectDir,
      stdio: ['ignore', 'pipe', 'ignore'],
      env: process.env,
    });
    this.#child = child;

    let out = '';
    child.stdout?.on('data', (c) => { out += c; });
    child.on('error', () => {
      // e.g. `claude` not on PATH — report a failed job rather than crash.
      this.#emit('job.completed', 'attention', { source: 'work-order', ok: false, reason: 'agent-unavailable' });
      this.#child = null;
    });
    child.on('exit', (code) => {
      let turns: number | undefined;
      try { turns = (JSON.parse(out) as { num_turns?: number }).num_turns; } catch { /* not json */ }
      // Game-safe summary only — no raw result text crosses the boundary (§4.3).
      this.#emit('job.completed', 'info', {
        source: 'work-order', ok: code === 0, ...(turns !== undefined ? { turns } : {}),
      });
      this.#log(`work order finished (exit ${code})`);
      this.#child = null;
    });
    return { ok: true };
  }

  stop(): void {
    this.#child?.kill('SIGTERM');
    this.#child = null;
  }

  #emit(eventType: string, severity: 'info' | 'attention', payload: object): void {
    this.#bus.emit(buildEvent({
      sessionId: 'work-order', projectId: this.#projectId, workerId: 'WX-9B72',
      eventType, severity, payload,
    }));
  }
}
