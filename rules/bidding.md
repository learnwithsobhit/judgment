# Bidding

**rule_id:** `bidding-001`  
**ruleset_version:** `mvp-1`  
**category:** bidding

## Bid range

Each player bids an integer from **0** through the number of cards dealt that round
(inclusive). Bidding more tricks than cards dealt is illegal.

## Order

Bidding starts with the player to the **left of the dealer** and proceeds clockwise.
The **dealer bids last**.

## Exact bid (no over/under)

The goal is to take **exactly** the number of tricks you bid. Taking more or fewer
than your bid scores nothing for that round (exact-bid scoring).

## Optional sum rule

Rooms may enable a **sum restriction**: the dealer’s bid must not make the sum of
all bids equal the number of tricks available that round. When the restriction is
off, any legal bid is allowed for the dealer.

## Timer

If the room enables a turn timer, failing to bid in time may auto-select a legal
default (for example 0). The timer never overrides the legal bid range.
