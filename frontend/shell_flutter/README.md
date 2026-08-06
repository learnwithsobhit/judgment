# shell_flutter

Multi-game shell: game picker + Dehla routes (`/dp…`).

Judgement remains on `judgement_flutter` until a non-breaking package cutover
(ADR 0006 — do not regress Judgement).

```bash
cd frontend/shell_flutter
flutter run -d chrome \
  --dart-define=DEHLA_API_BASE=http://localhost:8081
```
