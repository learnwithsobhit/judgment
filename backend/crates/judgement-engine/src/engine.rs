//! The deterministic game state machine (PLAN.md §6, Phase 1).
//!
//! The engine validates every command against the authoritative state; a
//! client-side disabled card is never sufficient validation (§5.6.7).

use std::collections::{HashMap, HashSet};

use judgement_domain::{
    full_deck, Card, CardId, GameError, GameId, GameRules, PlayerId, PlayerState, RoundScoreEntry,
    ScoreTable, TrumpRule,
};

use crate::events::GameEvent;
use crate::projection::{self, PlayerGameView, SpectatorGameView};
use crate::scoring::{scoring_strategy_for, ScoringContext};
use crate::shuffle::{DeckShuffler, SecureShuffler, SeededShuffler};
use crate::state::{CompletedTrick, GamePhase, InternalGameState, PlayedCard, RoundState};
use crate::trick::determine_trick_winner;

pub struct GameEngine {
    state: InternalGameState,
    shuffler: Box<dyn DeckShuffler>,
}

impl GameEngine {
    /// Production constructor with OS-backed secure shuffling.
    pub fn new(
        game_id: GameId,
        rules: GameRules,
        players: Vec<PlayerState>,
    ) -> Result<Self, GameError> {
        Self::with_shuffler(game_id, rules, players, Box::new(SecureShuffler::new()))
    }

    /// Deterministic constructor for tests, simulations, and bug reproduction
    /// (PLAN.md §23.3).
    pub fn new_with_seed(
        seed: u64,
        game_id: GameId,
        rules: GameRules,
        players: Vec<PlayerState>,
    ) -> Result<Self, GameError> {
        Self::with_shuffler(game_id, rules, players, Box::new(SeededShuffler::new(seed)))
    }

    pub fn with_shuffler(
        game_id: GameId,
        rules: GameRules,
        players: Vec<PlayerState>,
        shuffler: Box<dyn DeckShuffler>,
    ) -> Result<Self, GameError> {
        let count = players.len() as u8;
        if count < rules.min_players || count > rules.max_players {
            return Err(GameError::InvalidPlayerCount {
                required: rules.max_players,
                actual: count,
            });
        }

        let dealer = players[0].id;
        let state = InternalGameState {
            game_id,
            version: 0,
            phase: GamePhase::Lobby,
            rules,
            dealer,
            players,
            deck: Vec::new(),
            trump: None,
            trump_card: None,
            current_round: None,
            score_table: ScoreTable::default(),
        };
        Ok(Self { state, shuffler })
    }

    pub fn state(&self) -> &InternalGameState {
        &self.state
    }

    /// Replace the authoritative state (used to roll back after a failed
    /// persistence commit — PLAN.md §9.2).
    pub fn replace_state(&mut self, state: InternalGameState) {
        self.state = state;
    }

    /// Rebuild an engine from a persisted snapshot (PLAN.md §14.2 recovery).
    /// A secure shuffler is used for any subsequent deals; the restored
    /// `InternalGameState` already contains the current deal.
    pub fn from_restored_state(state: InternalGameState) -> Self {
        Self {
            state,
            shuffler: Box::new(SecureShuffler::new()),
        }
    }

    /// Like [`from_restored_state`] but with a deterministic shuffler for tests.
    pub fn from_restored_state_with_seed(state: InternalGameState, seed: u64) -> Self {
        Self {
            state,
            shuffler: Box::new(SeededShuffler::new(seed)),
        }
    }

    pub fn phase(&self) -> GamePhase {
        self.state.phase
    }

    pub fn version(&self) -> u64 {
        self.state.version
    }

    pub fn is_finished(&self) -> bool {
        self.state.phase == GamePhase::Finished
    }

    /// Update a seat's connection / bot-control status (Phase 6 presence).
    pub fn set_connection_status(
        &mut self,
        player_id: PlayerId,
        status: judgement_domain::ConnectionStatus,
    ) -> Result<(), GameError> {
        let player = self
            .state
            .players
            .iter_mut()
            .find(|p| p.id == player_id)
            .ok_or(GameError::PlayerNotInGame)?;
        player.connection_status = status;
        Ok(())
    }

    /// Cosmetic avatar pack id (does not affect rules).
    pub fn set_avatar(
        &mut self,
        player_id: PlayerId,
        avatar_id: String,
    ) -> Result<(), GameError> {
        let player = self
            .state
            .players
            .iter_mut()
            .find(|p| p.id == player_id)
            .ok_or(GameError::PlayerNotInGame)?;
        player.avatar_id = Some(avatar_id);
        self.state.version += 1;
        Ok(())
    }

    /// Mid-game seat claim: swap display identity on the same `player_id` seat.
    pub fn set_seat_identity(
        &mut self,
        player_id: PlayerId,
        nickname: String,
        avatar_id: Option<String>,
    ) -> Result<(), GameError> {
        let player = self
            .state
            .players
            .iter_mut()
            .find(|p| p.id == player_id)
            .ok_or(GameError::PlayerNotInGame)?;
        player.nickname = nickname;
        player.avatar_id = avatar_id;
        player.is_bot = false;
        player.connection_status = judgement_domain::ConnectionStatus::Connected;
        self.state.version += 1;
        Ok(())
    }

    /// Personalised projection for one player; never leaks hidden state.
    pub fn view_for(&self, player_id: PlayerId) -> Result<PlayerGameView, GameError> {
        if !self.state.contains_player(player_id) {
            return Err(GameError::PlayerNotInGame);
        }
        Ok(projection::project_for(&self.state, player_id, self.legal_bids(player_id), self.legal_cards(player_id)))
    }

    /// Hand-free public projection for audience watchers.
    pub fn spectator_view(&self, viewer_count: u32) -> SpectatorGameView {
        projection::project_spectator(&self.state, viewer_count)
    }

    /// True once the final round has begun (predictions lock).
    pub fn predictions_locked(&self) -> bool {
        let total = self.state.rules.round_pattern.rounds().len();
        if total == 0 {
            return true;
        }
        if self.state.phase == GamePhase::Finished {
            return true;
        }
        self.state
            .current_round
            .as_ref()
            .map(|r| r.round_index >= total.saturating_sub(1))
            .unwrap_or(false)
    }

    // ------------------------------------------------------------------
    // Commands
    // ------------------------------------------------------------------

    /// Start the game from the lobby: fixes the initial dealer and begins
    /// round 0 (deal + trump reveal + bidding).
    pub fn start_game(&mut self) -> Result<Vec<GameEvent>, GameError> {
        if self.state.phase != GamePhase::Lobby {
            return Err(GameError::WrongPhase);
        }

        let dealer = self.state.players[0].id;
        self.state.dealer = dealer;
        let mut events = vec![GameEvent::GameStarted { dealer }];
        events.extend(self.begin_round(0));
        self.state.version += 1;
        Ok(events)
    }

    pub fn place_bid(&mut self, player_id: PlayerId, bid: u8) -> Result<Vec<GameEvent>, GameError> {
        if self.state.phase == GamePhase::Finished {
            return Err(GameError::GameAlreadyFinished);
        }
        if !self.state.contains_player(player_id) {
            return Err(GameError::PlayerNotInGame);
        }
        if self.state.phase != GamePhase::Bidding {
            return Err(GameError::WrongPhase);
        }

        let player_count = self.state.players.len();
        let dealer = self.state.dealer;
        let dealer_restriction = self.state.rules.bidding_rule.dealer_total_restriction;
        let allow_zero = self.state.rules.bidding_rule.allow_zero;

        let round = self.state.current_round.as_mut().expect("bidding requires a round");
        if round.current_turn != player_id {
            return Err(GameError::NotYourTurn);
        }
        if round.bids.contains_key(&player_id) {
            return Err(GameError::BidAlreadyPlaced);
        }

        let max = round.cards_per_player;
        let min = if allow_zero { 0 } else { 1 };
        if bid < min || bid > max {
            return Err(GameError::BidOutOfRange { bid, max });
        }

        // The dealer bids last; when the restriction is enabled the total of
        // all bids must not equal the tricks available (§5.5).
        if player_id == dealer && dealer_restriction {
            let others: u32 = round.bids.values().map(|&b| b as u32).sum();
            if others + bid as u32 == max as u32 {
                return Err(GameError::DealerBidRestriction { bid, tricks_available: max });
            }
        }

        round.bids.insert(player_id, bid);
        let events = vec![GameEvent::BidPlaced { player_id, bid }];

        if round.all_bids_placed(player_count) {
            // First trick of the round is led by the player clockwise-left of
            // the dealer (locked decision 1) — the first bidder.
            round.current_turn = round.bidding_order[0];
            self.state.phase = GamePhase::Playing;
        } else {
            let position = round
                .bidding_order
                .iter()
                .position(|&p| p == player_id)
                .expect("bidder must be in bidding order");
            round.current_turn = round.bidding_order[position + 1];
        }

        self.state.version += 1;
        Ok(events)
    }

    pub fn play_card(
        &mut self,
        player_id: PlayerId,
        card_id: CardId,
    ) -> Result<Vec<GameEvent>, GameError> {
        if self.state.phase == GamePhase::Finished {
            return Err(GameError::GameAlreadyFinished);
        }
        if !self.state.contains_player(player_id) {
            return Err(GameError::PlayerNotInGame);
        }
        if self.state.phase != GamePhase::Playing {
            return Err(GameError::WrongPhase);
        }

        let player_count = self.state.players.len();
        let trump = self.state.trump_suit();
        let next_clockwise = self.state.next_clockwise(player_id);

        let round = self.state.current_round.as_mut().expect("playing requires a round");
        if round.current_turn != player_id {
            return Err(GameError::NotYourTurn);
        }

        let card = card_id.card();
        let hand = round.hands.get_mut(&player_id).expect("seated player has a hand");
        let Some(position) = hand.iter().position(|&c| c == card) else {
            return Err(GameError::CardNotInHand { card: card_id });
        };

        if let Some(lead_suit) = round.current_trick.first().map(|p| p.card.suit) {
            let holds_lead_suit = hand.iter().any(|c| c.suit == lead_suit);
            if card.suit != lead_suit && holds_lead_suit {
                return Err(GameError::MustFollowSuit { lead_suit, attempted: card_id });
            }
        }

        hand.remove(position);
        round.current_trick.push(PlayedCard { player_id, card });
        let mut events = vec![GameEvent::CardPlayed { player_id, card }];

        if round.current_trick.len() == player_count {
            let lead_suit = round.current_trick[0].card.suit;
            let winner = determine_trick_winner(lead_suit, trump, &round.current_trick)
                .expect("completed trick always has a winner");

            let trick_index = round.completed_tricks.len() as u32;
            round.completed_tricks.push(CompletedTrick {
                trick_index,
                lead_suit,
                plays: std::mem::take(&mut round.current_trick),
                winner,
            });
            *round.tricks_won.entry(winner).or_insert(0) += 1;
            round.current_turn = winner;
            events.push(GameEvent::TrickCompleted { trick_index, winner });

            if round.all_tricks_complete() {
                events.extend(self.complete_round());
            }
        } else {
            round.current_turn = next_clockwise;
        }

        self.state.version += 1;
        Ok(events)
    }

    // ------------------------------------------------------------------
    // Legal-action helpers (used by projections and bots)
    // ------------------------------------------------------------------

    /// Bids the player could legally place right now (empty when not their turn).
    pub fn legal_bids(&self, player_id: PlayerId) -> Vec<u8> {
        if self.state.phase != GamePhase::Bidding {
            return Vec::new();
        }
        let Some(round) = &self.state.current_round else { return Vec::new() };
        if round.current_turn != player_id || round.bids.contains_key(&player_id) {
            return Vec::new();
        }

        let max = round.cards_per_player;
        let min = if self.state.rules.bidding_rule.allow_zero { 0 } else { 1 };
        let mut bids: Vec<u8> = (min..=max).collect();

        if player_id == self.state.dealer && self.state.rules.bidding_rule.dealer_total_restriction {
            let others: u32 = round.bids.values().map(|&b| b as u32).sum();
            bids.retain(|&b| others + b as u32 != max as u32);
        }
        bids
    }

    /// Cards the player could legally play right now (empty when not their turn).
    pub fn legal_cards(&self, player_id: PlayerId) -> Vec<CardId> {
        if self.state.phase != GamePhase::Playing {
            return Vec::new();
        }
        let Some(round) = &self.state.current_round else { return Vec::new() };
        if round.current_turn != player_id {
            return Vec::new();
        }
        let Some(hand) = round.hands.get(&player_id) else { return Vec::new() };

        match round.lead_suit() {
            Some(lead_suit) if hand.iter().any(|c| c.suit == lead_suit) => hand
                .iter()
                .filter(|c| c.suit == lead_suit)
                .map(|c| c.id())
                .collect(),
            _ => hand.iter().map(|c| c.id()).collect(),
        }
    }

    // ------------------------------------------------------------------
    // Invariant checking (used by simulations and property tests)
    // ------------------------------------------------------------------

    /// Verify structural invariants (PLAN.md §23.2). Returns a description of
    /// the first violation found.
    pub fn check_invariants(&self) -> Result<(), String> {
        let state = &self.state;
        let Some(round) = &state.current_round else { return Ok(()) };

        let mut seen: HashSet<Card> = HashSet::new();
        let mut count = 0usize;
        let mut track = |cards: &[Card], location: &str| -> Result<(), String> {
            for &card in cards {
                if !seen.insert(card) {
                    return Err(format!("card {card} appears twice (in {location})"));
                }
                count += 1;
            }
            Ok(())
        };

        for (player, hand) in &round.hands {
            track(hand, &format!("hand of {player}"))?;
        }
        track(&state.deck, "undealt deck")?;
        if let Some(trump) = state.trump_card {
            track(&[trump], "trump card")?;
        }
        let trick_cards: Vec<Card> = round.current_trick.iter().map(|p| p.card).collect();
        track(&trick_cards, "current trick")?;
        for trick in &round.completed_tricks {
            let cards: Vec<Card> = trick.plays.iter().map(|p| p.card).collect();
            track(&cards, &format!("completed trick {}", trick.trick_index))?;
        }

        if matches!(
            state.phase,
            GamePhase::Bidding | GamePhase::Playing | GamePhase::RoundScoring
        ) && count != 52
        {
            return Err(format!("expected 52 cards accounted for, found {count}"));
        }

        let tricks_won: u32 = round.tricks_won.values().map(|&t| t as u32).sum();
        if tricks_won != round.completed_tricks.len() as u32 {
            return Err(format!(
                "tricks won ({tricks_won}) != completed tricks ({})",
                round.completed_tricks.len()
            ));
        }

        Ok(())
    }

    // ------------------------------------------------------------------
    // Internal transitions
    // ------------------------------------------------------------------

    fn begin_round(&mut self, round_index: usize) -> Vec<GameEvent> {
        self.state.phase = GamePhase::RoundSetup;
        let cards_per_player = self.state.rules.round_pattern.rounds()[round_index];
        let dealer = self.state.dealer;

        // Deal from a freshly shuffled deck, one card at a time, starting
        // clockwise-left of the dealer.
        self.state.phase = GamePhase::Dealing;
        let mut deck = full_deck();
        self.shuffler.shuffle_deck(&mut deck);

        let seat_order = self.seat_order_from(self.state.next_clockwise(dealer));
        let mut hands: HashMap<PlayerId, Vec<Card>> =
            seat_order.iter().map(|&p| (p, Vec::new())).collect();
        for _ in 0..cards_per_player {
            for &player in &seat_order {
                hands.get_mut(&player).expect("hand exists").push(
                    deck.pop().expect("deck has enough cards for the deal"),
                );
            }
        }

        // Trump for the round (ADR 0003): either reveal an undealt card, or
        // follow the fixed rotation from the chosen first trump.
        let (trump, trump_card) = match &self.state.rules.trump_rule {
            TrumpRule::RevealUndealtCard => {
                let card = deck.pop().expect("at least one undealt card remains");
                (Some(card.suit), Some(card))
            }
            TrumpRule::FixedSequence { suits } => {
                (Some(suits[round_index % suits.len()]), None)
            }
            // Remaining trump rules are not offered by any room configuration.
            _ => (None, None),
        };
        self.state.deck = deck;
        self.state.trump = trump;
        self.state.trump_card = trump_card;

        // Bidding starts clockwise-left of the dealer and ends with the dealer.
        let bidding_order = seat_order.clone();
        let first_bidder = bidding_order[0];
        self.state.current_round = Some(RoundState {
            round_index,
            cards_per_player,
            bidding_order,
            bids: HashMap::new(),
            hands,
            current_trick: Vec::new(),
            completed_tricks: Vec::new(),
            current_turn: first_bidder,
            tricks_won: HashMap::new(),
        });
        self.state.phase = GamePhase::Bidding;

        let mut events = vec![
            GameEvent::RoundStarted { round_index, cards_per_player, dealer },
            GameEvent::CardsDealt { round_index },
        ];
        if let Some(trump) = trump {
            events.push(GameEvent::TrumpSelected { round_index, trump, trump_card });
        }
        events
    }

    /// Score the finished round and pause in [`GamePhase::RoundScoring`] so
    /// clients can reveal the last trick before the next deal (or game end).
    /// Call [`Self::advance_from_round_scoring`] after the reveal delay.
    fn complete_round(&mut self) -> Vec<GameEvent> {
        self.state.phase = GamePhase::RoundScoring;
        let round = self.state.current_round.as_ref().expect("scoring requires a round");
        let round_index = round.round_index;

        let scoring = scoring_strategy_for(&self.state.rules.scoring_rule);
        let ctx = ScoringContext { round_index, cards_in_round: round.cards_per_player };
        let entries: HashMap<PlayerId, RoundScoreEntry> = self
            .state
            .players
            .iter()
            .map(|player| {
                let bid = round.bids[&player.id];
                let tricks_won = round.tricks_won.get(&player.id).copied().unwrap_or(0);
                let score = scoring.score_round(&ctx, bid, tricks_won);
                (player.id, RoundScoreEntry { bid, tricks_won, score })
            })
            .collect();
        self.state.score_table.record_round(entries);

        vec![GameEvent::RoundCompleted { round_index }]
    }

    /// Continue after the end-of-round trick reveal: start the next round or
    /// finish the game. Only valid while phase is [`GamePhase::RoundScoring`].
    pub fn advance_from_round_scoring(&mut self) -> Result<Vec<GameEvent>, GameError> {
        if self.state.phase != GamePhase::RoundScoring {
            return Err(GameError::WrongPhase);
        }
        let round_index = self
            .state
            .current_round
            .as_ref()
            .expect("scoring requires a round")
            .round_index;
        let total_rounds = self.state.rules.round_pattern.rounds().len();

        let mut events = Vec::new();
        if round_index + 1 < total_rounds {
            let new_dealer = self.state.next_clockwise(self.state.dealer);
            self.state.dealer = new_dealer;
            events.push(GameEvent::DealerRotated { new_dealer });
            events.extend(self.begin_round(round_index + 1));
        } else {
            self.state.phase = GamePhase::GameScoring;
            let ranking = self.state.score_table.final_ranking(&self.state.player_ids());
            self.state.phase = GamePhase::Finished;
            events.push(GameEvent::GameCompleted { ranking });
        }
        self.state.version += 1;
        Ok(events)
    }

    /// Seat order starting from `first`, wrapping clockwise around the table.
    fn seat_order_from(&self, first: PlayerId) -> Vec<PlayerId> {
        let players = &self.state.players;
        let start = players
            .iter()
            .position(|p| p.id == first)
            .expect("player must be seated");
        (0..players.len())
            .map(|offset| players[(start + offset) % players.len()].id)
            .collect()
    }
}
