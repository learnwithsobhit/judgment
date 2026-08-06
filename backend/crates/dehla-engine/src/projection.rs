//! Personalized views — never leak other hands.

use dehla_domain::{Card, GameId, PlayerId, Suit, TeamId};
use serde::{Deserialize, Serialize};

use crate::{one_away_seat, playable_cards, GameState, Phase, TrickPlay};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct OpponentView {
    pub player_id: PlayerId,
    pub nickname: String,
    pub seat: u8,
    pub team: TeamId,
    pub card_count: u8,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub avatar_id: Option<String>,
    #[serde(default)]
    pub vacant: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct LegalActions {
    pub playable_cards: Vec<Card>,
    pub can_announce_trump: bool,
    #[serde(default)]
    pub can_start_next_hand: bool,
    #[serde(default)]
    pub can_rematch: bool,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct PlayerGameView {
    pub game_id: GameId,
    pub state_version: u64,
    pub phase: Phase,
    pub own_hand: Vec<Card>,
    pub own_seat: u8,
    pub own_team: TeamId,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub own_avatar_id: Option<String>,
    pub opponents: Vec<OpponentView>,
    pub current_trick: Vec<TrickPlay>,
    pub trump: Option<Suit>,
    pub centre_pile_count: u8,
    pub last_trick_winner_seat: Option<u8>,
    /// Seat that is one consecutive win from capturing the pile.
    pub one_away_seat: Option<u8>,
    pub turn_seat: Option<u8>,
    pub dealer_seat: u8,
    pub kots_a: u8,
    pub kots_b: u8,
    pub tens_captured_a: u8,
    pub tens_captured_b: u8,
    pub hand_winner: Option<TeamId>,
    pub match_winner: Option<TeamId>,
    pub legal_actions: LegalActions,
    pub tricks_played: u8,
    /// Table paused while a seat is vacant (ADR 0004).
    #[serde(default)]
    pub paused: bool,
}

/// Optional presence overlay from the actor (not part of pure engine state).
#[derive(Debug, Clone, Default)]
pub struct PresenceOverlay {
    pub vacant_seats: Vec<u8>,
    pub paused: bool,
}

pub fn project(state: &GameState, viewer: PlayerId) -> Option<PlayerGameView> {
    project_with_presence(state, viewer, &PresenceOverlay::default())
}

pub fn project_with_presence(
    state: &GameState,
    viewer: PlayerId,
    presence: &PresenceOverlay,
) -> Option<PlayerGameView> {
    let own = state.players.iter().find(|p| p.player_id == viewer)?;
    let own_seat = own.seat;
    let own_team = dehla_domain::team_for_seat(own_seat);

    let opponents = state
        .players
        .iter()
        .filter(|p| p.player_id != viewer)
        .map(|p| OpponentView {
            player_id: p.player_id,
            nickname: p.nickname.clone(),
            seat: p.seat,
            team: dehla_domain::team_for_seat(p.seat),
            card_count: state.hands[p.seat as usize].len() as u8,
            avatar_id: p.avatar_id.clone(),
            vacant: presence.vacant_seats.contains(&p.seat),
        })
        .collect();

    let can_announce =
        state.phase == Phase::AnnounceTrump && state.lead_seat == own_seat && !presence.paused;

    let turn = if presence.paused {
        None
    } else {
        match state.phase {
            Phase::HandComplete | Phase::MatchComplete => None,
            Phase::AnnounceTrump => Some(state.lead_seat),
            _ => Some(state.turn_seat),
        }
    };

    Some(PlayerGameView {
        game_id: state.game_id,
        state_version: state.state_version,
        phase: state.phase.clone(),
        own_hand: state.hands[own_seat as usize].clone(),
        own_seat,
        own_team,
        own_avatar_id: own.avatar_id.clone(),
        opponents,
        current_trick: state.current_trick.clone(),
        trump: state.trump,
        centre_pile_count: state.centre_pile.len() as u8,
        last_trick_winner_seat: state.last_trick_winner,
        one_away_seat: one_away_seat(state),
        turn_seat: turn,
        dealer_seat: state.dealer_seat,
        kots_a: state.kots_a,
        kots_b: state.kots_b,
        tens_captured_a: state.captured_a.iter().filter(|c| c.is_ten()).count() as u8,
        tens_captured_b: state.captured_b.iter().filter(|c| c.is_ten()).count() as u8,
        hand_winner: state.hand_winner,
        match_winner: state.match_winner,
        legal_actions: LegalActions {
            playable_cards: if presence.paused {
                vec![]
            } else {
                playable_cards(state, own_seat)
            },
            can_announce_trump: can_announce,
            can_start_next_hand: state.phase == Phase::HandComplete && !presence.paused,
            can_rematch: state.phase == Phase::MatchComplete && !presence.paused,
        },
        tricks_played: state.tricks_played,
        paused: presence.paused,
    })
}
