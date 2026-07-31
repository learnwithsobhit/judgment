# Judgement Online Card Game — Product and Engineering Plan

**Document status:** Refined implementation plan  
**Target platform:** Browser-first multiplayer game  
**Frontend:** Flutter Web  
**Backend:** Rust  
**Primary backend framework:** Axum + Tokio  
**Database:** PostgreSQL  
**Optional vector search:** PostgreSQL + pgvector (feature-flagged; not on MVP critical path)  
**Primary game mode for MVP:** Private game, 4–8 players (amended by ADR 0003; originally six-player)  
**Default round sequence:** descending `max_cards → 1`, derived from player count (six players: `8 → 7 → … → 1`)

---

## 0. Locked decisions

These resolutions are binding for MVP implementation. Coding agents must not re-open them without an ADR.

| # | Decision | Chosen behaviour |
|---|----------|------------------|
| 1 | First-trick leader each round | Player clockwise-left of the dealer leads trick 1; thereafter the trick winner leads |
| 2 | Final ranking tie-break | Highest score, then most exact-bid rounds, then fewest total tricks missed; if still equal, shared rank |
| 3 | RAG in MVP | Deterministic reason-codes + a small curated FAQ map. pgvector RAG deferred to a later phase, feature-flagged |
| 4 | Permanent leave (never returns) | Rule-based bot plays out the remainder of the game for that seat |
| 5 | Host migration | On host disconnect/leave, auto-promote the longest-connected occupied seat to host |
| 6 | MVP state sync | Full `StateSnapshot` on every accepted command; `StateDelta` deferred as a later optimization |
| 7 | Table size (ADR 0003, pre-Phase-5 amendment) | 4–8 players per room; host picks size; start needs ≥ 4 seated and all ready |
| 8 | Turn timer (ADR 0003) | Optional per room; absent ⇒ no deadlines, no auto-play |
| 9 | Trump mode (ADR 0003) | Host may choose the first trump, which then rotates ♠→♦→♣→♥ each round; default remains the revealed undealt card |

---

## 1. Purpose

This document defines the product requirements, architecture, implementation sequence, AI capabilities, testing strategy, operational requirements, and acceptance criteria for an online multiplayer version of the Judgement card game.

It is intended to be used by:

- Coding agents
- Software engineers
- Product designers
- QA engineers
- DevOps engineers
- AI/ML engineers

The coding agent should treat this document as the primary source of truth unless a later architecture decision record explicitly overrides a section.

---

## 2. Product Vision

Build a browser-based multiplayer Judgement game that:

1. Allows six friends to create or join a private room.
2. Implements the game rules correctly and fairly.
3. Preserves private card information.
4. Survives browser refreshes and temporary network failures.
5. Provides smooth real-time gameplay.
6. Explains rules and invalid moves to new players.
7. Uses AI for coaching, explanations, tutorials, and summaries.
8. Keeps rules, scoring, legality, shuffling, and game state deterministic.
9. Can later scale to public matchmaking, ranked games, mobile apps, tournaments, and intelligent bots.

The key product differentiator should be:

> The game does not only tell players whether an action is valid. It explains why, analyses how decisions affected their bid, and helps them improve after every game.

---

## 3. First-Principles Architecture

### 3.1 Core problem

A multiplayer card game is not merely a UI showing cards.

It is a distributed state machine containing:

- Public information
- Private information
- Sequential actions
- Unreliable clients
- Unreliable networks
- Configurable rules
- Time-dependent decisions

### 3.2 Root architectural principle

> The client requests actions. The Rust server decides what actually happened.

Flutter must never be the authority for:

- Card ownership
- Turn order
- Legal moves
- Bids
- Trick winners
- Scores
- Dealer rotation
- Round progression
- Game completion
- Shuffle results

### 3.3 AI principle

> AI may explain, coach, summarise, classify, retrieve rules, or propose an action. AI must never directly mutate authoritative game state.

Every AI-proposed action must pass through:

1. Structured-output validation
2. Permission validation
3. Rust game-engine validation
4. Normal command processing

---

## 4. Scope

## 4.1 MVP scope

The MVP must include:

### Identity

- Guest play
- Nickname selection
- Temporary player identity (`SessionId`)
- Secure reconnect token (opaque, bound to `SessionId` + `GameId`, with expiry and rotation — see §15.1)

### Room management

- Create private room
- Generate room code
- Generate invite link
- Join room
- Leave room before start
- 4–8 player seats (host chooses table size; ADR 0003)
- Ready/unready state
- Host-controlled game start (needs ≥ 4 seated, all ready)
- Host migration when the host leaves (longest-connected occupied seat)
- Display selected rules (timer, trump mode, table size)

### Gameplay

- Standard 52-card deck
- 4–8 players (host-configured; default 6)
- Round pattern: descending `max → 1`, with `max` derived from player count
  (4 → 12…1, 5 → 10…1, 6 → 8…1, 7 → 7…1, 8 → 6…1)
- Trump modes (ADR 0003): revealed undealt card (default), **or** host-chosen
  first trump that then rotates ♠ → ♦ → ♣ → ♥ each round
- Optional turn timer (ADR 0003): omit ⇒ no deadlines / no auto-play
- Sequential bidding
- Zero bid allowed
- Configurable dealer-bid restriction
- Clockwise card play
- Mandatory follow-suit rule
- Trump-based trick winner
- Round scoring
- Final scoreboard
- Dealer rotation
- Rematch

### Reliability

- WebSocket connection
- Heartbeat
- Automatic reconnect
- State resynchronisation (full personalised snapshot)
- Server-side action deduplication
- Server-side state versioning
- Temporary disconnect pause
- Configurable bot takeover after timeout
- Permanent-leave bot playout
- Host migration
- Abandonment GC for idle rooms / empty games
- Game restoration after backend restart
- Turn-timer scheduling with stale-deadline guard

### AI MVP

- Deterministic reason-code explanations (“Why can’t I play this card?”, “Why did this player win the trick?”)
- Curated FAQ / common-questions map (no vector search required for MVP)
- Round summary from analytics features
- Post-game coaching from verified analytics
- Basic rule-based bot
- AI-generated game highlights (LLM only narrates structured facts)

Optional / post-MVP (feature-flagged):

- pgvector RAG over a growing rule corpus
- Adaptive tutorial skill profiles
- Natural-language rule configuration
- Voice assistant

### Security

- Server-only shuffle
- Secure random number generation
- Private player projections
- Authentication/session token
- WSS/HTTPS
- Rate limiting
- Origin validation
- Input validation
- Audit log for accepted actions

---

## 4.2 Explicit MVP non-goals

Do not include these in the initial MVP unless all mandatory requirements are complete:

- Ranked matchmaking
- Public rooms
- Tournaments
- Voice chat
- Text chat
- Real-money gaming
- Gambling mechanics
- Spectator mode
- Social login
- Friends list
- Learned reinforcement-learning bots
- Kubernetes
- Microservice decomposition
- Multi-region deployment
- Blockchain shuffle verification
- Native Android or iOS release
- Complex moderation workflows
- Arbitrary user-defined executable scoring code

---

## 5. Rule Specification

All game rules must be represented in structured configuration.

```rust
pub struct GameRules {
    pub min_players: u8,
    pub max_players: u8,
    pub round_pattern: RoundPattern,
    pub trump_rule: TrumpRule,
    pub bidding_rule: BiddingRule,
    pub scoring_rule: ScoringRule,
    /// `None` disables the turn timer entirely (ADR 0003).
    pub turn_timeout_seconds: Option<u16>,
    pub reconnect_grace_seconds: u16,
    pub allow_bots: bool,
}
```

---

## 5.1 Player count

### MVP (ADR 0003)

- **4 to 8 players**; host chooses table size at room creation (default 6)
- A game can start when **at least 4** players are seated and **everyone seated
  is ready** (an 8-seat room may start with 5)
- Empty seats may optionally be filled by bots (future room option)
- Seat numbers may be non-contiguous if players leave the lobby before start

### Future

- Public matchmaking tables
- Spectator seats

---

## 5.2 Maximum cards per player

When one card must remain undealt (so revealed-card trump remains possible at
every table size):

```text
maximum_cards_per_player = floor((52 - 1) / player_count)
```

| Players | Max cards / rounds |
|---------|--------------------|
| 4 | 12 → 1 |
| 5 | 10 → 1 |
| 6 | 8 → 1 |
| 7 | 7 → 1 |
| 8 | 6 → 1 |

The engine computes this; do not bake a literal `8` into pattern logic.

---

## 5.3 Round patterns

The rules engine should eventually support:

```rust
pub enum RoundPattern {
    Descending { max_cards: u8 },
    Ascending { max_cards: u8 },
    Mountain { max_cards: u8 },
    Custom(Vec<u8>),
}
```

`max_cards` must be **derived** from player count, not hardcoded:

```text
max_cards = floor((52 - 1) / player_count)
```

### MVP

Descending `max → 1` for the actual seated player count (see §5.2 table).

### Future

```text
1, 2, 3, …, max          # Ascending
1 … max … 1              # Mountain
```

```text
1, 2, 3, 4, 5, 6, 7, 8, 7, 6, 5, 4, 3, 2, 1
```

---

## 5.4 Trump rules

```rust
pub enum TrumpRule {
    RevealUndealtCard,
    RotatingSuit,
    DealerChooses,
    RandomSuit,
    NoTrump,
    FixedSequence { suits: Vec<Suit> },
}
```

### MVP (ADR 0003)

Host chooses one of two modes at room creation:

1. **Revealed undealt card** (default): shuffle, deal, reveal one card from the
   undealt remainder; its suit is trump; the revealed card stays out of play.
2. **Chosen first trump + rotation**: round 1 uses the host-picked suit; each
   later round advances one step in the fixed order **♠ → ♦ → ♣ → ♥**, wrapping.
   No card is revealed (`trump_card` is null; `trump` suit is always set).

`TrumpRule::rotating_from(first)` builds the `FixedSequence` starting at the
chosen suit.

---

## 5.5 Bidding rules

The bidding configuration must define:

- Starting bidder
- Direction
- Whether zero is allowed
- Whether bids are public immediately
- Whether bids may be edited (future; forced off in MVP)
- Whether the dealer restriction is enabled

```rust
pub struct BiddingRule {
    pub allow_zero: bool,
    pub bids_visible_immediately: bool,
    /// Parsed for forward compatibility; MVP always forces this to `false`.
    pub allow_edit_before_next_bid: bool,
    pub dealer_total_restriction: bool,
}
```

### Recommended MVP behaviour

- Bidding starts with the player clockwise from the dealer
- Bidding continues clockwise
- **The dealer bids last** (so the total-restriction lands on the dealer)
- Bids become visible immediately
- Bid range is `0..=cards_in_round`
- Once accepted, a bid cannot be changed (`allow_edit_before_next_bid` forced `false`)
- Dealer total restriction is configurable
- When enabled, the dealer cannot make total bids equal the number of tricks available
- **Invariant:** the restriction removes exactly one option from `0..=cards`, so a legal bid always remains — cover with a property test

---

## 5.6 Card-play rules

The game engine must validate:

1. The game is in the playing phase.
2. The command comes from the current player.
3. The player owns the card.
4. The card has not already been played.
5. The player follows the lead suit when possible.
6. If the player does not hold the lead suit, any card may be played.
7. A client-side disabled card is not considered sufficient validation.

---

## 5.7 Trick winner rules

A pure function must determine the winner.

```rust
pub fn determine_trick_winner(
    lead_suit: Suit,
    trump: Option<Suit>,
    plays: &[PlayedCard],
) -> Result<PlayerId, TrickEvaluationError>;
```

`plays` empty → `Err(EmptyTrick)`. Within a suit, rank order is Two (low) … Ace (high) — see §7.1.

### Who leads

0. **First trick of each round:** the player clockwise-left of the dealer leads.
1. Thereafter, the trick winner leads the next trick.

### Evaluation order

1. If one or more trump cards were played, the highest trump wins.
2. Otherwise, the highest card of the lead suit wins.
3. Cards outside the lead suit and trump cannot win.
4. Exactly one winner must be produced.

---

## 5.8 Scoring

Scoring must use a strategy interface.

```rust
pub struct ScoringContext {
    pub round_index: usize,
    pub cards_in_round: u8,
}

pub trait ScoringStrategy: Send + Sync {
    fn score_round(&self, ctx: &ScoringContext, bid: u8, tricks_won: u8) -> i32;
}
```

Pass `ScoringContext` now so progressive / zero-bid bonuses do not require a breaking trait change later.

### Recommended default scoring

```text
Exact bid: 10 + bid
Missed bid: 0
```

Example:

```text
Bid = 2
Won = 2
Score = 12
```

### Final ranking tie-break

1. Highest total score
2. Then most exact-bid rounds
3. Then fewest total tricks missed (absolute `|bid − won|` summed across rounds)
4. If still equal, shared rank

### Future alternatives

- Exact bid: `10 × bid`
- Missed bid: negative absolute difference
- Bonus for zero bids
- Progressive round bonus
- Custom predefined scoring profiles

Do not allow arbitrary user-submitted executable scoring scripts.

---

## 6. Game State Machine

```rust
pub enum GamePhase {
    Lobby,
    RoundSetup,
    Dealing,
    Bidding,
    Playing,
    RoundScoring,
    GameScoring,
    Finished,
}
```

### Required transitions

```text
Lobby
  -> RoundSetup
  -> Dealing
  -> Bidding
  -> Playing
  -> RoundScoring
  -> RoundSetup or GameScoring
  -> Finished
```

### Invalid transition examples

- Bid during `Dealing`
- Play a card during `Bidding`
- Start a second game while one is active
- Score a round before all tricks are complete
- Complete the game before the final round
- Accept a player action after `Finished`

State transitions should be represented as deterministic domain commands producing domain events.

---

## 7. Domain Model

## 7.1 Cards

```rust
pub struct Card {
    pub id: CardId,
    pub suit: Suit,
    pub rank: Rank,
}

pub enum Suit {
    Hearts,
    Diamonds,
    Clubs,
    Spades,
}

pub enum Rank {
    Two,
    Three,
    Four,
    Five,
    Six,
    Seven,
    Eight,
    Nine,
    Ten,
    Jack,
    Queen,
    King,
    Ace,
}
```

Within a suit, rank order is **Two (low) … Ace (high)**. Derive `Ord` / comparison for trick evaluation accordingly. There is no ranking across suits except via trump and lead-suit rules.

---

## 7.2 Core identifiers

Use strongly typed identifiers.

```rust
pub struct GameId(pub Uuid);
pub struct RoomId(pub Uuid);
pub struct PlayerId(pub Uuid);
pub struct ActionId(pub Uuid);
pub struct RoundId(pub u32);
pub struct TrickId(pub u32);
pub struct SessionId(pub Uuid);
```

Avoid passing raw strings throughout domain code.

---

## 7.3 Internal game state

```rust
pub struct InternalGameState {
    pub game_id: GameId,
    pub version: u64,
    pub phase: GamePhase,
    pub rules: GameRules,
    pub dealer: PlayerId,
    pub players: Vec<PlayerState>,
    pub deck: Vec<Card>,
    pub trump_card: Option<Card>,
    pub current_round: RoundState,
    pub score_table: ScoreTable,
    pub processed_actions: ProcessedActionRegistry,
}
```

---

## 7.4 Round state

```rust
pub struct RoundState {
    pub round_index: usize,
    pub cards_per_player: u8,
    pub bidding_order: Vec<PlayerId>,
    pub bids: HashMap<PlayerId, u8>,
    pub hands: HashMap<PlayerId, Vec<Card>>,
    pub current_trick: Vec<PlayedCard>,
    pub completed_tricks: Vec<CompletedTrick>,
    pub current_turn: PlayerId,
    pub tricks_won: HashMap<PlayerId, u8>,
    pub deadline: Option<DateTime<Utc>>,
}
```

---

## 8. Public and Private State Separation

Never serialize `InternalGameState` directly to clients.

Create a personalised projection.

```rust
pub struct PlayerGameView {
    pub game_id: GameId,
    pub state_version: u64,
    pub phase: GamePhase,
    pub own_hand: Vec<Card>,
    pub opponents: Vec<OpponentView>,
    pub current_trick: Vec<PlayedCard>,
    pub trump: Option<Suit>,
    pub trump_card: Option<Card>,
    pub current_turn: PlayerId,
    pub bids: Vec<PublicBid>,
    pub scores: Vec<PlayerScore>,
    pub round: PublicRoundState,
    pub legal_actions: LegalActionView,
}
```

```rust
pub struct OpponentView {
    pub player_id: PlayerId,
    pub nickname: String,
    pub seat: u8,
    pub card_count: usize,
    pub bid: Option<u8>,
    pub tricks_won: u8,
    pub connection_status: ConnectionStatus,
}
```

### Never expose during an active game

- Opponent cards
- Remaining deck order
- Shuffle seed
- Opponent private AI prompts
- Authentication token
- Session token
- Internal database identifiers not needed by the UI

---

## 9. Backend Architecture

```text
Flutter Web
    |
    | HTTPS / WSS
    v
Axum HTTP and WebSocket Layer
    |
    v
Authentication and Session Layer
    |
    v
Connection Manager
    |
    v
Room Registry
    |
    v
One Game Actor per Active Game
    |
    v
Pure Rust Game Engine
    |
    +--> PostgreSQL Event Store (+ action_id)
    +--> Snapshot Repository
    +--> Analytics / AI read models (event consumers only)
    +--> AI Orchestrator (explanations; optional RAG)
```

---

## 9.1 Game actor model

Each active game must have one sequential command processor.

```rust
pub struct GameCommandEnvelope {
    pub player_id: PlayerId,
    pub action_id: ActionId,
    pub expected_state_version: u64,
    pub command: ClientCommand,
    pub received_at: DateTime<Utc>,
}
```

```rust
pub async fn run_game_actor(
    mut state: InternalGameState,
    mut commands: mpsc::Receiver<GameCommandEnvelope>,
) {
    while let Some(envelope) = commands.recv().await {
        // Validate
        // Persist event
        // Apply event
        // Increment state version
        // Send personalised projections
    }
}
```

### Actor requirements

- Exactly one actor owns one active game state
- Commands are processed sequentially
- Bounded `mpsc` channel
- Queue overflow is observable and rejected with a retryable error (do not drop silently)
- Actor failure triggers restoration from durable state
- Actor shutdown persists a final snapshot where possible
- No external code may mutate the state directly
- Bot decision compute runs **off-actor** (spawned task); the result returns as a normal validated command envelope so long simulations cannot stall the actor loop
- Turn deadlines are scheduled as timer tasks that enqueue into the same bounded channel (see §16)

---

## 9.2 Read model / CQRS

Analytics, RAG, AI, and highlights **never** hold a handle to `InternalGameState`. They consume only:

- The persisted event stream
- Snapshots / projections written by the persistence layer

```text
Game Actor
  -> persist events (commit point)
  -> apply in memory
  -> broadcast PlayerGameView
  -> (async) project into analytics / AI read models
```

### Persistence requirements for idempotency

- Every persisted event stores `action_id` so `ProcessedActionRegistry` (§7.3) rebuilds correctly on restart
- The `games` row stores the fully-resolved `GameRules` snapshot used for that game so replay, coaching, and alternative-play reconstruct with the exact rules

### Commit ordering

1. Validate command
2. Produce domain events
3. **Persist transactionally (this is the commit)**
4. Apply events in memory
5. Increment version
6. Broadcast personalised views

If persistence fails, reject the command and do not advance in-memory state or broadcast.

---

## 9.3 Crate structure

```text
backend/
└── crates/
    ├── judgement-domain/
    ├── judgement-engine/
    ├── judgement-protocol/
    ├── judgement-server/
    ├── judgement-persistence/
    ├── judgement-analytics/
    ├── judgement-rag/
    ├── judgement-ai/
    └── judgement-bot/
```

### `judgement-domain`

- Card types
- Rule types
- Identifiers
- Player types
- Score types
- Domain errors

### `judgement-engine`

- State machine
- Command handling
- Domain events
- Bidding
- Trick evaluation
- Scoring
- Dealer rotation
- Projections
- State invariants

### `judgement-protocol`

- REST request/response models
- WebSocket message schema
- Versioned message envelopes
- Serialization tests

### `judgement-server`

- Axum routes
- WebSocket upgrades
- Session validation
- Room registry
- Game actor lifecycle
- Middleware
- Rate limiting
- Request tracing

### `judgement-persistence`

- PostgreSQL repositories
- Migrations
- Event store
- Snapshot store
- Player and room repositories

### `judgement-analytics`

- Bid analysis
- Trick analysis
- Mistake classification
- Player profile features
- Alternative-play simulation
- Game highlights

### `judgement-rag`

- Optional / feature-flagged vector retrieval over rule docs
- Chunking and embeddings (Phase 7b)
- pgvector storage with embedding-model version
- Metadata filters
- Rule citations
- Retrieval evaluation

MVP explanations live primarily in `judgement-engine` reason codes + `judgement-ai` templates / curated FAQ; this crate is not required to ship MVP.

### `judgement-ai`

- LLM client abstraction
- Prompt templates
- Structured output
- Safety filters
- Coaching
- Tutorial
- Commentary
- Rule explanation from reason codes / FAQ
- Rate limits and cost caps

### `judgement-bot`

- Bot trait
- Random bot
- Rule-based bot
- Heuristic bot
- Monte Carlo bot

---

## 10. Frontend Architecture

```text
frontend/
└── judgement_flutter/
    └── lib/
        ├── app/
        ├── screens/
        ├── widgets/
        ├── models/
        ├── state/
        ├── networking/
        ├── animations/
        ├── accessibility/
        └── ai_assistant/
```

### Frontend state categories

#### Local UI state

- Selected card
- Open/closed score panel
- Animation state
- Sound preference
- Tutorial overlay
- Pending command indicator

#### Authoritative server state

- Own cards
- Opponent card counts
- Turn
- Bids
- Scores
- Trump
- Current trick
- Round
- Phase
- Deadlines

#### Connection state

```dart
enum ConnectionState {
  connecting,
  connected,
  reconnecting,
  disconnected,
  sessionExpired,
}
```

### Command flow

```text
User taps card
  -> Flutter sends PlayCard command
  -> UI marks action as pending
  -> Rust validates
  -> Server emits accepted event or error
  -> Flutter commits or rolls back pending state
```

The UI may optimistically animate, but must not permanently update authoritative state before acknowledgement.

---

## 11. Required Screens

1. Landing page
2. Create room
3. Join room
4. Lobby
5. Main game table
6. Bidding overlay
7. Round result
8. Detailed scoreboard
9. Final game result
10. Reconnect/error screen
11. AI rule assistant panel
12. Post-game coaching screen

---

## 12. Game Table UX

### Desktop

- Oval or circular table
- Current player at bottom
- Other players around table
- Current trick in centre
- Scoreboard panel at side
- Player hand spread horizontally

### Mobile web

- Current player at bottom
- Opponents compressed around edges
- Scrollable or overlapping hand
- Scoreboard in drawer
- Large touch targets
- Landscape recommendation

### Required visible information

- Current round
- Cards per player
- Dealer indicator
- Trump suit
- Revealed trump card
- Bids
- Tricks won
- Total scores
- Current player
- Turn timer
- Connection status
- Valid cards
- Pending action status

### Card interaction

- Highlight legal cards
- Disable illegal cards visually
- Show reason on attempted illegal action
- Optional confirmation for mobile
- Animate played card to centre
- Highlight trick winner
- Delay trick clearing long enough to understand the result

---

## 13. Network Protocol

Use:

- REST for non-live operations
- WebSocket for game actions and live state

---

## 13.1 REST endpoints

```text
POST   /api/v1/guest-sessions
POST   /api/v1/rooms
POST   /api/v1/rooms/{room_id}/join
POST   /api/v1/rooms/{room_id}/leave
GET    /api/v1/rooms/{room_id}
POST   /api/v1/rooms/{room_id}/start
GET    /api/v1/games/{game_id}
GET    /api/v1/games/{game_id}/result
GET    /api/v1/games/{game_id}/history
POST   /api/v1/games/{game_id}/rematch
POST   /api/v1/ai/rules/query
GET    /api/v1/games/{game_id}/coach/{player_id}
```

---

## 13.2 WebSocket endpoint

```text
GET /api/v1/games/{game_id}/ws
```

### Protocol hardening

- Heartbeat ping/pong on a fixed interval; close if liveness timeout is exceeded
- Maximum WebSocket message size; reject with `CommandRejected { reason: MessageTooLarge }`
- Bounded actor channel backpressure: when full, reject with a retryable error (do not drop silently)
- MVP always emits full `StateSnapshot` after accepted commands; `StateDelta` is deferred (locked decision 6)

---

## 13.3 Client commands

```rust
pub enum ClientCommand {
    Ready,
    Unready,
    StartGame,
    PlaceBid { bid: u8 },
    PlayCard { card_id: CardId },
    SendReaction { reaction: Reaction },
    RequestStateSync,
    LeaveGame,
}
```

---

## 13.4 Command envelope

```json
{
  "protocol_version": 1,
  "action_id": "uuid",
  "game_id": "uuid",
  "expected_state_version": 84,
  "action": {
    "type": "play_card",
    "card_id": "heart-ace"
  }
}
```

### Required properties

- `action_id` prevents duplicate processing
- `expected_state_version` detects stale clients
- `protocol_version` supports future upgrades
- Every accepted command produces a new state version
- Duplicate action IDs return the prior result
- Stale commands receive a state-sync response

---

## 13.5 Server messages

```rust
pub enum ServerMessage {
    CommandAccepted(CommandAccepted),
    CommandRejected(CommandRejected),
    StateSnapshot(PlayerGameView),
    // StateDelta deferred past MVP — see locked decision 6
    PlayerConnected(PlayerConnectionEvent),
    PlayerDisconnected(PlayerConnectionEvent),
    HostChanged(HostChangedEvent),
    TimerUpdated(TimerEvent),
    AiExplanation(AiExplanationResponse),
}
```

`TimerEvent` includes `remaining_ms` and `server_now` for client clock reconciliation.

---

## 14. Persistence

Use PostgreSQL.

### Initial tables

```text
users
guest_sessions
rooms
room_players
games
game_players
game_events
game_snapshots
round_results
game_results
ai_explanations
player_analytics
```

---

## 14.1 Domain events

```rust
pub enum GameEvent {
    RoomCreated,
    PlayerJoined,
    PlayerLeft,
    PlayerReady,
    PlayerUnready,
    HostChanged,
    GameStarted,
    RoundStarted,
    CardsDealt,
    TrumpSelected,
    BidPlaced,
    CardPlayed,
    TrickCompleted,
    RoundCompleted,
    DealerRotated,
    GameCompleted,
    PlayerDisconnected,
    PlayerReconnected,
    BotTookOver,
    PlayerResumedControl,
    DeadlineExpired,
}
```

Every persisted event stores `action_id` (when originating from a client command) so deduplication survives restart.

---

## 14.2 Event log and snapshots

After every accepted command:

1. Validate command
2. Create domain events (include `action_id` on the event record)
3. Persist events transactionally (**commit point**)
4. Apply events
5. Increment version
6. Broadcast personalised snapshots

Create snapshots:

- Every fixed number of events, for example 25 or 50
- At round completion
- At game completion
- Before graceful actor shutdown

Recovery:

```text
Load latest snapshot
  -> Load later events
  -> Replay events
  -> Validate invariants
  -> Restart game actor
```

---

## 15. Disconnection and Reconnection

### On disconnect

- Mark player offline
- Preserve seat
- Preserve hand
- Start reconnect grace timer
- Do not reveal cards
- Notify remaining players
- Keep game paused initially

### Recommended MVP policy

```text
0–60 seconds:
- Pause game
- Allow secure reconnect

After 60 seconds:
- Rule-based bot takes temporary control

When player returns:
- Restore control at a safe command boundary

If player never returns (permanent leave):
- Rule-based bot plays out the remainder of the game for that seat
```

### Reconnect request

Client provides:

- Game ID
- Session / reconnect token
- Last received state version

Server responds with:

- A fresh personalised snapshot (MVP always uses full snapshot; deltas are a later optimisation)

---

## 15.1 Session and reconnect tokens

Guest login issues:

- `SessionId` (stable for the browser session)
- Opaque reconnect token (unguessable, cryptographically random)

Token properties:

- Bound to `SessionId` + `GameId` (or room while in lobby)
- Short TTL with rotation on every successful reconnect
- Stored client-side in Flutter web `localStorage`

XSS exposure mitigations:

- Short TTL + rotation
- WSS only
- Never log the token (see §22)
- Treat token theft as session compromise; rotate and invalidate prior token

---

## 15.2 Presence lifecycle

### Host migration

When the host disconnects or leaves (lobby or mid-game):

1. Auto-promote the **longest-connected occupied seat** to host
2. Emit `HostChanged`
3. New host receives start / kick controls in lobby

### Permanent leave

After reconnect grace expires, the seat is bot-controlled. If the player never returns, the bot finishes the game. `PlayerResumedControl` restores at a safe command boundary if they do return.

### Abandonment GC

Background reaper for:

- Rooms that never start within a TTL
- Games where all human seats have left

Emit metrics `rooms_reaped`, `games_abandoned`, and free the game actor.

---

## 16. Timers

The server owns all deadlines.

```rust
pub struct TurnDeadline {
    pub deadline_id: Uuid,
    pub expires_at: DateTime<Utc>,
}
```

The client only renders remaining time. Wire format sends **remaining duration + server `now`** (not only absolute `expires_at`) so clients reconcile clock skew, browser suspend, and DST.

### Scheduling inside the actor

The single-threaded game actor must not block on wall-clock time:

1. When entering a state with a deadline, the actor spawns a timer task that sends a `Timeout { round, trick, turn, deadline_id }` envelope into the **same bounded `mpsc`** at `expires_at`.
2. Each deadline has a `deadline_id`. A player action that advances the turn invalidates the prior `deadline_id`, so a late-arriving `Timeout` is ignored (**stale-deadline guard**).
3. On a valid `Timeout`, the actor applies a **legal** automatic action (auto-bid policy / lowest legal card) or triggers bot takeover — always through the normal validation path.
4. Bot compute itself runs off-actor; only the resulting command is enqueued.

### Requirements

- Device clock cannot extend the turn
- Browser suspension cannot extend the turn
- Server emits timeout event
- Timeout policy is configurable
- Automatic action must always be legal
- Bot takeover actions use the same command validation path
- Stale deadlines never mutate state

---

## 17. Bots

## 17.1 Bot abstraction

```rust
#[async_trait]
pub trait BotStrategy {
    async fn choose_bid(&self, view: BotGameView) -> Result<u8, BotError>;
    async fn choose_card(&self, view: BotGameView) -> Result<CardId, BotError>;
}
```

### Level 1: Random legal bot

Use for:

- Tests
- Load generation
- Basic fallback

### Level 2: Rule-based bot

Rules:

- Estimate likely tricks from high cards and trump strength
- If below bid, favour actions likely to win
- If bid already reached, favour actions likely to lose
- Preserve trump when future control is needed
- Discard dangerous high cards when avoiding tricks

### Level 3: Heuristic bot

Score legal actions using:

```text
action_score =
    exact_bid_probability
  + immediate_trick_value
  + future_hand_control
  + trump_preservation_value
  - unwanted_extra_trick_risk
```

### Level 4: Monte Carlo bot

For every legal card:

1. Generate possible hidden hands consistent with public information
2. Simulate round continuations
3. Calculate exact-bid probability
4. Select highest expected success

### Level 5: Learned bot

Future only:

- Self-play
- Reinforcement learning
- Imitation learning
- Human gameplay logs

Do not use an LLM as the authoritative card-selection engine for production gameplay.

---

## 18. AI Strategy

AI capabilities are divided into four categories:

1. Retrieval and rule explanation
2. Natural-language generation
3. Deterministic analytics plus explanation
4. Decision support and simulation

---

## 18.1 Rule assistant (MVP: deterministic + curated FAQ)

### Goal

Answer questions using:

- The configured room rules
- Deterministic engine reason codes
- A curated, versioned FAQ / common-questions document set

**MVP does not require vector search.** The Judgement ruleset is small and static; reason codes (§18.2 / §18.3) plus templates and a curated FAQ map beat RAG on accuracy, latency, and cost for the initial ship. pgvector RAG is an optional later enhancement (Phase 7b) when the corpus grows (variants, regional rulesets).

### Example questions

- Why can’t I play this card?
- What is trump?
- How is my score calculated?
- Why was my bid rejected?
- Can the dealer bid this number?
- Why did Player 4 win this trick?

### Knowledge base (curated)

```text
rules/
├── basic_gameplay.md
├── bidding.md
├── scoring_exact_bid.md
├── scoring_variants.md
├── trump_rules.md
├── dealer_restriction.md
├── six_player_rules.md
├── disconnect_policy.md
└── common_questions.md
```

### MVP response path

```text
Question or illegal-move attempt
  -> Engine reason code + structured facts (when gameplay-related)
  -> Template or curated FAQ lookup
  -> Optional LLM rewrite for tone
  -> Structured response with citations
```

### Optional later: vector RAG (feature-flagged)

When enabled:

- Chunk rule docs with metadata (`rule_id`, `ruleset_version`, `category`, `player_count`, `variant`)
- Store embeddings with **embedding-model version**
- Filter retrieval by active ruleset version **and** embedding version
- PostgreSQL + pgvector

### Response requirements

Every answer must return:

```json
{
  "answer": "You must play a Spade because you still hold the Seven of Spades.",
  "rule_references": ["follow-suit-001"],
  "confidence": 0.96,
  "suggested_action": "seven-of-spades"
}
```

Suggested actions remain advisory and require Rust validation.

---

## 18.2 Contextual invalid-move explanations

The game engine should produce deterministic reason codes.

```rust
pub enum GameError {
    NotYourTurn,
    WrongPhase,
    CardNotInHand,
    MustFollowSuit,
    BidOutOfRange,
    DealerBidRestriction,
    BidAlreadyPlaced,
    StaleState,
    ActionAlreadyProcessed,
    PlayerNotInGame,
    GameAlreadyFinished,
}
```

Example:

```text
Engine reason:
MUST_FOLLOW_SUIT

Structured facts:
Lead suit = Spades
Player owns Seven of Spades
Attempted card = Ace of Hearts
```

LLM output:

> Player 3 led with Spades. You still have the Seven of Spades, so you must follow suit. You can play the Ace of Hearts only when you have no Spades.

The LLM must never independently decide whether the move was legal.

---

## 18.3 Trick winner explanation

The engine emits a deterministic reason.

```json
{
  "lead_suit": "clubs",
  "trump_suit": "hearts",
  "plays": [
    ["player_1", "ace_of_clubs"],
    ["player_2", "two_of_hearts"],
    ["player_3", "king_of_clubs"]
  ],
  "winner": "player_2",
  "reason_code": "TRUMP_BEATS_LEAD_SUIT"
}
```

The LLM converts the verified reason into beginner-friendly language.

---

## 18.4 Adaptive tutorial

### Goals

- Teach rules at the moment they become relevant
- Reduce explanation detail as player competence improves
- Focus on repeatedly misunderstood rules

```rust
pub struct PlayerSkillProfile {
    pub understands_follow_suit: f32,
    pub understands_trump: f32,
    pub understands_bidding: f32,
    pub understands_avoidance_play: f32,
    pub games_played: u32,
}
```

Progression:

```text
First game:
- Detailed explanation

Second game:
- Short hint

Later games:
- Highlight valid cards only

Experienced player:
- No automatic tutorial
```

Players must be able to disable tutorials.

---

## 18.5 Round explanation

At round completion, calculate:

- Bid
- Tricks won
- Score
- Extra or missing tricks
- Most important trick
- Relevant rule reason
- One actionable suggestion

Example:

> You bid 2 and won 3. The extra trick came when your King of Clubs remained highest after everyone followed with lower Clubs.

The source facts must come from deterministic analytics.

---

## 18.6 Post-game coach

### Deterministic feature extraction

```rust
pub struct PlayerGameAnalysis {
    pub exact_bid_rounds: u8,
    pub total_rounds: u8,
    pub overbid_rounds: u8,
    pub underbid_rounds: u8,
    pub trump_cards_played_early: u8,
    pub avoidable_extra_tricks: u8,
    pub strongest_round: RoundId,
    pub weakest_round: RoundId,
    pub notable_decisions: Vec<DecisionAnalysis>,
}
```

### Coaching output

- Overall bid accuracy
- Strongest round
- Weakest round
- Risk pattern
- Trump usage pattern
- Two concrete improvement suggestions
- One positive observation
- No unsupported psychological claims

Allowed:

> You tend to bid conservatively when holding one or two trump cards.

Not allowed:

> You are an anxious person.

---

## 18.7 Alternative-play replay assistant

After a game:

1. Reconstruct historical state
2. Generate all legal actions
3. Simulate alternatives
4. Rank outcomes
5. Ask LLM to explain verified results

Example:

> Playing the Four of Spades was safer. The King forced you to win after you had already completed your bid.

This feature belongs after the basic analytics engine is stable.

---

## 18.8 AI game highlights

Generate highlights from deterministic events:

- Biggest comeback
- Most accurate bidder
- Best single round
- Closest miss
- Game-changing trick
- Surprise trump win
- Final margin
- Longest exact-bid streak

The LLM only converts structured highlights into natural language.

---

## 18.9 Natural-language rule configuration

A host may type:

> We play 4–8 players (host picks size), descending max→1 rounds, exact bid gives ten plus bid, and the dealer cannot make the total equal the tricks. Turn timer is optional; trump is either a revealed undealt card or a host-chosen suit that then rotates ♠→♦→♣→♥.

AI converts this into structured JSON.

```json
{
  "players": 6,
  "round_pattern": [8, 7, 6, 5, 4, 3, 2, 1],
  "scoring": {
    "exact_bid_bonus": 10,
    "add_bid_to_bonus": true,
    "missed_bid_score": 0
  },
  "dealer_bid_restriction": true
}
```

### Safety requirements

- Validate against JSON schema
- Reject unsupported rules
- Display detected rules for confirmation
- Never generate executable code
- Never silently modify the room configuration

This is a post-MVP feature.

---

## 18.10 Natural-language analytics

Example queries:

- Show games where I lost by fewer than five points.
- How accurate are my bids in five-card rounds?
- Which opponent defeats me most often?
- Do I perform better when Hearts is trump?

Architecture:

```text
Natural-language question
  -> LLM selects predefined analytics query
  -> Rust validates query
  -> Database executes safe parameterised query
  -> LLM explains results
```

Do not allow unrestricted model-generated SQL execution.

---

## 18.11 Voice assistant

Future feature:

```text
Speech
  -> Speech-to-text
  -> Intent extraction
  -> Rust game-state query
  -> RAG only when rules are needed
  -> Text response
  -> Optional text-to-speech
```

Example commands:

- What is the trump?
- How many tricks do I need?
- Read the current score.
- Why did Rahul win?

---

## 18.12 AI moderation

Required only when public text interaction is introduced.

Possible uses:

- Spam detection
- Abuse detection
- Harassment detection
- Inappropriate nickname detection
- Report prioritisation

Do not use AI alone for irreversible permanent bans.

---

## 19. Where RAG Must and Must Not Be Used

| Use case | RAG (MVP) | Primary mechanism |
|---|---:|---|
| Explain rules | Curated FAQ first; optional RAG later | Templates + FAQ; optional vector retrieval |
| Explain scoring variant | Curated FAQ / config | Active rule config + docs |
| Gameplay FAQ | Curated FAQ | FAQ map |
| Explain current trick | No | Engine reason + LLM |
| Detect legal cards | No | Rust rules engine |
| Calculate winner | No | Rust trick evaluator |
| Calculate score | No | Rust scoring strategy |
| Select best card | No | Heuristic or simulation |
| Post-game coaching | No | Analytics + LLM |
| Highlights | No | Structured events + LLM |
| Matchmaking | No | Rating algorithm |
| Voice state queries | Usually no | Structured game query |
| Chat moderation | No | Moderation classifier |
| Player profiling | No | Analytics features |

---

## 20. AI Security and Privacy

### During an active game, AI may receive

- Current player’s own cards
- Publicly played cards
- Public bids
- Scores
- Current room rules
- Current permitted player view
- Deterministic reason codes

### AI must not receive

- Opponent hidden cards
- Undealt deck order
- Shuffle seed
- Authentication token
- Session token
- Other players’ private queries
- Full internal game state

### Prompt injection defence

- Treat retrieved documents as untrusted data
- Use fixed system prompts
- Separate instructions from retrieved content
- Permit only expected structured output
- Validate all identifiers
- Reject unknown rule references
- Never allow retrieved text to invoke tools directly

### AI availability

The game must remain fully playable when:

- LLM provider is unavailable
- Embedding service is unavailable
- Vector search is unavailable
- AI response times out

AI features must fail independently without blocking gameplay.

### Cost and rate limits

- Per-user / per-session AI rate limits
- Hard token / cost caps with graceful deterministic fallback messages
- Track AI request count, latency, timeout rate, and estimated cost in metrics (§22)

---

## 21. Fairness and Anti-Cheating

### MVP controls

- Server-side shuffle
- OS-backed secure randomness
- Do not send hidden cards
- Validate all commands server-side
- Enforce turn order
- Deduplicate action IDs
- State-version checking
- Audit accepted actions
- WSS/HTTPS
- Secure cookies or tokens
- Rate limiting
- Explicit CORS/origin configuration
- No secrets in logs
- No private hands in logs

### Future verifiable shuffle

Commit-and-reveal:

1. Generate shuffle seed
2. Publish hash before deal
3. Shuffle using seed
4. Reveal seed after game
5. Allow independent verification

A stronger future version may combine random contributions from multiple players.

---

## 22. Observability

### Metrics

- Active WebSockets
- Connected players
- Active rooms
- Active game actors
- Games started
- Games completed
- Average game duration
- Reconnect count
- Bot takeover count
- Rooms reaped / games abandoned
- Invalid action count by reason
- Command processing latency
- Actor queue depth
- Stale-deadline ignores
- Database write failures
- Snapshot restoration failures
- AI request count
- AI latency
- AI timeout rate
- AI estimated cost
- Retrieval hit rate (when RAG enabled)
- AI fallback rate

### Structured log fields

```text
game_id
room_id
player_id
action_id
state_version
command_type
result
latency_ms
connection_id
trace_id
```

Never log:

- Session token
- Authentication token
- Full hidden hands
- Shuffle seed before game completion
- Sensitive AI prompts containing private user information

---

## 23. Testing Strategy

## 23.1 Unit tests

Must cover:

- Deck creation
- Deck uniqueness
- Shuffle determinism with injected seed
- Deal counts
- Trump selection
- Bid validation
- Dealer restriction (and that a legal bid always remains)
- First-trick leader (clockwise-left of dealer)
- Turn order
- Follow-suit validation
- Trick winner (including empty-trick error)
- Scoring and final ranking tie-break
- Dealer rotation
- Round progression
- Game completion
- Personalised projections
- Reconnection
- Action deduplication (including after event replay / restart)
- State-version conflicts
- Stale-deadline guard
- Host migration promotion order

---

## 23.2 Property-based tests

Required invariants:

- Exactly 52 unique cards exist
- No card appears in two hands
- Dealt cards + undealt cards = 52
- Every trick has exactly one winner
- A player cannot play a card not owned
- A player holding lead suit cannot play another suit
- Total tricks won equals total tricks played
- Every round is scored once
- Total completed rounds matches configured pattern
- Opponent hidden cards never appear in another player view
- Duplicate commands cannot modify state twice
- Replaying events reproduces the same state and the same `ProcessedActionRegistry`
- Dealer restriction removes exactly one bid option when enabled
- `max_cards = floor((52 - 1) / player_count)` for derived descending patterns

Use `proptest` or an equivalent Rust property-testing library.

---

## 23.3 Deterministic simulation

Support injected shuffle seed.

```rust
let engine = GameEngine::new_with_seed(42);
```

Bug reports should identify:

- Seed
- Game ID
- State version
- Round
- Trick
- Action ID

---

## 23.4 Bot simulation

Run thousands of complete games.

Assertions:

- Every game terminates
- No deadlock
- No impossible state
- No invalid card ownership
- Correct trick count
- Correct scoring count
- State can be replayed
- Bot commands pass normal validation
- Disconnect and reconnect do not duplicate actions

---

## 23.5 Protocol tests

- JSON round-trip
- Unknown protocol version
- Missing fields
- Invalid enum values
- Duplicate action
- Stale version
- Out-of-order delivery
- Reconnect snapshot
- Large-message rejection

---

## 23.6 Frontend tests

- Legal card highlighting
- Illegal card disabled
- Rejected action rollback
- Reconnect screen
- Responsive layout
- Scoreboard accuracy
- Bidding controls
- Timer display
- Accessibility labels
- Reduced-motion option

---

## 23.7 AI tests

### FAQ / explanation evaluation dataset

Create test questions for:

- Follow-suit
- Trump
- Bidding
- Dealer restriction
- Scoring
- Round sequence
- Disconnect policy

Evaluate:

- Correct rule / FAQ retrieved (or correct reason-code template)
- Correct ruleset version
- No irrelevant rule
- Correct citation
- No opponent-card leakage
- Graceful fallback when confidence is low or LLM is down

### Structured output tests

- Valid schema
- Invalid card ID rejected
- Unknown rule reference rejected
- Unsupported action rejected
- Timeout fallback
- Provider outage fallback
- Rate-limit / cost-cap fallback

### Coaching tests

- Numbers match deterministic analytics
- No hallucinated rounds
- No unsupported psychological claims
- Suggestions reference real game events

When vector RAG is enabled (Phase 7b), additionally evaluate embedding-version filtering and retrieval hit rate.

---

## 24. Accessibility

The application must support:

- Suit symbols and labels, not colour alone
- Keyboard navigation
- Screen-reader labels
- High contrast
- Reduced animation
- Mute sounds
- Adjustable card size
- Large touch targets
- Clear current-turn indicator
- Text alternatives for animations
- Responsive layouts

---

## 25. Deployment

## 25.1 MVP deployment

```text
Flutter static files -> CDN or static hosting
Rust Axum server     -> Single container
PostgreSQL           -> Managed database
Object storage       -> Optional rule-document source
```

Do not begin with Kubernetes.

### Basic infrastructure

- Containerised Rust backend
- Automated database migrations
- TLS termination
- Environment-based configuration
- Health endpoint
- Readiness endpoint
- Structured logging
- Metrics endpoint
- Daily database backup
- Secret manager

---

## 25.2 Future scaling

Partition by `game_id`.

```text
hash(game_id) -> owning backend instance
```

Later components may include:

- Redis for room ownership
- Redis for presence
- Pub/sub for cross-instance messages
- Sticky routing or explicit room routing
- Multiple backend replicas
- Background analytics worker
- Dedicated AI service
- Dedicated embedding service

The pure game engine must remain independent of distribution concerns.

---

## 26. Repository Layout

```text
judgement/
├── PLAN.md
├── README.md
├── docs/
│   ├── RULES.md
│   ├── ARCHITECTURE.md
│   ├── PROTOCOL.md
│   ├── AI_DESIGN.md
│   ├── SECURITY.md
│   ├── TEST_STRATEGY.md
│   └── adr/
│
├── backend/
│   ├── Cargo.toml
│   └── crates/
│       ├── judgement-domain/
│       ├── judgement-engine/
│       ├── judgement-protocol/
│       ├── judgement-server/
│       ├── judgement-persistence/
│       ├── judgement-analytics/
│       ├── judgement-rag/
│       ├── judgement-ai/
│       └── judgement-bot/
│
├── frontend/
│   └── judgement_flutter/
│
├── contracts/
│   ├── game_protocol.schema.json
│   ├── game_rules.schema.json
│   ├── ai_rule_response.schema.json
│   └── coach_response.schema.json
│
├── rules/
│   ├── basic_gameplay.md
│   ├── bidding.md
│   ├── scoring_exact_bid.md
│   ├── trump_rules.md
│   ├── dealer_restriction.md
│   ├── six_player_rules.md
│   └── common_questions.md
│
├── deployment/
│   ├── docker/
│   ├── migrations/
│   └── scripts/
│
└── tests/
    ├── simulations/
    ├── protocol/
    ├── e2e/
    └── rag_evaluation/
```

---

## 27. Implementation Phases

## Phase 0 — Rules and contracts

### Deliverables

- `RULES.md` (includes locked decisions from §0)
- `game_rules.schema.json`
- Card ranking definition (Ace high)
- Round pattern definition (derived `max_cards`)
- Bidding rule definition (dealer bids last; restriction invariant)
- First-trick leader and subsequent lead rules
- Scoring rule definition + final ranking tie-break
- Disconnect / host-migration / permanent-leave policy
- Error-code catalogue
- WebSocket protocol draft (snapshot-only MVP)

### Exit criteria

- All ambiguous rules resolved
- Six-player example game can be described end to end
- All rules represented in structured configuration
- Locked decisions table is reflected in `RULES.md`

---

## Phase 1 — Pure Rust game engine

### Deliverables

- Card and deck model
- Secure shuffle abstraction
- Dealing
- State machine
- Bidding
- Follow-suit validation
- Trick evaluation
- Scoring
- Dealer rotation
- Game completion
- Player-specific projections
- Unit and property tests

### Exit criteria

- Complete six-player games run without networking
- Engine has no dependency on Axum, PostgreSQL, or Flutter
- All state transitions are tested
- Hidden-card projection tests pass

---

## Phase 2 — Bot simulation

### Deliverables

- Random bot
- Rule-based bot
- Simulation runner
- Seeded reproducibility
- Invariant reporting

### Exit criteria

- At least 10,000 games complete in automated tests
- No invariant violations
- Failures are reproducible by seed

---

## Phase 3 — Backend room service

### Deliverables

- Axum application
- Guest session + reconnect token lifecycle
- Room creation
- Room join
- Room actor
- WebSocket endpoint (heartbeat, max message size, backpressure)
- Command envelope
- Full state snapshot (no deltas in MVP)
- Action deduplication
- State versioning
- Turn-timer scheduling + stale-deadline guard
- Error responses

### Exit criteria

- Six test clients can complete a game
- Duplicate actions do not apply twice
- Stale clients resynchronise correctly
- Timer expiry applies a legal automatic action
- Late timeouts after a player act are ignored

---

## Phase 4 — Flutter lobby and table

### Deliverables

- Landing
- Create/join room
- Lobby
- Main table
- Bidding
- Card play
- Scoreboard
- Final result (with tie-break display)
- Responsive layout

### Exit criteria

- Six browser tabs complete a full game
- Invalid moves receive understandable feedback
- Desktop and mobile layouts are usable

---

## Phase 4.5 — Table options (ADR 0003, before Phase 5)

Product amendments from play-testing after Phase 4. Documented in
`docs/adr/0003-table-size-timer-trump-options.md`.

### Deliverables

- Optional turn timer (`null` ⇒ no deadlines / no auto-play)
- Host-chosen table size 4–8; start needs ≥ 4 seated and all ready
- Optional first trump with fixed ♠ → ♦ → ♣ → ♥ rotation (else revealed-card)
- Landing create-room options UI; lobby displays the chosen rules
- Engine / protocol / bot simulations parameterised over 4–8 players

### Exit criteria

- 4-, 6-, and 8-seat configurations complete a full game
- A room with timer disabled never emits `TimerUpdated` and never auto-plays
- Chosen first trump appears in round 1; subsequent rounds follow the rotation
- An 8-seat room can start with 5 ready players

---

## Phase 5 — Persistence and recovery

### Deliverables

- PostgreSQL schema
- Event store (events include `action_id`)
- Snapshots
- Game restoration
- Round results
- Game results
- Game history
- Resolved `GameRules` snapshot on `games` row

### Exit criteria

- Backend can restart during a game
- Game actor restores to correct state
- Dedup registry rebuilds from events
- Players can reconnect and continue

---

## Phase 6 — Reconnect, timeout, presence, and bot takeover

### Deliverables

- Heartbeat
- Reconnect token rotation
- Pause policy
- Grace timer
- Bot takeover + permanent-leave bot playout
- Player control restoration
- Host migration
- Abandonment GC + metrics

### Exit criteria

- Refresh does not lose seat
- Temporary network loss is recoverable
- Bot actions are legal
- Returning player receives correct state
- Host leave promotes another seat
- Abandoned rooms/games are reaped

---

## Phase 7 — Explanations + curated FAQ

### Deliverables

- Versioned rule documents + `common_questions.md`
- Deterministic reason codes wired to templates
- Invalid-move explanation
- Trick-winner explanation
- Rule-query endpoint (FAQ / template path)
- Flutter assistant panel
- Rule citations
- Explanation evaluation tests
- AI rate limits + cost caps

### Exit criteria

- Core rule questions resolve via FAQ / reason codes with citations
- No hidden opponent information is exposed
- Gameplay works when AI is unavailable
- Cost caps trigger deterministic fallback

---

## Phase 7b — Vector RAG (optional, feature-flagged)

### Deliverables

- Chunking + embedding pipeline
- pgvector storage with embedding-model version
- Metadata + embedding-version filters
- Retrieval evaluation tests

### Exit criteria

- Flag off: behaviour identical to Phase 7
- Flag on: retrieval respects ruleset and embedding versions

---

## Phase 8 — Coaching and highlights

### Deliverables

- Round summary
- Post-game analytics
- Coaching response
- Game highlights

### Exit criteria

- All facts in AI output trace to deterministic data
- No hallucinated scores
- Coaching includes specific evidence
- AI timeout uses a deterministic fallback message

---

## Phase 9 — Production hardening

### Deliverables

- Rate limiting
- Origin validation
- Security review
- Observability
- Load testing
- Accessibility testing
- Backup verification
- Deployment automation
- Incident runbook

### Exit criteria

- Load target met
- Security checklist passed
- Database restore tested
- Monitoring dashboards available
- Basic incident response documented

---

## 28. Future Roadmap

### Version 1

- Mountain round pattern
- More scoring profiles
- Different player counts
- User accounts
- Reactions
- Game replay
- Personal statistics
- Improved heuristic bots

### Version 2

- Public rooms
- Matchmaking
- Friends
- Spectators
- Leaderboards
- Ranked games
- Moderation
- Tournaments
- Verifiable shuffle

### Version 3

- Android and iOS apps
- Regional rulesets
- Multilingual assistant
- Voice assistant
- Clubs and leagues
- Advanced Monte Carlo analysis
- Personalised training challenges
- Learned self-play bot

---

## 29. Coding-Agent Rules

The coding agent must follow these constraints.

### 29.1 Source-of-truth hierarchy

1. Tests
2. This `PLAN.md`
3. Architecture decision records
4. Code comments
5. Existing implementation

When requirements conflict, the coding agent must surface the conflict rather than silently choosing.

### 29.2 Development discipline

- Implement one vertical slice at a time
- Keep domain logic independent
- Add tests with every rule
- Do not introduce infrastructure before needed
- Do not duplicate game rules in Flutter
- Do not let AI bypass the engine
- Do not serialize internal game state
- Do not use unbounded channels
- Do not use global mutable game state
- Do not log private cards
- Do not generate raw SQL from LLM output
- Do not hardcode secrets
- Do not silently change protocol schemas

### 29.3 Required workflow for each feature

1. Identify affected requirements
2. Update or add tests
3. Update domain model
4. Implement pure logic
5. Add persistence if needed
6. Add protocol changes
7. Add UI
8. Add observability
9. Update documentation
10. Verify backward compatibility

### 29.4 Pull request checklist

Every change must answer:

- What requirement does this implement?
- What invariant is protected?
- What tests were added?
- Does it expose hidden state?
- Does it change the protocol?
- Does it change persistence?
- Does it change AI prompts or schemas?
- Can gameplay continue if AI fails?
- Is migration or rollback required?
- Are metrics and logs sufficient?

---

## 30. Definition of Done

A feature is done only when:

- Domain logic exists
- Unit tests pass
- Property tests pass where applicable
- Protocol is documented
- Persistence migration exists where required
- UI handles loading, success, failure, and reconnect
- Metrics exist for critical operations
- Security implications are reviewed
- AI output is structured and validated where applicable
- Documentation is updated
- Acceptance criteria are demonstrated

---

## 31. MVP Acceptance Criteria

The MVP is complete when all of the following are true:

1. 4–8 players can join a private room through browser links (host picks size).
2. The host can start once ≥ 4 are seated and all seated players are ready; host migration works if the host leaves.
3. Every round deals the correct number of cards (`max_cards` derived from player count).
4. No player can inspect another player’s hand.
5. Trump is selected correctly (revealed card **or** chosen-suit rotation per ADR 0003).
6. Bidding occurs in correct order; dealer bids last.
7. Dealer restriction works when enabled and always leaves a legal bid.
8. Illegal card plays are rejected with reason codes.
9. Follow-suit is enforced.
10. First trick is led by the player clockwise-left of the dealer; thereafter the winner leads.
11. Trick winner is correct (Ace high within suit).
12. Scores are correct; final ranking applies the locked tie-break.
13. Dealer rotates correctly.
14. All rounds complete (descending `max → 1` for the seated player count).
15. Final ranking is shown.
15b. Optional turn timer: when disabled, no auto-play occurs.
16. Refreshing a browser does not lose the game.
17. Duplicate actions are not processed twice (including after backend restart).
18. Backend restart restores an active game with rebuilt dedup registry.
19. A disconnected player may be temporarily replaced by a bot; permanent leave is bot-played out.
20. Rule explanations answer core questions via FAQ / reason codes with citations (pgvector not required).
21. AI cannot access hidden opponent cards.
22. The game remains playable when AI services fail; AI rate/cost caps fall back gracefully.
23. Post-game coaching uses verified analytics.
24. Automated bot simulation completes without invariant failure.
25. Production deployment uses HTTPS/WSS.
26. Monitoring exposes connection, game, error, abandonment, and AI metrics.
27. Turn timeouts apply legal automatic actions; stale deadlines are ignored.

---

## 32. Suggested Initial Technical Choices

### Backend

- Rust stable
- Axum
- Tokio
- Serde
- SQLx
- PostgreSQL
- UUID
- Chrono or time
- tracing
- tower-http
- proptest
- rand with OS-backed RNG
- thiserror
- async-trait where needed

Optional (feature-flagged, not MVP-critical):

- pgvector for vector RAG (Phase 7b)

### Frontend

- Flutter Web
- Riverpod or Bloc
- WebSocket client
- Freezed or equivalent immutable models
- JSON serialization
- Responsive layout utilities
- Integration tests
- Accessibility semantics

### AI

- Provider abstraction
- Structured JSON output
- Deterministic reason-code templates + curated FAQ for MVP
- Prompt templates stored and versioned
- Deterministic fallback responses
- AI request timeout
- Per-user rate limits and hard cost caps
- Cost and latency metrics
- Embedding abstraction only when Phase 7b RAG is enabled

---

## 33. Recommended First Development Sprint

### Sprint goal

Complete a deterministic six-player game entirely in Rust.

### Tasks

1. Create workspace and crates
2. Define card model
3. Generate 52-card deck
4. Implement injected-seed shuffle
5. Define six-player rules
6. Implement dealing
7. Implement bidding state
8. Implement follow-suit validation
9. Implement trick winner
10. Implement default scoring
11. Implement round transition
12. Implement dealer rotation
13. Implement game completion
14. Implement player projections
15. Add random bot
16. Add full-game simulation
17. Add unit tests
18. Add property tests
19. Add `RULES.md`
20. Add architecture decision for actor-per-game design

### Sprint exit criteria

```text
cargo test --workspace
```

passes, and a seeded simulation prints a complete eight-round game with valid final scores.

---

## 34. Final Design Summary

The recommended system is:

```text
Flutter Web SPA
        |
REST + WebSocket
        |
Axum + Tokio
        |
One Actor per Game
        |
Pure Rust State Machine
        |
PostgreSQL Events + Snapshots
        |
Analytics + Deterministic Explanations (+ optional RAG)
```

The system must maintain three strict boundaries:

### Boundary 1: Client versus server

The client requests; the server decides.

### Boundary 2: Game engine versus infrastructure

The game engine contains rules; infrastructure transports and stores events. Analytics and AI consume the event stream / projections only — never a live handle to `InternalGameState`.

### Boundary 3: Deterministic truth versus AI explanation

Rust calculates; AI explains. MVP explanations use reason codes and curated FAQ; vector RAG is optional.

These boundaries are mandatory because they directly protect fairness, correctness, privacy, reliability, and long-term maintainability.
