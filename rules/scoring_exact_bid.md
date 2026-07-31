# Exact-bid scoring

**rule_id:** `scoring-exact-001`  
**ruleset_version:** `mvp-1`  
**category:** scoring

## Round score

At the end of each round:

- If a player’s tricks won **equal** their bid, they score **10 + bid** points
  (MVP default).
- If they took more or fewer tricks than bid, they score **0** for that round.

Variant constants may change the base bonus, but the exact-match rule stays.

## Match score

Round scores accumulate. The match ends when the configured round schedule finishes
(for example a fixed card schedule or up-and-down). The highest total wins; ties
are reported as ties.
