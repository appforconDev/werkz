// Claude Code adapter (adapter #1) — translates CC hook payloads posted to
// the daemon's /cc-hook endpoint into internal WerkzEvents.
// Taxonomy: docs/event-model.md §2. Unknown hook events are dropped with a
// debug log — never an error.

import type { WerkzEvent } from '../../events/types.ts';

export interface CcHookPayload {
  hook_event_name: string;
  session_id?: string;
  [key: string]: unknown;
}

export function translate(_payload: CcHookPayload): WerkzEvent | null {
  // TODO(P1): implement per event-model.md §2 taxonomy table.
  return null;
}
