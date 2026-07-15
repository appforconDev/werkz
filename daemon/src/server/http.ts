// Local HTTP server — receives CC hook POSTs (event-model.md §0 transport)
// and will serve the LAN protocol for the app. Stub only.

import { createServer, type Server } from 'node:http';

export function createDaemonServer(): Server {
  return createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/health') {
      res.writeHead(200, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ ok: true }));
      return;
    }
    if (req.method === 'POST' && req.url === '/cc-hook') {
      // TODO(P1): parse hook payload, adapter.translate(), route decisions
      // per event-model.md §3 (incl. adaptive hold, §3.4).
      res.writeHead(501, { 'content-type': 'application/json' });
      res.end(JSON.stringify({ error: 'not implemented — P1' }));
      return;
    }
    res.writeHead(404);
    res.end();
  });
}
