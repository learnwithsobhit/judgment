# dehla_flutter

Dehla Pakad / Mendikot client package (ADR 0006).

- **No Judgement imports** — talks only to `DEHLA_API_BASE` (default `http://localhost:8081`).
- Embedded by `shell_flutter`; debug via package tests or shell navigation to Dehla.

```bash
cd frontend/dehla_flutter && flutter test
# API locally:
cd backend && cargo run -p dehla-server
```
