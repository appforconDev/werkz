// Narration engine (task 9, event-model.md §4). Subscribes to the bus and, when
// a narration key is present, turns qualifying events into a real Haiku line —
// emitted as a separate `narration.ready` event referencing the source event.
//
// Fire-and-forget: this is a bus subscriber (the bus already isolates
// subscribers), and narration runs async off the routing path — it can NEVER
// block a PreToolUse decision (§3.5). When no key is present, the engine does
// nothing and the app renders its dry templates.

import type { EventBus } from '../events/bus.ts';
import type { WerkzEvent } from '../events/types.ts';
import type { NarrationKeyStore } from './key-store.ts';
import { narrateWithHaiku } from './haiku.ts';
import { buildEvent } from '../adapter/cc/index.ts';

// Which events get a real LLM line. Routine per-tool churn stays templated in
// the app (§4.1: ~80% dry log, no LLM); decisions and session beats are where a
// narrated line earns its cost.
const NARRATABLE = new Set([
  'decision.requested',
  'decision.approved',
  'decision.denied',
  'session.started',
  'test.workshop.fire',
  'key.accepted',       // proof-of-life: first narrated line the moment a key is set
  'worker.dispatched',  // a work order was filed
  'job.completed',      // the dispatched job finished
]);

export class NarrationEngine {
  #bus: EventBus;
  #keys: NarrationKeyStore;
  #inFlight = 0;
  #maxConcurrent = 2;

  constructor(bus: EventBus, keys: NarrationKeyStore) {
    this.#bus = bus;
    this.#keys = keys;
    bus.subscribe((e) => this.#onEvent(e));
  }

  #onEvent(event: WerkzEvent): void {
    if (!NARRATABLE.has(event.eventType)) return;
    if (!this.#keys.hasKey()) return;
    if (this.#inFlight >= this.#maxConcurrent) return; // shed load rather than queue unbounded
    const key = this.#keys.getKey();
    if (!key) return;

    this.#inFlight++;
    void narrateWithHaiku({ event, narrationClass: 'situational' }, key)
      .then((text) => {
        if (text) {
          this.#bus.emit(
            buildEvent({
              sessionId: event.sessionId,
              projectId: event.projectId,
              workerId: event.workerId,
              eventType: 'narration.ready',
              severity: 'info',
              payload: { refEventId: event.eventId, text, source: 'haiku' },
            }),
          );
        }
      })
      .finally(() => {
        this.#inFlight--;
      });
  }
}
