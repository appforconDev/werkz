// Decision router — classifies a PreToolUse call and decides how to respond.
// event-model.md §3.1 (classes), §3.2 (destructive), §3.5 (latency: this path
// must stay < 50 ms — no I/O, no await, pure in-memory).

import { classifyCommand, classifyFileTarget } from '../classifier/index.ts';
import type { DaemonConfig } from '../config.ts';

export type DecisionClass =
  | 'read'
  | 'routine'
  | 'small-diff'
  | 'large-diff'
  | 'destructive';

export type RouteAction = 'allow' | 'ask' | 'hold';

export interface ToolCall {
  toolName: string;
  toolInput: Record<string, unknown>;
}

export interface Classification {
  decisionClass: DecisionClass;
  destructiveCategory?: string;
  diffLines?: number;
}

export interface RouteResult {
  action: RouteAction;
  decisionClass: DecisionClass;
  reason: string;
}

const READ_TOOLS = new Set(['Read', 'Grep', 'Glob']);
const EDIT_TOOLS = new Set(['Edit', 'Write', 'NotebookEdit']);

// Bash read-only and routine heuristics (non-destructive path only —
// destructive is checked first and wins).
const READ_ONLY_BASH = /^\s*(ls|cat|pwd|echo|which|git\s+(status|log|diff|show|branch\b(?!\s+-D)|stash\s+list)|grep|rg|find(?!.*-delete)|head|tail|wc|stat|env|node\s+--version|npm\s+(ls|list|view|outdated))\b/;
const ROUTINE_BASH = /\b(npm|pnpm|yarn|bun)\s+(test|run|install|i|ci|add|build)\b|\b(vitest|jest|pytest|go\s+test|cargo\s+(test|build|add)|flutter\s+(test|analyze)|mix\s+test|rspec|make)\b|\bpip\s+install\b/;

// Broader "critical file" globs for large-diff escalation (secrets are caught
// by the destructive classifier separately).
const CRITICAL_GLOBS = [
  /(^|\/)\.github\/workflows\//i,
  /(^|\/)(package-lock\.json|pnpm-lock\.yaml|yarn\.lock|Cargo\.lock|pubspec\.lock)$/i,
  /(^|\/)(Dockerfile|docker-compose\.ya?ml)$/i,
  /\.env(\.|$)/i,
];

export function estimateDiffLines(toolName: string, input: Record<string, unknown>): number {
  if (toolName === 'Write') {
    const content = typeof input.content === 'string' ? input.content : '';
    return content.length === 0 ? 0 : content.split('\n').length;
  }
  if (toolName === 'Edit' || toolName === 'NotebookEdit') {
    const oldStr = typeof input.old_string === 'string' ? input.old_string : '';
    const newStr = typeof input.new_string === 'string' ? input.new_string : '';
    const oldLines = oldStr ? oldStr.split('\n').length : 0;
    const newLines = newStr ? newStr.split('\n').length : 0;
    return Math.max(oldLines, newLines);
  }
  return 0;
}

function isCriticalFile(path: string): boolean {
  return CRITICAL_GLOBS.some((re) => re.test(path));
}

/** Pure classification — no side effects, no I/O. */
export function classify(call: ToolCall, config: DaemonConfig): Classification {
  const { toolName, toolInput } = call;

  // Destructive wins over everything, for every tool.
  if (toolName === 'Bash') {
    const command = typeof toolInput.command === 'string' ? toolInput.command : '';
    const d = classifyCommand(command);
    if (d.destructive) return { decisionClass: 'destructive', destructiveCategory: d.categoryId };
    if (READ_ONLY_BASH.test(command)) return { decisionClass: 'read' };
    if (ROUTINE_BASH.test(command)) return { decisionClass: 'routine' };
    return { decisionClass: 'routine' }; // other bash defaults to routine (non-destructive)
  }

  if (READ_TOOLS.has(toolName)) return { decisionClass: 'read' };

  if (EDIT_TOOLS.has(toolName)) {
    const path = typeof toolInput.file_path === 'string' ? toolInput.file_path : '';
    const fileVerdict = classifyFileTarget(path);
    if (fileVerdict.destructive) {
      return { decisionClass: 'destructive', destructiveCategory: fileVerdict.categoryId };
    }
    const diffLines = estimateDiffLines(toolName, toolInput);
    if (diffLines >= config.smallDiffMaxLines || isCriticalFile(path)) {
      return { decisionClass: 'large-diff', diffLines };
    }
    return { decisionClass: 'small-diff', diffLines };
  }

  // Unknown / MCP / web tools: treat as routine activity (non-destructive,
  // non-editing). event-model.md §2.2 maps them to stations, not decisions.
  return { decisionClass: 'routine' };
}

/**
 * Decide the response for a classified call given current trust.
 * Returns 'allow' (auto-approve), 'ask' (let CC's dialog handle it), or
 * 'hold' (raise a requisition and block until the phone answers).
 */
export function route(
  cls: Classification,
  trust: number,
  config: DaemonConfig,
): RouteResult {
  const t = config.trustThresholds;
  const base = { decisionClass: cls.decisionClass };

  switch (cls.decisionClass) {
    case 'destructive':
      // Hard line — never auto, regardless of trust (GDD + §3.1).
      return { ...base, action: 'hold', reason: `destructive:${cls.destructiveCategory ?? 'unknown'}` };
    case 'large-diff':
      return { ...base, action: 'hold', reason: `large-diff:${cls.diffLines ?? '?'}lines` };
    case 'small-diff':
      return trust >= t.smallDiff
        ? { ...base, action: 'allow', reason: `trust ${trust} ≥ ${t.smallDiff}` }
        : { ...base, action: 'ask', reason: `trust ${trust} < ${t.smallDiff}` };
    case 'routine':
      return trust >= t.routine
        ? { ...base, action: 'allow', reason: `trust ${trust} ≥ ${t.routine}` }
        : { ...base, action: 'ask', reason: `trust ${trust} < ${t.routine}` };
    case 'read':
      return trust >= t.read
        ? { ...base, action: 'allow', reason: `trust ${trust} ≥ ${t.read}` }
        : { ...base, action: 'ask', reason: `trust ${trust} < ${t.read}` };
  }
}
