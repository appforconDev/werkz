// Terminal QR + status line (task 6 §1). QR encodes the base64url pairing
// payload; the raw payload is also printed so headless/test clients can pair
// without a camera.

import qrcode from 'qrcode-terminal';
import type { PairingPayload } from './auth.ts';
import { encodePayload } from './auth.ts';

export function printPairing(payload: PairingPayload): void {
  const encoded = encodePayload(payload);
  console.log('');
  console.log('  WERKZ INDUSTRIES — DEPARTMENT OF AGENT OPERATIONS');
  console.log('  Pairing requisition ready. Present this to the workshop terminal (your phone):');
  console.log('');
  qrcode.generate(encoded, { small: true }, (qr) => {
    for (const line of qr.split('\n')) console.log('  ' + line);
  });
  console.log('');
  console.log(`  or pair by hand:  ${encoded}`);
  console.log(`  workshop at:      http://${payload.host}:${payload.port}`);
  console.log('');
}
