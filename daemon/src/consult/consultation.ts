// Advisor Consultation (backlog item 2) — chat WITH the Advisor to PLAN a job
// BEFORE dispatch. Planning, not execution. Zero keys: every turn spawns the
// user's OWN claude in PLAN MODE (read + reason, NEVER write/run — verified flag
// `--permission-mode plan` against the binary), same keyless path as narration
// (c270653). We hold the conversation history ourselves and send it each turn —
// CC's own context is not reused across spawns (provider-agnostic).
//
// Sessions persist in .werkz/ so a consultation survives app backgrounding /
// reconnect (and .werkz/ self-ignores, task 37 A — never leaks). Graceful: no
// claude / plan-limit / timeout ⇒ a loud-but-kind error, never a silent hang.

import { spawn } from 'node:child_process';
import { loadJson, saveJson } from '../state/store.ts';
import { uuidv7 } from '../util/id.ts';
import type { Spawner } from '../narration/narrate.ts';

export interface ConsultMessage { role: 'operator' | 'advisor'; text: string; at: number; }
export interface ConsultSession { id: string; messages: ConsultMessage[]; createdAt: number; updatedAt: number; }

// HARD plan-mode lock (task D): every consultation spawn carries these, always.
// Plan mode = read + reason, never write or run. Not a setting — a constant.
export const PLAN_ARGS = ['--permission-mode', 'plan', '--output-format', 'json'] as const;

const SYSTEM = [
  'You are the Advisor at WERKZ, a 1955 industrial-bureaucracy workshop, consulted by a',
  'developer to PLAN a coding job before it is dispatched to a worker. You are in PLAN',
  'MODE: you may read the repository and reason, but you must NEVER write files or run',
  'commands — you only advise. Reply in a dry, deadpan, bureaucratic tone (Severance/Portal),',
  'plain and concrete. Produce a clear, actionable plan the operator can hand to a worker.',
  'Keep it focused; no preamble, no sign-off.',
].join(' ');

const MSG_CAP = 8 * 1024;           // one operator message
const HISTORY_CAP = 40;             // turns kept (older trimmed from the front)
const TURN_TIMEOUT_MS = 120_000;    // per-turn ceiling — planning can be slow, but never hangs
const SESSION_MAX_AGE_MS = 24 * 3600_000; // consultations older than a day are swept

export interface SendResult { ok: boolean; reply?: string; error?: string; }

export class ConsultationManager {
  #projectDir: string;
  #claudePath: string | null;
  #statePath: string | null;
  #log: (m: string) => void;
  #spawner: Spawner;
  #now: () => number;
  #sessions = new Map<string, ConsultSession>();

  constructor(
    projectDir: string,
    claudePath: string | null,
    opts: { statePath?: string | null; log?: (m: string) => void; spawner?: Spawner; now?: () => number } = {},
  ) {
    this.#projectDir = projectDir;
    this.#claudePath = claudePath;
    this.#statePath = opts.statePath ?? null;
    this.#log = opts.log ?? (() => {});
    this.#spawner = opts.spawner ?? spawn;
    this.#now = opts.now ?? (() => Date.now());
    if (this.#statePath) {
      for (const s of loadJson<ConsultSession[]>(this.#statePath, [])) this.#sessions.set(s.id, s);
      this.#sweep();
    }
  }

  setClaudePath(path: string | null): void { this.#claudePath = path; }

  /** Start a fresh consultation. Returns its id. */
  start(): { sessionId: string } {
    this.#sweep();
    const now = this.#now();
    const s: ConsultSession = { id: uuidv7(now), messages: [], createdAt: now, updatedAt: now };
    this.#sessions.set(s.id, s);
    this.#persist();
    return { sessionId: s.id };
  }

  get(sessionId: string): ConsultSession | null {
    return this.#sessions.get(sessionId) ?? null;
  }

  end(sessionId: string): void {
    this.#sessions.delete(sessionId);
    this.#persist();
  }

  /**
   * One consultation turn: append the operator message, spawn plan-mode claude
   * with the whole (self-held) transcript, append the Advisor reply, persist.
   * Graceful: no claude / plan-limit / timeout ⇒ { ok:false, error } — a loud but
   * kind message for the phone, never a silent hang. The operator message stays
   * in history on failure so a retry doesn't lose it.
   */
  async send(sessionId: string, message: string): Promise<SendResult> {
    const s = this.#sessions.get(sessionId);
    if (!s) return { ok: false, error: 'consultation not found (it may have expired — start a new one)' };
    const text = message.trim().slice(0, MSG_CAP);
    if (!text) return { ok: false, error: 'empty message' };

    const now = this.#now();
    s.messages.push({ role: 'operator', text, at: now });
    if (s.messages.length > HISTORY_CAP) s.messages.splice(0, s.messages.length - HISTORY_CAP);
    s.updatedAt = now;
    this.#persist();

    if (!this.#claudePath) {
      this.#log('consult: no runnable claude — Advisor unavailable');
      return { ok: false, error: 'Advisor unavailable — no Claude found on this machine. (`werkz config claude-path`)' };
    }

    const prompt = this.#buildPrompt(s);
    const reply = await this.#spawnPlan(prompt);
    if (reply.error) {
      return { ok: false, error: reply.error };
    }
    s.messages.push({ role: 'advisor', text: reply.text!, at: this.#now() });
    s.updatedAt = this.#now();
    this.#persist();
    return { ok: true, reply: reply.text };
  }

  #buildPrompt(s: ConsultSession): string {
    const transcript = s.messages
      .map((m) => `${m.role === 'operator' ? 'OPERATOR' : 'ADVISOR'}: ${m.text}`)
      .join('\n\n');
    return `${SYSTEM}\n\n${transcript}\n\nADVISOR:`;
  }

  // Spawn claude in PLAN MODE (read+reason only), json output. Returns the
  // `result` text, or a friendly error. Never throws.
  #spawnPlan(prompt: string): Promise<{ text?: string; error?: string }> {
    return new Promise((resolve) => {
      let done = false;
      const finish = (v: { text?: string; error?: string }) => { if (!done) { done = true; resolve(v); } };
      let child: ReturnType<Spawner>;
      try {
        child = this.#spawner(this.#claudePath!, ['-p', prompt, ...PLAN_ARGS], {
          cwd: this.#projectDir,
          stdio: ['ignore', 'pipe', 'pipe'],
          env: process.env,
        });
      } catch {
        return finish({ error: 'Advisor unavailable — could not start Claude on this machine.' });
      }
      const timer = setTimeout(() => {
        try { child.kill('SIGKILL'); } catch { /* gone */ }
        finish({ error: 'The Advisor is taking too long — try again, or ask something smaller.' });
      }, TURN_TIMEOUT_MS);
      if (typeof timer.unref === 'function') timer.unref();

      let out = '';
      child.stdout?.on('data', (c) => { out += c; });
      child.on('error', () => { clearTimeout(timer); finish({ error: 'Advisor unavailable — Claude could not be started.' }); });
      child.on('exit', (code) => {
        clearTimeout(timer);
        if (code !== 0) return finish({ error: 'The Advisor could not respond (a plan limit or interruption). Try again shortly.' });
        try {
          const parsed = JSON.parse(out) as { result?: string };
          const t = typeof parsed.result === 'string' ? parsed.result.trim() : '';
          return t ? finish({ text: t }) : finish({ error: 'The Advisor returned nothing. Try rephrasing.' });
        } catch {
          const t = out.trim();
          return t ? finish({ text: t }) : finish({ error: 'The Advisor returned an unreadable response.' });
        }
      });
    });
  }

  #sweep(): void {
    const now = this.#now();
    let changed = false;
    for (const [id, s] of this.#sessions) {
      if (now - s.updatedAt > SESSION_MAX_AGE_MS) { this.#sessions.delete(id); changed = true; }
    }
    if (changed) this.#persist();
  }

  #persist(): void {
    if (this.#statePath) saveJson(this.#statePath, [...this.#sessions.values()]);
  }
}
