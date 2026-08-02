# Disconnect policy

**rule_id:** `disconnect-001`  
**ruleset_version:** `mvp-1`  
**category:** presence

If a player’s WebSocket drops mid-game, their seat becomes **vacant
immediately** (`reconnect_grace_seconds` default **0**). The table stays
paused. The same player or another human may claim the seat with the room
invite code (`POST /rooms/{code}/claim` or join while in-game). If no
replacement is available, the host can end the game (or a 10-minute vacancy
timeout ends it). Host migration applies when the host disconnects.
A non-zero grace (legacy) still allows short reconnect-before-vacant; see
ADR 0004.
