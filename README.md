# WERKZ

**The mobile game layer for agentic coding.** Your real coding agents are
workers in a 1955 industrial workshop on your phone. Permission prompts
become requisitions you stamp with a swipe; agent disputes become Octagon
matches; the waiting becomes the game. Free over LAN, paid relay for
anywhere. BYOK end-to-end.

## Monorepo map

| Directory | What | Stack |
|---|---|---|
| `docs/` | Source of truth: [gamedesign.md](docs/gamedesign.md) (GDD), [MASTERPLAN.md](docs/MASTERPLAN.md) (phases), [event-model.md](docs/event-model.md) (CC → game bridge), [AKTUELLT.md](docs/AKTUELLT.md) (work queue — read first) | — |
| `daemon/` | `npx werkz` — CC hooks listener → event stream, LAN server, relay client | Node 22+, TS, ESM |
| `app/` | The workshop | Flutter (portrait-only), Flame + Riverpod |
| `backend/` | Relay broker, auth, push, share cards, Stripe | Cloudflare Workers + Supabase |
| `landing/` | werkz.app — signup, checkout, the npx command | Astro + Tailwind |
| `assets-pipeline/` | Theme/concept art generation (gpt-image-2 via Fal) | Node scripts |

## Status

P0 (concept & identity) complete: style locked, event model approved.
Next: P1 — daemon + event stream. See [docs/AKTUELLT.md](docs/AKTUELLT.md).

## Development

- `daemon/`: `npm install && npm run typecheck && npm test`
- `app/`: `flutter pub get && flutter analyze`
- Secrets live in `.env` (gitignored) — see `.env.example`.
