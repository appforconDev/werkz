// Narration engine (task 9 → task 30 E). Subscribes to the bus and turns
// qualifying events into a real Haiku line by spawning the user's own `claude`
// binary (zero keys — BYOK key store retired in task 30). Emitted as a separate
// `narration.ready` event referencing the source event.
//
// Fire-and-forget: this is a bus subscriber (the bus already isolates
// subscribers), and narration runs async off the routing path — it can NEVER
// block a PreToolUse decision (§3.5). No claude / spawn failure / plan limit ⇒
// nothing emitted and the app renders its dry templates. A quiet workshop is
// not an error (logged once, dry tone).

import type { EventBus } from '../events/bus.ts';
import type { WerkzEvent } from '../events/types.ts';
import { narrateWithClaude, type Spawner } from './narrate.ts';
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
  'worker.dispatched',  // a work order was filed
  'job.completed',      // the dispatched job finished
]);

export class NarrationEngine {
  #bus: EventBus;
  #claudePath: string | null;
  #spawner: Spawner | undefined;
  #log: (m: string) => void;
  #quietLogged = false;
  #inFlight = 0;
  #maxConcurrent = 2;

  constructor(
    bus: EventBus,
    claudePath: string | null,
    opts: { log?: (m: string) => void; spawner?: Spawner } = {},
  ) {
    this.#bus = bus;
    this.#claudePath = claudePath;
    this.#spawner = opts.spawner;
    this.#log = opts.log ?? ((m) => console.log(m));
    bus.subscribe((e) => this.#onEvent(e));
  }

  /** Update the resolved claude path (e.g. after `werkz config claude-path`). */
  setClaudePath(path: string | null): void {
    this.#claudePath = path;
  }

  #onEvent(event: WerkzEvent): void {
    if (!NARRATABLE.has(event.eventType)) return;
    if (!this.#claudePath) {
      if (!this.#quietLogged) {
        this.#quietLogged = true;
        this.#log('narration: no runnable claude found — workshop stays quiet (dry templates only)');
      }
      return;
    }
    if (this.#inFlight >= this.#maxConcurrent) return; // shed load rather than queue unbounded

    this.#inFlight++;
    void narrateWithClaude({ event, narrationClass: 'situational' }, this.#claudePath, this.#spawner)
      .then((text) => {
        if (text) {
          this.#bus.emit(
            buildEvent({
              sessionId: event.sessionId,
              projectId: event.projectId,
              workerId: event.workerId,
              eventType: 'narration.ready',
              severity: 'info',
              payload: { refEventId: event.eventId, text, source: 'claude' },
            }),
          );
        }
      })
      .finally(() => {
        this.#inFlight--;
      });
  }
}
