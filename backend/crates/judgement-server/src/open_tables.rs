//! Waiting tables for Join room. A projection of rooms already in memory.
//!
//! The rooms lock is never held while the session lock is taken. Callers copy
//! a snapshot, release the rooms lock, then mark which seats are signed in.

use std::collections::HashSet;

use chrono::{DateTime, Utc};
use judgement_domain::{RoomId, SessionId};
use judgement_protocol::OpenTable;

use crate::state::{Room, RoomStatus};

#[derive(Clone)]
pub struct SeatSnap {
    pub session_id: SessionId,
    pub nickname: String,
    pub avatar_id: Option<String>,
    pub signed_in: bool,
}

#[derive(Clone)]
pub struct RoomSnap {
    pub id: RoomId,
    pub host_session: SessionId,
    pub listed: bool,
    pub in_game: bool,
    pub max_players: u8,
    pub seats: Vec<SeatSnap>,
    pub opened_at: DateTime<Utc>,
}

impl RoomSnap {
    pub fn from_room(room: &Room) -> Self {
        let opened_at = room
            .seats
            .iter()
            .map(|seat| seat.joined_at)
            .min()
            .unwrap_or_else(Utc::now);
        Self {
            id: room.id,
            host_session: room.host_session,
            listed: room.listed,
            in_game: matches!(room.status, RoomStatus::InGame(_)),
            max_players: room.max_players,
            seats: room
                .seats
                .iter()
                .map(|seat| SeatSnap {
                    session_id: seat.session_id,
                    nickname: seat.nickname.clone(),
                    avatar_id: seat.avatar_id.clone(),
                    signed_in: false,
                })
                .collect(),
            opened_at,
        }
    }
}

pub fn mark_signed_in(rooms: &mut [RoomSnap], signed_in: &HashSet<SessionId>) {
    for room in rooms {
        for seat in &mut room.seats {
            seat.signed_in = signed_in.contains(&seat.session_id);
        }
    }
}

/// Tables a signed-in player may see. `mine` is every session of that account.
pub fn visible_tables(rooms: &[RoomSnap], mine: &HashSet<SessionId>) -> Vec<OpenTable> {
    let mut tables: Vec<(bool, DateTime<Utc>, OpenTable)> = rooms
        .iter()
        .filter_map(|room| row_for(room, mine).map(|row| (row.yours, room.opened_at, row)))
        .collect();
    tables.sort_by(|a, b| b.0.cmp(&a.0).then(b.1.cmp(&a.1)));
    tables.into_iter().map(|(_, _, row)| row).collect()
}

fn row_for(room: &RoomSnap, mine: &HashSet<SessionId>) -> Option<OpenTable> {
    let seated = room.seats.len();
    if seated == 0 {
        return None;
    }
    let yours = room
        .seats
        .iter()
        .any(|seat| mine.contains(&seat.session_id));
    let signed_in = room.seats.iter().any(|seat| seat.signed_in);
    let full = seated >= usize::from(room.max_players);
    if !yours && (!room.listed || room.in_game || !signed_in || full) {
        return None;
    }
    let label = label_seat(room)?;
    let with_names = room
        .seats
        .iter()
        .filter(|seat| seat.session_id != label.session_id)
        .take(2)
        .map(|seat| seat.nickname.clone())
        .collect();
    Some(OpenTable {
        room_id: room.id,
        host_nickname: label.nickname.clone(),
        host_avatar_id: label.avatar_id.clone(),
        seated: seated as u8,
        max_players: room.max_players,
        seats_open: room.max_players.saturating_sub(seated as u8),
        with_names,
        yours,
        in_game: room.in_game,
    })
}

/// Host when they are signed in and sitting. Otherwise the first signed-in
/// player, which covers "I'm not playing" and a guest host beside a friend.
fn label_seat(room: &RoomSnap) -> Option<&SeatSnap> {
    let host = room
        .seats
        .iter()
        .find(|seat| seat.session_id == room.host_session);
    if host.is_some_and(|seat| seat.signed_in) {
        return host;
    }
    room.seats.iter().find(|seat| seat.signed_in).or(host)
}

#[cfg(test)]
mod tests {
    use super::*;
    use judgement_domain::SessionId;

    fn seat(id: u8, name: &str, signed_in: bool) -> SeatSnap {
        SeatSnap {
            session_id: SessionId(uuid::Uuid::from_u128(id as u128)),
            nickname: name.into(),
            avatar_id: None,
            signed_in,
        }
    }

    fn room(seats: Vec<SeatSnap>, max: u8, listed: bool, in_game: bool) -> RoomSnap {
        let host = seats
            .first()
            .map(|s| s.session_id)
            .unwrap_or(SessionId(uuid::Uuid::nil()));
        RoomSnap {
            id: RoomId::new(),
            host_session: host,
            listed,
            in_game,
            max_players: max,
            seats,
            opened_at: Utc::now(),
        }
    }

    #[test]
    fn a_waiting_signed_in_table_is_listed_without_a_code() {
        let table = room(
            vec![seat(1, "Upavan", true), seat(2, "Ankit", true)],
            6,
            true,
            false,
        );
        let rows = visible_tables(&[table], &HashSet::new());
        assert_eq!(rows.len(), 1);
        assert_eq!(rows[0].host_nickname, "Upavan");
        assert_eq!(rows[0].seated, 2);
        assert_eq!(rows[0].max_players, 6);
        assert_eq!(rows[0].seats_open, 4);
        assert_eq!(rows[0].with_names, vec!["Ankit".to_string()]);
        assert!(!rows[0].yours);
    }

    #[test]
    fn guest_only_full_unlisted_and_empty_tables_stay_hidden() {
        let guest = room(vec![seat(1, "Guest", false)], 4, true, false);
        let full = room(
            vec![seat(2, "Ada", true), seat(3, "Bea", true)],
            2,
            true,
            false,
        );
        let hidden = room(vec![seat(4, "Priya", true)], 4, false, false);
        let empty = room(vec![], 4, true, false);
        let started = room(vec![seat(5, "Ada", true)], 4, true, true);
        assert!(visible_tables(&[guest, full, hidden, empty, started], &HashSet::new()).is_empty());
    }

    #[test]
    fn your_table_stays_visible_when_full_or_already_started() {
        let mine = SessionId(uuid::Uuid::from_u128(7));
        let started = RoomSnap {
            id: RoomId::new(),
            host_session: mine,
            listed: true,
            in_game: true,
            max_players: 4,
            seats: vec![SeatSnap {
                session_id: mine,
                nickname: "Ada".into(),
                avatar_id: None,
                signed_in: true,
            }],
            opened_at: Utc::now(),
        };
        let rows = visible_tables(&[started], &HashSet::from([mine]));
        assert_eq!(rows.len(), 1);
        assert!(rows[0].yours);
        assert!(rows[0].in_game);
    }

    #[test]
    fn an_unseated_host_is_named_from_the_signed_in_friend() {
        let organizer = SessionId(uuid::Uuid::from_u128(1));
        let friend = seat(2, "Ankit", true);
        let table = RoomSnap {
            id: RoomId::new(),
            host_session: organizer,
            listed: true,
            in_game: false,
            max_players: 6,
            seats: vec![friend],
            opened_at: Utc::now(),
        };
        let rows = visible_tables(&[table], &HashSet::new());
        assert_eq!(rows[0].host_nickname, "Ankit");
    }
}
