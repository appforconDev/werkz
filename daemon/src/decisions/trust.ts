// Trust store (event-model.md §4.1 / GDD §4.1). Task 27: PERSISTED per
// WORKSHOP — the file lives in the project's .werkz state dir (trust.json),
// keyed by workerId, so trust survives daemon restarts AND phone re-pairs
// (pairing identity never touches it; before 27 the store was memory-only,
// which meant every daemon start silently reset every worker to 0).
//
// Lifecycle implemented here: the IMMEDIATE +1 per phone-approved decision
// (GDD §4.1) — applied by DecisionService on release. The refinements
// (−5 on a revert within 24h, −1 per decision ignored 48h, the no-revert
// qualifier on the +1) remain P2: they need revert detection, which does not
// exist yet. Trust never decays on calendar time (GDD hard rule).

import { loadJson, saveJson } from '../state/store.ts';

export class TrustStore {
  #trust = new Map<string, number>();
  #default: number;
  #persistPath: string | null;

  constructor(defaultTrust = 0, persistPath: string | null = null) {
    this.#default = defaultTrust;
    this.#persistPath = persistPath;
    if (persistPath) {
      for (const [k, v] of Object.entries(loadJson<Record<string, number>>(persistPath, {}))) {
        if (typeof v === 'number') this.#trust.set(k, v);
      }
    }
  }

  get(workerId: string): number {
    return this.#trust.get(workerId) ?? this.#default;
  }

  set(workerId: string, value: number): void {
    this.#trust.set(workerId, Math.max(0, Math.min(100, value)));
    this.#save();
  }

  /** GDD §4.1: +1 per approved decision (immediate; revert deduction is P2). */
  increment(workerId: string, by = 1): number {
    const next = Math.max(0, Math.min(100, this.get(workerId) + by));
    this.#trust.set(workerId, next);
    this.#save();
    return next;
  }

  #save(): void {
    if (this.#persistPath) saveJson(this.#persistPath, Object.fromEntries(this.#trust));
  }
}
