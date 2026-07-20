// Form 22-C — Completion Filing (backlog item 3). When a dispatched job finishes
// but leaves UNCOMMITTED changes, the operator gets a swipe card: right =
// commit+push, left = leave them and log. This module is the daemon side:
//
//  A. DETECT — on job.completed, read `git status --porcelain` in the job's dir.
//     Clean tree → no filing (silent). Dirty → gather the file list + `git diff
//     --stat`, capped, and a dry Haiku one-line summary (spawned on the user's
//     own claude, same path as narration). Graceful: no claude / plan limit /
//     timeout ⇒ the card still ships with the raw --stat, no summary, logged once.
//  C. APPROVE — commit + push. Push happens ONLY here (explicit right-swipe),
//     never on trust, never auto. A failed push returns its reason loudly; the
//     changes stay put. `git add -A` respects .werkz/.gitignore (task 37 A) so
//     credentials can never ride along.

import { spawnSync } from 'node:child_process';
import { promptClaudeLine, type Spawner } from '../narration/narrate.ts';

// Injectable git so tests don't need a real repo. Mirrors spawnSync's shape.
export interface GitResult { status: number | null; stdout: string; stderr: string; }
export type GitRunner = (args: string[], cwd: string) => GitResult;

export const realGit: GitRunner = (args, cwd) => {
  const r = spawnSync('git', args, { cwd, encoding: 'utf8' });
  return { status: r.status, stdout: r.stdout ?? '', stderr: r.stderr ?? '' };
};

// Caps — same spirit as the 16KB report cap; a chatty diff can't bloat the event.
export const FILING_FILES_CAP = 60;         // file list length
export const FILING_STAT_CAP = 4 * 1024;    // --stat text
export const FILING_DIFF_CAP = 16 * 1024;   // diff sent to Haiku

// The git-derived filing (INSTANT — rides on job.completed). The Haiku summary
// arrives separately (a `filing.summary` follow-up event) so job.completed is
// never delayed by the spawn, and both survive replay.
export interface Filing {
  files: string[];      // porcelain paths — device-zone (real repo paths, never shared)
  fileCount: number;    // real total (files[] may be capped)
  stat: string;         // `git diff --stat` tail, capped
}

/** Parse `git status --porcelain` into a clean file list (drops the XY prefix). */
function parsePorcelain(porcelain: string): string[] {
  return porcelain.split('\n').map((l) => l.trimEnd()).filter(Boolean).map((l) => {
    // "XY path" or "XY orig -> path" (rename)
    const path = l.slice(3);
    const arrow = path.indexOf(' -> ');
    return arrow >= 0 ? path.slice(arrow + 4) : path;
  });
}

const SUMMARY_SYSTEM = [
  'You are the filing clerk for WERKZ, a 1955 industrial-bureaucracy game.',
  'A completed work order left uncommitted changes. Given a git diff, write ONE',
  'dry, deadpan line (max 16 words) stating WHAT changed and roughly where —',
  'plain and factual, Severance/Portal tone, no praise, no exclamation, no quotes,',
  'output only the line. It will become a commit message.',
].join(' ');

/**
 * DETECT (instant, sync): the git-derived filing, or null for a clean tree.
 * No spawn here — rides on job.completed without delaying it.
 */
export function detectDirty(dir: string, git: GitRunner = realGit): Filing | null {
  const status = git(['status', '--porcelain'], dir);
  if (status.status !== 0) return null;                  // not a git repo / git error → no card
  const files = parsePorcelain(status.stdout);
  if (files.length === 0) return null;                   // clean tree → silent, no 22-C

  const statOut = git(['diff', '--stat'], dir).stdout;
  const stat = statOut.length > FILING_STAT_CAP ? statOut.slice(0, FILING_STAT_CAP - 1) + '…' : statOut;
  return { files: files.slice(0, FILING_FILES_CAP), fileCount: files.length, stat };
}

/**
 * SUMMARIZE (async): a dry Haiku one-liner for the diff, or null on ANY failure
 * (no claude / plan limit / timeout) — the card degrades to the raw --stat. The
 * returned line also becomes the commit message on approve.
 */
export async function summarizeDiff(
  dir: string,
  git: GitRunner = realGit,
  claudePath: string | null = null,
  spawner?: Spawner,
): Promise<string | null> {
  const files = parsePorcelain(git(['status', '--porcelain'], dir).stdout);
  const diff = git(['diff'], dir).stdout;
  const cappedDiff = diff.length > FILING_DIFF_CAP ? diff.slice(0, FILING_DIFF_CAP) : diff;
  const prompt = `${SUMMARY_SYSTEM}\n\nChanged files:\n${files.slice(0, FILING_FILES_CAP).join('\n')}\n\nDiff:\n${cappedDiff}`;
  const summary = await promptClaudeLine(prompt, claudePath, spawner);
  return summary && summary.trim() ? summary.trim() : null;
}

export interface ApproveResult { ok: boolean; error?: string; }

// A commit-message prefix so the origin is unmistakable in git history.
export const COMMIT_PREFIX = 'werkz: ';
export const COMMIT_TRAILER = '\n\nFiled from a Werkz completion (Form 22-C).';

/**
 * APPROVE FILING (right swipe): `git add -A && git commit && git push`, in [dir].
 * The message is the Haiku [summary] (or a dry default), prefixed so git history
 * shows it came from Werkz. Returns ok, or a loud reason on push/commit failure —
 * the changes stay put on any error (no silent success). PUSH ONLY happens here.
 */
export function approveFiling(dir: string, summary: string | null, git: GitRunner = realGit): ApproveResult {
  const line = (summary && summary.trim()) || 'file uncommitted changes from a completed work order';
  const message = `${COMMIT_PREFIX}${line}${COMMIT_TRAILER}`;

  const add = git(['add', '-A'], dir);
  if (add.status !== 0) return { ok: false, error: gitError('git add failed', add) };

  const commit = git(['commit', '-m', message], dir);
  if (commit.status !== 0) {
    // Nothing to commit (e.g. only ignored files changed) is not a hard error —
    // but there's also nothing to push, so report it plainly.
    const out = (commit.stdout + commit.stderr).toLowerCase();
    if (out.includes('nothing to commit')) return { ok: false, error: 'nothing to commit (only ignored files changed)' };
    return { ok: false, error: gitError('git commit failed', commit) };
  }

  const push = git(['push'], dir);
  if (push.status !== 0) {
    return { ok: false, error: gitError('git push failed — the commit is saved locally, not pushed', push) };
  }
  return { ok: true };
}

function gitError(prefix: string, r: GitResult): string {
  const tail = (r.stderr || r.stdout).split('\n').map((s) => s.trim()).filter(Boolean).pop() ?? `exit ${r.status}`;
  const msg = `${prefix}: ${tail}`;
  return msg.length > 200 ? msg.slice(0, 199) + '…' : msg;
}
