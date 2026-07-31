# Common questions (curated FAQ)

**ruleset_version:** `mvp-1`  
**source:** curated (not model-generated)

This file is the MVP authority for gameplay FAQ answers. Entries are keyed for
deterministic lookup. Each answer cites `rule_id` values from the sibling docs.

---

## faq.what-is-judgement

**aliases:** what is judgement, what is oh hell, how do you play, basic rules  
**rule_references:** `basic-gameplay-001`

Judgement (Oh Hell) is a trick-taking game where you bid how many tricks you will
win and must hit that number exactly. Trump and follow-suit rules decide who wins
each trick; exact bids score, misses score zero.

---

## faq.bid-range

**aliases:** what can i bid, bid limits, maximum bid, can i bid zero  
**rule_references:** `bidding-001`

You may bid any integer from 0 up to the number of cards dealt in the current
round. Bidding above the card count is illegal. Zero is always allowed.

---

## faq.dealer-bids-last

**aliases:** who bids first, dealer bid order, bidding order  
**rule_references:** `bidding-001`

Bidding starts left of the dealer and goes clockwise. The dealer always bids last.

---

## faq.sum-restriction

**aliases:** sum rule, equal tricks, dealer cannot make sum equal, bid sum  
**rule_references:** `bidding-001`

If the room enables the sum restriction, the dealer’s bid must not make the total
of all bids equal the number of tricks available. When the restriction is off,
the dealer may bid any legal amount.

---

## faq.follow-suit

**aliases:** must i follow suit, can i trump, off suit, discard  
**rule_references:** `follow-suit-001`, `trump-001`

If you hold the lead suit, you must play it. Only when you have none of the lead
suit may you play trump or any other card.

---

## faq.trump-wins

**aliases:** who wins the trick, does trump beat ace, highest trump  
**rule_references:** `trump-001`, `follow-suit-001`

If any trump was played in the trick, the highest trump wins. Otherwise the
highest card of the lead suit wins. Off-suit non-trump cards never win.

---

## faq.how-trump-chosen

**aliases:** how is trump chosen, revealed card, rotating trump, choose trump  
**rule_references:** `trump-001`

Default rooms reveal an undealt card’s suit as trump (or no trump if the deck is
exhausted). Rooms may instead use chosen first trump with suit rotation each round.

---

## faq.exact-bid-scoring

**aliases:** how do points work, scoring, overtrick, undertrick, 10 plus bid  
**rule_references:** `scoring-exact-001`

Hitting your bid exactly scores 10 + bid (MVP default). Taking more or fewer
tricks than bid scores 0 for that round.

---

## faq.player-count

**aliases:** how many players, 4 players, 8 players, seats  
**rule_references:** `basic-gameplay-001`

Matches support 3 to 8 players. The deck and round schedule scale with the seat
count configured for the room.

---

## faq.turn-timer

**aliases:** timer, time limit, auto play, timeout  
**rule_references:** `bidding-001`, `basic-gameplay-001`

Rooms may enable an optional turn timer. If time expires, the server may apply a
legal default action. Gameplay rules (legal bids and cards) still apply.
