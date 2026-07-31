# judgement_flutter

Flutter Web client for the Judgement card game. The server is authoritative:
this app renders `PlayerGameView` snapshots and sends commands; it never
computes game rules locally (PLAN.md §3.2).

## Structure

```text
lib/
├── app/          # MaterialApp, theme
├── models/       # Dart mirrors of the wire protocol (judgement-protocol)
├── networking/   # REST client + WebSocket game socket
├── state/        # GameController: snapshots, pending commands, timer, reconnect
├── screens/      # Landing, lobby, table, final result
└── widgets/      # Playing card, scoreboard
```

State management is plain `ChangeNotifier` + `ListenableBuilder` (no external
state package needed at this size; can move to Riverpod later if state graphs
grow — PLAN.md §32 lists it as a suggestion, not a lock).

## Running

```bash
# Backend first (from judgement/backend):
cargo run -p judgement-server

# Then (API_BASE defaults to http://localhost:8080):
flutter run -d chrome --dart-define=API_BASE=http://localhost:8080
```

## Tests

```bash
flutter analyze
flutter test                       # protocol + widget tests

# Six clients play a full game against a live server:
flutter test test/e2e_full_game_test.dart \
  --dart-define=E2E=true --dart-define=API_BASE=http://localhost:8080
```
