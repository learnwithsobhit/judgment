# Judgement — Online Multiplayer Card Game

Browser-first multiplayer implementation of the Judgement (Oh Hell) card game.
3–8 players, private rooms, authoritative Rust server, Flutter Web client.

See `PLAN.md` for the full product and engineering plan, `docs/RULES.md` for
the rule specification, and `docs/adr/` for architecture decisions.

## Status

| Phase | Description | Status |
|-------|-------------|--------|
| 0 | Rules and contracts | Done (`docs/RULES.md`) |
| 1 | Pure Rust game engine | Done (`backend/crates/judgement-engine`) |
| 2 | Bot simulation | Done — random bot + seeded simulation runner |
| 3 | Backend room service (Axum, WebSocket) | Done (`judgement-protocol`, `judgement-server`) |
| 4 | Flutter lobby and table | Done (`frontend/judgement_flutter`) |
| 4.5 | Table options (size / timer / trump) | Done (ADR 0003) |
| 4.6 | Round schedule (automatic / manual) | Done (host `{cards, repeat}` → `Custom`) |
| 4.7 | Scheduled game events | Done (ADR 0005 — invite link + `.ics` reminders; set `PUBLIC_WEB_ORIGIN` for share URLs) |
| 5 | Persistence and recovery (PostgreSQL) | Done (`judgement-persistence`) |
| 6 | Reconnect, timeout, presence, bot takeover | Done (ADR 0004) |
| 7 | Explanations + curated FAQ | Done (`judgement-ai`, `rules/`, FAQ + templates; Rig rewrite optional) |
| 7b | Vector RAG (feature-flagged) | Done (`judgement-rag` + pgvector; `RAG_ENABLED=1`) |
| 8 | Coaching and highlights | Done (`judgement-analytics` + coach/highlights APIs) |
| 9 | Production hardening | Done (rate limits, CORS, metrics, deploy, runbooks) |

## Layout

```text
judgement/
├── PLAN.md                  # Source of truth
├── docs/                    # RULES.md, ADRs
├── backend/                 # Rust cargo workspace
│   └── crates/
│       ├── judgement-domain   # Cards, ids, rules config, errors, scores
│       ├── judgement-engine   # Pure deterministic state machine + projections
│       ├── judgement-bot      # Bot strategies + full-game simulation
│       ├── judgement-protocol # REST models + WebSocket envelope/messages
│       ├── judgement-server   # Axum app: sessions, rooms, game actors, WS
│       ├── judgement-persistence # PostgreSQL events, snapshots, recovery
│       ├── judgement-ai       # FAQ + templates + coaching narration
│       ├── judgement-rag      # Chunking + pgvector retrieval (Phase 7b, flagged)
│       └── judgement-analytics # Bid/round analysis + highlight facts
├── frontend/
│   └── judgement_flutter/   # Flutter Web client: lobby, table, scoreboard
├── docker-compose.yml       # Local Postgres + pgvector for Phase 5 / 7b
├── deployment/              # Dockerfile, nginx, backup/restore, load smoke
├── contracts/               # JSON schemas (Phase 3)
└── rules/                   # Curated rule documents + common_questions.md
```


## Development

Requires stable Rust.

```bash
cd backend

# Run the full test suite (unit + property + simulation tests)
cargo test --workspace

# Watch a complete seeded six-player game
cargo run -p judgement-bot --bin simulate -- 42

# Phase 2 exit gate: 10,000 seeded games, invariant-checked
cargo test -p judgement-bot --release -- --ignored

# Run the server (PORT env var, default 8080)
# Without DATABASE_URL the server uses an in-memory store (dev only).
cargo run -p judgement-server

# With PostgreSQL (recommended):
#   docker compose up -d   # from judgement/
#   DATABASE_URL=postgres://judgement:judgement@127.0.0.1:5434/judgement \
#     cargo run -p judgement-server
```

### Persistence (Phase 5)

Active games, guest sessions, and lobbies are written to PostgreSQL. On boot the
server reloads sessions/rooms and respawns actors from the latest snapshot,
rebuilding the action-id dedup registry from `game_events`. Round and game
results are stored for history.

```bash
# Postgres-backed store smoke test (ignored by default)
DATABASE_URL=postgres://judgement:judgement@127.0.0.1:5434/judgement \
  cargo test -p judgement-persistence --test postgres_store -- --ignored
```

### Explanations (Phase 7) + Vector RAG (Phase 7b)

`POST /api/v1/ai/rules/query` answers via curated FAQ and engine reason-code
templates. No LLM is required. Optional Rig rewrite is behind the `rig` feature
on `judgement-ai` (`OPENAI_API_KEY`); cost caps fall back to the deterministic
answer. Gameplay never depends on this endpoint.

**Phase 7b** adds optional vector retrieval over `rules/*.md` after an FAQ miss:

- Off by default (`RAG_ENABLED` unset) — behaviour identical to Phase 7
- On: `RAG_ENABLED=1` ingest/query with ruleset + embedding-model version filters
- Local default embedder: `deterministic-hash-v1` (64-d, no API key)
- Postgres image must provide pgvector (`docker compose` uses `pgvector/pgvector:pg16`)

```bash
cargo test -p judgement-ai
cargo test -p judgement-rag
cargo test -p judgement-server --test ai_rules
cargo test -p judgement-server --test rag_flag

# With Postgres + RAG:
#   docker compose up -d
#   DATABASE_URL=postgres://judgement:judgement@127.0.0.1:5434/judgement \
#     RAG_ENABLED=1 cargo run -p judgement-server
```

### Production hardening (Phase 9)

| Concern | How |
|---------|-----|
| HTTP rate limits | `HTTP_RATE_LIMIT` / `HTTP_GUEST_RATE_LIMIT` (middleware → 429) |
| Origin validation | `ALLOWED_ORIGINS` comma list (unset = permissive **dev only**) |
| Readiness | `/readyz` pings the store (`SELECT 1` on Postgres) |
| Metrics | Prometheus text at `/metrics` |
| Security checklist | [`docs/SECURITY.md`](docs/SECURITY.md) |
| Incident response | [`docs/runbooks/incident.md`](docs/runbooks/incident.md) |
| Load target | [`docs/LOAD.md`](docs/LOAD.md) + `deployment/load/smoke.sh` |
| Backup / restore | `deployment/scripts/backup.sh`, `restore_verify.sh` |
| Deploy | `deployment/docker/Dockerfile`, `deployment/docker-compose.prod.yml` |

```bash
cargo test -p judgement-server --test hardening
# with a local server:
#   ./deployment/load/smoke.sh
```

### Coaching & highlights (Phase 8)

After a finished game:

- `GET /api/v1/games/{id}/coach/{player_id}` — bid accuracy, strongest/weakest
  rounds, risk pattern, two improvements, evidence (all from `ScoreTable`)
- `GET /api/v1/games/{id}/highlights` — structured highlight facts + narration
- `GET /api/v1/games/{id}/rounds/{n}/summary?player_id=` — round explanation

No LLM is required; optional rewrite timeouts fall back to the same templates.
The Flutter result screen loads coach + highlights automatically.

```bash
cargo test -p judgement-analytics
cargo test -p judgement-server --test coaching
```

### Frontend (Flutter Web)

Requires the Flutter SDK (stable channel).

```bash
cd frontend/judgement_flutter

# Static analysis + unit/widget tests
flutter analyze
flutter test

# Run against a local server (open six tabs to fill a room)
flutter run -d chrome --dart-define=API_BASE=http://localhost:8080

# End-to-end check: six Dart clients play a full game over the wire
# (needs the server running first)
flutter test test/e2e_full_game_test.dart \
  --dart-define=E2E=true --dart-define=API_BASE=http://localhost:8080
```

Playing card faces/backs are a public-domain PNG deck (Byron Knoll / vector
playing cards), vendored under `frontend/judgement_flutter/assets/cards/`
(see that folder’s `LICENSE`).

The client never computes game rules: legality comes from the server's
`legal_actions` in each snapshot, and every command is acknowledged or
rejected with a stable reason code (PLAN.md §29.2).

Every game is fully reproducible from its seed (`GameEngine::new_with_seed`);
bug reports should include the seed and state version.

## Production deploy (GitHub + Fly.io + Firebase)

| Piece | Host |
|-------|------|
| Flutter Web | Firebase Hosting |
| API + WebSocket | Fly.io (`fly.toml` + `deployment/docker/Dockerfile`) |
| Postgres | Fly Postgres (attached `DATABASE_URL`) |

Full click-through: [`docs/runbooks/deploy.md`](docs/runbooks/deploy.md).

**Quick first launch**

1. Push this repo to GitHub (`git` root is this directory — see the runbook).
2. Fly.io: `fly auth login`, then create app/Postgres and `fly deploy` (see runbook).
   Config: [`fly.toml`](fly.toml), secrets template [`deployment/fly.env.example`](deployment/fly.env.example).
3. Build web against the Fly URL and deploy Hosting:
   ```bash
   cd frontend/judgement_flutter
   flutter build web --release --dart-define=API_BASE=https://judgment-api.fly.dev
   firebase deploy --only hosting --project judgment-lws-260731
   ```
4. Set Fly secrets `ALLOWED_ORIGINS` + `PUBLIC_WEB_ORIGIN` to the Firebase URL(s).
5. GitHub Actions variables/secrets: `API_BASE`, `FIREBASE_PROJECT_ID`,
   `PUBLIC_WEB_ORIGIN`, `FIREBASE_TOKEN`, `FLY_API_TOKEN`.
   Workflows: [`.github/workflows/ci.yml`](.github/workflows/ci.yml),
   [`.github/workflows/deploy.yml`](.github/workflows/deploy.yml).

v1 launch defaults: `RAG_ENABLED=0`, platform URLs (no custom domain required).

## Core boundaries (mandatory)

1. **Client vs server** — the client requests; the server decides.
2. **Engine vs infrastructure** — the engine contains rules only; it has no
   dependency on Axum, PostgreSQL, or Flutter.
3. **Deterministic truth vs AI explanation** — Rust calculates; AI only
   explains verified facts.
