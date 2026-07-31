//! Personalised player projections (PLAN.md §8).
//!
//! Clients only ever see a `PlayerGameView`. Opponent hands, the undealt deck
//! order, and the shuffle seed are never included.

use serde::{Deserialize, Serialize};

use judgement_domain::{Card, CardId, ConnectionStatus, GameId, PlayerId, RankedPlayer, Suit};

use crate::state::{GamePhase, InternalGameState, PlayedCard};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct OpponentView {
    pub player_id: PlayerId,
    pub nickname: String,
    pub seat: u8,
    pub card_count: usize,
    pub bid: Option<u8>,
    pub tricks_won: u8,
    pub connection_status: ConnectionStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub avatar_id: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct PublicBid {
    pub player_id: PlayerId,
    pub bid: u8,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlayerScore {
    pub player_id: PlayerId,
    pub total_score: i32,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct PublicRoundState {
    pub round_index: usize,
    pub total_rounds: usize,
    pub cards_per_player: u8,
    pub dealer: PlayerId,
    pub tricks_completed: u32,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct LegalActionView {
    /// Bids the viewing player may place right now (empty when not bidding
    /// or not their turn).
    pub legal_bids: Vec<u8>,
    /// Cards the viewing player may play right now (empty when not playing
    /// or not their turn).
    pub playable_cards: Vec<CardId>,
}

/// Last fully-played trick, kept until the next lead so clients can show it.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CompletedTrickView {
    pub trick_index: u32,
    pub winner_id: PlayerId,
    pub plays: Vec<PlayedCard>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct RoundScoreLine {
    pub player_id: PlayerId,
    pub bid: u8,
    pub tricks_won: u8,
    pub score: i32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RoundScoreView {
    pub round_index: usize,
    pub entries: Vec<RoundScoreLine>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct LeaderView {
    pub player_id: PlayerId,
    /// Points ahead of second place (0 if tied for lead).
    pub margin: i32,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlayerGameView {
    pub game_id: GameId,
    pub state_version: u64,
    pub phase: GamePhase,
    pub own_hand: Vec<Card>,
    /// The viewer's table seat. Authoritative — with 3–8 player rooms seat
    /// numbers can be non-contiguous, so clients must not infer this
    /// (ADR 0003).
    pub own_seat: u8,
    pub own_bid: Option<u8>,
    pub own_tricks_won: u8,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub own_avatar_id: Option<String>,
    pub opponents: Vec<OpponentView>,
    pub current_trick: Vec<PlayedCard>,
    /// Present after a trick completes until the next card is led.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub last_completed_trick: Option<CompletedTrickView>,
    pub trump: Option<Suit>,
    pub trump_card: Option<Card>,
    pub current_turn: Option<PlayerId>,
    pub bids: Vec<PublicBid>,
    pub scores: Vec<PlayerScore>,
    /// Completed rounds with per-player points (for surprise scoreboard UX).
    #[serde(default)]
    pub round_history: Vec<RoundScoreView>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub leader: Option<LeaderView>,
    pub round: Option<PublicRoundState>,
    pub legal_actions: LegalActionView,
    /// Present only once the game is finished: the final ranking with the
    /// locked tie-break fields (score, exact-bid rounds, tricks missed).
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub final_ranking: Option<Vec<RankedPlayer>>,
}

/// Build the personalised view for `player_id` from authoritative state.
pub(crate) fn project_for(
    state: &InternalGameState,
    player_id: PlayerId,
    legal_bids: Vec<u8>,
    playable_cards: Vec<CardId>,
) -> PlayerGameView {
    let round = state.current_round.as_ref();
    let total_rounds = state.rules.round_pattern.rounds().len();

    let mut own_hand: Vec<Card> = round
        .and_then(|r| r.hands.get(&player_id))
        .cloned()
        .unwrap_or_default();
    own_hand.sort();

    let own_player = state
        .players
        .iter()
        .find(|p| p.id == player_id)
        .expect("projection is only built for seated players");
    let own_seat = own_player.seat;

    let own_bid = round.and_then(|r| r.bids.get(&player_id)).copied();
    let own_tricks_won = round
        .and_then(|r| r.tricks_won.get(&player_id))
        .copied()
        .unwrap_or(0);

    let opponents = state
        .players
        .iter()
        .filter(|p| p.id != player_id)
        .map(|p| OpponentView {
            player_id: p.id,
            nickname: p.nickname.clone(),
            seat: p.seat,
            card_count: round.and_then(|r| r.hands.get(&p.id)).map_or(0, Vec::len),
            bid: round.and_then(|r| r.bids.get(&p.id)).copied(),
            tricks_won: round.and_then(|r| r.tricks_won.get(&p.id)).copied().unwrap_or(0),
            connection_status: p.connection_status,
            avatar_id: p.avatar_id.clone(),
        })
        .collect();

    // Bids in bidding order, only those already placed (visible immediately).
    let bids = round
        .map(|r| {
            r.bidding_order
                .iter()
                .filter_map(|&p| r.bids.get(&p).map(|&bid| PublicBid { player_id: p, bid }))
                .collect()
        })
        .unwrap_or_default();

    let scores: Vec<PlayerScore> = state
        .players
        .iter()
        .map(|p| PlayerScore {
            player_id: p.id,
            total_score: state.score_table.total_score(p.id),
        })
        .collect();

    let round_history = project_round_history(state);
    let leader = project_leader(&scores);

    let current_trick = round.map(|r| r.current_trick.clone()).unwrap_or_default();
    let last_completed_trick = round.and_then(|r| {
        if !current_trick.is_empty() {
            return None;
        }
        r.completed_tricks.last().map(|t| CompletedTrickView {
            trick_index: t.trick_index,
            winner_id: t.winner,
            plays: t.plays.clone(),
        })
    });

    let final_ranking = (state.phase == GamePhase::Finished)
        .then(|| state.score_table.final_ranking(&state.player_ids()));

    PlayerGameView {
        game_id: state.game_id,
        state_version: state.version,
        phase: state.phase,
        own_hand,
        own_seat,
        own_bid,
        own_tricks_won,
        own_avatar_id: own_player.avatar_id.clone(),
        opponents,
        current_trick,
        last_completed_trick,
        trump: state.trump_suit(),
        trump_card: state.trump_card,
        current_turn: round.map(|r| r.current_turn),
        bids,
        scores,
        round_history,
        leader,
        round: round.map(|r| PublicRoundState {
            round_index: r.round_index,
            total_rounds,
            cards_per_player: r.cards_per_player,
            dealer: state.dealer,
            tricks_completed: r.completed_tricks.len() as u32,
        }),
        legal_actions: LegalActionView {
            legal_bids,
            playable_cards,
        },
        final_ranking,
    }
}

fn project_round_history(state: &InternalGameState) -> Vec<RoundScoreView> {
    state
        .score_table
        .rounds
        .iter()
        .enumerate()
        .map(|(round_index, map)| RoundScoreView {
            round_index,
            entries: state
                .players
                .iter()
                .filter_map(|p| {
                    map.get(&p.id).map(|e| RoundScoreLine {
                        player_id: p.id,
                        bid: e.bid,
                        tricks_won: e.tricks_won,
                        score: e.score,
                    })
                })
                .collect(),
        })
        .collect()
}

fn project_leader(scores: &[PlayerScore]) -> Option<LeaderView> {
    if scores.is_empty() {
        return None;
    }
    let mut sorted = scores.to_vec();
    sorted.sort_by(|a, b| b.total_score.cmp(&a.total_score));
    let best = sorted[0];
    let second = sorted.get(1).map(|s| s.total_score).unwrap_or(best.total_score);
    Some(LeaderView {
        player_id: best.player_id,
        margin: best.total_score - second,
    })
}
