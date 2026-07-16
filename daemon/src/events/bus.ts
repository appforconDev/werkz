// Internal event bus — in-memory fan-out + JSONL persistence (P1-grade).
// The app will subscribe over the LAN protocol later; for now subscribers are
// in-process and events are appended to a JSONL file for inspection.
//
// Only game-safe envelopes cross this bus. The adapter strips raw payloads
// (event-model.md §4.3) before emitting; `raw` is never persisted here.

import { appendFileSync } from 'node:fs';
import type { WerkzEvent } from './types.ts';

type Subscriber = (event: WerkzEvent) => void;

export class EventBus {
  #subscribers = new Set<Subscriber>();
  #logPath: string | null;

  constructor(logPath: string | null = null) {
    this.#logPath = logPath;
  }

  subscribe(fn: Subscriber): () => void {
    this.#subscribers.add(fn);
    return () => this.#subscribers.delete(fn);
  }

  emit(event: WerkzEvent): void {
    if (this.#logPath) {
      const { raw: _raw, ...safe } = event; // never persist adapter-private raw
      appendFileSync(this.#logPath, JSON.stringify(safe) + '\n');
    }
    for (const fn of this.#subscribers) fn(event);
  }
}
