// LAN WebSocket channel (task 7). The live protocol the Flutter app speaks.
// Attaches to the existing http server; upgrades at /ws with session-token
// auth. JSON frames, versioned via the hello handshake, heartbeat ping/pong.
//
// Server→client: welcome (pending snapshot + replayed events), event, released, pong, error
// Client→server: hello {protocolVersion,lastEventId?,filters?}, release {decisionId,decision},
//                subscribe {filters}, ping
//
// Broadcast is fire-and-forget from the bus (§3.5): a slow socket never blocks
// PreToolUse routing — ws.send buffers, and the bus swallows subscriber throws.

import { WebSocketServer, WebSocket } from 'ws';
import type { Server, IncomingMessage } from 'node:http';
import type { EventBus } from '../events/bus.ts';
import type { DecisionService } from '../decisions/service.ts';
import type { PairingManager } from '../pairing/auth.ts';
import type { WerkzEvent, Severity } from '../events/types.ts';
import type { Preflight } from '../preflight/index.ts';

export const PROTOCOL_VERSION = 1;
const HEARTBEAT_MS = 30_000;

const SEVERITY_RANK: Record<Severity, number> = { info: 0, attention: 1, decision: 2, incident: 2 };

interface ClientState {
  alive: boolean;
  minSeverityRank: number;
  connectedAt: number; // for uptime in the close log
}

export function attachWsServer(
  httpServer: Server,
  deps: {
    bus: EventBus;
    service: DecisionService;
    pairing: PairingManager;
    getPreflight?: () => Preflight;
    // Connection-drop instrumentation (task 22 B): log WHY a socket ended so the
    // evening's diagnosis has both ends. Injectable so tests can capture it.
    log?: (msg: string) => void;
  },
): { close: () => void } {
  const { bus, service, pairing, getPreflight } = deps;
  const log = deps.log ?? ((m: string) => console.log(m));
  const upSec = (st?: ClientState) => (st ? Math.round((Date.now() - st.connectedAt) / 1000) : 0);
  const wss = new WebSocketServer({ noServer: true });
  const clients = new Map<WebSocket, ClientState>();

  httpServer.on('upgrade', (req: IncomingMessage, socket, head) => {
    const url = new URL(req.url ?? '/', 'http://127.0.0.1');
    if (url.pathname !== '/ws') return; // let other upgrade handlers (none yet) pass
    const token = url.searchParams.get('token');
    if (!pairing.verify(token)) {
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }
    wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws, req));
  });

  function send(ws: WebSocket, msg: object): void {
    if (ws.readyState === WebSocket.OPEN) {
      try { ws.send(JSON.stringify(msg)); } catch { /* fire-and-forget */ }
    }
  }

  wss.on('connection', (ws: WebSocket) => {
    clients.set(ws, { alive: true, minSeverityRank: 0, connectedAt: Date.now() });

    ws.on('pong', () => {
      const st = clients.get(ws);
      if (st) st.alive = true;
    });

    ws.on('message', (data) => {
      let msg: Record<string, unknown>;
      try { msg = JSON.parse(data.toString()); } catch { return send(ws, { type: 'error', message: 'bad json' }); }
      const st = clients.get(ws);
      if (!st) return;

      switch (msg.type) {
        case 'hello': {
          if (typeof msg.filters === 'object' && msg.filters) {
            st.minSeverityRank = severityRank((msg.filters as { minSeverity?: string }).minSeverity);
          }
          const lastEventId = typeof msg.lastEventId === 'string' ? msg.lastEventId : null;
          const replay = bus.replayAfter(lastEventId).filter((e) => SEVERITY_RANK[e.severity] >= st.minSeverityRank);
          // Replay observability (task 24.1): whether completion reports ride a
          // replay is exactly what the next device diagnosis needs in the log.
          const withReports = replay.filter((e) => (e.payload as { report?: unknown }).report != null).length;
          log(`WS hello: replaying ${replay.length} events${withReports ? ` (${withReports} carry reports)` : ''} (from=${lastEventId ?? 'start'})`);
          send(ws, {
            type: 'welcome',
            protocolVersion: PROTOCOL_VERSION,
            pending: service.listPending(),
            replayed: replay.length,
            ...service.permissionModeSummary(), // { mode, autopilot }
            ...(getPreflight ? { preflight: getPreflight() } : {}), // startup diagnostics (task 13 B)
          });
          // Mark replayed events so the app treats them as HISTORY (log only) —
          // never re-presenting a decision or re-firing a banner (task 16 B).
          for (const e of replay) send(ws, { type: 'event', event: e, replay: true });
          break;
        }
        case 'subscribe': {
          st.minSeverityRank = severityRank((msg.filters as { minSeverity?: string } | undefined)?.minSeverity);
          send(ws, { type: 'subscribed', minSeverity: msg.filters ?? null });
          break;
        }
        case 'release': {
          const decisionId = typeof msg.decisionId === 'string' ? msg.decisionId : '';
          const decision = msg.decision === 'deny' ? 'deny' : 'allow';
          const ok = service.release(decisionId, decision);
          send(ws, { type: 'released', decisionId, decision, ok });
          break;
        }
        case 'ping':
          send(ws, { type: 'pong' });
          break;
        default:
          send(ws, { type: 'error', message: `unknown type: ${String(msg.type)}` });
      }
    });

    ws.on('close', (code: number, reason: Buffer) => {
      const st = clients.get(ws);
      const r = reason?.toString() || '';
      log(`WS close: code=${code}${r ? ` reason="${r}"` : ''} (layer=peer, up=${upSec(st)}s)`);
      clients.delete(ws);
    });
    ws.on('error', (err: Error) => {
      log(`WS error: ${err?.message ?? err} (layer=error, up=${upSec(clients.get(ws))}s)`);
      clients.delete(ws);
    });
  });

  // Broadcast every bus event to clients that pass the severity filter.
  const unsubscribe = bus.subscribe((event: WerkzEvent) => {
    for (const [ws, st] of clients) {
      if (SEVERITY_RANK[event.severity] >= st.minSeverityRank) send(ws, { type: 'event', event });
    }
  });

  // Heartbeat: terminate sockets that miss a pong (the daemon-side zombie sweep).
  const heartbeat = setInterval(() => {
    for (const [ws, st] of clients) {
      if (!st.alive) {
        log(`WS heartbeat: terminating dead socket — missed pong (layer=heartbeat-sweep, up=${upSec(st)}s)`);
        ws.terminate();
        clients.delete(ws);
        continue;
      }
      st.alive = false;
      try { ws.ping(); } catch { /* ignore */ }
    }
  }, HEARTBEAT_MS);
  if (typeof heartbeat.unref === 'function') heartbeat.unref();

  return {
    close: () => {
      clearInterval(heartbeat);
      unsubscribe();
      for (const ws of clients.keys()) ws.terminate();
      wss.close();
    },
  };
}

function severityRank(minSeverity: string | undefined): number {
  if (minSeverity && minSeverity in SEVERITY_RANK) return SEVERITY_RANK[minSeverity as Severity];
  return 0;
}
