// Project identity (event-model.md §1). projectId derives from GIT identity:
// the remote origin URL if present, else the repo-root path hash. Consequence:
// worktrees, branches, and clones of the same repo map to the SAME workshop;
// multiple CC sessions in one repo = multiple workers, one building.
//
// The raw URL/path never leaves the daemon — only the hash is emitted.

import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

function git(cwd: string, args: string[]): string | null {
  try {
    return execFileSync('git', args, { cwd, encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }).trim();
  } catch {
    return null;
  }
}

/** Normalize remote URLs so ssh/https forms of the same repo collapse. */
export function normalizeRemote(url: string): string {
  let u = url.trim().toLowerCase();
  u = u.replace(/^git\+/, '');
  // git@host:owner/repo(.git) → host/owner/repo
  const scp = u.match(/^[^@]+@([^:]+):(.+)$/);
  if (scp) u = `${scp[1]}/${scp[2]}`;
  u = u.replace(/^[a-z]+:\/\//, '');       // strip scheme
  u = u.replace(/^[^@/]+@/, '');           // strip userinfo
  u = u.replace(/\.git$/, '').replace(/\/+$/, '');
  return u;
}

export interface ProjectIdentity {
  projectId: string;   // 12-hex hash, emitted
  source: 'remote' | 'path';
}

export function deriveProjectIdentity(cwd: string): ProjectIdentity {
  const remote = git(cwd, ['remote', 'get-url', 'origin']);
  if (remote) {
    const id = createHash('sha256').update('remote:' + normalizeRemote(remote)).digest('hex').slice(0, 12);
    return { projectId: id, source: 'remote' };
  }
  // Repo root if inside a git worktree, else cwd itself.
  const root = git(cwd, ['rev-parse', '--show-toplevel']) ?? cwd;
  const id = createHash('sha256').update('path:' + root).digest('hex').slice(0, 12);
  return { projectId: id, source: 'path' };
}
