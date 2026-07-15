# backend/ — Cloudflare Workers + Supabase

Relay broker, auth, push, share-card generation, Stripe webhooks (P3).
Nothing here runs yet — structure only.

Rules (CLAUDE.md):
- **Supabase strictly no-CLI**: all schema changes are applied as SQL via the
  Dashboard. Keep a copy of every migration in `sql/` for history.
- RLS on from table one.
- The daemon must never require this backend (free LAN mode is standalone).

Layout:
- `sql/` — chronological migration SQL copies (`NNNN_description.sql`)
- `workers/` — Cloudflare Workers source (P3)
