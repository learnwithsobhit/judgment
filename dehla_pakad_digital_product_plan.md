# Dehla Pakad Digital Game — Product, Strategy, Architecture, Monetization and Go-to-Market Plan

**Version:** 1.0  
**Date:** 6 August 2026  
**Recommended positioning:** *India’s partnership card classic — protect the tens, control the pile, win the Kot.*

---

## 1. Executive decision

Build **Dehla Pakad as a social, skill-oriented, non-real-money card game**, with the North Indian **two-consecutive-trick pile-capture rule** as its signature mechanic.

The product should support multiple regional rule packs, but it must not mix those rules silently. At table creation, the selected rule pack must be clearly visible:

1. **Dehla Pakad Classic — Double-Sar pile capture**
2. **Mendikot Classic — immediate trick capture**
3. **Custom Family Table — configurable house rules**

The initial product should be free to play and monetized through:

- cosmetic card backs, tables, avatars and emotes;
- optional rewarded advertisements outside active hands;
- ad-free membership;
- premium statistics, replays, private-club tools and advanced coaching;
- seasonal cosmetic passes with no gameplay advantage.

Do **not** launch with cash entry, cash prizes, redeemable chips, paid wagering, tradable assets or paid-entry tournaments. India’s current online-gaming framework prohibits online money games and evaluates factors including stakes, expected monetary winnings, revenue structure and whether rewards can be monetized outside the game.

---

# Part I — First-principles product framing

## 2. What problem exists without a deliberate product strategy?

A direct digital copy of a physical card game usually fails for one of five reasons:

### 2.1 Players disagree about the rules

Dehla Pakad is played through family and regional traditions. Players may disagree about:

- how trump is selected;
- whether trump is hidden or declared;
- whether all 13 cards are dealt before play;
- whether tricks are collected immediately;
- whether the same player or merely the same team must win consecutive tricks;
- how a 2–2 split of tens is resolved;
- how a Kot is scored;
- who deals next;
- whether a match ends by time, Kots or hands.

A digital product cannot resolve such disagreements socially. The software must encode one exact answer for every state.

### 2.2 A correct game can still feel boring

The physical game gets energy from friends, teasing, facial reactions, local language and rematches. A plain digital table removes much of that social texture. Without invitations, reactions, rivalry, team identity, rematches, leagues and progression, the app becomes a rules simulator rather than entertainment.

### 2.3 Multiplayer products fail when tables are empty

Four-player matchmaking requires enough concurrent users. A new game will initially have low liquidity. Long queues create abandonment, while poor bots damage trust.

### 2.4 Aggressive monetization can destroy cultural trust

Players may reject the app if it resembles a gambling product, sells competitive power, interrupts hands with advertisements or creates artificial frustration. The product must earn money without corrupting the game.

### 2.5 Online play introduces cheating and reliability problems

A client-controlled deck, weak reconnection, hidden-card leakage, partner collusion or incorrect scoring can permanently damage the brand. Card-game players remember unfair losses.

## 3. What is the root cause?

The root cause is treating the product as **“cards displayed on a screen”** rather than as a combination of:

- a deterministic rules system;
- an imperfect-information strategy game;
- a four-player social network;
- a live multiplayer service;
- a long-term entertainment economy;
- a regulated digital product.

## 4. So how can we solve this problem?

Use five product pillars:

1. **Rule clarity:** named, testable rule packs.
2. **Strategic depth:** emphasize pile control, tens management and partnership inference.
3. **Social density:** private rooms, rematches, clubs, reactions and rivalries.
4. **Fair competition:** server-authoritative play, verifiable shuffle and deterministic replays.
5. **Ethical monetization:** players pay for identity, convenience and insight—not victory.

---

# Part II — Game study and canonical rules

## 5. Game identity

Dehla Pakad means **“collect/catch the tens.”** It is normally played by four players in two fixed partnerships, with partners sitting opposite. A standard 52-card deck is used and cards rank:

**A > K > Q > J > 10 > 9 > 8 > 7 > 6 > 5 > 4 > 3 > 2**

The strategic objective is not simply to win the most tricks. It is to secure tricks containing the four tens and, in Dehla Pakad’s distinctive form, to control when the accumulated centre pile is captured.

## 6. Recommended canonical rule pack: Dehla Pakad Classic

### 6.1 Setup

- 4 players.
- 2 teams; partners sit opposite.
- Deal and play anticlockwise.
- First dealer selected randomly.
- Player to dealer’s right leads.

### 6.2 Deal

Recommended default:

1. Deal five cards to every player.
2. Determine trump using the selected trump method.
3. Deal the remaining eight cards per player in two groups of four.

### 6.3 Trump methods

Support both at launch, but set **Cut Trump** as the branded default because it creates discovery and suspense.

#### A. Cut Trump

- Play begins with five-card hands and no trump.
- The first player unable to follow the led suit plays a card of another suit.
- That played suit becomes trump.
- Complete the remaining deal after that trick.

Digital advantage: the server knows the five-card hands, so it can enforce honest following of suit. The physical-game trust weakness disappears.

#### B. Announced Trump

- After receiving five cards, the player to the dealer’s right announces a trump suit.
- Remaining cards are dealt.
- That player leads the first trick.

This variant is faster and easier for beginners.

### 6.4 Trick resolution

- A player must follow the led suit when holding it.
- Otherwise the player may play any card.
- Highest trump wins if one or more trump cards were played.
- Otherwise the highest card of the led suit wins.
- Trick winner leads the next trick.

### 6.5 The signature pile-capture rule

This is the main differentiator from ordinary Mendikot:

- Completed tricks remain face down in a centre pile.
- The pile is captured only when the **same individual player** wins two consecutive tricks.
- Consecutive wins by two partners do not capture the pile.
- After collection, the next trick starts a new pile.
- The winner of the final, thirteenth trick collects all cards still remaining in the centre.

The UI must make three things visually obvious:

1. current centre-pile size;
2. which player won the previous trick;
3. who is currently “one win away” from capturing the pile.

### 6.6 Hand result

Recommended default aligned to the documented North Indian rule:

- Four tens captured by one team: **1 Kot**.
- Otherwise, the team with the hand-winning condition gains a hand win.
- A team winning seven consecutive hands gains **1 Kot**.
- A Kot from four tens resets the consecutive-hand counter.

Because local treatment of a 2–2 tens split varies, the digital product must expose the rule explicitly. Recommended selectable tie rules:

- **Non-dealing team wins 2–2** — Dehla Pakad Classic default.
- **Most tricks wins 2–2** — familiar Mendikot-style tie-break.
- **Hand drawn** — optional family rule.

### 6.7 Match formats

- Quick: first to 1 Kot.
- Standard: first to 3 Kots.
- Long: first to 5 Kots.
- Timed social room: highest Kots after 20/30/45 minutes.
- Best-of series: 3 or 5 hands for casual events.

Do not use ranked mode until match duration and comeback probability are validated through telemetry.

## 7. Secondary rule pack: Mendikot Classic

Mendikot should be offered as a related but separate mode:

- all 13 cards are dealt;
- tricks are collected immediately by the trick winner’s team;
- three or four tens wins the deal;
- a 2–2 split is normally resolved by the team winning at least seven tricks;
- all four tens is Mendikot;
- all 13 tricks is a whitewash/52-card Mendikot.

Trump options can include:

- random visible trump;
- closed/hidden trump;
- cut trump.

## 8. Post-launch variants

Only add variants after the core population is healthy:

- 6-player and 8-player team Mendikot using a reduced 48-card deck;
- no-trump mode;
- dummy-player mode;
- speed mode with shorter turn timers;
- regional tournament presets;
- creator-designed weekly rules.

Too many queues at launch will fragment matchmaking.

---

# Part III — Strategy system

## 9. Why this game has deep strategy

Players have incomplete information. They can see played cards and outcomes but not opponents’ remaining hands. The player must continuously infer:

- who is void in a suit;
- which tens remain unseen;
- how many trump cards may remain;
- whether a partner can protect a ten;
- who can capture the current centre pile;
- whether preserving a high card for the final trick is more valuable than winning now.

## 10. Strategy layers

### 10.1 Initial five-card evaluation

A player should evaluate:

- longest suit;
- short/void suits that can create cutting opportunities;
- high honours A/K/Q/J;
- protected versus exposed tens;
- trump density;
- ability to win two consecutive tricks rather than one isolated trick.

For announced trump, a strong suit is not merely a long suit. It should contain enough control cards to create consecutive wins or protect a ten.

### 10.2 Tens management

A ten is strategically valuable only when the trick containing it is ultimately captured.

Core principles:

- do not expose a ten merely because the current trick appears safe;
- distinguish winning a trick from owning the centre pile;
- unload a ten when the partner has near-certain control and the opponent cannot overtrump;
- track every ten as **in hand, played into centre, captured or unseen**;
- when two tens are already secured, shift from ordinary trick winning to denial of the opponent’s remaining tens.

### 10.3 Centre-pile control

This is the product’s “killer strategy mechanic.”

A player should ask:

- Who won the previous trick?
- Can that same player win this trick?
- How many tens are sitting in the centre?
- Is it worth spending a high trump to deny the second consecutive win?
- Should I allow my partner to win, knowing that partner-to-partner consecutive wins do not collect the pile?

High-value tactics:

- **Chain setup:** win a low-cost trick, then retain a control card for the next trick.
- **Chain break:** spend a premium card to prevent an opponent’s second consecutive win.
- **Pile bait:** allow the centre pile to grow when your team controls late-game trump.
- **False safety:** opponents may place a ten into a trick won by your partner, but the pile remains unsecured until the same player wins again.
- **Last-trick reserve:** retain a high trump or winner because the thirteenth trick collects the unresolved centre pile.

### 10.4 Suit and trump tracking

Show optional beginner aids in casual mode:

- played-card history;
- visible count of remaining cards by suit, not ownership;
- markers when a player has demonstrated being void in a suit;
- tens tracker.

In ranked mode, aids should be limited to information a player could legally derive from public play.

### 10.5 Partnership inference

Partners cannot reveal their hands. Coordination happens through legal play:

- a lead can indicate strength or request continuation;
- a low discard can reveal a weak suit;
- declining to overtake a partner may preserve control;
- cutting a trick may signal void status;
- saving or releasing a ten provides information about confidence.

Do not permit free-form partner-only chat during a live ranked hand. It enables illegal signalling. Use public preset reactions visible to all players.

### 10.6 Defensive strategy

- break an opponent’s consecutive-win chain;
- force the likely trump-rich player to spend trump early;
- lead suits where the previous trick winner is weak;
- deny safe ten disposal;
- preserve a control card for the final trick;
- count unseen honours before risking a ten.

### 10.7 Endgame strategy

During the final four tricks:

- exact card counting becomes possible for experienced players;
- centre-pile value may exceed the value of an individual trick;
- the final-trick sweep changes optimal play;
- a player may intentionally lose the twelfth trick to win the thirteenth;
- the game should provide a post-match explanation of such turning points.

---

# Part IV — Product experience

## 11. Product promise

**Easy to start in 60 seconds, socially satisfying in 10 minutes, strategically deep for years.**

## 12. Player personas

### Persona A — Nostalgia player

- Age: approximately 28–50.
- Played with family or college friends.
- Wants correct local rules and private tables.
- Pays for ad-free play, classic themes and easy friend invitations.

### Persona B — Social group organizer

- Creates WhatsApp groups and game nights.
- Needs one-tap room links, rematches, flexible rules and spectator support.
- Pays for club tools, room customization and event hosting.

### Persona C — Competitive strategist

- Wants rank, statistics, fair matchmaking and strong opponents.
- Pays for advanced analysis, seasonal cosmetics and replay tools.

### Persona D — New learner

- Has heard the game name but does not know the rules.
- Needs an interactive tutorial, hint mode and forgiving bots.
- Converts only after trust and competence are established.

## 13. Core player journeys

### 13.1 First session

1. Select language.
2. Choose “I know the game” or “Teach me.”
3. Play a three-minute guided mini-hand.
4. Continue against bots without sign-in.
5. After first completed match, offer profile creation and friend invitation.

Never require account creation before the player experiences the game.

### 13.2 Private friends table

1. Host selects rule pack and match format.
2. App generates deep link and short room code.
3. Invite through WhatsApp or copy link.
4. Missing seats are temporarily filled by bots.
5. A human may replace a bot before the next hand.
6. Rematch retains the table and rules.

### 13.3 Public matchmaking

- unranked quick match;
- ranked standard match;
- team queue with a known partner;
- solo queue with skill-based partner assignment;
- bot backfill only in unranked play and clearly labelled.

### 13.4 Reconnection

- player has a reconnect grace period;
- bot safely takes over after timeout;
- returning player resumes on the next legal action;
- no hidden cards are exposed during disconnect;
- repeated deliberate disconnects affect reliability score, not skill rating.

## 14. Engagement design

### 14.1 Healthy retention loops

- daily strategy puzzle;
- weekly “Kot challenge”;
- rotating regional table theme;
- club matches;
- friend rematch notifications;
- seasonal rank reset with placement matches;
- personal mastery levels: Beginner, Counter, Protector, Pile Master, Kot Master.

Avoid punishing missed-day streaks. Reward return without creating loss anxiety.

### 14.2 Social features

Launch:

- friends list;
- private rooms;
- public preset reactions;
- rematch;
- match history;
- block, mute and report.

Later:

- clubs;
- club tournaments;
- spectators with delay;
- moderated voice rooms;
- creator-hosted events.

### 14.3 Cultural identity

Support Hindi and English first, then Gujarati, Marathi, Punjabi, Bengali, Tamil, Telugu and Kannada based on demand.

Themes should celebrate card-table culture without stereotyping:

- family courtyard;
- college hostel;
- tea stall;
- monsoon evening;
- festive Diwali table;
- minimalist competitive arena.

### 14.4 AI coach

The coach should answer:

- Why was my ten unsafe?
- Why did the centre pile go to the opponent?
- Which card could have broken the chain?
- What public information showed that a player was void in a suit?
- Was preserving trump for the last trick better?

Coach output should cite the exact match state and offer one alternative move. Do not provide live ranked assistance.

---

# Part V — Monetization

## 15. Monetization principle

Players should pay to express identity, remove friction or understand their play. They should never pay to receive better cards, stronger trump, easier opponents or hidden information.

## 16. Recommended revenue stack

### 16.1 Optional advertisements

- banner ads only on non-game lobby surfaces if used at all;
- interstitial ads only after a completed match, frequency capped;
- rewarded ads for optional cosmetic trial, bonus non-wagerable tokens or an additional post-match analysis;
- never interrupt an active hand;
- paid members receive no ads.

### 16.2 Cosmetic purchases

- card backs;
- card faces designed for readability;
- table themes;
- avatars and frames;
- public emote packs;
- win animations;
- club badges.

All cosmetics should be directly purchasable. Avoid randomized paid loot boxes.

### 16.3 Membership

Test pricing rather than fixing it before retention is known.

Suggested experiment bands for India:

- monthly: ₹79 / ₹99 / ₹149;
- annual: ₹599 / ₹799 / ₹999;
- one-time ad removal: ₹149 / ₹249 / ₹399.

Possible membership benefits:

- ad-free experience;
- expanded match history;
- advanced statistics;
- full replay viewer;
- additional private-table presets;
- premium table themes;
- deeper post-match coaching;
- club administration tools.

### 16.4 Season pass

- cosmetic-only progression;
- free and paid tracks;
- no paid competitive boost;
- players can complete it through normal play without excessive grind;
- expired pass items may return later to reduce fear-driven purchasing.

### 16.5 Club plan

A club organizer may pay for:

- custom club badge and table;
- scheduled internal leagues;
- member roles;
- match archive;
- club leaderboard;
- spectator controls;
- exportable event results.

This is a promising high-intent monetization surface because one organizer can activate many free players.

## 17. Explicitly prohibited product mechanics

- entry fees tied to match outcomes;
- cash or withdrawable prizes;
- redeemable virtual currency;
- player-to-player transfer of purchased currency;
- betting on games;
- paid “double your reward” outcome multipliers;
- purchasable better cards or matchmaking advantage;
- deceptive near-win effects;
- advertisements disguised as cards or gameplay controls;
- targeted advertising to children.

## 18. Monetization experiments

| Experiment | Hypothesis | Primary metric | Guardrail |
|---|---|---|---|
| Ad-free one-time purchase | Nostalgia players prefer ownership | Purchase conversion | D7 retention |
| Membership | Competitive users value stats and replay | Trial-to-paid conversion | Cancellation/refund rate |
| Theme bundle | Cultural identity drives first purchase | First-week payer conversion | Match completion |
| Club organizer plan | Group hosts have higher willingness to pay | Paid clubs / active clubs | Free-member growth |
| Rewarded post-match analysis | Insight is a valuable voluntary reward | Rewarded completion rate | Session abandonment |

---

# Part VI — Technical architecture

## 19. Architecture principle

Start with a **modular monolith**, not microservices. The early risk is rule correctness and player experience, not service decomposition.

Recommended stack:

- **Client:** Flutter for Android, iOS and Web/PWA.
- **Backend:** Rust with Axum.
- **Realtime transport:** secure WebSocket connection.
- **Primary database:** PostgreSQL.
- **Ephemeral state and presence:** Redis.
- **Analytics pipeline:** event collector into warehouse/object storage.
- **Hosting:** India-region cloud deployment; containerized services.

## 20. Core backend modules

### 20.1 Identity and profile

- guest identity;
- phone/email/social upgrade;
- player preferences;
- age gate;
- blocks and reports.

### 20.2 Lobby and matchmaking

- private room codes;
- queue segmentation;
- partner queue;
- skill and latency matching;
- bot backfill;
- table lifecycle.

### 20.3 Deterministic rules engine

Implement as a pure Rust state machine:

- input: current state plus legal player command;
- validation: turn, card ownership, follow-suit rule, timer, rule pack;
- output: new state plus domain events;
- no network, database or clock dependency inside rule calculation;
- deterministic replay from initial seed and command log.

Suggested state phases:

1. Lobby
2. Seating
3. Initial deal
4. Trump selection
5. Remaining deal
6. Trick in progress
7. Trick resolved
8. Centre pile captured/not captured
9. Hand result
10. Kot/match result
11. Rematch or closure

### 20.4 Game-session actor

One logical actor owns each active table:

- serializes commands;
- prevents concurrent double-play;
- manages turn timers;
- persists events;
- broadcasts player-specific views;
- masks hidden information;
- supports reconnect.

### 20.5 Bot engine

Bot levels:

- Beginner: legal random with simple tens protection.
- Casual: rule-based suit/trump and pile-control heuristics.
- Skilled: belief-state model plus Information Set Monte Carlo Tree Search.
- Expert, later: self-play trained policy evaluated against fixed benchmarks.

Do not start with reinforcement learning. First build a strong deterministic heuristic baseline and simulation harness.

### 20.6 Rating and leaderboard

- separate rating per rule pack;
- team-based rating update;
- uncertainty for new players;
- inactivity decay only at top competitive ranks;
- seasonal leaderboards;
- anti-smurf checks.

### 20.7 Economy and catalog

- non-redeemable currency only;
- immutable transaction ledger;
- receipt verification for Google Play and Apple;
- entitlement service;
- refund and revocation handling;
- no currency attached to match outcome wagering.

### 20.8 Moderation and safety

- public reaction rate limits;
- mute/block/report;
- username moderation;
- club moderation roles;
- chat retention policy;
- child-safe defaults;
- grievance workflow and audit trail.

## 21. Fair shuffle design

Use a cryptographically secure random generator on the server.

For verifiable fairness:

1. Server creates a random shuffle seed.
2. Before dealing, server publishes a cryptographic commitment/hash of the seed and table identifier.
3. Cards are shuffled deterministically from the committed seed.
4. After the match, the seed is revealed in the replay record.
5. A verifier can reproduce the deck and confirm no deal changed mid-game.

The seed must never be revealed before the match ends.

## 22. Data model outline

Core entities:

- Player
- PlayerDevice
- Friendship
- Club
- RulePack
- Table
- Seat
- Match
- Hand
- DealCommitment
- Command
- DomainEvent
- Trick
- PileCapture
- MatchResult
- RatingChange
- Purchase
- Entitlement
- Report
- ExperimentAssignment

## 23. Event taxonomy

Track product behavior without storing unnecessary personal data:

- tutorial_started/completed;
- table_created/joined;
- queue_started/matched/cancelled;
- hand_started/completed;
- player_disconnected/reconnected;
- illegal_command_rejected;
- turn_timeout;
- pile_captured;
- ten_played/secured;
- match_completed/abandoned/rematch;
- coach_opened;
- ad_offered/accepted/completed;
- store_viewed/purchase_completed/refunded;
- report_submitted.

## 24. Non-functional targets

MVP targets:

- 99.9% monthly availability for live gameplay;
- p95 command acknowledgement under 200 ms within India, excluding player network delay;
- no duplicate card or impossible state across simulation tests;
- deterministic replay success for 100% of completed matches;
- reconnect state restoration under 3 seconds after transport recovery;
- crash-free sessions above 99.5%;
- match completion above 85% in private rooms;
- queue-time p95 below 30 seconds after adequate liquidity, with transparent bot fallback in casual mode.

## 25. Testing strategy

### Rules tests

- 52 unique cards per deck;
- exactly 13 cards per player after complete deal;
- only legal cards accepted;
- follow-suit enforced;
- one trick winner;
- pile captured only by the same player’s consecutive trick wins;
- final trick captures remaining centre pile;
- exactly four tens accounted for;
- Kot and dealer transitions verified;
- each rule pack has golden replay fixtures.

### Property-based tests

Generate thousands of random legal games and prove invariants:

- no card appears twice;
- no card disappears;
- total captured plus centre plus hands equals 52;
- hidden cards never enter another player’s view;
- game always reaches a terminal state.

### Simulation

Run millions of bot matches to test:

- rule completion;
- average hand duration;
- trump distribution;
- team-seat fairness;
- Kot frequency;
- tie frequency;
- bot strength and exploitability.

### Network tests

- packet delay and reordering;
- disconnect during card selection;
- duplicate commands;
- app background/foreground;
- server restart and table recovery;
- stale client version.

---

# Part VII — Compliance and responsible design

## 26. India regulatory position

The product should be designed as an **online social game**, not an online money game.

Compliance-by-design controls:

- no financial stake tied to a hand or match;
- no expectation of monetary or externally monetizable winnings;
- purchased items are entertainment entitlements and cosmetics;
- no transfer or redemption of virtual goods;
- age-gating and parental controls;
- play-time reminders;
- clear grievance process;
- fair-play monitoring;
- India-region storage architecture and configurable retention;
- documented classification review before launch;
- legal review before tournaments, sponsorship prizes or material economy changes.

Current Indian rules provide for classification, possible registration of notified social games, user-safety features, grievance redressal and oversight by the Online Gaming Authority of India. Treat compliance as a continuous product capability, not a one-time launch checklist.

## 27. Store compliance

- Use Google Play Billing and Apple In-App Purchase for digital goods where required.
- Clearly disclose price, renewal and cancellation terms.
- Avoid paid randomized loot boxes; if ever introduced, platform rules may require probability disclosure.
- Use opt-in rewarded ads and avoid accidental-click placements.
- If children are part of the declared audience, use child-appropriate SDKs, disable personalized advertising and follow parental-consent/privacy requirements.

## 28. Responsible-play controls

- optional session timer;
- break reminder after long continuous play;
- quiet hours for notifications;
- notification frequency controls;
- no “your streak will die” messages;
- no loss-chasing language;
- transparent match history;
- parental play-time controls;
- easy account deletion and data request flow.

---

# Part VIII — Go-to-market plan

## 29. Brand strategy

### Name architecture

Use a searchable combined name during launch:

**Dehla Pakad — Mindi & Mendikot**

This captures regional search terms while allowing the product to educate users about rule differences.

### Brand line

**Protect the tens. Control the pile. Win the Kot.**

### Brand personality

- clever, warm and competitive;
- culturally Indian without looking dated;
- social rather than casino-like;
- premium card readability;
- no casino chips, roulette imagery or cash language.

## 30. Market-entry sequence

### Stage 1 — Community seed

Recruit 100–300 known players from:

- family and college WhatsApp groups;
- North Indian card communities;
- Gujarati/Marathi Mendikot communities;
- offline card clubs;
- internal company communities.

Use them to validate rules, terminology and rematch behavior.

### Stage 2 — City and language clusters

Do not spread acquisition evenly. Seed concentrated groups where players can find each other:

- Delhi NCR / Uttar Pradesh / Rajasthan for Dehla Pakad;
- Gujarat / Maharashtra for Mindi/Mendikot;
- diaspora groups using private tables.

### Stage 3 — Creator-led education

Content formats:

- “Dehla Pakad in 60 seconds”;
- “Why your partner’s win did not capture the pile”;
- “Three ways to protect a ten”;
- “Dehla Pakad vs Mendikot”;
- replay breakdowns;
- family challenge videos.

### Stage 4 — Referral loop

The primary referral message is not “install this game.” It is:

**“I created our table. Join my team.”**

Reward both players with a cosmetic trial or profile badge, never match advantage.

## 31. ASO and SEO keywords

- Dehla Pakad
- Dehla Pakad online
- Mindi game
- Mindi Kot
- Mendikot
- Mendicot
- Mendhi Coat
- collect tens card game
- Indian team card game
- Kot card game
- Coat Piece

Create separate localized store descriptions rather than keyword stuffing one English listing.

## 32. Launch campaigns

- **College Reunion Table:** bring four old friends back together.
- **Family Kot Night:** private family league.
- **State Rivalry Season:** non-cash regional leaderboard.
- **Festival Table Themes:** Diwali and Holi cosmetics.
- **Beat the Bot Challenge:** shareable result cards.
- **Partner Chemistry Score:** post-match social statistic based on legal teamwork indicators.

## 33. Community operations

- official Discord/WhatsApp community only if moderation capacity exists;
- monthly rule council with experienced players;
- public issue tracker for disputed rules;
- creator program for tutorials and tournaments;
- transparent patch notes for bot and rule changes.

---

# Part IX — Roadmap and delivery plan

## 34. Phase 0 — Rule and market validation (2–3 weeks)

Deliverables:

- rule-variant matrix;
- 30–50 player interviews;
- five recorded physical play sessions;
- terminology glossary by region;
- clickable table prototype;
- monetization interviews;
- compliance classification memo;
- MVP backlog and test vectors.

Exit criteria:

- at least 80% of target players understand the selected default rules;
- top three house-rule conflicts documented;
- one canonical Dehla Pakad rule pack approved by a player council;
- first-session prototype tested with beginners.

## 35. Phase 1 — Playable MVP (8–10 weeks)

Scope:

- Flutter Android/Web client;
- guest play;
- Dehla Pakad Classic rules engine;
- announced and cut trump;
- offline/online bots;
- private rooms and deep links;
- reconnect and bot takeover;
- guided tutorial;
- Hindi/English;
- match history;
- analytics;
- basic reporting;
- no purchases initially.

Exit criteria:

- 10,000 automated full-match simulations without invariant failure;
- 100-player closed alpha;
- private match completion above 80%;
- tutorial completion above 60%;
- no unresolved scoring defects.

## 36. Phase 2 — Public beta and monetization (6–8 weeks)

Scope:

- public casual matchmaking;
- ranked queue;
- ratings and seasons;
- Mendikot rule pack;
- friends and rematch;
- cosmetics store;
- rewarded ads after matches;
- one-time ad removal;
- moderation dashboard;
- performance hardening;
- Android production launch, web public beta.

Exit criteria:

- D1 retention target: 30%+;
- D7 retention target: 12%+;
- match completion: 85%+;
- rematch rate: 25%+ for private rooms;
- p95 matchmaking below 30 seconds in seeded regions;
- crash-free sessions: 99.5%+.

Targets are hypotheses and should be adjusted after cohort data.

## 37. Phase 3 — Social scale (8–12 weeks)

Scope:

- iOS launch;
- clubs;
- club leagues;
- season pass;
- premium statistics;
- replay viewer;
- AI coach;
- additional languages;
- spectator mode with delay;
- creator events;
- regional growth campaigns.

## 38. Phase 4 — Competitive platform

Only after sustainable retention and liquidity:

- scheduled non-cash tournaments;
- team rankings;
- anti-collusion models;
- expert ISMCTS/self-play bots;
- shareable replay clips;
- API for approved community events;
- possible esports classification/registration assessment.

---

# Part X — Team and operating model

## 39. Recommended core team

- 1 Chief Product Owner / Product Manager
- 1 Game Designer and rules analyst
- 1 Product Designer
- 2 Flutter engineers
- 2 Rust backend engineers
- 1 QA/SDET
- 0.5 DevOps/SRE
- 0.5 Data analyst
- 0.5 Growth/ASO marketer
- part-time legal/privacy advisor
- community manager from public beta onward

A strong MVP can be built by 6–8 full-time contributors plus fractional specialists.

## 40. Product governance

### Weekly product review

- retention and funnel;
- disputed-rule reports;
- matchmaking health;
- fairness/cheating incidents;
- monetization guardrails;
- top crashes and disconnects.

### Monthly rule council

- experienced Dehla Pakad and Mendikot players;
- product owner;
- game designer;
- rules-engine engineer;
- QA lead.

Rule changes must create a new versioned rule pack. Never silently alter historical match behavior.

---

# Part XI — Metrics

## 41. North-star metric

**Completed human-player matches per weekly active player.**

This metric joins entertainment, liquidity and reliability. Revenue should not become the north-star metric before the game earns repeat play.

## 42. Funnel metrics

- install/open to tutorial start;
- tutorial completion;
- first match completion;
- account upgrade;
- first friend invite;
- invite acceptance;
- second match within 24 hours;
- D1/D7/D30 retention.

## 43. Match health

- queue time;
- bot-fill rate;
- turn timeout rate;
- disconnect rate;
- match completion;
- average hand and match duration;
- rematch rate;
- surrender/abandon rate;
- reported unfairness;
- replay-verification failures.

## 44. Social health

- private tables per active user;
- invited users activated;
- matches with a known partner;
- club weekly activity;
- report rate;
- mute/block rate;
- toxic username/chat incidence.

## 45. Monetization health

- payer conversion;
- first purchase timing;
- ad opt-in and completion;
- average revenue per daily active user;
- membership trial and renewal;
- refund rate;
- revenue by cosmetic/membership/ads;
- retention difference between payer and non-payer;
- complaint rate after monetization exposure.

## 46. Fairness metrics

- win rate by seat/dealer/team position;
- win rate by device/network quality;
- suspicious partner co-play patterns;
- impossible-information decisions;
- repeated disconnect advantage;
- bot win rates by skill cohort;
- shuffle-verification success.

---

# Part XII — Risk register

| Risk | Impact | Mitigation |
|---|---|---|
| Regional rule disputes | Poor ratings and mistrust | Named rule packs, visible settings, rule council, replayable rules version |
| Empty matchmaking | Early churn | Private-room focus, geographic seeding, bots, limited queues |
| Weak bots | Single-player churn | Heuristic baseline, simulation ladder, difficulty calibration |
| Collusion/signalling | Ranked integrity loss | No private in-hand chat, server logs, partner pattern analysis, reporting |
| Reconnect abuse | Unfair outcomes | grace period, server timers, reliability score, bot takeover |
| Gambling perception | Store/legal/brand risk | no cash, no wagering, social visual design, direct-purchase cosmetics |
| Ad frustration | Retention damage | no in-hand ads, caps, rewarded opt-in, ad-free purchase |
| Over-engineering | Delayed launch | modular monolith, one rule pack first, managed infrastructure |
| Rule-engine defect | Severe trust loss | pure state machine, golden replays, property tests, simulations |
| Child privacy breach | Regulatory and store risk | age gate, parental controls, non-personalized ads, data minimization |
| Toxic social features | Community damage | preset reactions first, mute/block/report, delayed voice launch |

---

# Part XIII — Prioritized backlog

## Must-have MVP

- canonical Dehla Pakad rules;
- deterministic server-authoritative engine;
- legal-move enforcement;
- smart casual bots;
- interactive tutorial;
- private room link/code;
- reconnect and bot takeover;
- match result and Kot tracking;
- Hindi and English;
- analytics and crash monitoring;
- report/block/mute;
- fairness commitment and replay log.

## Should-have V1

- public casual/ranked matchmaking;
- Mendikot rules;
- friends and rematch;
- leaderboards;
- cosmetics;
- ad removal;
- rewarded post-match ads;
- match history and basic replay;
- additional Indian languages.

## Could-have V2

- clubs;
- club leagues;
- AI coach;
- spectator mode;
- premium analytics;
- creator events;
- advanced bots;
- custom family-rule presets.

## Not now

- cash games;
- paid-entry tournaments;
- blockchain/NFT assets;
- open voice chat;
- many simultaneous regional queues;
- microservice decomposition;
- reinforcement learning before a stable simulation baseline.

---

# 47. Final recommendation

The winning product is not “another Indian card game app.” It is a **high-trust social strategy platform built around the unique centre-pile mechanic**.

The best launch sequence is:

1. perfect one canonical Dehla Pakad ruleset;
2. make private play effortless;
3. use bots to solve initial liquidity;
4. demonstrate fairness and reliability;
5. add ranked and Mendikot modes;
6. monetize identity, analysis and club organization;
7. scale through regional language, creators and friend invitations.

The most defensible feature is not the deck or the basic rules. It is the combination of:

- culturally accurate rule packs;
- excellent partnership gameplay;
- explainable strategy coaching;
- reliable multiplayer;
- verifiable fairness;
- a non-gambling business model.

---

# Research basis

- Pagat, **Dehla Pakad — card game rules**, updated 1 August 2026.
- Pagat, **Mendikot — card game rules**.
- Google Play listings for current Mendicot/Mindi competitors and user reviews.
- Lumikai, **State of India Interactive Media Report 2025**, published March 2026.
- Government of India, Press Information Bureau, **Promotion and Regulation of Online Gaming Rules, 2026**.
- Google Play payments, Families and rewarded-ad policies.
- Apple App Review Guidelines and In-App Purchase guidance.

**Important:** Regulatory interpretation and pricing are product-planning recommendations, not legal or tax advice. Obtain Indian gaming, consumer-protection, privacy and platform-policy review before production launch.

---

# Addendum A — Multi-game packaging with Judgement (2026-08-06)

This addendum amends the standalone assumptions in Parts VI–IX for delivery
**inside the Judgement monorepo**. Binding architecture: [`docs/adr/0006-multi-game-platform.md`](docs/adr/0006-multi-game-platform.md),
capacity: [`docs/dehla_game_estimation.md`](docs/dehla_game_estimation.md).

## A.1 Decisions locked

1. **Monorepo** with separate Dehla backend crates (`dehla-*`) and
   `frontend/dehla_flutter` package; thin `frontend/shell_flutter` for game picker.
2. **Separate Railway service + Postgres** for Dehla; Judgement API unchanged.
3. **Presence:** Judgement ADR 0004 — vacant seat + pause + human reclaim;
   **no bot fill** at MVP.
4. **Partnership:** after four players seated, default **random opposite
   partners**; optional **choose partners** before start.
5. **MVP tables:** private rooms + namespaced deep links (`/dp/r/{CODE}`) first;
   public matchmaking / ranked deferred.
6. **CAP/NFR:** CP table authority, single-writer, Judgement-aligned latency and
   ~99.0–99.5% availability **class** (not a 99.9% MVP contract). Redis deferred.
7. **Judgement non-regression (must follow):** do not modify Judgement game
   engine, protocol, persistence, actor, or table UI for Dehla. Copy or
   redevelop under `dehla-*` / `dehla_flutter`.

## A.2 §24 Non-functional targets — superseded for MVP

Replace the MVP bullets in §24 with:

| NFR | MVP target |
|-----|------------|
| CAP class | CP (persist tip before observe) |
| Availability class | ~99.0–99.5% if API+DB healthy (not contractual SLO) |
| Perceived action latency (India) | ~100–200 ms p50 |
| Persist p95 | &lt; 50 ms |
| Reconnect restore | &lt; 3 s after transport recovery |
| Crash-free sessions | &gt; 99.5% |
| Private match completion | &gt; 85% |
| Deterministic replay | 100% of completed matches |
| Queue / bot-fallback latency | N/A at MVP (no bots, private rooms only) |

99.9% availability and Redis-backed presence remain **Phase B+** only with an
explicit HA / multi-writer design.

## A.3 Phase 1 MVP scope — trimmed

In scope:

- Dehla Pakad Classic rules engine (server-authoritative);
- announced + cut trump;
- private rooms, deep links, guest sessions;
- ADR 0004 reclaim (no bots);
- partnership modes (random default + choose partners);
- pile-capture HUD;
- Hindi/English basics;
- analytics hooks;
- separate `dehla-server` on Railway.

Out of Phase 1 (defer): Mendikot pack, Custom Family Table schema, public
matchmaking, ranked, economy/IAP, Redis, bot engine, clubs/voice/spectators.

## A.4 Frontend layout

```text
frontend/shell_flutter/      # game picker + /dp and Judgement deep-link host
frontend/judgement_flutter/  # existing Judgement — do not regress
frontend/dehla_flutter/      # Dehla package (standalone main_dev for debug)
```

Dehla never imports Judgement protocol/table code (and reverse). Reclaim keys
namespaced (`dehla_reclaim_v1`, etc.).
