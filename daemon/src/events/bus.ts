// Internal event bus — in-memory fan-out + JSONL persistence (P1-grade).
// Subscribers are fire-and-forget: emit() must never block the PreToolUse
// routing path (§3.5), so subscriber exceptions are swallowed here.
//
// Only game-safe envelopes cross this bus. The adapter strips raw payloads
// (event-model.md §4.3) before emitting; `raw` is never persisted.

import { appendFileSync, existsSync, readFileSync } from 'node:fs';
import type { WerkzEvent } from './types.ts';

type Subscriber = (event: WerkzEvent) => void;

export class EventBus {
  #subscribers = new Set<Subscriber>();
  #logPath: string | null;
  #recent: WerkzEvent[] = []; // in-memory replay buffer when no logPath
  #recentCap = 1000;

  constructor(logPath: string | null = null) {
    this.#logPath = logPath;
  }

  subscribe(fn: Subscriber): () => void {
    this.#subscribers.add(fn);
    return () => this.#subscribers.delete(fn);
  }

  emit(event: WerkzEvent): void {
    const { raw: _raw, ...safe } = event; // never persist adapter-private raw
    if (this.#logPath) {
      appendFileSync(this.#logPath, JSON.stringify(safe) + '\n');
    } else {
      this.#recent.push(safe as WerkzEvent);
      if (this.#recent.length > this.#recentCap) this.#recent.shift();
    }
    for (const fn of this.#subscribers) {
      try {
        fn(safe as WerkzEvent);
      } catch {
        // A slow/broken subscriber must never break event routing.
      }
    }
  }

  /**
   * Replay events emitted after `lastEventId` (exclusive). eventId is uuidv7
   * (time-ordered), and the log/buffer is in emit order, so "after" = every
   * entry following the matching id. If the id isn't found (log rotated/gap),
   * returns all available events so the client resyncs rather than silently
   * missing state.
   */
  replayAfter(lastEventId: string | null): WerkzEvent[] {
    const all = this.#allEvents();
    if (!lastEventId) return all;
    const idx = all.findIndex((e) => e.eventId === lastEventId);
    return idx === -1 ? all : all.slice(idx + 1);
  }

  #allEvents(): WerkzEvent[] {
    if (!this.#logPath) return [...this.#recent];
    if (!existsSync(this.#logPath)) return [];
    const lines = readFileSync(this.#logPath, 'utf8').split('\n').filter(Boolean);
    const out: WerkzEvent[] = [];
    for (const line of lines) {
      try {
        out.push(JSON.parse(line) as WerkzEvent);
      } catch {
        // skip malformed trailing writes
      }
    }
    return out;
  }
}
