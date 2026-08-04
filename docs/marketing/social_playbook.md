# Judgement social playbook

**Positioning:** Judgement with friends — bid, trump, brag in ~15 minutes.

**Handle / tag:** `#JudgementTable` (product share templates already include this).

## Content pillars (weekly)

1. **Win flex** — trophy cards exported from the app (Share → Save trophy card).
2. **Rules in 15s** — trump / exact bid / dealer restriction shorts.
3. **Challenge drops** — timed table nights; winners post Stories with `#JudgementTable`.
4. **Table energy** — emotes / voice moments (no player PII without consent).
5. **Event invites** — scheduled lobbies via `/e/{slug}`.

## Platform cadence (steady state)

| Platform | Format | Cadence |
|----------|--------|---------|
| WhatsApp | Product-driven group forwards | Organic from Share |
| Telegram | Channel + challenge night | 3 posts / week |
| Instagram | Stories (trophy card) + Reels | 4 Stories + 3 Reels / week |
| X | Clips + challenge prompts | 5 posts / week |
| Facebook | Reels + family-group events | 3 / week |

## Challenge formats

- **Weekly Trump Night** — host event; winners Story their card.
- **Exact Bid Streak** — most exact rounds brag.
- **Underdog Comeback** — #1 after trailing.
- **Bring 3 Friends** — lobby invite CTA.

## In-app share surfaces

- Victory: **Share win** / **Challenge friends**
- Results: **Share** (+ copy summary with UTM link)
- Lobby: **Invite friends**
- Event manage: **Share on WhatsApp**

UTMs: `utm_source=share`, `utm_medium` = channel, `utm_campaign` =
`result_win` | `result_challenge` | `lobby_invite` | `event_invite`.

Landing captures UTMs into localStorage (`judgement_utm_last_v1`) and increments
share counters (`judgement_share_events_v1`).

## Two-week launch sketch

**Week 1:** Soft-launch share CTAs with friends; post 3 Reels (rules / win / invite).
**Week 2:** First Trump Night event; seed 5–10 micro creators with lobby + trophy cards.
No paid Meta ads until share→join UTMs show signal.
