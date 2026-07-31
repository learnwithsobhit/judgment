# Following suit

**rule_id:** `follow-suit-001`  
**ruleset_version:** `mvp-1`  
**category:** play

## Must follow

When a trick is led, the lead suit is the suit of the first card played. Every
later player who **holds at least one card of the lead suit** must play a card of
that suit.

## When you cannot follow

If you have no card of the lead suit, you may play **any** card from your hand,
including trump or an off-suit discard.

## Illegal plays

Playing a card that is not in your hand, playing out of turn, or failing to follow
suit when able are rejected by the server with a deterministic reason code.
The client only offers cards listed in `legal_actions`.
