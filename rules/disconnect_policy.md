# Disconnect policy

**rule_id:** `disconnect-001`  
**ruleset_version:** `mvp-1`  
**category:** presence

If a player’s WebSocket drops mid-game, their seat becomes **vacant
immediately** (`reconnect_grace_seconds` default **0**). The table stays
paused. Options:

1. **Rejoin** — same session reconnects the game WS, or another human claims
   via room code (`POST /rooms/{code}/claim` / join while in-game).
2. **Restart** — host, remaining ≥ 3: `POST /rooms/{code}/restart` (new game,
   same room).
3. **End** — host ends the game (or **10-minute** vacancy TTL auto-ends).

Host migration applies when the host disconnects (and `host_session` is
synced). A non-zero grace (legacy) still allows short reconnect-before-vacant;
see ADR 0004.
