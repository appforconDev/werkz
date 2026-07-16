// Pairing & auth (task 6 §3). A one-time pairing token (shown in the QR) is
// exchanged at POST /pair for a long-lived session token. All decision/state
// endpoints require the session token afterwards.

import { randomBytes } from 'node:crypto';
import { loadJson, saveJson } from '../state/store.ts';

export interface PairingPayload {
  v: 1;
  host: string;
  port: number;
  token: string; // one-time pairing token
}

export class PairingManager {
  #pairingToken: string;
  #pairingUsed = false;
  #sessions = new Set<string>();
  #persistPath: string | null;

  constructor(pairingToken: string = randomBytes(16).toString('hex'), persistPath: string | null = null) {
    this.#pairingToken = pairingToken;
    this.#persistPath = persistPath;
    if (persistPath) {
      // Session tokens survive a daemon restart (task 7 §4).
      for (const s of loadJson<string[]>(persistPath, [])) this.#sessions.add(s);
    }
  }

  #save(): void {
    if (this.#persistPath) saveJson(this.#persistPath, [...this.#sessions]);
  }

  get pairingToken(): string {
    return this.#pairingToken;
  }

  payload(host: string, port: number): PairingPayload {
    return { v: 1, host, port, token: this.#pairingToken };
  }

  /** Exchange the one-time pairing token for a session token. Single use. */
  pair(token: string): string | null {
    if (this.#pairingUsed || token !== this.#pairingToken) return null;
    this.#pairingUsed = true;
    const session = randomBytes(24).toString('hex');
    this.#sessions.add(session);
    this.#save();
    return session;
  }

  verify(sessionToken: string | undefined | null): boolean {
    return !!sessionToken && this.#sessions.has(sessionToken);
  }

  /** Allow re-pairing (e.g. a new phone). Invalidates nothing existing. */
  resetPairing(newToken: string = randomBytes(16).toString('hex')): void {
    this.#pairingToken = newToken;
    this.#pairingUsed = false;
  }
}

export function encodePayload(p: PairingPayload): string {
  return Buffer.from(JSON.stringify(p), 'utf8').toString('base64url');
}

export function decodePayload(s: string): PairingPayload {
  return JSON.parse(Buffer.from(s, 'base64url').toString('utf8')) as PairingPayload;
}
