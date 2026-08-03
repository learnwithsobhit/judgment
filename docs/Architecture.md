# Judgement — System Architecture

Last reviewed: 2026-07-31

This document describes the architecture of the Judgement (Oh Hell) multiplayer product: layered design, runtime flows, interfaces, communication, and data durability. It complements [`PLAN.md`](../PLAN.md), ADRs under [`docs/adr/`](adr/), and [`docs/RULES.md`](RULES.md).

**Core principle:** the client requests; the server decides. Flutter never owns legality, scores, turn order, or shuffle.

---

## 1. System context

```mermaid
flowchart TB
  players[Players browsers]
  spa[Flutter Web SPA]
  firebase[Firebase Hosting]
  api[Fly.io Axum API and WSS]
  pg[(PostgreSQL)]
  optionalRag[Optional RAG and LLM]

  players -->|HTTPS| firebase
  firebase -->|serves SPA assets| spa
  spa -->|HTTPS REST| api
  spa -->|"WSS direct browser to Fly"| api
  api --> pg
  api -.->|side path never blocks gameplay| optionalRag
```

| Piece | Host | Notes |
|-------|------|--------|
| Flutter Web SPA | Firebase Hosting (`judgment-lws-260731`) | SPA rewrites for `/e/{slug}` and `/r/{CODE}` deep links |
| API + WebSocket | Fly.io (`judgment-api`) | Browser talks to Fly for WSS; Firebase does **not** proxy WS |
| Postgres | Fly Postgres / Neon / Supabase | Events + snapshots; migrations on boot |
| AI / RAG | Same API process | Optional; never mutates game state |

---

## 2. Layered design

### 2.1 Backend crate layers

Dependency direction is strictly inward: outer crates may depend on inner ones; the engine and domain never import Axum, sqlx, or Flutter.

```mermaid
flowchart TB
  subgraph presentation [Presentation and IO]
    server[judgement-server Axum]
    protocol[judgement-protocol REST and WS DTOs]
  end

  subgraph application [Application services]
    bot[judgement-bot]
    analytics[judgement-analytics]
    ai[judgement-ai]
    rag[judgement-rag]
  end

  subgraph domainCore [Domain core]
    engine[judgement-engine]
    domain[judgement-domain]
  end

  subgraph durable [Durability]
    persistence[judgement-persistence]
  end

  server --> protocol
  server --> engine
  server --> persistence
  server --> bot
  server --> ai
  server --> analytics
  ai --> rag
  ai --> analytics
  ai --> domain
  protocol --> engine
  protocol --> domain
  bot --> engine
  bot --> domain
  persistence --> engine
  persistence --> domain
  analytics --> domain
  engine --> domain
```

| Crate | Responsibility |
|-------|----------------|
| `judgement-domain` | Cards, IDs, rules config, scores, `GameError`, connection status |
| `judgement-engine` | Deterministic state machine: deal, bid, play, score, projections |
| `judgement-protocol` | Wire schema: REST/WS DTOs, `PROTOCOL_VERSION = 1` |
| `judgement-persistence` | `GameStore` trait, `MemoryStore`, `PostgresStore`, SQL migrations |
| `judgement-bot` | Rule/random strategies for disconnect takeover and sims |
| `judgement-analytics` | Deterministic post-game facts (no LLM) |
| `judgement-rag` | Optional vector retrieval over curated rule chunks |
| `judgement-ai` | FAQ / templates / coach narration; optional RAG + tone rewrite |
| `judgement-server` | HTTP/WS, actors, AppState, CORS, rate limits, restore, events |

### 2.2 Server internal layers

```mermaid
flowchart LR
  subgraph httpEdge [HTTP edge]
    cors[CORS]
    rate[HTTP rate limit]
    routes[REST routes]
    events[Scheduled events]
  end

  subgraph realtime [Realtime]
    ws[WS upgrade and heartbeats]
    actor[GameActor per game]
  end

  subgraph runtime [Runtime hub]
    appState[AppState maps]
  end

  subgraph core [Authoritative core]
    eng[GameEngine]
    store[GameStore]
  end

  cors --> rate --> routes
  rate --> ws
  routes --> appState
  events --> appState
  ws --> actor
  actor --> eng
  actor --> store
  routes --> store
  appState --> store
```

Key files under `backend/crates/judgement-server/src/`:

| Module | Role |
|--------|------|
| `routes.rs` | Guest, rooms, start, history, AI, coach |
| `events.rs` | Scheduled meetups, RSVP, open-lobby, ICS |
| `ws.rs` | Auth, token rotate, ping/liveness, enqueue commands |
| `actor.rs` | Sequential apply → persist → broadcast |
| `state.rs` | Sessions, rooms, games, tokens, store handle |
| `persist.rs` / `restore.rs` | Runtime ↔ store mapping; boot restore |
| `emotes.rs` | Allow-lists and text→emoji lexicon |
| `audio.rs` | Soundboard allow-list + voice-note size/mime caps |
| `cors.rs` / `http_limit.rs` | Origins and abuse controls |

### 2.3 Frontend layers

```mermaid
flowchart TB
  screens[Screens landing lobby table results events]
  widgets[Widgets cards scoreboard emotes avatars AI panels]
  controller[GameController ChangeNotifier]
  models[protocol.dart wire models]
  net[ApiClient REST and GameSocket WS]
  screens --> widgets
  screens --> controller
  screens --> net
  controller --> net
  controller --> models
  net --> models
  widgets --> controller
```

Root: `frontend/judgement_flutter/lib/`

| Layer | Path | Role |
|-------|------|------|
| Entry / theme / deep links | `main.dart`, `app/app.dart` | Material shell; `/e/{slug}`, `/r/{CODE}` routing |
| Screens | `screens/` | Landing → lobby → table → results; event flows |
| State | `state/game_controller.dart` | Snapshot mirror + command lifecycle |
| Networking | `networking/api_client.dart`, `game_socket.dart` | REST + WSS |
| Models | `models/protocol.dart` | Dart mirror of `judgement-protocol` |
| Widgets / util | `widgets/`, `util/` | UI and cosmetic packs |

State management: `ChangeNotifier` + `ListenableBuilder` (no Riverpod).

---

## 3. Production topology and config

```mermaid
flowchart LR
  gh[GitHub Actions]
  flyBuild[Fly remote Docker build]
  fbBuild[Flutter web release build]
  flyApp[judgment-api]
  fbHost[Firebase Hosting]
  db[(Fly Postgres DATABASE_URL)]

  gh -->|deploy-api FLY_API_TOKEN| flyBuild --> flyApp
  gh -->|deploy-web API_BASE dart-define| fbBuild --> fbHost
  flyApp --> db
  fbHost -.->|SPA only| browsers[Browsers]
  browsers -->|REST and WSS| flyApp
```

| Variable | Where | Purpose |
|----------|-------|---------|
| `API_BASE` | Flutter `--dart-define` / GH variable | REST base; WS scheme derived (`http`→`ws`) |
| `ALLOWED_ORIGINS` | Fly secret | CORS allow-list (unset = permissive **dev only**) |
| `PUBLIC_WEB_ORIGIN` | Fly secret + GH variable | Invite / WhatsApp / ICS absolute links |
| `DATABASE_URL` | Fly secret (attach) | Postgres; unset → in-memory store |
| `JUDGEMENT_ALLOW_SEED` | Env (non-prod) | Allow deterministic `seed` on start |
| `RAG_ENABLED` | Fly secret | Optional RAG path |

See [`docs/runbooks/deploy.md`](runbooks/deploy.md) and [`deployment/fly.env.example`](../deployment/fly.env.example).

---

## 4. Interfaces

### 4.1 REST vs WebSocket split

| Transport | Use |
|-----------|-----|
| **REST** | Guest session, rooms/lobby (incl. host remove-player before start), avatar (lobby), scheduled events, AI rules query, coach/highlights, history |
| **WebSocket** | Live bids/plays, snapshots, presence, timers, pause/resume, bot takeover, in-game avatar, table emotes, soundboard, short voice notes |

Lobby freshness uses **HTTP polling** (~2s). Live play uses **full personalized snapshots** after each accepted mutation (no client-side deltas).

### 4.2 Major REST surface

```mermaid
flowchart TB
  subgraph identity [Identity]
    guest[POST /api/v1/guest-sessions]
    avatar[POST /api/v1/me/avatar]
  end

  subgraph lobby [Lobby]
    createRoom[POST /api/v1/rooms]
    joinRoom[POST /api/v1/rooms/ref/join]
    ready[POST ready]
    removePlayer[POST remove-player host only]
    start[POST start]
  end

  subgraph liveOps [Ops]
    health[GET /healthz]
    readyz[GET /readyz]
    metrics[GET /metrics]
  end

  subgraph postGame [Post-game and AI]
    history[GET games/id/history]
    coach[GET coach]
    highlights[GET highlights]
    aiQuery[POST /api/v1/ai/rules/query]
  end

  subgraph sched [Scheduled events]
    eventsApi[POST/GET /api/v1/events...]
  end
```

Authoritative router: `backend/crates/judgement-server/src/lib.rs`.

### 4.3 WebSocket contract

**Endpoint:** `GET /api/v1/games/{game_id}/ws?token={bearer}`

```mermaid
sequenceDiagram
  participant C as Flutter client
  participant WS as ws.rs
  participant A as GameActor
  participant E as GameEngine
  participant S as GameStore

  C->>WS: Connect with bearer token
  WS->>WS: Authenticate and rotate token
  WS->>A: Connect seat
  A-->>C: TokenRotated
  A-->>C: StateSnapshot personalized view

  C->>WS: ClientEnvelope action_id state_version command
  WS->>A: ActorMessage Command
  A->>A: Dedup pause bot version checks
  A->>E: place_bid or play_card
  E-->>A: GameEvents and version bump
  A->>S: commit_command
  alt persist ok
    A-->>C: CommandAccepted
    A-->>C: StateSnapshot to each seat
  else persist fail
    A->>E: replace_state previous
    A-->>C: CommandRejected QueueFull retryable
  end
```

**Client envelope fields:** `protocol_version`, `action_id` (UUID, idempotent), `game_id`, `expected_state_version`, `action`.

**Server messages (selected):** `CommandAccepted` / `CommandRejected`, `StateSnapshot`, presence, `GamePaused` / `GameResumed`, `BotTookOver` / `PlayerResumedControl`, `TokenRotated`, `TimerUpdated`, `TableEvent` (emotes / soundboard), `VoiceNote` (ephemeral Opus ≤6s, not persisted).

Hardening: max message 64 KiB; ping 15s; liveness 45s; command queue capacity 256.

---

## 5. End-to-end product flows

### 5.1 Guest → lobby → game → results

```mermaid
flowchart TD
  startNode[Open SPA]
  guest[Create guest session REST]
  room[Create or join room REST]
  lobby[Lobby poll ready avatars]
  startGame[Host start REST]
  table[TableScreen WS]
  play[Bid and play loop]
  victory[Victory celebration]
  results[Results coach highlights]

  startNode --> guest --> room --> lobby --> startGame --> table --> play
  play -->|GameCompleted| victory --> results
```

### 5.2 One accepted bid or play (data path)

```mermaid
flowchart LR
  ui[UI legal_actions hint]
  gc[GameController pendingActionId]
  sock[GameSocket]
  actor[GameActor]
  eng[GameEngine]
  db[(Postgres commit)]
  snap[StateSnapshot broadcast]

  ui --> gc --> sock --> actor --> eng --> db --> snap
  snap --> gc
```

Client uses `legal_actions` only to enable UI; rejects and scores always come from the server.

### 5.3 Scheduled event path

```mermaid
flowchart TD
  createEvt[Host creates event REST]
  rsvp[Players RSVP capacity 8 plus waitlist]
  openLobby[Host open-lobby]
  room2[Room created]
  sameStart[Same start and WS flow]

  createEvt --> rsvp --> openLobby --> room2 --> sameStart
```

Deep links: `/e/{slug}` invite, `/e/{slug}/manage?token=` manage, `/r/{CODE}` room join (Firebase SPA rewrite). ADR: [`0005-scheduled-game-events.md`](adr/0005-scheduled-game-events.md).

### 5.4 Presence, pause, bot takeover

```mermaid
stateDiagram-v2
  [*] --> Connected
  Connected --> Disconnected: socket drop
  Disconnected --> Connected: reconnect within grace
  Disconnected --> BotControlled: grace expired
  BotControlled --> Connected: player reconnects
  Connected --> BotControlled: LeaveGame immediate

  note right of Disconnected
    Table paused while any seat in grace
    Host may migrate
  end note
```

ADR: [`0004-presence-grace-bot-takeover.md`](adr/0004-presence-grace-bot-takeover.md). Defaults: reconnect grace ~60s; optional turn timer from room options (ADR [`0003`](adr/0003-table-size-timer-trump-options.md)).

Every successful WS upgrade **rotates** the bearer token (`TokenRotated`); old token invalidated.

### 5.5 Actor-per-game concurrency model

```mermaid
flowchart TB
  subgraph process [Single Fly machine]
    r1[Room and session maps]
    a1[Actor game A sequential]
    a2[Actor game B sequential]
    eng1[Engine A]
    eng2[Engine B]
  end

  clientsA[Clients game A] --> a1 --> eng1
  clientsB[Clients game B] --> a2 --> eng2
  a1 --> store[(GameStore)]
  a2 --> store
  r1 --> store
```

ADR: [`0001-actor-per-game.md`](adr/0001-actor-per-game.md). One sequential tokio task per active game avoids locks inside the engine.

**CAP stance:** the realtime path is **CP** — one writer per `game_id`, durable tip before clients see accepts. Availability is improved by pool headroom, product capacity gates (busy notice at 25 tables; `CAPACITY_FULL` at 35 tables or 200 WS), emergency `MAX_ACTIVE_GAMES` (100), client auto-resend on `PersistUnavailable`, actor respawn from tip, and outbound snapshot dirty-resync — not by multi-writer AP. Horizontal scale beyond one Fly machine needs game ownership leases + sticky routing (deferred; see `docs/game_estimation.md` cost ladder). Keep API and Postgres colocated in the same region.

---

## 6. Domain game loop

```mermaid
flowchart TD
  lobbyPhase[Lobby]
  deal[Deal and trump]
  bidding[Bidding dealer last]
  playing[Playing follow suit]
  scoreRound[Score and RoundScoring reveal hold]
  nextRound{More rounds}
  finished[Finished ranking]

  lobbyPhase --> deal --> bidding --> playing --> scoreRound --> nextRound
  nextRound -->|yes after ~1.8s rotate dealer| deal
  nextRound -->|no after ~1.8s| finished
```

Rules reference: [`docs/RULES.md`](RULES.md). Optional dealer total restriction is **off by default** (host toggle at room create).

Projection: `PlayerGameView` exposes own hand + legal actions; opponents see `card_count` only — never hidden cards.

---

## 7. Data model and durability

### 7.1 Durable vs runtime-only

```mermaid
flowchart TB
  subgraph durable [Durable GameStore]
    sessions[guest_sessions]
    rooms[rooms and room_players]
    games[games and game_players]
    eventsTbl[game_events]
    snapshots[game_snapshots]
    results[round_results game_results]
    sched[scheduled_events RSVPs]
  end

  subgraph runtime [Runtime only]
    actors[GameActor clients queues]
    grace[Pause and grace timers]
    emotes[TableEvent emotes]
    httpBuckets[HTTP and AI rate buckets]
  end

  appState[AppState mirrors sessions rooms] --> durable
  actors --> snapshots
```

**Commit rule:** mutate engine → `commit_command` → on failure `replace_state(previous)` so clients never observe undurable authoritative state.

### 7.2 Persistence migrations

| Migration | Purpose |
|-----------|---------|
| `0001_init` | Sessions, rooms, games, events, snapshots, results |
| `0002` | Round schedule on rooms |
| `0003` | Scheduled events + RSVPs |
| `0004` | Min players 3 |
| `0005` | Waitlist status |
| `0006` | Avatars |
| `0007` | Dealer total restriction column |

Path: `backend/crates/judgement-persistence/migrations/`. Boot: `JUDGEMENT_MIGRATIONS_DIR` (Fly sets `/srv/migrations/persistence`).

### 7.3 Restore on boot

```mermaid
flowchart LR
  boot[Server boot]
  migrate[Run migrations]
  load[Load sessions rooms events active games]
  spawn[Respawn actors from snapshots]
  listen[Listen PORT]

  boot --> migrate --> load --> spawn --> listen
```

`DATABASE_URL` unset → `MemoryStore` (dev; lost on restart).

---

## 8. Communication summary

```mermaid
flowchart TB
  subgraph client [Flutter]
    restClient[ApiClient]
    wsClient[GameSocket]
    ui[Screens and widgets]
  end

  subgraph server [judgement-server]
    rest[REST handlers]
    wsH[WS handler]
    actors[Actors]
    engine[Engine]
    store[Store]
    aiSide[AI and analytics side path]
  end

  ui --> restClient
  ui --> wsClient
  restClient -->|HTTPS JSON Bearer| rest
  wsClient -->|WSS JSON envelopes| wsH
  rest --> store
  rest --> aiSide
  wsH --> actors --> engine
  actors --> store
  aiSide -.->|read finished facts only| store
```

| Channel | Format | Auth |
|---------|--------|------|
| REST | JSON | `Authorization: Bearer {token}` |
| WS | JSON envelopes | Query `?token=` then rotated token on wire |
| Emotes | WS `TableEvent` | Ephemeral; not persisted as engine events |
| Soundboard | WS `TableEvent` kind `soundboard` | Asset id only; clients play local `assets/sounds/`; 10s audio cooldown |
| Voice notes | WS `VoiceNote` | Short Opus/WebM base64 ≤40KB / ≤6s; fan-out only; not stored; shared audio cooldown + client FIFO queue |
| Metrics | Prometheus text | Public `/metrics` |

---

## 9. AI and coaching boundary

```mermaid
flowchart LR
  gameplay[Gameplay critical path]
  side[Side path REST]
  faq[FAQ and templates]
  ragOpt[Optional RAG]
  llmOpt[Optional LLM tone]
  coach[Post-game coach]

  gameplay -.->|never waits on| side
  side --> faq --> ragOpt --> llmOpt
  side --> coach
```

ADR: [`0002-rig-for-ai-and-rag.md`](adr/0002-rig-for-ai-and-rag.md).

- AI never mutates engine state and must not receive hidden hands or shuffle seeds.
- Coach/highlights run only for finished games from durable scores.
- Bots (`judgement-bot`) are rule strategies, not LLM.

---

## 10. Frontend screen map

```mermaid
flowchart TD
  uri{Deep link}
  invite[EventInviteScreen]
  manage[EventManageScreen]
  landing[LandingScreen]
  lobby[LobbyScreen REST poll]
  table[TableScreen WS]
  victory[VictoryCelebration]
  result[ResultScreen]

  uri -->|/e/slug/manage| manage
  uri -->|/e/slug| invite
  uri -->|/r/CODE| landing
  uri -->|else| landing
  landing --> lobby --> table
  table --> victory --> result
  landing --> schedule[ScheduleEventScreen]
```

Cosmetic engagement (avatars, reactions, cartoon text blasts) is presentation-only; mid-game scoreboard shows round history without a Totals row until the game finishes.

---

## 11. Design decisions index (ADRs)

| ADR | Title | Impact |
|-----|-------|--------|
| [0001](adr/0001-actor-per-game.md) | Actor per game | Sequential commands; snapshot broadcast |
| [0002](adr/0002-rig-for-ai-and-rag.md) | Rig + RAG | AI off critical path |
| [0003](adr/0003-table-size-timer-trump-options.md) | Table options | 3–8 seats, timer, trump, schedules |
| [0004](adr/0004-presence-grace-bot-takeover.md) | Presence | Grace, bots, token rotation |
| [0005](adr/0005-scheduled-game-events.md) | Scheduled events | Meetup RSVP → lobby |

---

## 12. Repository map

```text
judgement/
├── backend/crates/          # Rust workspace (domain → engine → server)
├── frontend/judgement_flutter/  # Flutter Web client
├── docs/                    # Rules, ADRs, runbooks, this file
├── rules/                   # Curated rule text for FAQ/RAG
├── deployment/              # Docker, compose, env examples, scripts
├── fly.toml                 # Fly app config
└── .github/workflows/       # CI + Deploy
```

---

## 13. Related docs

- Product / engineering plan: [`PLAN.md`](../PLAN.md)
- Rules: [`RULES.md`](RULES.md)
- Deploy: [`runbooks/deploy.md`](runbooks/deploy.md)
- Security gate: [`SECURITY.md`](SECURITY.md)
- Frontend layout: [`frontend/judgement_flutter/README.md`](../frontend/judgement_flutter/README.md)
