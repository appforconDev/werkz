// Pending-decision hold manager (event-model.md §3.4). Holds the PreToolUse
// http response open until the phone releases it, or the caller-chosen ceiling
// elapses. The ceiling is fixed when the hook opens — it cannot be extended
// (proven in the hold prototype).
//
// A hold can also be superseded early with a reason (task 17 A): the CC
// session's socket closed ('session-ended'), the ceiling elapsed
// ('hold-ceiling'), or the TTL sweep caught a zombie ('stale-ttl').

export type Decision = 'allow' | 'deny';
export type HoldOutcome = Decision | { superseded: string };

export interface PendingHandle {
  decisionId: string;
  key: string;
  resolve: (d: Decision) => void; // called by /release
  supersede: (reason: string) => void;
  promise: Promise<HoldOutcome>;
  openedAt: number;
}

export class PendingDecisions {
  #byId = new Map<string, PendingHandle>();
  #byKey = new Map<string, PendingHandle>();

  open(
    decisionId: string,
    key: string,
    ceilingSeconds: number,
    now: number = Date.now(),
  ): PendingHandle {
    let resolveFn!: (d: Decision) => void;
    let supersedeFn!: (reason: string) => void;
    let settled = false;
    const promise = new Promise<HoldOutcome>((res) => {
      resolveFn = (d: Decision) => {
        if (settled) return;
        settled = true;
        res(d);
      };
      supersedeFn = (reason: string) => {
        if (settled) return;
        settled = true;
        this.#drop(decisionId, key);
        res({ superseded: reason });
      };
      // Ceiling: superseded if unanswered (§3.4).
      const timer = setTimeout(() => supersedeFn('hold-ceiling'), ceilingSeconds * 1000);
      // Don't keep the process alive purely for a hold.
      if (typeof timer.unref === 'function') timer.unref();
    });

    const handle: PendingHandle = {
      decisionId, key, resolve: resolveFn, supersede: supersedeFn, promise, openedAt: now,
    };
    this.#byId.set(decisionId, handle);
    this.#byKey.set(key, handle);
    void promise.finally(() => this.#drop(decisionId, key));
    return handle;
  }

  release(decisionId: string, decision: Decision): boolean {
    const h = this.#byId.get(decisionId);
    if (!h) return false;
    h.resolve(decision);
    return true;
  }

  /** Supersede an open hold early (session died, TTL sweep). */
  supersede(decisionId: string, reason: string): boolean {
    const h = this.#byId.get(decisionId);
    if (!h) return false;
    h.supersede(reason);
    return true;
  }

  byKey(key: string): PendingHandle | undefined {
    return this.#byKey.get(key);
  }

  has(decisionId: string): boolean {
    return this.#byId.has(decisionId);
  }

  handles(): IterableIterator<PendingHandle> {
    return this.#byId.values();
  }

  get size(): number {
    return this.#byId.size;
  }

  #drop(decisionId: string, key: string): void {
    this.#byId.delete(decisionId);
    if (this.#byKey.get(key)?.decisionId === decisionId) this.#byKey.delete(key);
  }
}
