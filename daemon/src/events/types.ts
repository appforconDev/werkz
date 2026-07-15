// Internal event schema — verbatim from docs/event-model.md §1.
// Nothing downstream of the adapter may reference provider concepts.

export type Severity = 'info' | 'attention' | 'decision' | 'incident';

export interface WerkzEvent {
  eventId: string;          // uuidv7 (time-ordered)
  schemaVersion: 1;         // integer, bump on breaking change; adapters pin the version they emit
  timestamp: string;        // ISO-8601, daemon clock
  sessionId: string;        // internal session, NOT the CC session_id (adapter maps)
  projectId: string;        // hash of project root path — raw path never leaves the daemon
  workerId: string | null;  // stable persona id; null for building-level events
  eventType: string;        // dot-namespaced, see event-model.md §2 taxonomy
  severity: Severity;
  payload: object;          // per-type; game-safe fields only (event-model.md §4.3)
  raw?: object;             // adapter-private original payload; NEVER serialized past the daemon boundary
}
