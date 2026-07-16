// uuidv7 — time-ordered ids for events (event-model.md §1). Millisecond
// timestamp prefix + random tail, RFC-9562 layout. Good enough for ordering
// and uniqueness at daemon scale.

import { randomBytes } from 'node:crypto';

export function uuidv7(now: number = Date.now()): string {
  const ts = BigInt(now);
  const bytes = randomBytes(16);
  // 48-bit big-endian timestamp
  bytes[0] = Number((ts >> 40n) & 0xffn);
  bytes[1] = Number((ts >> 32n) & 0xffn);
  bytes[2] = Number((ts >> 24n) & 0xffn);
  bytes[3] = Number((ts >> 16n) & 0xffn);
  bytes[4] = Number((ts >> 8n) & 0xffn);
  bytes[5] = Number(ts & 0xffn);
  bytes[6] = (bytes[6] & 0x0f) | 0x70; // version 7
  bytes[8] = (bytes[8] & 0x3f) | 0x80; // variant
  const hex = bytes.toString('hex');
  return `${hex.slice(0, 8)}-${hex.slice(8, 12)}-${hex.slice(12, 16)}-${hex.slice(16, 20)}-${hex.slice(20)}`;
}

import { createHash } from 'node:crypto';

/** Stable decision key for dedup (event-model.md §3.6). */
export function decisionKey(sessionId: string, toolName: string, toolInput: unknown): string {
  const h = createHash('sha256').update(JSON.stringify(toolInput ?? null)).digest('hex').slice(0, 16);
  return `${sessionId}:${toolName}:${h}`;
}
