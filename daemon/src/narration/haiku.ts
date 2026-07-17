// BYOK Haiku narration (task 9, event-model.md §4). Turns a game-safe event
// into one dry, bureaucratic line via the user's own Anthropic key. Runs on the
// user's key only — our backend never proxies this (GDD §6, BYOK).
//
// Verified against platform.claude.com/docs (2026-07-17): model
// `claude-haiku-4-5`, POST https://api.anthropic.com/v1/messages, headers
// x-api-key + anthropic-version: 2023-06-01, body { model, max_tokens, messages }.
// Raw fetch (Node 22 global) is used deliberately — the daemon stays lean and
// this is a single short completion, not worth pulling in the full SDK.
//
// SANITIZER (§4.3): only the game-safe fields below are sent — categories,
// counts, counters. Never raw command/content/paths/diffCore.

import type { WerkzEvent } from '../events/types.ts';

const ENDPOINT = 'https://api.anthropic.com/v1/messages';
const MODEL = 'claude-haiku-4-5';
const ANTHROPIC_VERSION = '2023-06-01';

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

/** Returns one narration line, or null on any failure (caller falls back to a template). */
export async function narrateWithHaiku(
  input: NarrationInput,
  apiKey: string,
  signal?: AbortSignal,
): Promise<string | null> {
  try {
    const res = await fetch(ENDPOINT, {
      method: 'POST',
      signal,
      headers: {
        'content-type': 'application/json',
        'x-api-key': apiKey,
        'anthropic-version': ANTHROPIC_VERSION,
      },
      body: JSON.stringify({
        model: MODEL,
        max_tokens: 60,
        system: SYSTEM,
        messages: [{ role: 'user', content: `Event: ${factsFor(input)}` }],
      }),
    });
    if (!res.ok) return null;
    const data = (await res.json()) as { content?: Array<{ type: string; text?: string }> };
    const text = data.content?.find((b) => b.type === 'text')?.text?.trim();
    return text && text.length > 0 ? text : null;
  } catch {
    return null; // network/timeout/abort → template fallback
  }
}
