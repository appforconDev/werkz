// Trust store (event-model.md §4.1 / GDD §4.1). In-memory for this slice;
// persistence and the full lifecycle (+1 after 24h no-revert, −5 on revert,
// −1 on expiry) land in P2. For now it holds per-worker trust and applies
// the immediate deltas the router/decision flow needs.

export class TrustStore {
  #trust = new Map<string, number>();
  #default: number;

  constructor(defaultTrust = 0) {
    this.#default = defaultTrust;
  }

  get(workerId: string): number {
    return this.#trust.get(workerId) ?? this.#default;
  }

  set(workerId: string, value: number): void {
    this.#trust.set(workerId, Math.max(0, Math.min(100, value)));
  }
}
