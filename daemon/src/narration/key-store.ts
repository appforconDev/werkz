// Narration key store (task 9). Holds the user's Anthropic (Haiku-class) API
// key locally so BYOK narration can run. BYOK rule (CLAUDE.md / GDD §6): the key
// lives ONLY on the daemon — never in git, never sent to our backend, never
// logged. Persisted to the per-project state dir (gitignored `.werkz/`).

import { readFileSync, writeFileSync, existsSync, mkdirSync, rmSync } from 'node:fs';
import { dirname } from 'node:path';

export interface KeyStatus {
  present: boolean;
  updatedAt: string | null;
}

export class NarrationKeyStore {
  #path: string | null;
  #key: string | null = null;
  #updatedAt: string | null = null;

  constructor(path: string | null) {
    this.#path = path;
    if (path && existsSync(path)) {
      try {
        const data = JSON.parse(readFileSync(path, 'utf8')) as { key?: string; updatedAt?: string };
        this.#key = data.key ?? null;
        this.#updatedAt = data.updatedAt ?? null;
      } catch {
        // corrupt/partial write — treat as no key
      }
    }
  }

  setKey(key: string, now: string): void {
    this.#key = key.trim() || null;
    this.#updatedAt = now;
    if (this.#path) {
      mkdirSync(dirname(this.#path), { recursive: true });
      // Persist with restrictive intent; the file lives under the user's own
      // project state dir. Never logged anywhere.
      writeFileSync(this.#path, JSON.stringify({ key: this.#key, updatedAt: this.#updatedAt }), { mode: 0o600 });
    }
  }

  clear(): void {
    this.#key = null;
    this.#updatedAt = null;
    if (this.#path) rmSync(this.#path, { force: true });
  }

  hasKey(): boolean {
    return this.#key !== null;
  }

  /** Internal use only — never send this anywhere except the Anthropic API. */
  getKey(): string | null {
    return this.#key;
  }

  status(): KeyStatus {
    return { present: this.#key !== null, updatedAt: this.#updatedAt };
  }
}
