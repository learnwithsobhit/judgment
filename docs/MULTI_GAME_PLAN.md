# Multi-Game Platform — Research & Development Plan

**Ask:** develop more multiplayer games beyond Judgement. Hard requirements: (1) popular &
engaging, (2) competitive, (3) addictive, (4) ranking-based, (5) no grouping (free-for-all, no
teams). New or well-known games both acceptable.

**Central thesis:** you are not building "more games." You have already built a **multiplayer
table platform** and happened to ship one game on it. The expensive, hard, done-once work —
authoritative actor-per-game concurrency, reconnect/presence/bot-takeover, seats, personalized
snapshots, token auth, capacity limits, the reaper, and the ranking system now on the roadmap —
is **game-agnostic**. The card rules are a thin, swappable layer. So the correct move is to turn
the platform into a **multi-game host** and drop new game engines into it. The second game costs
a fraction of the first; the tenth is almost free.

Status: research + plan only. No code changed.

**Product source of truth for game mix and build order:** `MULTIPLAYER_GAME_PORTFOLIO.md` v2.1
(Table Arena). This file is the **engineering** plan for the GameEngine refactor and how new
engines drop into the host. If the two documents disagree, the portfolio wins on *which games and
in what order*; this file wins on *how the trait and actor change*.

**Repo decision (locked):** all multi-game work happens in a **new Table Arena repository**.
Judgment is imported once (prefer git history), then frozen to hotfixes. Do not develop Callbreak
on top of the live Judgment repo in parallel.

---

## 1. Executive summary

**What already generalizes (verified in code):** card logic is confined to `judgement-engine`
(2,134 LOC) and part of `judgement-domain`. The 10,307-LOC `judgement-server` — presence,
reconnect grace, seat vacancy/claim, snapshots, token rotation, reaper, metrics, capacity — never
mentions a suit or a trick. It orchestrates *seated players taking turns*. That is true of almost
every game you'd want to add.

**Recommended first three games**, aligned with Table Arena portfolio v2.1 (India then global;
reuse, then demand, then first original):

| Order | Game | Why | Engine reuse | New engine effort |
|---|---|---|---|---|
| **1st** | **Callbreak** | Trick-taking, 4-player **free-for-all**, massive in South Asia, near-identical to Judgement. Ships fastest, validates the multi-game refactor with lowest risk. **MVP = Judgement + Callbreak.** | ~85% | Small |
| **2nd** | **Color Clash** | UNO-like shedding with original rules/art. Universal mental model, highest rematch of any card family, global acquisition. New engine family (not a trick-taker), so the trait is proven beyond bid/trick scoring. | ~55% | Low |
| **3rd** | **Chain Dominion** | First **non-card original**. Still turn-based. High spectacle, low infra. Proves a board engine on the same session gateway. | ~40% (platform only) | Low–medium |

Hearts remains the right *global trick-taking sibling* but is **Wave 3**, not game #2 — Callbreak
already proves the trick-taking host; a second trick-taker does not prove the abstraction as well
as a shedding game does. Ludo remains the India social default but is **Phase 6** (party first,
ranked Master Ludo only if it passes a skill-vs-dice gate).

**The decision that matters:** lift into `table-arena` and approve the **GameEngine trait
refactor** (§5) *before* writing a second game. Add game #2 as a special case in the old repo and
you'll copy-paste the actor; do the lift + trait first and games #2…#N are engine crates plus a
registry entry.

---

## 2. Selection criteria — mapping the requirements

Your five requirements plus four hidden ones that actually decide success on a mobile-first,
guest-identity platform:

| Requirement | What it forces in game selection |
|---|---|
| **Popular & engaging** | Prefer games with an existing mental model — zero rules-teaching cost. "Everyone already knows how to play" is the cheapest acquisition channel you have. |
| **Competitive** | Outcome must be **skill-expressible** and **rankable**. Pure-luck games (e.g. straight Snakes & Ladders) can't sustain a ladder — no perceived skill growth, ranking feels arbitrary. |
| **Addictive** | Short sessions (**3–12 min**), a clear "one more game" loop, and frequent small wins. Long games (full poker tournaments, Risk) fight mobile session length. |
| **Ranking-based** | Needs a **placement or win/loss** result the ranking system already consumes. Your planned placement-Elo (`RANKING_PLAN.md`) is game-agnostic — any FFA finish order feeds it. |
| **No grouping** | **Excludes team games**: Spades, Bridge, Euchre, most MOBA-likes. Every recommendation here is individual free-for-all. |
| *(hidden)* Mobile-first | Fits a phone screen; tolerates the reconnect reality you just fixed in `RECONNECT_PLAN.md`. |
| *(hidden)* Low-teach | Learnable in one game without a tutorial wall. |
| *(hidden)* Bot-able | The platform already fills empty/absent seats with bots; a new game needs a plausible bot or the away/vacancy flow breaks. |
| *(hidden)* Provably-fair | Guest players trust nothing; needs a seeded, auditable RNG. You already have `SeededShuffler`/`SecureShuffler` — generalize to dice/tiles. |

**Market decision (locked in portfolio v2.1):** **India launch, then global.** Every Wave 1–2
game must work in India; Wave 2–3 must also travel. Engineering is invariant to that ordering.
Retention is aggressive (streaks, Daily Duel, rematch, featured events) but **no cash, no
pay-to-win, no loot-box power**. Ranked play stays free-for-all; partnership games are
private-room packs only.

---

## 3. What every future game inherits for free

From the current codebase, a new game written as an engine gets all of this without touching it:

- **Authoritative actor-per-game** (ADR 0001): one sequential task per game, durable tip before
  clients see accepts. Concurrency and consistency: solved.
- **Presence / reconnect / bot-takeover** (ADR 0004, hardened in `RECONNECT_PLAN.md`): grace,
  pause, seat vacancy, claim-by-code, away/bot. Solved.
- **Seats & identity**: guest sessions, `PlayerId` per membership, host migration, capacity caps.
- **Snapshots**: per-player personalized `StateSnapshot` after each accepted mutation — the
  "server decides, client renders" contract. The *shape* of the snapshot is game-specific; the
  *delivery machinery* is not.
- **Persistence**: append-only event log, dedup by `action_id`, replay/restore, TTL reaper.
- **Ranking** (roadmap, `RANKING_PLAN.md`): placement-Elo, `player_stats`, seasons — consumes a
  generic finish order, so it works for any FFA game unchanged.
- **Social**: emotes, soundboard, voice notes, avatars — all game-neutral table events.
- **Ops**: metrics, `/healthz`/`/readyz`, rate limiting, CORS, load ladder.

**The only things a new game must supply:** rules (legal moves, turn advance, terminal + finish
order), its own snapshot/view projection, a bot policy, and its move set on the wire. Everything
else is platform.

---

## 4. Game shortlist, tiered by reuse

### Tier 0 — trick-taking siblings (~80–85% reuse, ships in weeks)

Both reuse `trick.rs`, `shuffle.rs`, deck/card domain, bidding UI patterns, and the entire table
layer. These are the "free" games that pay for the refactor.

- **Callbreak** *(recommended #1, MVP)* — 4-player FFA, bid tricks, spades always trump, score per
  round. Culturally huge in India/Nepal/Bangladesh. Differs from Judgement mainly in fixed trump
  and scoring — a small rules delta. Bot: Judgement's bot policy adapts almost directly.
- **Hearts** *(Wave 3, not game #2)* — 4-player FFA, no bidding, avoid hearts + Q♠, "shoot the
  moon." Still the right global sibling and a cheap abstraction test, but portfolio v2.1 sequences
  a *new card family* (Color Clash) before a second trick-taker. Ship Hearts after Ludo / Word Rush
  / Lane Crash unless export demand pulls it forward.

*Excluded here:* **Spades** and **Bridge** — partnership games, violate "no grouping." **Dehla
Pakad** is the same: private-room cultural pack later, never ranked Arena.

### Tier 1 — other card families (~50–65% reuse, moderate effort)

Reuse deck/shuffle/table but need genuinely new engines.

- **Color Clash** *(recommended #2)* — original UNO-like shedding (not a clone of protected
  branding/art). 3–8 FFA, fast, chaotic, highest rematch of any card family. Simple engine,
  global acquisition. Ranked mode should limit king-making (e.g. next-seat-only action cards).
- **Rummy 13 (Points / Indian 13-card)** *(Wave 2 / Phase 4)* — the single biggest card-game
  market in India. FFA, deeply skill-based (melding, discard tracking), extremely rankable.
  Higher engine complexity (meld validation, jokers) and the strongest **regulatory**
  consideration if real money is ever involved — **skill-ranked, no cash**. Not game #2 because
  Callbreak + Color Clash should prove the host first.
- **Big Two / Thirteen (Tiến lên)** — climbing/shedding FFA, huge in East/SE Asia, high skill
  ceiling. Optional later for SE Asia expansion, not Wave 1–2.

### Tier 2 — non-card games (platform reuse only, ~40%, proves the thesis)

New engine and new RNG domain, but the entire table/presence/ranking layer carries over. Shipping
one of these is what turns "a card app" into "a game platform."

- **Chain Dominion** *(recommended #3, first original)* — chain-reaction board, 3–8 FFA, 5–10
  minutes, very low luck. First non-card engine on the same actor. Dots Royale is a map/mode, not
  a separate title.
- **Ludo** *(Phase 6)* — 2–4 FFA, dice + board, the defining casual multiplayer game in India.
  Needs a **provably-fair dice** primitive (generalize `SeededShuffler`) and a board-state engine.
  **Party Ludo is unranked by default.** Ranked "Master Ludo" only if extra decisions make the
  ladder more skill than dice. Highest demand; do not put party Ludo on the Judgement ladder.
- **Dominoes (Block/Draw)** — 2–4 FFA, tile-based, globally popular. Optional later, not Wave 1–2.

### Tier 3 — novel / differentiation (higher risk, higher ceiling)

New engines that don't map to any existing infra but score maximally on *addictive* + *attention*.

- **Word Rush** *(Phase 6, with Ludo)* — 4–10 FFA, 2–4 minutes, simultaneous words. Tiny infra.
  Native Daily Duel. Number Rush / Pattern Clash are event round-types on this runtime, not
  separate titles.
- **Lane Crash** *(Phase 7)* — Take 6 family, original presentation. Simultaneous turns, brutal
  near-miss, cheap engine.
- **Bluff Arena** *(Phase 5)* — liar's-dice family, original presentation. Hidden info +
  anti-collusion. Psychology pillar.
- **Live trivia / Number Rush** — live-ops / Featured Game of the Week, tied to scheduled events.
  Not a year-one ranked home-screen pillar.

Grid Conquest, Auction Wars, Trick Shot/Carrom, Territory Rush: see portfolio v2.1 Phases 8–11.
Do not start physics or 30-player realtime until the turn-based factory is proven.

### Explicitly flagged, not recommended first

- **Poker (Texas Hold'em)** — perfect on paper (FFA, ranked, addictive) but real-money/regulatory
  exposure and higher complexity. Defer; if built, skill-ranked play-chips only.
- **Chess / Checkers** — 2-player only (weakens the 3–8 social-table model), Elo-native but a
  crowded, hard-to-differentiate market.

---

## 5. The engineering refactor — one platform, many engines

This is the actual work. It happens in the **new Table Arena repo** after a one-time Judgment
lift — not as a long-lived feature branch on the shipping Judgment repo.

### 5.0 Repository lift

**Do this.** New product-named repo, import Judgment with git history (`git filter-repo` or
subtree), rename crates toward `game-core` / `arena-server` / `engine-judgment`, keep one live
host.

**Do not do this.** Manual file copy of "the bits we need" while Judgment keeps getting features.
That forks reconnect/presence and you will fix the same bug twice.

**Copy wholesale:** `judgement-server`, protocol, persistence, engine, bot, Flutter table spine,
tests, deploy, ADRs. That *is* the platform.

**Do not bother copying first:** secrets, local env, and Judgment-only RAG/FAQ unless they
generalize on day one.

**Old repo:** hotfix-only until Table Arena MVP cutover, then archive. Judgment remains a
`GameKind` inside Table Arena — players still play Judgment; they just play it on the arena host.

Target crate split after lift:

```text
game-core              # trait, Placement, GameEvent
arena-server           # was judgement-server (actor, WS, lobby)
engine-judgment        # was judgement-engine
engine-callbreak       # Phase 1
```

Today `judgement-engine` is a concrete state machine. After the lift, extract the
contract it already implicitly satisfies into a trait, and make the actor generic over it.

### 5.1 The trait (in a new `game-core` crate)

```rust
/// Everything the platform needs from a game; nothing it needs to know about cards.
pub trait GameEngine: Send + 'static {
    type Command;              // deserialized player intent (bid, play, roll, discard…)
    type View: Serialize;      // per-player personalized snapshot
    type Config;               // rules/options chosen in the lobby

    fn start(config: Self::Config, players: &[SeatId], seed: u64) -> Self;

    /// Validate + apply one command. Platform commits the events durably (CP tip)
    /// before any client sees the accept — unchanged from today.
    fn apply(&mut self, seat: SeatId, cmd: Self::Command)
        -> Result<Vec<GameEvent>, GameError>;

    fn view_for(&self, seat: SeatId) -> Self::View;
    fn legal_actions(&self, seat: SeatId) -> LegalActions;   // drives client affordances + bots
    fn turn_deadline(&self) -> Option<Duration>;             // reuses the actor's timer wheel
    fn is_finished(&self) -> bool;
    fn finish_order(&self) -> Option<Vec<Placement>>;        // ← feeds ranking, game-agnostic
    fn restore(state: SerializedState, seed: u64) -> Self;   // reuses event replay
}
```

`finish_order() -> Vec<Placement>` is the seam that makes **cross-game ranking automatic**: the
ranking system (`RANKING_PLAN.md`) consumes placements, not cards.

### 5.2 What changes vs. what doesn't

- **Refactor:** `actor.rs` becomes generic over `E: GameEngine` (or dispatches through a
  `dyn`-friendly wrapper). Its presence/pause/reconnect/timer logic — the bulk of it — is
  untouched; only the `place_bid`/`play_card` calls become `engine.apply(seat, cmd)`.
- **Refactor:** `judgement-protocol` gains a `game_kind` tag and a per-game command sub-enum;
  `StateSnapshot` carries an opaque-to-platform `View`.
- **Refactor:** persistence stores `game_kind` on the game row; event log is already generic
  (`Vec<GameEvent>` blobs).
- **New per game:** one engine crate (`engine-callbreak`, `engine-color-clash`,
  `engine-chain-dominion`, …), a bot policy, and a Flutter table/board renderer.
- **Unchanged:** reconnect, seats, capacity, reaper, metrics, auth, social, ranking core.

### 5.3 Registry & routing

A `GameKind` registry maps `game_kind → factory`. Lobby creation picks the kind; the actor spawns
the right engine. One WS endpoint, one lobby flow, N games. Room codes, join, claim, and the
mobile-reconnect fixes all apply to every game for free.

### 5.4 Frontend

Flutter already separates `GameController` (platform/socket/lifecycle) from table widgets. Split
it: a game-neutral `TableController` (connection, presence, reclaim, ranking) plus a per-game
`GameView` widget tree. Callbreak reuses most of the Judgement table UI; Color Clash needs a
hand/discard widget on the same connection spine; Chain Dominion needs a board widget but the
same reconnect path (including everything from `RECONNECT_PLAN.md`). Hearts, when it ships,
reuses the Judgement table almost as Callbreak does.

---

## 6. Cross-game ranking & unified identity

The ranking plan becomes far more powerful across multiple games — and it's the mechanism that
makes the platform *sticky*.

- **Per-game ladders:** separate placement-Elo per `game_kind` (a Callbreak shark isn't
  automatically a Ludo shark). `player_stats` gains `game_kind` in its key.
- **Unified profile / platform level:** one identity (`players` table from `RANKING_PLAN.md`,
  keyed on `(device_key_hash, nickname_norm)`) accumulates XP across *all* games → a single
  "level" and a cross-game presence. This is the retention multiplier: a player who came for Ludo
  discovers Callbreak under the same profile and ladder.
- **Shared seasons:** one monthly season spanning all games; per-game boards + a blended
  "platform championship." Directly serves *attention span* and *competitiveness*.
- **Shared engagement mechanics** (apply to every game at once, built once): daily streaks, daily
  "first win of the day" bonus, per-game and cross-game achievements, "top 5 this week" surfacing.

Because ranking consumes `finish_order()`, **every new engine is ranked the day it ships** — no
per-game ranking work.

---

## 7. Roadmap

Aligned with Table Arena portfolio v2.1. Product detail lives there; this table is the
engineering sequence.

| Phase | Scope | Outcome |
|---|---|---|
| **P0 — Repo lift + refactor** | Create `table-arena`; import Judgment with history; freeze old repo to hotfixes; extract `GameEngine` trait; make the actor generic; add `game_kind` to protocol + persistence; split Flutter `TableController`/`GameView`. Judgement becomes the *first implementer* of the trait (no behavior change — regression-guarded by the existing suite). | Platform can host N games in a product-named repo. No user-visible change yet. |
| **P1 — Game #2 (Callbreak)** | New `engine-callbreak` + bot + table renderer + registry entry. Shared profile, per-game rating, match history. | **MVP:** two games, one platform. Proves the refactor. Fastest possible second game. |
| **P2 — Game #3 (Color Clash)** | `engine-color-clash` (shedding family, original rules). Ranked targeting rules to limit king-making. | Proves the abstraction isn't overfit to trick-taking. Acquisition / rematch vehicle. |
| **P3 — First original (Chain Dominion)** | Board engine + renderer. Spawn-advantage and cascade telemetry. | Non-card title on the same gateway. |
| **P4 — Rummy 13** | Meld engine, jokers, declare validation, collusion signals. **No cash.** | India market depth. |
| **P5 — Bluff Arena** | Hidden dice/symbols, reveal, anti-collusion analytics. | Psychology pillar; partial-info runtime. |
| **P6 — Ludo + Word Rush** | Provably-fair dice + party Ludo (unranked). Word Rush + Daily Duel. Master Ludo ranked only if it passes the skill-vs-dice gate. | Social default + 90s DAU hook. |
| **P7+ — Lane Crash, Hearts, then flagships** | Simultaneous-turn (Lane Crash), global trick-taking sibling (Hearts), then Grid Conquest, Auction Wars, Trick Shot/Carrom, Territory Rush. | See portfolio Phases 7–11. |

P0 is the only phase without a shippable game — do it anyway. It's the difference between N games
costing O(N) and O(1) each.

Cross-game ranking (per-game ladders, Arena Rating, shared seasons) is **Epic B in P0/P1**, not a
phase after three games. Every engine is ranked the day it ships because ranking consumes
`finish_order()`. Streaks, rematch/revenge and Play Now (<60s, bot fill) are platform systems in
the same window — see portfolio Part F.

---

## 8. Risks & open decisions

**Risks**
- *Over-abstraction:* designing the trait against one game risks baking in Judgement assumptions.
  **Mitigation:** design the trait against Judgement, Callbreak *and* Color Clash on paper before
  coding it — two trick-takers plus a shedding game shake out turn-order, hand-view and "game
  over" assumptions cheaply. Hearts remains a later paper check, not a blocker for P0.
- *Real-time games don't fit the turn model:* trivia royale is simultaneous, not turn-based. It
  may want a sibling actor variant. Keep it in a later phase; don't let it distort the core trait.
- *Content/regulatory:* Rummy/Poker attract real-money expectations. Stay **skill-ranked, no
  cash** unless you deliberately take on that compliance burden.
- *Dual-repo drift:* copying Judgment and then keeping both repos feature-active. **Mitigation:**
  one live host. Old repo is hotfixes only until cutover, then archive.
- *Cherry-pick copy:* lifting only `judgement-engine` and rewriting the server. **Mitigation:**
  copy the server/protocol/persistence/Flutter spine wholesale — that is the platform.
- *Bot quality per game:* every game needs a non-embarrassing bot for the away/vacancy flow;
  budget engine + bot together, never engine alone.

**Open decisions**
1. **Target market** — *locked:* India then global. Ordering is Callbreak → Color Clash → Chain
   Dominion, not Hearts/Dominoes first.
2. **First game after the refactor** — **Callbreak** (highest reuse, proven demand). Unchanged.
3. **Do the trait refactor before or after game #2?** Strong recommend **before**. Building #2 as
   a one-off guarantees a painful re-refactor at #3.
4. **Per-game vs. blended ranking emphasis** — per-game ladders + Arena Rating (best-N
   normalized percentile). Not one merged rating.
5. **Real-money ever?** Explicit **no**. It changes architecture, compliance, and risk profile.
6. Remaining product questions (Arena Rating weights, Master Ludo randomness, Color Clash
   targeting) live in portfolio §39.
7. **New repo vs keep developing in Judgment?** *Locked:* new Table Arena repo, one-time lift,
   freeze Judgment. See §5.0.

---

## 9. One-paragraph recommendation

Create `table-arena`, lift Judgment into it (history-preserving; freeze the old repo), then
approve the `GameEngine` trait refactor (P0) as the next major initiative. Ship **Callbreak** as
game #2 to prove and amortize it (MVP = Judgement + Callbreak + shared identity/rating), then
**Color Clash** for acquisition/rematch and **Chain Dominion** as the first non-card original.
Wire **cross-game ranking** from day one using `finish_order()` and the placement-Elo already
planned. Ludo and Hearts still ship — as Phase 6 party social and Phase 7 global sibling, not as
games #2 and #3. This reuses ~80% of the hardest-won infrastructure for the early card games and
100% of the table platform for all of them, matches portfolio v2.1, and converts a single-game
product into a game *platform* whose marginal cost per new game keeps falling.
