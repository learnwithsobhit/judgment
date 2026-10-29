//! sqlx-backed PostgreSQL implementation.

use async_trait::async_trait;
use chrono::Utc;
use judgement_domain::{
    ActionId, EventId, GameId, GameRules, PlayerId, RankedPlayer, RoomId, RsvpId, SessionId, Suit,
};
use judgement_engine::InternalGameState;
use sqlx::postgres::PgPoolOptions;
use sqlx::{PgPool, Row};
use uuid::Uuid;

use crate::error::PersistError;
use crate::models::*;
use crate::GameStore;

#[derive(Clone)]
pub struct PostgresStore {
    pool: PgPool,
}

impl PostgresStore {
    pub async fn connect(database_url: &str) -> Result<Self, PersistError> {
        let pool = PgPoolOptions::new()
            // Sized for a single API machine; leave headroom under PG max_connections.
            .max_connections(10)
            .acquire_timeout(std::time::Duration::from_secs(2))
            .idle_timeout(std::time::Duration::from_secs(60))
            .max_lifetime(std::time::Duration::from_secs(30 * 60))
            .test_before_acquire(true)
            .after_connect(|conn, _meta| {
                Box::pin(async move {
                    sqlx::query("SET statement_timeout = '3s'")
                        .execute(&mut *conn)
                        .await?;
                    Ok(())
                })
            })
            .connect(database_url)
            .await?;
        Ok(Self { pool })
    }

    pub fn from_pool(pool: PgPool) -> Self {
        Self { pool }
    }

    pub fn pool(&self) -> &PgPool {
        &self.pool
    }

    /// Run SQL migrations from `crates/judgement-persistence/migrations`.
    pub async fn migrate(
        &self,
        migrations_dir: impl AsRef<std::path::Path>,
    ) -> Result<(), PersistError> {
        let migrator = sqlx::migrate::Migrator::new(migrations_dir.as_ref())
            .await
            .map_err(|e| PersistError::Conflict(format!("migration load failed: {e}")))?;
        migrator
            .run(&self.pool)
            .await
            .map_err(|e| PersistError::Conflict(format!("migration failed: {e}")))?;
        Ok(())
    }
}

fn suit_to_db(suit: Suit) -> String {
    serde_json::to_value(suit)
        .ok()
        .and_then(|v| v.as_str().map(str::to_owned))
        .unwrap_or_default()
}

fn suit_from_db(raw: &str) -> Option<Suit> {
    serde_json::from_value(serde_json::Value::String(raw.to_owned())).ok()
}

#[async_trait]
impl GameStore for PostgresStore {
    async fn upsert_session(&self, session: &StoredSession) -> Result<(), PersistError> {
        sqlx::query(
            r#"
            INSERT INTO guest_sessions (session_id, nickname, token, created_at, avatar_id, user_id)
            VALUES ($1, $2, $3, $4, $5, $6)
            ON CONFLICT (session_id) DO UPDATE
              SET nickname = EXCLUDED.nickname,
                  token = EXCLUDED.token,
                  avatar_id = EXCLUDED.avatar_id,
                  user_id = EXCLUDED.user_id
            "#,
        )
        .bind(session.session_id.0)
        .bind(&session.nickname)
        .bind(&session.token)
        .bind(session.created_at)
        .bind(&session.avatar_id)
        .bind(session.user_id)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    async fn upsert_room(&self, room: &StoredRoom) -> Result<(), PersistError> {
        let mut tx = self.pool.begin().await?;

        sqlx::query(
            r#"
            INSERT INTO rooms (
                room_id, code, host_session_id, max_players, turn_timeout_seconds,
                first_trump, trump_cycle, round_schedule, dealer_total_restriction,
                open_start, phase, game_id, created_at
            ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13)
            ON CONFLICT (room_id) DO UPDATE SET
                host_session_id = EXCLUDED.host_session_id,
                max_players = EXCLUDED.max_players,
                turn_timeout_seconds = EXCLUDED.turn_timeout_seconds,
                first_trump = EXCLUDED.first_trump,
                trump_cycle = EXCLUDED.trump_cycle,
                round_schedule = EXCLUDED.round_schedule,
                dealer_total_restriction = EXCLUDED.dealer_total_restriction,
                open_start = EXCLUDED.open_start,
                phase = EXCLUDED.phase,
                game_id = EXCLUDED.game_id
            "#,
        )
        .bind(room.room_id.0)
        .bind(&room.code)
        .bind(room.host_session_id.0)
        .bind(room.max_players as i16)
        .bind(room.turn_timeout_seconds.map(|t| t as i16))
        .bind(room.first_trump.map(suit_to_db))
        .bind(serde_json::to_value(&room.trump_cycle)?)
        .bind(serde_json::to_value(&room.round_schedule)?)
        .bind(room.dealer_total_restriction)
        .bind(room.open_start)
        .bind(&room.phase)
        .bind(room.game_id.map(|g| g.0))
        .bind(room.created_at)
        .execute(&mut *tx)
        .await?;

        sqlx::query("DELETE FROM room_players WHERE room_id = $1")
            .bind(room.room_id.0)
            .execute(&mut *tx)
            .await?;

        for player in &room.players {
            sqlx::query(
                r#"
                INSERT INTO room_players (
                    room_id, session_id, player_id, nickname, seat, ready, joined_at, avatar_id
                ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
                "#,
            )
            .bind(room.room_id.0)
            .bind(player.session_id.0)
            .bind(player.player_id.0)
            .bind(&player.nickname)
            .bind(player.seat as i16)
            .bind(player.ready)
            .bind(player.joined_at)
            .bind(&player.avatar_id)
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;
        Ok(())
    }

    async fn delete_room(&self, room_id: RoomId) -> Result<(), PersistError> {
        sqlx::query("DELETE FROM rooms WHERE room_id = $1")
            .bind(room_id.0)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn load_sessions(&self) -> Result<Vec<StoredSession>, PersistError> {
        let rows = sqlx::query(
            "SELECT session_id, nickname, token, created_at, avatar_id, user_id FROM guest_sessions",
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(rows
            .into_iter()
            .map(|row| StoredSession {
                session_id: SessionId(row.get("session_id")),
                nickname: row.get("nickname"),
                token: row.get("token"),
                created_at: row.get("created_at"),
                avatar_id: row.get("avatar_id"),
                user_id: row.get("user_id"),
            })
            .collect())
    }

    async fn load_rooms(&self) -> Result<Vec<StoredRoom>, PersistError> {
        let room_rows = sqlx::query(
            r#"
            SELECT room_id, code, host_session_id, max_players, turn_timeout_seconds,
                   first_trump, trump_cycle, round_schedule, dealer_total_restriction,
                   open_start, phase, game_id, created_at
            FROM rooms
            "#,
        )
        .fetch_all(&self.pool)
        .await?;

        let mut rooms = Vec::new();
        for row in room_rows {
            let room_id: Uuid = row.get("room_id");
            let players = sqlx::query(
                r#"
                SELECT session_id, player_id, nickname, seat, ready, joined_at, avatar_id
                FROM room_players WHERE room_id = $1 ORDER BY seat
                "#,
            )
            .bind(room_id)
            .fetch_all(&self.pool)
            .await?
            .into_iter()
            .map(|p| StoredRoomPlayer {
                session_id: SessionId(p.get("session_id")),
                player_id: PlayerId(p.get("player_id")),
                nickname: p.get("nickname"),
                seat: p.get::<i16, _>("seat") as u8,
                ready: p.get("ready"),
                joined_at: p.get("joined_at"),
                avatar_id: p.get("avatar_id"),
            })
            .collect();

            let first_trump: Option<String> = row.get("first_trump");
            let cycle_value: Option<serde_json::Value> = row.get("trump_cycle");
            let trump_cycle = cycle_value.and_then(|v| {
                if v.is_null() {
                    None
                } else {
                    serde_json::from_value(v).ok()
                }
            });
            let schedule_value: serde_json::Value = row.get("round_schedule");
            let round_schedule = serde_json::from_value(schedule_value).unwrap_or_default();
            rooms.push(StoredRoom {
                room_id: RoomId(room_id),
                code: row.get("code"),
                host_session_id: SessionId(row.get("host_session_id")),
                max_players: row.get::<i16, _>("max_players") as u8,
                turn_timeout_seconds: row
                    .get::<Option<i16>, _>("turn_timeout_seconds")
                    .map(|t| t as u16),
                first_trump: first_trump.as_deref().and_then(suit_from_db),
                trump_cycle,
                round_schedule,
                dealer_total_restriction: row.get("dealer_total_restriction"),
                open_start: row.get("open_start"),
                phase: row.get("phase"),
                game_id: row.get::<Option<Uuid>, _>("game_id").map(GameId),
                players,
                created_at: row.get("created_at"),
            });
        }
        Ok(rooms)
    }

    async fn create_game(&self, record: &NewGame) -> Result<(), PersistError> {
        let mut tx = self.pool.begin().await?;
        let rules = serde_json::to_value(&record.rules)?;
        let state = serde_json::to_value(&record.initial_state)?;

        sqlx::query(
            r#"
            INSERT INTO games (game_id, room_id, rules, seed, status, state_version)
            VALUES ($1, $2, $3, $4, 'active', $5)
            "#,
        )
        .bind(record.game_id.0)
        .bind(record.room_id.0)
        .bind(rules)
        .bind(record.seed.map(|s| s as i64))
        .bind(record.initial_state.version as i64)
        .execute(&mut *tx)
        .await?;

        for player in &record.players {
            sqlx::query(
                r#"
                INSERT INTO game_players (game_id, player_id, session_id, nickname, seat, user_id)
                VALUES ($1, $2, $3, $4, $5, $6)
                "#,
            )
            .bind(record.game_id.0)
            .bind(player.player_id.0)
            .bind(player.session_id.0)
            .bind(&player.nickname)
            .bind(player.seat as i16)
            .bind(player.user_id)
            .execute(&mut *tx)
            .await?;
        }

        for (index, event) in record.initial_events.iter().enumerate() {
            let payload = serde_json::to_value(event)?;
            sqlx::query(
                r#"
                INSERT INTO game_events (game_id, state_version, event_index, action_id, payload)
                VALUES ($1, $2, $3, $4, $5)
                "#,
            )
            .bind(record.game_id.0)
            .bind(record.initial_state.version as i64)
            .bind(index as i16)
            .bind(record.start_action_id.0)
            .bind(payload)
            .execute(&mut *tx)
            .await?;
        }

        sqlx::query(
            r#"
            INSERT INTO game_snapshots (game_id, state_version, state)
            VALUES ($1, $2, $3)
            "#,
        )
        .bind(record.game_id.0)
        .bind(record.initial_state.version as i64)
        .bind(state)
        .execute(&mut *tx)
        .await?;

        sqlx::query(
            r#"
            UPDATE rooms SET phase = 'in_game', game_id = $2 WHERE room_id = $1
            "#,
        )
        .bind(record.room_id.0)
        .bind(record.game_id.0)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(())
    }

    async fn commit_command(&self, commit: &CommandCommit) -> Result<(), PersistError> {
        let mut tx = self.pool.begin().await?;

        let existing: Option<(Uuid,)> = sqlx::query_as(
            r#"
            SELECT action_id FROM game_events
            WHERE game_id = $1 AND action_id = $2
            LIMIT 1
            "#,
        )
        .bind(commit.game_id.0)
        .bind(commit.action_id.0)
        .fetch_optional(&mut *tx)
        .await?;
        if existing.is_some() {
            tx.commit().await?;
            return Ok(());
        }

        for (index, event) in commit.events.iter().enumerate() {
            let payload = serde_json::to_value(event)?;
            sqlx::query(
                r#"
                INSERT INTO game_events (game_id, state_version, event_index, action_id, payload)
                VALUES ($1, $2, $3, $4, $5)
                "#,
            )
            .bind(commit.game_id.0)
            .bind(commit.state.version as i64)
            .bind(index as i16)
            .bind(commit.action_id.0)
            .bind(payload)
            .execute(&mut *tx)
            .await?;
        }

        // Keep a single latest snapshot (restore only needs the tip).
        let state = serde_json::to_value(&commit.state)?;
        sqlx::query(
            r#"
            DELETE FROM game_snapshots
            WHERE game_id = $1 AND state_version <> $2
            "#,
        )
        .bind(commit.game_id.0)
        .bind(commit.state.version as i64)
        .execute(&mut *tx)
        .await?;
        sqlx::query(
            r#"
            INSERT INTO game_snapshots (game_id, state_version, state)
            VALUES ($1, $2, $3)
            ON CONFLICT (game_id, state_version) DO UPDATE SET state = EXCLUDED.state
            "#,
        )
        .bind(commit.game_id.0)
        .bind(commit.state.version as i64)
        .bind(state)
        .execute(&mut *tx)
        .await?;

        let finished = commit.game_result.is_some();
        sqlx::query(
            r#"
            UPDATE games
            SET state_version = $2,
                status = CASE WHEN $3 THEN 'finished' ELSE status END,
                finished_at = CASE WHEN $3 THEN now() ELSE finished_at END,
                player_pace = $4
            WHERE game_id = $1
            "#,
        )
        .bind(commit.game_id.0)
        .bind(commit.state.version as i64)
        .bind(finished)
        .bind(serde_json::to_value(&commit.pace)?)
        .execute(&mut *tx)
        .await?;

        if let Some(round) = &commit.round_result {
            sqlx::query(
                r#"
                INSERT INTO round_results (game_id, round_index, scores)
                VALUES ($1, $2, $3)
                ON CONFLICT (game_id, round_index) DO UPDATE SET scores = EXCLUDED.scores
                "#,
            )
            .bind(commit.game_id.0)
            .bind(round.round_index as i32)
            .bind(&round.scores)
            .execute(&mut *tx)
            .await?;
        }

        if let Some(result) = &commit.game_result {
            let ranking = serde_json::to_value(&result.ranking)?;
            sqlx::query(
                r#"
                INSERT INTO game_results (game_id, ranking)
                VALUES ($1, $2)
                ON CONFLICT (game_id) DO UPDATE SET ranking = EXCLUDED.ranking
                "#,
            )
            .bind(commit.game_id.0)
            .bind(ranking)
            .execute(&mut *tx)
            .await?;
        }

        if crate::stats::stats_enabled() {
            if let Some(result) = &commit.game_result {
                sqlx::query("SAVEPOINT user_stats")
                    .execute(&mut *tx)
                    .await?;
                if let Err(error) = record_user_stats(&mut tx, commit, result).await {
                    tracing::warn!(%error, "user stats skipped so the game commit can finish");
                    sqlx::query("ROLLBACK TO SAVEPOINT user_stats")
                        .execute(&mut *tx)
                        .await?;
                } else {
                    let _ = sqlx::query("RELEASE SAVEPOINT user_stats")
                        .execute(&mut *tx)
                        .await;
                }
            }
        }

        tx.commit().await?;
        Ok(())
    }

    async fn action_committed(
        &self,
        game_id: GameId,
        action_id: ActionId,
    ) -> Result<bool, PersistError> {
        let row = sqlx::query(
            r#"
            SELECT 1 AS ok FROM game_events
            WHERE game_id = $1 AND action_id = $2
            LIMIT 1
            "#,
        )
        .bind(game_id.0)
        .bind(action_id.0)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.is_some())
    }

    async fn load_active_games(&self) -> Result<Vec<RestoredGame>, PersistError> {
        let game_rows = sqlx::query(
            r#"
            SELECT game_id, room_id, rules, seed, state_version
            FROM games WHERE status = 'active'
            "#,
        )
        .fetch_all(&self.pool)
        .await?;

        let mut out = Vec::new();
        for row in game_rows {
            let game_id = GameId(row.get("game_id"));
            if let Some(restored) = self.load_active_game(game_id).await? {
                out.push(restored);
            }
        }
        Ok(out)
    }

    async fn load_active_game(
        &self,
        game_id: GameId,
    ) -> Result<Option<RestoredGame>, PersistError> {
        let Some(row) = sqlx::query(
            r#"
            SELECT game_id, room_id, rules, seed, state_version, created_at, player_pace
            FROM games WHERE game_id = $1 AND status = 'active'
            "#,
        )
        .bind(game_id.0)
        .fetch_optional(&self.pool)
        .await?
        else {
            return Ok(None);
        };

        let rules: GameRules = serde_json::from_value(row.get("rules"))?;
        let seed: Option<i64> = row.get("seed");

        let Some(snapshot) = sqlx::query(
            r#"
            SELECT state FROM game_snapshots
            WHERE game_id = $1
            ORDER BY state_version DESC
            LIMIT 1
            "#,
        )
        .bind(game_id.0)
        .fetch_optional(&self.pool)
        .await?
        else {
            return Err(PersistError::NotFound(format!("snapshot for {game_id}")));
        };

        let state: InternalGameState = serde_json::from_value(snapshot.get("state"))?;

        let players = sqlx::query(
            r#"
            SELECT player_id, session_id, nickname, seat, user_id
            FROM game_players WHERE game_id = $1 ORDER BY seat
            "#,
        )
        .bind(game_id.0)
        .fetch_all(&self.pool)
        .await?
        .into_iter()
        .map(|p| NewGamePlayer {
            player_id: PlayerId(p.get("player_id")),
            session_id: SessionId(p.get("session_id")),
            nickname: p.get("nickname"),
            seat: p.get::<i16, _>("seat") as u8,
            user_id: p.get("user_id"),
        })
        .collect();

        let processed_actions = self.load_processed_actions(game_id).await?;

        Ok(Some(RestoredGame {
            game_id,
            room_id: RoomId(row.get("room_id")),
            rules,
            seed: seed.map(|s| s as u64),
            state,
            players,
            processed_actions,
            created_at: row.get("created_at"),
            pace: serde_json::from_value(row.get("player_pace"))?,
        }))
    }

    async fn load_processed_actions(
        &self,
        game_id: GameId,
    ) -> Result<Vec<(ActionId, u64)>, PersistError> {
        let rows = sqlx::query(
            r#"
            SELECT DISTINCT action_id, state_version
            FROM game_events
            WHERE game_id = $1 AND action_id IS NOT NULL
            "#,
        )
        .bind(game_id.0)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows
            .into_iter()
            .map(|row| {
                (
                    ActionId(row.get("action_id")),
                    row.get::<i64, _>("state_version") as u64,
                )
            })
            .collect())
    }

    async fn load_game_history(
        &self,
        game_id: GameId,
    ) -> Result<Option<GameHistory>, PersistError> {
        let Some(row) = sqlx::query("SELECT status, rules FROM games WHERE game_id = $1")
            .bind(game_id.0)
            .fetch_optional(&self.pool)
            .await?
        else {
            return Ok(None);
        };

        let rules: GameRules = serde_json::from_value(row.get("rules"))?;
        let status: String = row.get("status");

        let round_results = sqlx::query(
            "SELECT round_index, scores FROM round_results WHERE game_id = $1 ORDER BY round_index",
        )
        .bind(game_id.0)
        .fetch_all(&self.pool)
        .await?
        .into_iter()
        .map(|r| RoundResultRecord {
            round_index: r.get::<i32, _>("round_index") as usize,
            scores: r.get("scores"),
        })
        .collect();

        let ranking = sqlx::query("SELECT ranking FROM game_results WHERE game_id = $1")
            .bind(game_id.0)
            .fetch_optional(&self.pool)
            .await?
            .map(|r| {
                let value: serde_json::Value = r.get("ranking");
                serde_json::from_value::<Vec<RankedPlayer>>(value)
            })
            .transpose()?;

        let event_count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM game_events WHERE game_id = $1")
                .bind(game_id.0)
                .fetch_one(&self.pool)
                .await?;

        Ok(Some(GameHistory {
            game_id,
            status,
            rules,
            ranking,
            round_results,
            event_count: event_count as u64,
        }))
    }

    async fn upsert_scheduled_event(
        &self,
        event: &StoredScheduledEvent,
    ) -> Result<(), PersistError> {
        let mut tx = self.pool.begin().await?;
        sqlx::query(
            r#"
            INSERT INTO scheduled_events (
                event_id, slug, manage_token_hash, host_nickname, host_session_id,
                title, starts_at, timezone, duration_minutes, max_players,
                turn_timeout_seconds, first_trump, trump_cycle, round_schedule,
                status, room_id, created_at, updated_at
            ) VALUES (
                $1,$2,$3,$4,$5,$6,$7,$8,$9,$10,$11,$12,$13,$14,$15,$16,$17,$18
            )
            ON CONFLICT (event_id) DO UPDATE SET
                manage_token_hash = EXCLUDED.manage_token_hash,
                title = EXCLUDED.title,
                starts_at = EXCLUDED.starts_at,
                timezone = EXCLUDED.timezone,
                duration_minutes = EXCLUDED.duration_minutes,
                max_players = EXCLUDED.max_players,
                turn_timeout_seconds = EXCLUDED.turn_timeout_seconds,
                first_trump = EXCLUDED.first_trump,
                trump_cycle = EXCLUDED.trump_cycle,
                round_schedule = EXCLUDED.round_schedule,
                status = EXCLUDED.status,
                room_id = EXCLUDED.room_id,
                updated_at = EXCLUDED.updated_at
            "#,
        )
        .bind(event.event_id.0)
        .bind(&event.slug)
        .bind(&event.manage_token_hash)
        .bind(&event.host_nickname)
        .bind(event.host_session_id.map(|s| s.0))
        .bind(&event.title)
        .bind(event.starts_at)
        .bind(&event.timezone)
        .bind(event.duration_minutes as i16)
        .bind(event.max_players as i16)
        .bind(event.turn_timeout_seconds.map(|t| t as i16))
        .bind(event.first_trump.map(suit_to_db))
        .bind(serde_json::to_value(&event.trump_cycle)?)
        .bind(serde_json::to_value(&event.round_schedule)?)
        .bind(&event.status)
        .bind(event.room_id.map(|r| r.0))
        .bind(event.created_at)
        .bind(event.updated_at)
        .execute(&mut *tx)
        .await?;

        sqlx::query("DELETE FROM scheduled_event_rsvps WHERE event_id = $1")
            .bind(event.event_id.0)
            .execute(&mut *tx)
            .await?;

        for rsvp in &event.rsvps {
            sqlx::query(
                r#"
                INSERT INTO scheduled_event_rsvps (
                    rsvp_id, event_id, display_name, mobile_e164, status,
                    manage_token_hash, contact_consent, created_at
                ) VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
                "#,
            )
            .bind(rsvp.rsvp_id.0)
            .bind(event.event_id.0)
            .bind(&rsvp.display_name)
            .bind(&rsvp.mobile_e164)
            .bind(&rsvp.status)
            .bind(&rsvp.manage_token_hash)
            .bind(rsvp.contact_consent)
            .bind(rsvp.created_at)
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;
        Ok(())
    }

    async fn load_scheduled_events(&self) -> Result<Vec<StoredScheduledEvent>, PersistError> {
        let rows = sqlx::query(
            r#"
            SELECT event_id, slug, manage_token_hash, host_nickname, host_session_id,
                   title, starts_at, timezone, duration_minutes, max_players,
                   turn_timeout_seconds, first_trump, trump_cycle, round_schedule,
                   status, room_id, created_at, updated_at
            FROM scheduled_events
            "#,
        )
        .fetch_all(&self.pool)
        .await?;

        let mut events = Vec::new();
        for row in rows {
            let event_id: Uuid = row.get("event_id");
            let rsvps = sqlx::query(
                r#"
                SELECT rsvp_id, display_name, mobile_e164, status, manage_token_hash,
                       contact_consent, created_at
                FROM scheduled_event_rsvps WHERE event_id = $1 ORDER BY created_at
                "#,
            )
            .bind(event_id)
            .fetch_all(&self.pool)
            .await?
            .into_iter()
            .map(|r| StoredEventRsvp {
                rsvp_id: RsvpId(r.get("rsvp_id")),
                display_name: r.get("display_name"),
                mobile_e164: r.get("mobile_e164"),
                status: r.get("status"),
                manage_token_hash: r.get("manage_token_hash"),
                contact_consent: r.get("contact_consent"),
                created_at: r.get("created_at"),
            })
            .collect();

            let first_trump: Option<String> = row.get("first_trump");
            let cycle_value: Option<serde_json::Value> = row.get("trump_cycle");
            let trump_cycle = cycle_value.and_then(|v| {
                if v.is_null() {
                    None
                } else {
                    serde_json::from_value(v).ok()
                }
            });
            let schedule_value: serde_json::Value = row.get("round_schedule");
            events.push(StoredScheduledEvent {
                event_id: EventId(event_id),
                slug: row.get("slug"),
                manage_token_hash: row.get("manage_token_hash"),
                host_nickname: row.get("host_nickname"),
                host_session_id: row.get::<Option<Uuid>, _>("host_session_id").map(SessionId),
                title: row.get("title"),
                starts_at: row.get("starts_at"),
                timezone: row.get("timezone"),
                duration_minutes: row.get::<i16, _>("duration_minutes") as u16,
                max_players: row.get::<i16, _>("max_players") as u8,
                turn_timeout_seconds: row
                    .get::<Option<i16>, _>("turn_timeout_seconds")
                    .map(|t| t as u16),
                first_trump: first_trump.as_deref().and_then(suit_from_db),
                trump_cycle,
                round_schedule: serde_json::from_value(schedule_value).unwrap_or_default(),
                status: row.get("status"),
                room_id: row.get::<Option<Uuid>, _>("room_id").map(RoomId),
                rsvps,
                created_at: row.get("created_at"),
                updated_at: row.get("updated_at"),
            });
        }
        Ok(events)
    }

    async fn remap_game_player_session(
        &self,
        game_id: GameId,
        player_id: PlayerId,
        new_session_id: SessionId,
        nickname: &str,
        user_id: Option<Uuid>,
    ) -> Result<(), PersistError> {
        let mut tx = self.pool.begin().await?;
        sqlx::query(
            r#"
            UPDATE game_players
            SET session_id = $3, nickname = $4, user_id = $5
            WHERE game_id = $1 AND player_id = $2
            "#,
        )
        .bind(game_id.0)
        .bind(player_id.0)
        .bind(new_session_id.0)
        .bind(nickname)
        .bind(user_id)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(())
    }

    async fn abort_game(&self, game_id: GameId) -> Result<(), PersistError> {
        let result = sqlx::query(
            r#"
            UPDATE games
            SET status = 'aborted', finished_at = now()
            WHERE game_id = $1 AND status = 'active'
            "#,
        )
        .bind(game_id.0)
        .execute(&self.pool)
        .await?;
        if result.rows_affected() == 0 {
            return Err(PersistError::NotFound(format!("active game {game_id}")));
        }
        Ok(())
    }

    async fn compact_finished_game(&self, game_id: GameId) -> Result<(), PersistError> {
        let mut tx = self.pool.begin().await?;
        let latest: Option<(i64,)> = sqlx::query_as(
            r#"
            SELECT COALESCE(MAX(state_version), 0) FROM game_snapshots WHERE game_id = $1
            "#,
        )
        .bind(game_id.0)
        .fetch_optional(&mut *tx)
        .await?;
        let latest_version = latest.map(|r| r.0).unwrap_or(0);
        sqlx::query("DELETE FROM game_events WHERE game_id = $1")
            .bind(game_id.0)
            .execute(&mut *tx)
            .await?;
        sqlx::query(
            r#"
            DELETE FROM game_snapshots
            WHERE game_id = $1 AND state_version <> $2
            "#,
        )
        .bind(game_id.0)
        .bind(latest_version)
        .execute(&mut *tx)
        .await?;
        tx.commit().await?;
        Ok(())
    }

    async fn delete_game(&self, game_id: GameId) -> Result<(), PersistError> {
        sqlx::query("DELETE FROM games WHERE game_id = $1")
            .bind(game_id.0)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn list_terminal_games_older_than(
        &self,
        older_than: chrono::DateTime<chrono::Utc>,
    ) -> Result<Vec<(GameId, RoomId)>, PersistError> {
        let rows = sqlx::query(
            r#"
            SELECT game_id, room_id FROM games
            WHERE status IN ('finished', 'aborted')
              AND finished_at IS NOT NULL
              AND finished_at < $1
            "#,
        )
        .bind(older_than)
        .fetch_all(&self.pool)
        .await?;
        Ok(rows
            .into_iter()
            .map(|r| (GameId(r.get("game_id")), RoomId(r.get("room_id"))))
            .collect())
    }

    async fn delete_orphan_sessions(
        &self,
        older_than: chrono::DateTime<chrono::Utc>,
    ) -> Result<u64, PersistError> {
        let result = sqlx::query(
            r#"
            DELETE FROM guest_sessions gs
            WHERE gs.created_at < $1
              AND NOT EXISTS (
                  SELECT 1 FROM room_players rp WHERE rp.session_id = gs.session_id
              )
              AND NOT EXISTS (
                  SELECT 1 FROM game_players gp WHERE gp.session_id = gs.session_id
              )
              AND NOT EXISTS (
                  SELECT 1 FROM rooms r WHERE r.host_session_id = gs.session_id
              )
              AND NOT EXISTS (
                  SELECT 1 FROM scheduled_events se WHERE se.host_session_id = gs.session_id
              )
            "#,
        )
        .bind(older_than)
        .execute(&self.pool)
        .await?;
        Ok(result.rows_affected())
    }

    async fn ping(&self) -> Result<(), PersistError> {
        sqlx::query_scalar::<_, i32>("SELECT 1")
            .fetch_one(&self.pool)
            .await
            .map_err(PersistError::from)?;
        Ok(())
    }

    async fn upsert_user(&self, user: &StoredUser) -> Result<(), PersistError> {
        sqlx::query(
            r#"
            INSERT INTO users (
                user_id, display_name, avatar_id, created_at, updated_at, last_seen_at,
                legal_accepted_at, legal_version
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
            ON CONFLICT (user_id) DO UPDATE SET
                display_name = EXCLUDED.display_name,
                avatar_id = COALESCE(EXCLUDED.avatar_id, users.avatar_id),
                updated_at = now(),
                last_seen_at = now(),
                legal_accepted_at = COALESCE(EXCLUDED.legal_accepted_at, users.legal_accepted_at),
                legal_version = COALESCE(EXCLUDED.legal_version, users.legal_version)
            "#,
        )
        .bind(user.user_id)
        .bind(&user.display_name)
        .bind(&user.avatar_id)
        .bind(user.created_at)
        .bind(user.updated_at)
        .bind(user.last_seen_at)
        .bind(user.legal_version.as_ref().map(|_| user.last_seen_at))
        .bind(&user.legal_version)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    async fn upsert_identity(&self, identity: &StoredIdentity) -> Result<(), PersistError> {
        sqlx::query(
            r#"
            INSERT INTO user_identities (user_id, provider, subject, email)
            VALUES ($1, $2, $3, $4)
            ON CONFLICT (provider, subject) DO UPDATE SET
                email = COALESCE(EXCLUDED.email, user_identities.email)
            "#,
        )
        .bind(identity.user_id)
        .bind(&identity.provider)
        .bind(&identity.subject)
        .bind(&identity.email)
        .execute(&self.pool)
        .await?;
        Ok(())
    }

    async fn find_user_by_identity(
        &self,
        provider: &str,
        subject: &str,
    ) -> Result<Option<StoredUser>, PersistError> {
        let row = sqlx::query(
            r#"
            SELECT u.user_id, u.display_name, u.avatar_id, u.legal_version,
                   u.created_at, u.updated_at, u.last_seen_at
            FROM users u
            JOIN user_identities i ON i.user_id = u.user_id
            WHERE i.provider = $1 AND i.subject = $2
            "#,
        )
        .bind(provider)
        .bind(subject)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(user_from_row))
    }

    async fn load_user(&self, user_id: Uuid) -> Result<Option<StoredUser>, PersistError> {
        let row = sqlx::query(
            r#"
            SELECT user_id, display_name, avatar_id, legal_version,
                   created_at, updated_at, last_seen_at
            FROM users WHERE user_id = $1
            "#,
        )
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await?;
        Ok(row.map(user_from_row))
    }

    async fn delete_user(&self, user_id: Uuid) -> Result<(), PersistError> {
        sqlx::query("DELETE FROM users WHERE user_id = $1")
            .bind(user_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn set_user_avatar(&self, user_id: Uuid, avatar_id: &str) -> Result<(), PersistError> {
        sqlx::query("UPDATE users SET avatar_id = $2, updated_at = now() WHERE user_id = $1")
            .bind(user_id)
            .bind(avatar_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }

    async fn load_leaderboard(&self, limit: i64) -> Result<Vec<LeaderboardRow>, PersistError> {
        let rows = sqlx::query(
            r#"
            SELECT u.user_id, u.display_name, u.avatar_id,
                   s.ranked_wins, s.ranked_games, s.ranked_points,
                   s.ranked_rounds, s.ranked_exact
            FROM user_stats s
            JOIN users u ON u.user_id = s.user_id
            WHERE s.ranked_games > 0
            ORDER BY s.ranked_wins DESC,
                     COALESCE(s.ranked_wins::bigint * 1000000 / NULLIF(s.ranked_games, 0), 0) DESC,
                     COALESCE(s.ranked_exact::bigint * 1000000 / NULLIF(s.ranked_rounds, 0), 0) DESC,
                     COALESCE(s.ranked_points / NULLIF(s.ranked_games, 0), 0) DESC
            LIMIT $1
            "#,
        )
        .bind(if limit > 0 { limit } else { i64::MAX })
        .fetch_all(&self.pool)
        .await?;
        Ok(rows
            .into_iter()
            .map(|row| {
                let games: i32 = row.get("ranked_games");
                let exact: i32 = row.get("ranked_exact");
                let rounds: i32 = row.get("ranked_rounds");
                let points: i64 = row.get("ranked_points");
                LeaderboardRow {
                    user_id: row.get("user_id"),
                    display_name: row.get("display_name"),
                    avatar_id: row.get("avatar_id"),
                    wins: row.get("ranked_wins"),
                    games,
                    exact_percent: crate::stats::exact_percent(exact, rounds),
                    average_score: crate::stats::average_score(points, games),
                }
            })
            .collect())
    }

    async fn load_match_pulse(&self) -> Result<MatchPulse, PersistError> {
        let (today, week, last_week) = crate::stats::india_bounds(Utc::now());
        let mut tx = self.pool.begin().await?;
        // Timeout dies with this transaction, so the pooled connection stays usable.
        sqlx::query("SET LOCAL statement_timeout = '2s'")
            .execute(&mut *tx)
            .await?;
        let row = sqlx::query(
            r#"
            WITH counted AS (
                SELECT game_id, user_id, finished_at, finish_rank,
                       exact_bid_rounds, rounds_played, total_score
                FROM user_game_results
                WHERE counted
            ),
            bounds AS (
                SELECT
                    COUNT(DISTINCT game_id) AS games_all,
                    COUNT(DISTINCT game_id) FILTER (WHERE finished_at >= $1) AS games_today,
                    COUNT(DISTINCT game_id) FILTER (WHERE finished_at >= $2) AS games_week,
                    COUNT(DISTINCT game_id) FILTER (
                        WHERE finished_at >= $3 AND finished_at < $2
                    ) AS games_last_week,
                    COUNT(DISTINCT user_id) FILTER (WHERE finished_at >= $2) AS players_week,
                    MIN(finished_at) AS since
                FROM counted
            ),
            week_user AS (
                SELECT user_id,
                       COUNT(DISTINCT game_id)::int AS games,
                       COUNT(DISTINCT game_id) FILTER (WHERE finish_rank = 1)::int AS wins,
                       COALESCE(SUM(exact_bid_rounds), 0)::int AS exact,
                       COALESCE(SUM(rounds_played), 0)::int AS rounds,
                       COALESCE(SUM(total_score), 0)::bigint AS points
                FROM counted
                WHERE finished_at >= $2
                GROUP BY user_id
            ),
            leader AS (
                SELECT u.display_name, w.wins
                FROM week_user w
                JOIN users u ON u.user_id = w.user_id
                WHERE w.wins > 0
                ORDER BY w.wins DESC,
                         COALESCE(w.wins::bigint * 1000000 / NULLIF(w.games, 0), 0) DESC,
                         COALESCE(w.exact::bigint * 1000000 / NULLIF(w.rounds, 0), 0) DESC,
                         COALESCE(w.points / NULLIF(w.games, 0), 0) DESC
                LIMIT 1
            ),
            last_user AS (
                SELECT user_id,
                       COUNT(DISTINCT game_id)::int AS games,
                       COUNT(DISTINCT game_id) FILTER (WHERE finish_rank = 1)::int AS wins,
                       COALESCE(SUM(exact_bid_rounds), 0)::int AS exact,
                       COALESCE(SUM(rounds_played), 0)::int AS rounds,
                       COALESCE(SUM(total_score), 0)::bigint AS points
                FROM counted
                WHERE finished_at >= $3 AND finished_at < $2
                GROUP BY user_id
            ),
            last_leader AS (
                SELECT u.display_name, w.wins
                FROM last_user w
                JOIN users u ON u.user_id = w.user_id
                WHERE w.wins > 0
                ORDER BY w.wins DESC,
                         COALESCE(w.wins::bigint * 1000000 / NULLIF(w.games, 0), 0) DESC,
                         COALESCE(w.exact::bigint * 1000000 / NULLIF(w.rounds, 0), 0) DESC,
                         COALESCE(w.points / NULLIF(w.games, 0), 0) DESC
                LIMIT 1
            )
            SELECT b.games_all, b.games_today, b.games_week, b.games_last_week,
                   b.players_week, b.since,
                   l.display_name AS week_leader_name,
                   l.wins AS week_leader_wins,
                   ll.display_name AS last_week_leader_name,
                   ll.wins AS last_week_leader_wins
            FROM bounds b
            LEFT JOIN leader l ON true
            LEFT JOIN last_leader ll ON true
            "#,
        )
        .bind(today)
        .bind(week)
        .bind(last_week)
        .fetch_one(&mut *tx)
        .await?;
        tx.commit().await?;
        let wins: Option<i32> = row.get("week_leader_wins");
        let last_wins: Option<i32> = row.get("last_week_leader_wins");
        Ok(MatchPulse {
            games_all: row.get("games_all"),
            games_today: row.get("games_today"),
            games_week: row.get("games_week"),
            games_last_week: row.get("games_last_week"),
            players_week: row.get("players_week"),
            since: row.get("since"),
            week_leader_name: row.get("week_leader_name"),
            week_leader_wins: i64::from(wins.unwrap_or(0)),
            last_week_leader_name: row.get("last_week_leader_name"),
            last_week_leader_wins: i64::from(last_wins.unwrap_or(0)),
        })
    }

    async fn load_user_stats(&self, user_id: Uuid) -> Result<Option<UserStatsView>, PersistError> {
        let user = match self.load_user(user_id).await? {
            Some(user) => user,
            None => return Ok(None),
        };
        let row = sqlx::query(
            r#"
            SELECT games_played, wins, lifetime_points, rounds_played, exact_bid_rounds,
                   ranked_games, ranked_wins, ranked_points, ranked_rounds, ranked_exact
            FROM user_stats WHERE user_id = $1
            "#,
        )
        .bind(user_id)
        .fetch_optional(&self.pool)
        .await?;
        let (
            games,
            wins,
            points,
            rounds,
            exact,
            ranked_games,
            ranked_wins,
            ranked_points,
            ranked_rounds,
            ranked_exact,
        ) = if let Some(row) = row {
            (
                row.get::<i32, _>("games_played"),
                row.get::<i32, _>("wins"),
                row.get::<i64, _>("lifetime_points"),
                row.get::<i32, _>("rounds_played"),
                row.get::<i32, _>("exact_bid_rounds"),
                row.get::<i32, _>("ranked_games"),
                row.get::<i32, _>("ranked_wins"),
                row.get::<i64, _>("ranked_points"),
                row.get::<i32, _>("ranked_rounds"),
                row.get::<i32, _>("ranked_exact"),
            )
        } else {
            (0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
        };
        let rank = if ranked_games == 0 {
            None
        } else {
            let win_rate = if ranked_games == 0 {
                0
            } else {
                i64::from(ranked_wins) * 1_000_000 / i64::from(ranked_games)
            };
            let strike = if ranked_rounds == 0 {
                0
            } else {
                i64::from(ranked_exact) * 1_000_000 / i64::from(ranked_rounds)
            };
            let average = if ranked_games == 0 {
                0
            } else {
                ranked_points / i64::from(ranked_games)
            };
            let better: i64 = sqlx::query_scalar(
                r#"
                SELECT COUNT(*) FROM user_stats s
                WHERE s.ranked_games > 0
                  AND s.user_id <> $1
                  AND (
                    s.ranked_wins > $2
                    OR (
                      s.ranked_wins = $2
                      AND COALESCE(s.ranked_wins::bigint * 1000000 / NULLIF(s.ranked_games, 0), 0) > $3
                    )
                    OR (
                      s.ranked_wins = $2
                      AND COALESCE(s.ranked_wins::bigint * 1000000 / NULLIF(s.ranked_games, 0), 0) = $3
                      AND COALESCE(s.ranked_exact::bigint * 1000000 / NULLIF(s.ranked_rounds, 0), 0) > $4
                    )
                    OR (
                      s.ranked_wins = $2
                      AND COALESCE(s.ranked_wins::bigint * 1000000 / NULLIF(s.ranked_games, 0), 0) = $3
                      AND COALESCE(s.ranked_exact::bigint * 1000000 / NULLIF(s.ranked_rounds, 0), 0) = $4
                      AND COALESCE(s.ranked_points / NULLIF(s.ranked_games, 0), 0) > $5
                    )
                  )
                "#,
            )
            .bind(user_id)
            .bind(ranked_wins)
            .bind(win_rate)
            .bind(strike)
            .bind(average)
            .fetch_one(&self.pool)
            .await?;
            Some(better as i32 + 1)
        };
        Ok(Some(UserStatsView {
            user_id,
            display_name: user.display_name,
            avatar_id: user.avatar_id,
            games_played: games,
            wins,
            lifetime_points: points,
            rounds_played: rounds,
            exact_bid_rounds: exact,
            ranked_games,
            rank,
        }))
    }
}

fn user_from_row(row: sqlx::postgres::PgRow) -> StoredUser {
    StoredUser {
        user_id: row.get("user_id"),
        display_name: row.get("display_name"),
        avatar_id: row.get("avatar_id"),
        legal_version: row.get("legal_version"),
        created_at: row.get("created_at"),
        updated_at: row.get("updated_at"),
        last_seen_at: row.get("last_seen_at"),
    }
}

async fn record_user_stats(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    commit: &CommandCommit,
    result: &GameResultRecord,
) -> Result<(), PersistError> {
    use crate::stats::SeatFinish;
    use std::collections::HashMap;

    let seats = sqlx::query(
        "SELECT player_id, user_id FROM game_players WHERE game_id = $1 AND user_id IS NOT NULL",
    )
    .bind(commit.game_id.0)
    .fetch_all(&mut **tx)
    .await?;
    let mut owners: HashMap<Uuid, Uuid> = HashMap::new();
    for seat in seats {
        owners.insert(seat.get("player_id"), seat.get("user_id"));
    }

    let rounds = commit.state.score_table.rounds.len() as i32;
    let table_size = commit.state.players.len() as i16;
    let counted = commit.state.players.len() >= 3;
    let mut by_user: HashMap<Uuid, SeatFinish> = HashMap::new();
    for ranked in &result.ranking {
        let Some(user_id) = owners.get(&ranked.player_id.0).copied() else {
            continue;
        };
        let seat = SeatFinish {
            user_id,
            finish_rank: ranked.rank as i32,
            total_score: ranked.total_score,
            exact_bid_rounds: ranked.exact_bid_rounds as i32,
            tricks_missed: ranked.total_tricks_missed as i32,
        };
        match by_user.get(&user_id) {
            Some(existing) if existing.finish_rank <= seat.finish_rank => {}
            _ => {
                by_user.insert(user_id, seat);
            }
        }
    }

    for seat in by_user.values() {
        let inserted = sqlx::query(
            r#"
            INSERT INTO user_game_results (
                game_id, user_id, table_size, rounds_played, finish_rank,
                total_score, exact_bid_rounds, tricks_missed, counted
            ) VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9)
            ON CONFLICT (game_id, user_id) DO NOTHING
            RETURNING user_id
            "#,
        )
        .bind(commit.game_id.0)
        .bind(seat.user_id)
        .bind(table_size)
        .bind(rounds as i16)
        .bind(seat.finish_rank as i16)
        .bind(seat.total_score)
        .bind(seat.exact_bid_rounds as i16)
        .bind(seat.tricks_missed)
        .bind(counted)
        .fetch_optional(&mut **tx)
        .await?;
        if inserted.is_none() {
            continue;
        }
        let ranked_wins = if counted && seat.finish_rank == 1 {
            1
        } else {
            0
        };
        let wins = if seat.finish_rank == 1 { 1 } else { 0 };
        let ranked_games = if counted { 1 } else { 0 };
        let ranked_points = if counted {
            i64::from(seat.total_score)
        } else {
            0
        };
        let ranked_rounds = if counted { rounds } else { 0 };
        let ranked_exact = if counted { seat.exact_bid_rounds } else { 0 };
        sqlx::query(
            r#"
            INSERT INTO user_stats (
                user_id, games_played, wins, ranked_wins, ranked_games,
                lifetime_points, ranked_points, rounds_played, exact_bid_rounds,
                ranked_rounds, ranked_exact, updated_at
            ) VALUES ($1, 1, $2, $3, $4, $5, $6, $7, $8, $9, $10, now())
            ON CONFLICT (user_id) DO UPDATE SET
                games_played = user_stats.games_played + 1,
                wins = user_stats.wins + EXCLUDED.wins,
                ranked_wins = user_stats.ranked_wins + EXCLUDED.ranked_wins,
                ranked_games = user_stats.ranked_games + EXCLUDED.ranked_games,
                lifetime_points = user_stats.lifetime_points + EXCLUDED.lifetime_points,
                ranked_points = user_stats.ranked_points + EXCLUDED.ranked_points,
                rounds_played = user_stats.rounds_played + EXCLUDED.rounds_played,
                exact_bid_rounds = user_stats.exact_bid_rounds + EXCLUDED.exact_bid_rounds,
                ranked_rounds = user_stats.ranked_rounds + EXCLUDED.ranked_rounds,
                ranked_exact = user_stats.ranked_exact + EXCLUDED.ranked_exact,
                updated_at = now()
            "#,
        )
        .bind(seat.user_id)
        .bind(wins)
        .bind(ranked_wins)
        .bind(ranked_games)
        .bind(i64::from(seat.total_score))
        .bind(ranked_points)
        .bind(rounds)
        .bind(seat.exact_bid_rounds)
        .bind(ranked_rounds)
        .bind(ranked_exact)
        .execute(&mut **tx)
        .await?;
    }
    Ok(())
}
