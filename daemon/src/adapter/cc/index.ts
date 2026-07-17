// Claude Code adapter (adapter #1) — translates CC hook payloads into internal
// WerkzEvents. Taxonomy: event-model.md §2. Unknown hook events are dropped
// with a debug log — never an error. Nothing CC-specific leaves this module.

import { createHash } from 'node:crypto';
import type { WerkzEvent, Severity } from '../../events/types.ts';
import { uuidv7 } from '../../util/id.ts';
import type { DecisionClass } from '../../router/index.ts';

export interface CcHookPayload {
  hook_event_name?: string;
  session_id?: string;
  cwd?: string;
  tool_name?: string;
  tool_input?: Record<string, unknown>;
  permission_mode?: string;
  [key: string]: unknown;
}

// event-model.md §1: projectId is a hash of the project root — the raw path
// never leaves the daemon.
export function projectIdFromCwd(cwd: string | undefined): string {
  return createHash('sha256').update(cwd ?? 'unknown').digest('hex').slice(0, 12);
}

// §2.2 tool → room mapping (subset needed for this slice).
export function roomForTool(toolName: string, command?: string): string {
  if (toolName === 'Bash') {
    if (command && /\b(test|vitest|jest|pytest|go test|cargo test|flutter test|rspec)\b/.test(command)) {
      return 'test-workshop';
    }
    return 'workshop-floor';
  }
  if (toolName === 'Read' || toolName === 'Grep' || toolName === 'Glob') return 'archive';
  if (toolName === 'Edit' || toolName === 'Write' || toolName === 'NotebookEdit') return 'workshop-floor';
  return 'workshop-floor';
}

// Diff core for the decision overlay (event-model.md §4.3: device-zone only —
// this carries raw repo strings and must NEVER reach the share zone or be
// persisted to disk). Returns structured lines so the app tints +/-/context.
export interface DiffLine { sign: '+' | '-' | ' '; text: string }

export function buildDiffCore(toolName: string, input: Record<string, unknown>): DiffLine[] {
  const asLines = (s: string, sign: DiffLine['sign']): DiffLine[] =>
    s.split('\n').map((text) => ({ sign, text }));
  if (toolName === 'Bash') {
    const cmd = typeof input.command === 'string' ? input.command : '';
    return cmd.split('\n').map((text) => ({ sign: ' ' as const, text: '$ ' + text }));
  }
  if (toolName === 'Write') {
    return asLines(typeof input.content === 'string' ? input.content : '', '+');
  }
  if (toolName === 'Edit' || toolName === 'NotebookEdit') {
    const oldStr = typeof input.old_string === 'string' ? input.old_string : '';
    const newStr = typeof input.new_string === 'string' ? input.new_string : '';
    return [...(oldStr ? asLines(oldStr, '-') : []), ...(newStr ? asLines(newStr, '+') : [])];
  }
  return [];
}

interface BuildArgs {
  sessionId: string;         // internal session id (adapter-mapped)
  projectId: string;
  workerId: string | null;
  eventType: string;
  severity: Severity;
  payload: object;
}

export function buildEvent(args: BuildArgs): WerkzEvent {
  return {
    eventId: uuidv7(),
    schemaVersion: 1,
    timestamp: new Date().toISOString(),
    sessionId: args.sessionId,
    projectId: args.projectId,
    workerId: args.workerId,
    eventType: args.eventType,
    severity: args.severity,
    payload: args.payload,
  };
}

// A PreToolUse translates to either task.started (non-decision) or
// decision.requested (decision class). Payload is game-safe: tool category,
// room, class, and line counts only — never raw file contents (§4.3).
export function preToolUseEvent(
  ctx: { sessionId: string; projectId: string; workerId: string | null },
  toolName: string,
  decisionClass: DecisionClass,
  isDecision: boolean,
  extras: { diffLines?: number; destructiveCategory?: string; command?: string; decisionId?: string; diffCore?: DiffLine[] },
): WerkzEvent {
  return buildEvent({
    sessionId: ctx.sessionId,
    projectId: ctx.projectId,
    workerId: ctx.workerId,
    eventType: isDecision ? 'decision.requested' : 'task.started',
    severity: isDecision ? 'decision' : 'info',
    payload: {
      room: roomForTool(toolName, extras.command),
      toolCategory: toolName, // category, not raw command/content
      decisionClass,
      // decisionId is how the app releases a held decision (§3.4).
      ...(extras.decisionId ? { decisionId: extras.decisionId } : {}),
      ...(extras.diffLines !== undefined ? { diffLines: extras.diffLines } : {}),
      ...(extras.destructiveCategory ? { destructiveCategory: extras.destructiveCategory } : {}),
      // Device-zone only (§4.3): the diff core shown in the overlay. Never
      // persisted, never shared.
      ...(isDecision && extras.diffCore ? { diffCore: extras.diffCore } : {}),
    },
  });
}
