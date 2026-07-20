// Zero-key narration (task 30 E). Turns a game-safe event into one dry,
// bureaucratic line by spawning the USER'S OWN `claude` binary in one-shot
// print mode with a Haiku model flag — no API key anywhere. Same BYOK spirit
// (their compute, their auth), zero setup: if they can run `claude`, narration
// works. Replaces the removed x-api-key path (BYOK key store retired).
//
// SANITIZER (§4.3): only the game-safe fields below reach the model —
// categories, counts, counters. Never raw command/content/paths/diffCore.
//
// Graceful degradation: ANY failure (no binary, spawn error, non-zero exit,
// plan/limit refusal, timeout) returns null and the app renders its dry
// template. A quiet workshop is not an error.

import { spawn } from 'node:child_process';
import type { WerkzEvent } from '../events/types.ts';

const MODEL = 'claude-haiku-4-5';
const TIMEOUT_MS = 15_000;

const SYSTEM = [
  'You are the narrator for WERKZ, a 1955 industrial-bureaucracy game where a',
  "developer's coding agents are workers in a workshop.",
  'Given a game event, write ONE dry, deadpan line of factory-bureaucracy',
  'narration (requisitions, stamps, incident reports). Severance/Portal tone —',
  'never clownish, never an exclamation. Describe only what the event states.',
  'Max 18 words. No quotes, no preamble, output only the line.',
].join(' ');

export interface NarrationInput {
  event: WerkzEvent;
  narrationClass: 'routine' | 'situational' | 'golden';
  counters?: Record<string, number>;
}

function factsFor(input: NarrationInput): string {
  const p = input.event.payload as Record<string, unknown>;
  const facts: Record<string, unknown> = {
    eventType: input.event.eventType,
    class: input.narrationClass,
  };
  // Allowlist of game-safe fields (§4.3) — no raw strings from the repo.
  for (const k of ['room', 'toolCategory', 'decisionClass', 'destructiveCategory', 'diffLines']) {
    if (p[k] !== undefined) facts[k] = p[k];
  }
  if (input.counters) facts.counters = input.counters;
  return JSON.stringify(facts);
}

// Injectable spawn (tests substitute a fake) — mirrors the work-order pattern.
export type Spawner = typeof spawn;

/**
 * One narration line, or null on ANY failure (caller falls back to a template).
 * Spawns `<claude> -p <prompt> --model claude-haiku-4-5 --output-format text`
 * with the system prompt prepended (headless print mode has no separate system
 * flag, so it rides the prompt). Never throws.
 */
export function narrateWithClaude(
  input: NarrationInput,
  claudePath: string | null,
  spawner: Spawner = spawn,
): Promise<string | null> {
  return promptClaudeLine(`${SYSTEM}\n\nEvent: ${factsFor(input)}`, claudePath, spawner);
}

/**
 * Shared one-shot Haiku spawn (task 32/38): `<claude> -p <prompt> --model
 * claude-haiku-4-5 --output-format text`. Returns the trimmed output, or null on
 * ANY failure (no binary, spawn error, non-zero exit, plan limit, timeout) — the
 * caller degrades gracefully. Never throws. Used by narration AND the Form 22-C
 * diff summary.
 */
export function promptClaudeLine(
  prompt: string,
  claudePath: string | null,
  spawner: Spawner = spawn,
): Promise<string | null> {
  if (!claudePath) return Promise.resolve(null);
  return new Promise((resolve) => {
    let done = false;
    const finish = (v: string | null) => {
      if (done) return;
      done = true;
      resolve(v);
    };
    let child: ReturnType<Spawner>;
    try {
      child = spawner(claudePath, ['-p', prompt, '--model', MODEL, '--output-format', 'text'], {
        stdio: ['ignore', 'pipe', 'ignore'],
        env: process.env,
      });
    } catch {
      return finish(null); // spawn threw synchronously (ENOENT/EACCES)
    }
    const timer = setTimeout(() => {
      try { child.kill('SIGKILL'); } catch { /* already gone */ }
      finish(null);
    }, TIMEOUT_MS);
    if (typeof timer.unref === 'function') timer.unref();

    let out = '';
    child.stdout?.on('data', (c) => { out += c; });
    child.on('error', () => { clearTimeout(timer); finish(null); }); // spawn failed async
    child.on('exit', (code) => {
      clearTimeout(timer);
      if (code !== 0) return finish(null); // plan limit / refusal / crash → quiet
      const text = out.trim();
      finish(text.length > 0 ? text : null);
    });
  });
}
