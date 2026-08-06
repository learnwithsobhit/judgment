//! Pure Dehla Pakad Classic rules engine.
//!
//! Contract: `(state, command) → Result<new state>` — no I/O or wall clock.

mod projection;

pub use projection::{
    project, project_with_presence, LegalActions, OpponentView, PlayerGameView, PresenceOverlay,
};

use dehla_domain::{
    next_seat, standard_deck, team_for_seat, Card, GameId, PartnershipMode, PlayerId, RulePack,
    Suit, TABLE_SEATS, TeamId, TensTieRule, TrumpMethod,
};
use rand::rngs::StdRng;
use rand::seq::SliceRandom;
use rand::SeedableRng;
use serde::{Deserialize, Serialize};
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum Phase {
    /// Waiting for trump announcement (AnnouncedTrump only).
    AnnounceTrump,
    /// Playing with 5-card hands; trump unset until cut.
    CutPlay,
    TrickPlay,
    HandComplete,
    MatchComplete,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameConfig {
    pub rule_pack: RulePack,
    pub trump_method: TrumpMethod,
    pub partnership_mode: PartnershipMode,
    pub tens_tie_rule: TensTieRule,
    /// First team to this many Kots wins (Quick=1, Standard=3).
    pub kots_to_win: u8,
}

impl Default for GameConfig {
    fn default() -> Self {
        Self {
            rule_pack: RulePack::DehlaPakadClassic,
            trump_method: TrumpMethod::CutTrump,
            partnership_mode: PartnershipMode::RandomOpposite,
            tens_tie_rule: TensTieRule::NonDealerWins,
            kots_to_win: 1,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct SeatPlayer {
    pub player_id: PlayerId,
    pub nickname: String,
    pub seat: u8,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub avatar_id: Option<String>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct TrickPlay {
    pub seat: u8,
    pub card: Card,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct GameState {
    pub game_id: GameId,
    pub phase: Phase,
    pub config: GameConfig,
    pub state_version: u64,
    pub players: Vec<SeatPlayer>,
    pub hands: [Vec<Card>; 4],
    pub undealt: Vec<Card>,
    pub dealer_seat: u8,
    pub trump: Option<Suit>,
    pub current_trick: Vec<TrickPlay>,
    pub lead_seat: u8,
    pub turn_seat: u8,
    /// Cards in the centre pile awaiting capture.
    pub centre_pile: Vec<Card>,
    /// Seat that won the previous trick (for double-sar).
    pub last_trick_winner: Option<u8>,
    /// Captured cards per team this hand.
    pub captured_a: Vec<Card>,
    pub captured_b: Vec<Card>,
    pub tricks_played: u8,
    pub kots_a: u8,
    pub kots_b: u8,
    pub consecutive_hands_a: u8,
    pub consecutive_hands_b: u8,
    pub hand_winner: Option<TeamId>,
    pub match_winner: Option<TeamId>,
    /// True after cut trump is set and remaining cards were dealt.
    pub remaining_dealt: bool,
}

#[derive(Debug, thiserror::Error, Clone, PartialEq, Eq)]
pub enum EngineError {
    #[error("illegal action: {0}")]
    Illegal(&'static str),
    #[error("not your turn")]
    NotYourTurn,
    #[error("card not in hand")]
    CardNotInHand,
    #[error("must follow suit")]
    MustFollowSuit,
    #[error("wrong phase")]
    WrongPhase,
    #[error("unsupported rule pack")]
    UnsupportedRulePack,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum Command {
    AnnounceTrump { suit: Suit },
    PlayCard { card: Card },
    /// Advance dealer and deal the next hand (phase must be HandComplete).
    StartNextHand,
    /// Reset Kot counters and deal a new match (phase must be MatchComplete).
    Rematch,
}

pub struct StartGame {
    pub game_id: GameId,
    pub config: GameConfig,
    pub players: Vec<SeatPlayer>,
    pub seed: u64,
}

pub fn start_game(args: StartGame) -> Result<GameState, EngineError> {
    if args.config.rule_pack != RulePack::DehlaPakadClassic {
        return Err(EngineError::UnsupportedRulePack);
    }
    if args.players.len() != TABLE_SEATS as usize {
        return Err(EngineError::Illegal("need exactly 4 players"));
    }
    let mut seats = args.players;
    seats.sort_by_key(|p| p.seat);
    for (i, p) in seats.iter().enumerate() {
        if p.seat != i as u8 {
            return Err(EngineError::Illegal("seats must be 0..3 contiguous"));
        }
    }

    let mut rng = StdRng::seed_from_u64(args.seed);
    let mut deck = standard_deck();
    deck.shuffle(&mut rng);

    let dealer_seat = (args.seed % 4) as u8;
    let lead = next_seat(dealer_seat);

    let mut hands: [Vec<Card>; 4] = [vec![], vec![], vec![], vec![]];
    // Deal 5 each
    for _ in 0..5 {
        for seat in 0..4u8 {
            hands[seat as usize].push(deck.pop().expect("deck"));
        }
    }

    let phase = match args.config.trump_method {
        TrumpMethod::AnnouncedTrump => Phase::AnnounceTrump,
        TrumpMethod::CutTrump => Phase::CutPlay,
    };

    Ok(GameState {
        game_id: args.game_id,
        phase,
        config: args.config,
        state_version: 1,
        players: seats,
        hands,
        undealt: deck,
        dealer_seat,
        trump: None,
        current_trick: vec![],
        lead_seat: lead,
        turn_seat: lead,
        centre_pile: vec![],
        last_trick_winner: None,
        captured_a: vec![],
        captured_b: vec![],
        tricks_played: 0,
        kots_a: 0,
        kots_b: 0,
        consecutive_hands_a: 0,
        consecutive_hands_b: 0,
        hand_winner: None,
        match_winner: None,
        remaining_dealt: false,
    })
}

pub fn apply(state: &GameState, actor: PlayerId, cmd: &Command) -> Result<GameState, EngineError> {
    let seat = seat_of(state, actor)?;
    let mut next = state.clone();
    match cmd {
        Command::AnnounceTrump { suit } => {
            if next.phase != Phase::AnnounceTrump {
                return Err(EngineError::WrongPhase);
            }
            if seat != next.lead_seat {
                return Err(EngineError::NotYourTurn);
            }
            next.trump = Some(*suit);
            deal_remaining(&mut next);
            next.phase = Phase::TrickPlay;
            next.state_version += 1;
            Ok(next)
        }
        Command::PlayCard { card } => play_card(&mut next, seat, *card).map(|()| {
            next.state_version += 1;
            next
        }),
        Command::StartNextHand => {
            if next.phase != Phase::HandComplete {
                return Err(EngineError::WrongPhase);
            }
            let dealer = next.dealer_seat.wrapping_add(1) % 4;
            begin_new_hand(&mut next, dealer);
            next.state_version += 1;
            Ok(next)
        }
        Command::Rematch => {
            if next.phase != Phase::MatchComplete {
                return Err(EngineError::WrongPhase);
            }
            next.kots_a = 0;
            next.kots_b = 0;
            next.consecutive_hands_a = 0;
            next.consecutive_hands_b = 0;
            next.match_winner = None;
            let dealer = next.dealer_seat.wrapping_add(1) % 4;
            begin_new_hand(&mut next, dealer);
            next.state_version += 1;
            Ok(next)
        }
    }
}

fn begin_new_hand(state: &mut GameState, dealer_seat: u8) {
    let seed = state.state_version.wrapping_mul(1_000_003).wrapping_add(dealer_seat as u64);
    let mut rng = StdRng::seed_from_u64(seed);
    let mut deck = standard_deck();
    deck.shuffle(&mut rng);

    let mut hands: [Vec<Card>; 4] = [vec![], vec![], vec![], vec![]];
    for _ in 0..5 {
        for seat in 0..4u8 {
            hands[seat as usize].push(deck.pop().expect("deck"));
        }
    }
    let lead = next_seat(dealer_seat);
    state.hands = hands;
    state.undealt = deck;
    state.dealer_seat = dealer_seat;
    state.trump = None;
    state.current_trick.clear();
    state.lead_seat = lead;
    state.turn_seat = lead;
    state.centre_pile.clear();
    state.last_trick_winner = None;
    state.captured_a.clear();
    state.captured_b.clear();
    state.tricks_played = 0;
    state.hand_winner = None;
    state.match_winner = None;
    state.remaining_dealt = false;
    state.phase = match state.config.trump_method {
        TrumpMethod::AnnouncedTrump => Phase::AnnounceTrump,
        TrumpMethod::CutTrump => Phase::CutPlay,
    };
}

fn seat_of(state: &GameState, player: PlayerId) -> Result<u8, EngineError> {
    state
        .players
        .iter()
        .find(|p| p.player_id == player)
        .map(|p| p.seat)
        .ok_or(EngineError::Illegal("unknown player"))
}

fn deal_remaining(state: &mut GameState) {
    if state.remaining_dealt {
        return;
    }
    // 8 more each from undealt (32 cards)
    for _ in 0..8 {
        for seat in 0..4u8 {
            if let Some(c) = state.undealt.pop() {
                state.hands[seat as usize].push(c);
            }
        }
    }
    state.remaining_dealt = true;
}

fn play_card(state: &mut GameState, seat: u8, card: Card) -> Result<(), EngineError> {
    if !matches!(state.phase, Phase::CutPlay | Phase::TrickPlay) {
        return Err(EngineError::WrongPhase);
    }
    if seat != state.turn_seat {
        return Err(EngineError::NotYourTurn);
    }
    let hand = &mut state.hands[seat as usize];
    let idx = hand
        .iter()
        .position(|c| *c == card)
        .ok_or(EngineError::CardNotInHand)?;

    if let Some(lead) = state.current_trick.first() {
        let lead_suit = lead.card.suit;
        let has_lead = hand.iter().any(|c| c.suit == lead_suit);
        if has_lead && card.suit != lead_suit {
            return Err(EngineError::MustFollowSuit);
        }
        // Cut trump: first unable-to-follow offsuit sets trump
        if state.phase == Phase::CutPlay
            && state.trump.is_none()
            && !has_lead
            && card.suit != lead_suit
        {
            state.trump = Some(card.suit);
        }
    }

    hand.remove(idx);
    state.current_trick.push(TrickPlay { seat, card });

    if state.current_trick.len() < 4 {
        state.turn_seat = next_seat(seat);
        return Ok(());
    }

    resolve_trick(state)
}

fn resolve_trick(state: &mut GameState) -> Result<(), EngineError> {
    let winner = trick_winner(state)?;
    let mut trick_cards: Vec<Card> = state.current_trick.drain(..).map(|p| p.card).collect();
    state.centre_pile.append(&mut trick_cards);
    state.tricks_played += 1;

    let capture = state.last_trick_winner == Some(winner) || state.tricks_played == 13;
    if capture {
        let pile = std::mem::take(&mut state.centre_pile);
        match team_for_seat(winner) {
            TeamId::A => state.captured_a.extend(pile),
            TeamId::B => state.captured_b.extend(pile),
        }
        state.last_trick_winner = None;
    } else {
        state.last_trick_winner = Some(winner);
    }

    // After cut sets trump on first offsuit trick, deal remaining once that trick ends
    if state.phase == Phase::CutPlay && state.trump.is_some() && !state.remaining_dealt {
        deal_remaining(state);
        state.phase = Phase::TrickPlay;
    } else if state.phase == Phase::CutPlay && state.trump.is_some() {
        state.phase = Phase::TrickPlay;
    }

    if state.tricks_played >= 13 {
        finish_hand(state);
        return Ok(());
    }

    state.lead_seat = winner;
    state.turn_seat = winner;
    Ok(())
}

fn trick_winner(state: &GameState) -> Result<u8, EngineError> {
    let lead_suit = state
        .current_trick
        .first()
        .ok_or(EngineError::Illegal("empty trick"))?
        .card
        .suit;
    let trump = state.trump;
    let mut best_seat = state.current_trick[0].seat;
    let mut best_card = state.current_trick[0].card;
    for play in state.current_trick.iter().skip(1) {
        if beats(play.card, best_card, lead_suit, trump) {
            best_seat = play.seat;
            best_card = play.card;
        }
    }
    Ok(best_seat)
}

fn beats(card: Card, current: Card, lead_suit: Suit, trump: Option<Suit>) -> bool {
    let card_trump = trump == Some(card.suit);
    let cur_trump = trump == Some(current.suit);
    if card_trump && !cur_trump {
        return true;
    }
    if !card_trump && cur_trump {
        return false;
    }
    if card_trump && cur_trump {
        return card.rank.strength() > current.rank.strength();
    }
    // Neither trump
    if card.suit == lead_suit && current.suit != lead_suit {
        return true;
    }
    if card.suit != lead_suit {
        return false;
    }
    card.rank.strength() > current.rank.strength()
}

fn finish_hand(state: &mut GameState) {
    // Sweep any remainder into last trick winner's team (already handled if tricks==13)
    if !state.centre_pile.is_empty() {
        if let Some(w) = state.last_trick_winner {
            let pile = std::mem::take(&mut state.centre_pile);
            match team_for_seat(w) {
                TeamId::A => state.captured_a.extend(pile),
                TeamId::B => state.captured_b.extend(pile),
            }
        }
    }

    let tens_a = state.captured_a.iter().filter(|c| c.is_ten()).count();
    let tens_b = state.captured_b.iter().filter(|c| c.is_ten()).count();

    let winner = if tens_a == 4 {
        state.kots_a += 1;
        state.consecutive_hands_a = 0;
        state.consecutive_hands_b = 0;
        TeamId::A
    } else if tens_b == 4 {
        state.kots_b += 1;
        state.consecutive_hands_a = 0;
        state.consecutive_hands_b = 0;
        TeamId::B
    } else if tens_a > tens_b {
        hand_win(state, TeamId::A)
    } else if tens_b > tens_a {
        hand_win(state, TeamId::B)
    } else {
        // 2–2
        match state.config.tens_tie_rule {
            TensTieRule::Draw => {
                state.consecutive_hands_a = 0;
                state.consecutive_hands_b = 0;
                // No hand winner; still advance dealer for next hand in rematch flow
                state.phase = Phase::HandComplete;
                state.hand_winner = None;
                return;
            }
            TensTieRule::MostTricks => {
                let tricks_a = estimate_tricks(state, TeamId::A);
                let tricks_b = estimate_tricks(state, TeamId::B);
                if tricks_a >= tricks_b {
                    hand_win(state, TeamId::A)
                } else {
                    hand_win(state, TeamId::B)
                }
            }
            TensTieRule::NonDealerWins => {
                let dealer_team = team_for_seat(state.dealer_seat);
                hand_win(state, dealer_team.other())
            }
        }
    };

    state.hand_winner = Some(winner);
    state.phase = Phase::HandComplete;

    if state.kots_a >= state.config.kots_to_win {
        state.match_winner = Some(TeamId::A);
        state.phase = Phase::MatchComplete;
    } else if state.kots_b >= state.config.kots_to_win {
        state.match_winner = Some(TeamId::B);
        state.phase = Phase::MatchComplete;
    }
}

fn hand_win(state: &mut GameState, team: TeamId) -> TeamId {
    match team {
        TeamId::A => {
            state.consecutive_hands_a += 1;
            state.consecutive_hands_b = 0;
            if state.consecutive_hands_a >= 7 {
                state.kots_a += 1;
                state.consecutive_hands_a = 0;
            }
        }
        TeamId::B => {
            state.consecutive_hands_b += 1;
            state.consecutive_hands_a = 0;
            if state.consecutive_hands_b >= 7 {
                state.kots_b += 1;
                state.consecutive_hands_b = 0;
            }
        }
    }
    team
}

fn estimate_tricks(state: &GameState, team: TeamId) -> usize {
    // Approx from captured card count / 4
    let cards = match team {
        TeamId::A => state.captured_a.len(),
        TeamId::B => state.captured_b.len(),
    };
    cards / 4
}

pub fn playable_cards(state: &GameState, seat: u8) -> Vec<Card> {
    if state.turn_seat != seat || !matches!(state.phase, Phase::CutPlay | Phase::TrickPlay) {
        return vec![];
    }
    let hand = &state.hands[seat as usize];
    if let Some(lead) = state.current_trick.first() {
        let lead_suit = lead.card.suit;
        let follow: Vec<Card> = hand.iter().copied().filter(|c| c.suit == lead_suit).collect();
        if !follow.is_empty() {
            return follow;
        }
    }
    hand.clone()
}

pub fn one_away_seat(state: &GameState) -> Option<u8> {
    state.last_trick_winner.filter(|_| !state.centre_pile.is_empty())
}

/// Assign seats for partnership: team A opposite, team B opposite.
/// For ChoosePartners, `chosen_pairs` is [(a1,a2), (b1,b2)] seated opposite.
pub fn seats_for_partners(
    mode: PartnershipMode,
    player_ids: [PlayerId; 4],
    chosen_pairs: Option<[(PlayerId, PlayerId); 2]>,
    seed: u64,
) -> Result<[PlayerId; 4], EngineError> {
    match mode {
        PartnershipMode::RandomOpposite => {
            let mut ids = player_ids;
            let mut rng = StdRng::seed_from_u64(seed);
            ids.shuffle(&mut rng);
            // seats 0,2 team A; 1,3 team B — already opposite after any perm
            Ok(ids)
        }
        PartnershipMode::ChoosePartners => {
            let pairs = chosen_pairs.ok_or(EngineError::Illegal("pairs required"))?;
            let (a1, a2) = pairs[0];
            let (b1, b2) = pairs[1];
            Ok([a1, b1, a2, b2])
        }
    }
}

pub fn new_game_id() -> GameId {
    Uuid::new_v4()
}

#[cfg(test)]
mod tests {
    use super::*;
    use dehla_domain::Rank;

    fn four_players() -> Vec<SeatPlayer> {
        (0..4)
            .map(|seat| SeatPlayer {
                player_id: Uuid::new_v4(),
                nickname: format!("P{seat}"),
                seat,
                avatar_id: Some(format!("face_0{}", seat + 1)),
            })
            .collect()
    }

    #[test]
    fn start_next_hand_rotates_dealer() {
        let players = four_players();
        let mut cfg = GameConfig::default();
        cfg.kots_to_win = 3;
        let mut state = start_game(StartGame {
            game_id: Uuid::new_v4(),
            config: cfg,
            players: players.clone(),
            seed: 1,
        })
        .unwrap();
        state.phase = Phase::HandComplete;
        state.hand_winner = Some(TeamId::A);
        let dealer = state.dealer_seat;
        let pid = state.players[0].player_id;
        let next = apply(&state, pid, &Command::StartNextHand).unwrap();
        assert_eq!(next.dealer_seat, (dealer + 1) % 4);
        assert!(matches!(next.phase, Phase::CutPlay | Phase::AnnounceTrump));
        for h in &next.hands {
            assert_eq!(h.len(), 5);
        }
    }

    #[test]
    fn start_deals_five_each() {
        let players = four_players();
        let state = start_game(StartGame {
            game_id: Uuid::new_v4(),
            config: GameConfig::default(),
            players,
            seed: 42,
        })
        .unwrap();
        assert!(matches!(state.phase, Phase::CutPlay));
        for h in &state.hands {
            assert_eq!(h.len(), 5);
        }
        assert_eq!(state.undealt.len(), 32);
    }

    #[test]
    fn announce_deals_remaining() {
        let players = four_players();
        let mut cfg = GameConfig::default();
        cfg.trump_method = TrumpMethod::AnnouncedTrump;
        let state = start_game(StartGame {
            game_id: Uuid::new_v4(),
            config: cfg,
            players: players.clone(),
            seed: 7,
        })
        .unwrap();
        let announcer = state.players[state.lead_seat as usize].player_id;
        let next = apply(
            &state,
            announcer,
            &Command::AnnounceTrump { suit: Suit::Hearts },
        )
        .unwrap();
        assert_eq!(next.trump, Some(Suit::Hearts));
        assert!(matches!(next.phase, Phase::TrickPlay));
        for h in &next.hands {
            assert_eq!(h.len(), 13);
        }
    }

    #[test]
    fn must_follow_suit() {
        let players = four_players();
        let state = start_game(StartGame {
            game_id: Uuid::new_v4(),
            config: GameConfig {
                trump_method: TrumpMethod::AnnouncedTrump,
                ..Default::default()
            },
            players,
            seed: 99,
        })
        .unwrap();
        let lead = state.players[state.lead_seat as usize].player_id;
        let state = apply(
            &state,
            lead,
            &Command::AnnounceTrump { suit: Suit::Spades },
        )
        .unwrap();
        let turn = state.turn_seat;
        let pid = state.players[turn as usize].player_id;
        let lead_card = state.hands[turn as usize][0];
        let state = apply(&state, pid, &Command::PlayCard { card: lead_card }).unwrap();
        let turn2 = state.turn_seat;
        let pid2 = state.players[turn2 as usize].player_id;
        let hand2 = &state.hands[turn2 as usize];
        if let Some(off) = hand2.iter().find(|c| c.suit != lead_card.suit) {
            if hand2.iter().any(|c| c.suit == lead_card.suit) {
                let err = apply(&state, pid2, &Command::PlayCard { card: *off }).unwrap_err();
                assert_eq!(err, EngineError::MustFollowSuit);
            }
        }
    }

    #[test]
    fn ten_detection() {
        assert!(Card {
            suit: Suit::Hearts,
            rank: Rank::Ten
        }
        .is_ten());
    }

    #[test]
    fn tens_tie_non_dealer_wins() {
        let players = four_players();
        let mut state = start_game(StartGame {
            game_id: Uuid::new_v4(),
            config: GameConfig {
                tens_tie_rule: TensTieRule::NonDealerWins,
                kots_to_win: 3,
                ..Default::default()
            },
            players,
            seed: 3,
        })
        .unwrap();
        // Fabricate end-of-hand captures: 2 tens each.
        let tens = [
            Card {
                suit: Suit::Hearts,
                rank: Rank::Ten,
            },
            Card {
                suit: Suit::Spades,
                rank: Rank::Ten,
            },
            Card {
                suit: Suit::Diamonds,
                rank: Rank::Ten,
            },
            Card {
                suit: Suit::Clubs,
                rank: Rank::Ten,
            },
        ];
        state.captured_a = vec![tens[0], tens[1], Card {
            suit: Suit::Hearts,
            rank: Rank::Ace,
        }];
        state.captured_b = vec![tens[2], tens[3], Card {
            suit: Suit::Spades,
            rank: Rank::Ace,
        }];
        state.tricks_played = 13;
        state.centre_pile.clear();
        state.last_trick_winner = None;
        finish_hand(&mut state);
        let dealer_team = team_for_seat(state.dealer_seat);
        assert_eq!(state.hand_winner, Some(dealer_team.other()));
        assert!(matches!(state.phase, Phase::HandComplete));
    }

    #[test]
    fn cut_play_sets_trump_on_first_offsuit() {
        let players = four_players();
        let mut state = start_game(StartGame {
            game_id: Uuid::new_v4(),
            config: GameConfig {
                trump_method: TrumpMethod::CutTrump,
                ..Default::default()
            },
            players,
            seed: 11,
        })
        .unwrap();
        assert!(matches!(state.phase, Phase::CutPlay));
        assert!(state.trump.is_none());

        // Force hands so seat 0 leads hearts and seat 1 must cut with a club.
        let lead = state.lead_seat;
        let follower = next_seat(lead);
        state.hands[lead as usize] = vec![
            Card {
                suit: Suit::Hearts,
                rank: Rank::Ace,
            },
            Card {
                suit: Suit::Hearts,
                rank: Rank::King,
            },
            Card {
                suit: Suit::Hearts,
                rank: Rank::Queen,
            },
            Card {
                suit: Suit::Hearts,
                rank: Rank::Jack,
            },
            Card {
                suit: Suit::Hearts,
                rank: Rank::Nine,
            },
        ];
        state.hands[follower as usize] = vec![
            Card {
                suit: Suit::Clubs,
                rank: Rank::Ace,
            },
            Card {
                suit: Suit::Clubs,
                rank: Rank::King,
            },
            Card {
                suit: Suit::Diamonds,
                rank: Rank::Ace,
            },
            Card {
                suit: Suit::Spades,
                rank: Rank::Ace,
            },
            Card {
                suit: Suit::Spades,
                rank: Rank::King,
            },
        ];
        state.turn_seat = lead;

        let lead_pid = state.players[lead as usize].player_id;
        let lead_card = Card {
            suit: Suit::Hearts,
            rank: Rank::Ace,
        };
        state = apply(&state, lead_pid, &Command::PlayCard { card: lead_card }).unwrap();
        assert!(state.trump.is_none());

        let cut_pid = state.players[follower as usize].player_id;
        let cut_card = Card {
            suit: Suit::Clubs,
            rank: Rank::Ace,
        };
        state = apply(&state, cut_pid, &Command::PlayCard { card: cut_card }).unwrap();
        assert_eq!(state.trump, Some(Suit::Clubs));
        assert!(matches!(state.phase, Phase::CutPlay));
    }
}
