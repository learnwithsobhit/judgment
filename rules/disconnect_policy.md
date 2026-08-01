# Disconnect policy

**rule_id:** `disconnect-001`  
**ruleset_version:** `mvp-1`  
**category:** presence

If a player’s WebSocket drops mid-game, the table pauses briefly (grace period,
default ~60s). Reconnect with a valid session token restores control. If grace
expires or the player leaves permanently, their seat becomes **vacant** — the
table stays paused. Another human may claim the seat with the room invite code
(`POST /rooms/{code}/claim` or join while in-game). If no replacement is
available, the host can end the game (or a 10-minute vacancy timeout ends it).
Host migration applies when the host disconnects. See ADR 0004.
