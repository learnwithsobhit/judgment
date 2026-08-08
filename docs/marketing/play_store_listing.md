# Play Store listing copy — Judgement

Use with Play Console account `chaturvedi99@gmail.com`  
Package: `com.judgement.game`

## App details
- **App name:** Judgement
- **Category:** Games → Card
- **Free**
- **Privacy policy:** https://judgment-lws-260731.web.app/privacy/
- **Contact email:** shobhit.chaturvedi@zohomail.in (or Play account email)

## Short description (80 chars max)
Bid. Trump. Brag. Multiplayer Judgement (Oh Hell) with friends.

## Full description
Judgement is a free multiplayer card game — the classic “Oh Hell” / Judgement table, in your pocket.

Create a room, share a code, and play with friends. Pick a nickname (no account required), bid each round, follow trump, and try to hit your bid exactly.

Features
• Guest play — nickname + session, no registration
• Create or join rooms with a shareable code
• Configurable table size, timers, trump cycle, and round schedules
• Emotes, soundboard, and short voice notes at the table
• Reclaim your seat if you drop for a moment

You must be 16+ (or the age of digital consent where you live). Optional microphone access is only used when you send a voice note.

Privacy: https://judgment-lws-260731.web.app/privacy/  
Terms: https://judgment-lws-260731.web.app/terms/

## Graphics
- **App icon:** `frontend/judgement_flutter/web/icons/Icon-512.png` (512×512)
- **Feature graphics (1024×500, ready for Play):**
  - `docs/marketing/play_store_assets/feature-graphic-cards-1024x500.png` — Ace/King + title (best match to app icon)
  - `docs/marketing/play_store_assets/feature-graphic-type-1024x500.png` — clean wordmark + suits
  - `docs/marketing/play_store_assets/feature-graphic-table-1024x500.png` — table atmosphere + card fan
- **Phone screenshots:** capture from emulator/device (lobby, table, results) — Play requires at least 2

## Google Play Games on PC (game card)
Upload **both** together under Grow → Store presence → Main store listing:

**Feature graphic (background, no text)** — 16:9 PNG/JPG  
- `docs/marketing/play_store_assets/play_games_pc/play-games-pc-feature-cards-1920x1080.png`  
- `docs/marketing/play_store_assets/play_games_pc/play-games-pc-feature-table-1920x1080.png`

**Logo (overlay, transparent PNG)** — exact **600×400**  
- Preferred: `play-games-pc-logo-clean-600x400.png` or `play-games-pc-logo-title-only-600x400.png`  
- Styled: `play-games-pc-logo-judgement-600x400.png` / `play-games-pc-logo-suits-600x400.png`

Recommended pair: **feature-cards** + **logo-clean**.

## AAB upload path
`frontend/judgement_flutter/build/app/outputs/bundle/release/app-release.aab`

## Data safety (answers summary)
| Data | Collected | Shared | Purpose |
|------|-----------|--------|---------|
| Nickname | Yes (ephemeral session) | With table players | App functionality |
| App activity / game state | Yes | With table players | App functionality |
| Optional RSVP phone (events) | Optional | With event host if opted in | App functionality |
| Voice notes | Ephemeral, not archived | Broadcast to current table | App functionality |
| Microphone | Permission; only when sending voice | N/A (audio payload as above) | App functionality |

Not sold. Not used for advertising. Not required to create a permanent account.

## Content rating notes
- Game / Card
- Social interaction (chat-like: emotes, voice notes)
- No gambling with real money
- Users 16+
