# Disconnect policy

**rule_id:** `disconnect-001`  
**ruleset_version:** `mvp-1`  
**category:** presence

If a player’s WebSocket drops mid-game, the table pauses briefly (grace period).
Reconnect with a valid session token restores control. If grace expires or the
player leaves permanently, a rule-based bot takes their seat. Host migration
applies when the host disconnects. See ADR 0004.
