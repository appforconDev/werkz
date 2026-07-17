// Preflight diagnostics (task 13 B — Rickard's design). The daemon checks its
// own environment at startup and exposes the result to the phone, so a broken
// dependency surfaces as a clear, actionable banner instead of a silent failure
// (a dispatched job that can never run). Every future dependency gets a check
// here — the rule is: no silent degradation.
//
// Checks are game-safe: ids/labels/versions and a short actionable hint, never
// raw repo strings. This object rides /status and the WS welcome frame.

import { resolveClaudePath, type ClaudeResolution } from '../util/claude-path.ts';
import { isHookInstalled } from '../install/hooks.ts';

export interface PreflightCheck {
  id: 'claude' | 'hook' | 'node' | 'port';
  label: string;       // short human label ("Claude Code")
  ok: boolean;
  detail: string;      // one-line status ("v2.1.187" / "not found on PATH")
  hint?: string;       // actionable fix when !ok
}

export interface Preflight {
  ok: boolean;         // AND of every check → the app dispatch-gate
  checks: PreflightCheck[];
  claudePath: string | null; // resolved absolute path (for WorkOrderManager)
}

const MIN_NODE_MAJOR = 22;

export interface PreflightInput {
  projectDir: string;
  configClaudePath?: string | null;
  port: number;
  portBindable?: boolean; // set by the CLI once listen() succeeds/fails
}

export function runPreflight(input: PreflightInput): Preflight {
  const checks: PreflightCheck[] = [];

  // 1. Claude Code binary — the dispatch dependency.
  const claude: ClaudeResolution = resolveClaudePath(input.configClaudePath);
  checks.push(claude.path
    ? { id: 'claude', label: 'Claude Code', ok: true, detail: claude.version ?? `found (${claude.source})` }
    : {
        id: 'claude', label: 'Claude Code', ok: false, detail: 'not found',
        hint: 'Install Claude Code, or point Werkz at it: werkz config claude-path /path/to/claude',
      });

  // 2. Our PreToolUse hook installed in this project.
  const hook = isHookInstalled(input.projectDir);
  checks.push(hook
    ? { id: 'hook', label: 'Decision hook', ok: true, detail: 'installed in this project' }
    : {
        id: 'hook', label: 'Decision hook', ok: false, detail: 'not installed',
        hint: 'Run npx werkz in the project root, then restart your Claude Code session.',
      });

  // 3. Node runtime version.
  const major = Number(process.versions.node.split('.')[0]);
  checks.push(major >= MIN_NODE_MAJOR
    ? { id: 'node', label: 'Node runtime', ok: true, detail: `v${process.versions.node}` }
    : {
        id: 'node', label: 'Node runtime', ok: false, detail: `v${process.versions.node} (need ${MIN_NODE_MAJOR}+)`,
        hint: `Upgrade Node to ${MIN_NODE_MAJOR} or newer.`,
      });

  // 4. Port bindable — reported by the CLI after listen() resolves.
  const portOk = input.portBindable !== false;
  checks.push(portOk
    ? { id: 'port', label: 'LAN port', ok: true, detail: `${input.port} bound` }
    : {
        id: 'port', label: 'LAN port', ok: false, detail: `${input.port} in use`,
        hint: `Another process holds port ${input.port}. Stop it, or start with --port <n>.`,
      });

  return { ok: checks.every((c) => c.ok), checks, claudePath: claude.path };
}
