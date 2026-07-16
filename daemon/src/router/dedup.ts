// Decision dedup (event-model.md §3.6): retry-after-deny re-fires PreToolUse
// for the same logical decision. Within the dedup window, a repeat key reuses
// the prior outcome instead of raising a second requisition.

export type DedupOutcome = 'allow' | 'deny';

interface Entry {
  outcome: DedupOutcome;
  at: number; // ms
}

export class DedupStore {
  #entries = new Map<string, Entry>();
  #windowMs: number;

  constructor(windowSeconds: number) {
    this.#windowMs = windowSeconds * 1000;
  }

  /** Returns a still-valid prior outcome for this key, or null. */
  lookup(key: string, now: number = Date.now()): DedupOutcome | null {
    const e = this.#entries.get(key);
    if (!e) return null;
    if (now - e.at > this.#windowMs) {
      this.#entries.delete(key);
      return null;
    }
    return e.outcome;
  }

  record(key: string, outcome: DedupOutcome, now: number = Date.now()): void {
    this.#entries.set(key, { outcome, at: now });
  }
}
