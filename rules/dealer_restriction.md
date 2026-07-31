# Dealer bid restriction

**rule_id:** `dealer-restriction-001`  
**ruleset_version:** `mvp-1`  
**category:** bidding

When enabled, after every other player has bid, the dealer may not choose a bid
that makes the **sum of all bids equal** the number of tricks in the round.
This prevents every player from being able to succeed simultaneously under
exact-bid scoring.

When disabled, the dealer may bid any value in `0..=cards_dealt`.
See also `bidding-001`.
