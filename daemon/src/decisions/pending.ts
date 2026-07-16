// Pending-decision hold manager (event-model.md §3.4). Holds the PreToolUse
// http response open until the phone releases it, or the caller-chosen ceiling
// elapses. The ceiling is fixed when the hook opens — it cannot be extended
// (proven in the hold prototype).

export type Decision = 'allow' | 'deny';

export interface PendingHandle {
  decisionId: string;
  key: string;
  resolve: (d: Decision) => void; // called by /release
  promise: Promise<Decision | 'superseded'>;
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
    let settled = false;
    const promise = new Promise<Decision | 'superseded'>((res) => {
      resolveFn = (d: Decision) => {
        if (settled) return;
        settled = true;
        res(d);
      };
      // Ceiling: superseded if unanswered (§3.4).
      const timer = setTimeout(() => {
        if (settled) return;
        settled = true;
        this.#drop(decisionId, key);
        res('superseded');
      }, ceilingSeconds * 1000);
      // Don't keep the process alive purely for a hold.
      if (typeof timer.unref === 'function') timer.unref();
    });

    const handle: PendingHandle = { decisionId, key, resolve: resolveFn, promise, openedAt: now };
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

  byKey(key: string): PendingHandle | undefined {
    return this.#byKey.get(key);
  }

  get size(): number {
    return this.#byId.size;
  }

  #drop(decisionId: string, key: string): void {
    this.#byId.delete(decisionId);
    if (this.#byKey.get(key)?.decisionId === decisionId) this.#byKey.delete(key);
  }
}
