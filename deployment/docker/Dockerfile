# Multi-stage build for judgement-server (PLAN.md §25.1).
# Build from repo root: docker build -f deployment/docker/Dockerfile .

FROM rust:1.88-bookworm AS builder
WORKDIR /app
COPY backend/ ./backend/
COPY rules/ ./rules/
WORKDIR /app/backend
RUN cargo build --release -p judgement-server

FROM debian:bookworm-slim
RUN apt-get update \
    && apt-get install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*
WORKDIR /srv
COPY --from=builder /app/backend/target/release/judgement-server /usr/local/bin/judgement-server
COPY --from=builder /app/backend/crates/judgement-persistence/migrations /srv/migrations/persistence
COPY --from=builder /app/backend/crates/judgement-rag/migrations /srv/migrations/rag
COPY --from=builder /app/rules /srv/rules
ENV RUST_LOG=info
ENV PORT=8080
ENV JUDGEMENT_MIGRATIONS_DIR=/srv/migrations/persistence
EXPOSE 8080
HEALTHCHECK --interval=10s --timeout=3s --start-period=10s --retries=3 \
  CMD curl -fsS http://127.0.0.1:8080/healthz || exit 1
USER nobody
CMD ["judgement-server"]
