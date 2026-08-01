//! End-to-end engine tests without networking (PLAN.md §23.1, Phase 1 exit).

use judgement_domain::{
    CardId, GameError, GameId, GameRules, PlayerId, PlayerState, RoundPattern, Suit, TrumpRule,
};
use judgement_engine::{GameEngine, GameEvent, GamePhase};

fn six_players() -> Vec<PlayerState> {
    (0..6)
        .map(|seat| PlayerState::human(PlayerId::new(), format!("P{}", seat + 1), seat))
        .collect()
}

fn engine_with_seed(seed: u64) -> GameEngine {
    GameEngine::new_with_seed(seed, GameId::new(), GameRules::default_six_player(), six_players())
        .expect("six players are valid")
}

fn current_player(engine: &GameEngine) -> PlayerId {
    engine
        .state()
        .current_round
        .as_ref()
        .expect("round in progress")
        .current_turn
}

/// Place the first legal bid for every player in order.
fn bid_all(engine: &mut GameEngine) {
    while engine.phase() == GamePhase::Bidding {
        let player = current_player(engine);
        let bids = engine.legal_bids(player);
        assert!(!bids.is_empty(), "current bidder must always have a legal bid");
        engine.place_bid(player, bids[0]).expect("legal bid is accepted");
    }
}

fn play_one_card(engine: &mut GameEngine) -> Vec<GameEvent> {
    let player = current_player(engine);
    let cards = engine.legal_cards(player);
    assert!(!cards.is_empty(), "current player must always have a legal card");
    engine.play_card(player, cards[0]).expect("legal card is accepted")
}

fn run_full_game(seed: u64) -> GameEngine {
    let mut engine = engine_with_seed(seed);
    engine.start_game().unwrap();
    while !engine.is_finished() {
        match engine.phase() {
            GamePhase::Bidding => bid_all(&mut engine),
            GamePhase::Playing => {
                play_one_card(&mut engine);
            }
            GamePhase::RoundScoring => {
                engine
                    .advance_from_round_scoring()
                    .expect("advance after round scoring");
            }
            other => panic!("unexpected phase {other:?}"),
        }
        engine.check_invariants().expect("invariants hold after every command");
    }
    engine
}

#[test]
fn start_deals_correct_counts_and_reveals_trump() {
    let mut engine = engine_with_seed(1);
    let events = engine.start_game().unwrap();

    let state = engine.state();
    let round = state.current_round.as_ref().unwrap();
    assert_eq!(round.cards_per_player, 8);
    for hand in round.hands.values() {
        assert_eq!(hand.len(), 8);
    }
    // 52 - 48 dealt - 1 revealed trump = 3 undealt cards.
    assert_eq!(state.deck.len(), 3);

    let trump_card = state.trump_card.expect("trump revealed");
    assert_eq!(state.trump_suit(), Some(trump_card.suit));
    // The revealed trump card is out of play.
    assert!(round.hands.values().all(|hand| !hand.contains(&trump_card)));

    assert!(matches!(events[0], GameEvent::GameStarted { .. }));
    assert!(events.iter().any(|e| matches!(e, GameEvent::TrumpSelected { .. })));
    assert_eq!(engine.phase(), GamePhase::Bidding);
    assert_eq!(engine.version(), 1);
}

#[test]
fn cannot_start_twice() {
    let mut engine = engine_with_seed(1);
    engine.start_game().unwrap();
    assert_eq!(engine.start_game(), Err(GameError::WrongPhase));
}

#[test]
fn rejects_wrong_player_count() {
    // 3–8 players are legal; 2 and 9 are not.
    for (count, expected_ok) in [(2u8, false), (3, true), (4, true), (8, true), (9, false)] {
        let players: Vec<PlayerState> = (0..count)
            .map(|seat| PlayerState::human(PlayerId::new(), format!("P{seat}"), seat))
            .collect();
        let rules = GameRules::mvp_for_players(count);
        let result = GameEngine::new_with_seed(1, GameId::new(), rules, players);
        assert_eq!(
            result.is_ok(),
            expected_ok,
            "player count {count} should be {}",
            if expected_ok { "accepted" } else { "rejected" }
        );
    }
}

#[test]
fn rotating_trump_follows_the_fixed_order_without_revealing_a_card() {
    let players: Vec<PlayerState> = (0..4)
        .map(|seat| PlayerState::human(PlayerId::new(), format!("P{seat}"), seat))
        .collect();
    let rules = GameRules {
        trump_rule: TrumpRule::rotating_from(Suit::Clubs),
        // Short game so the test drives only a few rounds.
        round_pattern: RoundPattern::Custom { rounds: vec![1, 1, 1, 1, 1] },
        ..GameRules::mvp_for_players(4)
    };
    let mut engine = GameEngine::new_with_seed(7, GameId::new(), rules, players).unwrap();
    engine.start_game().unwrap();

    // Chosen first trump, then ♠ ♦ ♣ ♥ order wrapping: clubs, hearts,
    // spades, diamonds, clubs.
    let expected = [Suit::Clubs, Suit::Hearts, Suit::Spades, Suit::Diamonds, Suit::Clubs];
    for (round, &want) in expected.iter().enumerate() {
        assert_eq!(
            engine.state().current_round.as_ref().unwrap().round_index,
            round
        );
        assert_eq!(engine.state().trump_suit(), Some(want), "round {round}");
        assert_eq!(engine.state().trump_card, None, "no card is revealed in rotation mode");
        play_out_round(&mut engine);
    }
    assert_eq!(engine.phase(), GamePhase::Finished);
}

/// Drive the current round to completion with first-legal actions.
fn play_out_round(engine: &mut GameEngine) {
    let start_round = engine.state().current_round.as_ref().unwrap().round_index;
    while !engine.is_finished() {
        let round = engine.state().current_round.as_ref().unwrap();
        if round.round_index != start_round {
            break;
        }
        let current = round.current_turn;
        match engine.phase() {
            GamePhase::Bidding => {
                let bid = engine.legal_bids(current)[0];
                engine.place_bid(current, bid).unwrap();
            }
            GamePhase::Playing => {
                let card = engine.legal_cards(current)[0];
                engine.play_card(current, card).unwrap();
            }
            GamePhase::RoundScoring => {
                engine.advance_from_round_scoring().unwrap();
            }
            other => panic!("unexpected phase {other:?}"),
        }
    }
}

#[test]
fn bidding_starts_left_of_dealer_and_dealer_bids_last() {
    let mut engine = engine_with_seed(2);
    engine.start_game().unwrap();

    let dealer = engine.state().dealer;
    let expected_first = engine.state().next_clockwise(dealer);
    assert_eq!(current_player(&engine), expected_first);

    let order = engine.state().current_round.as_ref().unwrap().bidding_order.clone();
    assert_eq!(*order.last().unwrap(), dealer, "dealer bids last");
    assert_eq!(order[0], expected_first);
}

#[test]
fn bid_validation_rules() {
    let mut engine = engine_with_seed(3);
    engine.start_game().unwrap();

    let first = current_player(&engine);
    let someone_else = engine.state().players.iter().find(|p| p.id != first).unwrap().id;
    let outsider = PlayerId::new();

    assert_eq!(engine.place_bid(someone_else, 1), Err(GameError::NotYourTurn));
    assert_eq!(engine.place_bid(outsider, 1), Err(GameError::PlayerNotInGame));
    assert_eq!(engine.place_bid(first, 9), Err(GameError::BidOutOfRange { bid: 9, max: 8 }));

    // Playing a card during bidding is the wrong phase.
    let any_card: CardId = "ace-of-hearts".parse().unwrap();
    assert_eq!(engine.play_card(first, any_card), Err(GameError::WrongPhase));

    let version_before = engine.version();
    engine.place_bid(first, 0).unwrap();
    assert_eq!(engine.version(), version_before + 1);
}

#[test]
fn dealer_restriction_forbids_exactly_the_matching_total() {
    let mut rules = GameRules::default_six_player();
    rules.bidding_rule.dealer_total_restriction = true;
    let mut engine = GameEngine::new_with_seed(4, GameId::new(), rules, six_players())
        .expect("six players are valid");
    engine.start_game().unwrap();

    // First five bidders each bid 1 (total 5); with 8 tricks available the
    // dealer may not bid 3.
    for _ in 0..5 {
        let player = current_player(&engine);
        engine.place_bid(player, 1).unwrap();
    }

    let dealer = engine.state().dealer;
    assert_eq!(current_player(&engine), dealer);

    let legal = engine.legal_bids(dealer);
    assert!(!legal.contains(&3), "dealer cannot make totals equal 8");
    assert_eq!(legal.len(), 8, "exactly one option is removed from 0..=8");

    assert_eq!(
        engine.place_bid(dealer, 3),
        Err(GameError::DealerBidRestriction { bid: 3, tricks_available: 8 })
    );
    engine.place_bid(dealer, 2).unwrap();
    assert_eq!(engine.phase(), GamePhase::Playing);
}

#[test]
fn dealer_may_match_total_when_restriction_off() {
    let mut engine = engine_with_seed(4);
    engine.start_game().unwrap();
    assert!(!engine.state().rules.bidding_rule.dealer_total_restriction);

    for _ in 0..5 {
        let player = current_player(&engine);
        engine.place_bid(player, 1).unwrap();
    }
    let dealer = engine.state().dealer;
    let legal = engine.legal_bids(dealer);
    assert!(legal.contains(&3), "matching total is allowed by default");
    engine.place_bid(dealer, 3).unwrap();
    assert_eq!(engine.phase(), GamePhase::Playing);
}

#[test]
fn first_trick_led_by_player_left_of_dealer_then_winner_leads() {
    let mut engine = engine_with_seed(5);
    engine.start_game().unwrap();
    bid_all(&mut engine);

    let dealer = engine.state().dealer;
    assert_eq!(
        current_player(&engine),
        engine.state().next_clockwise(dealer),
        "first trick is led by the player clockwise-left of the dealer"
    );

    // Play one full trick; the winner must lead the next one.
    let mut winner = None;
    for _ in 0..6 {
        for event in play_one_card(&mut engine) {
            if let GameEvent::TrickCompleted { winner: w, .. } = event {
                winner = Some(w);
            }
        }
    }
    let winner = winner.expect("trick completed after six plays");
    assert_eq!(current_player(&engine), winner, "trick winner leads the next trick");
}

#[test]
fn play_proceeds_clockwise_within_a_trick() {
    let mut engine = engine_with_seed(6);
    engine.start_game().unwrap();
    bid_all(&mut engine);

    let first = current_player(&engine);
    play_one_card(&mut engine);
    assert_eq!(current_player(&engine), engine.state().next_clockwise(first));
}

#[test]
fn must_follow_suit_when_holding_lead_suit() {
    // Search a few seeds for a state where the second player to act holds
    // both the lead suit and an off-suit card.
    for seed in 0..40 {
        let mut engine = engine_with_seed(seed);
        engine.start_game().unwrap();
        bid_all(&mut engine);
        play_one_card(&mut engine);

        let lead_suit = engine
            .state()
            .current_round
            .as_ref()
            .unwrap()
            .lead_suit()
            .expect("a card has been led");
        let player = current_player(&engine);
        let hand = engine.state().current_round.as_ref().unwrap().hands[&player].clone();

        let holds_lead = hand.iter().any(|c| c.suit == lead_suit);
        let off_suit = hand.iter().find(|c| c.suit != lead_suit).copied();
        if let (true, Some(off_suit_card)) = (holds_lead, off_suit) {
            assert_eq!(
                engine.play_card(player, off_suit_card.id()),
                Err(GameError::MustFollowSuit { lead_suit, attempted: off_suit_card.id() })
            );
            // Legal cards are exactly the lead-suit cards.
            let legal = engine.legal_cards(player);
            assert!(legal.iter().all(|id| id.suit == lead_suit));
            return;
        }
    }
    panic!("no seed produced the follow-suit scenario");
}

#[test]
fn cannot_play_a_card_you_do_not_hold() {
    let mut engine = engine_with_seed(7);
    engine.start_game().unwrap();
    bid_all(&mut engine);

    let player = current_player(&engine);
    let hand = engine.state().current_round.as_ref().unwrap().hands[&player].clone();
    let not_held = judgement_domain::full_deck()
        .into_iter()
        .find(|c| !hand.contains(c))
        .unwrap();

    assert_eq!(
        engine.play_card(player, not_held.id()),
        Err(GameError::CardNotInHand { card: not_held.id() })
    );
}

#[test]
fn round_completion_rotates_dealer_and_deals_next_round() {
    let mut engine = engine_with_seed(8);
    engine.start_game().unwrap();
    let first_dealer = engine.state().dealer;

    bid_all(&mut engine);
    // Round 1 has 8 tricks of 6 cards each.
    for _ in 0..48 {
        play_one_card(&mut engine);
    }

    assert_eq!(engine.phase(), GamePhase::RoundScoring);
    assert_eq!(
        engine.state().score_table.rounds.len(),
        1,
        "round 1 scored exactly once before the next deal"
    );
    engine.advance_from_round_scoring().unwrap();

    let state = engine.state();
    let round = state.current_round.as_ref().unwrap();
    assert_eq!(round.round_index, 1);
    assert_eq!(round.cards_per_player, 7);
    assert_eq!(state.dealer, state.next_clockwise(first_dealer), "dealer rotates clockwise");
    assert_eq!(engine.phase(), GamePhase::Bidding);
}

#[test]
fn full_game_completes_after_eight_rounds() {
    let engine = run_full_game(9);

    assert_eq!(engine.phase(), GamePhase::Finished);
    let state = engine.state();
    assert_eq!(state.score_table.rounds.len(), 8);

    let ranking = state.score_table.final_ranking(&state.player_ids());
    assert_eq!(ranking.len(), 6);
    assert_eq!(ranking[0].rank, 1);

    // Scores follow the 10 + bid rule.
    for round in &state.score_table.rounds {
        assert_eq!(round.len(), 6, "every player scored every round");
        for entry in round.values() {
            if entry.bid == entry.tricks_won {
                assert_eq!(entry.score, 10 + entry.bid as i32);
            } else {
                assert_eq!(entry.score, 0);
            }
        }
    }
}

#[test]
fn finished_game_rejects_further_commands() {
    let mut engine = run_full_game(10);
    let player = engine.state().players[0].id;

    assert_eq!(engine.place_bid(player, 1), Err(GameError::GameAlreadyFinished));
    assert_eq!(
        engine.play_card(player, "two-of-clubs".parse().unwrap()),
        Err(GameError::GameAlreadyFinished)
    );
}

#[test]
fn same_seed_produces_identical_deals() {
    let mut a = engine_with_seed(11);
    let mut b = engine_with_seed(11);
    a.start_game().unwrap();
    b.start_game().unwrap();

    let hands_a = &a.state().current_round.as_ref().unwrap().hands;
    let hands_b = &b.state().current_round.as_ref().unwrap().hands;
    // Player ids differ between the two engines, so compare by seat order.
    for (pa, pb) in a.state().players.iter().zip(b.state().players.iter()) {
        assert_eq!(hands_a[&pa.id], hands_b[&pb.id]);
    }
    assert_eq!(a.state().trump_card, b.state().trump_card);
}

#[test]
fn projection_never_leaks_opponent_cards() {
    let mut engine = engine_with_seed(12);
    engine.start_game().unwrap();

    let players = engine.state().player_ids();
    for &viewer in &players {
        let view = engine.view_for(viewer).unwrap();
        let json = serde_json::to_string(&view).unwrap();

        let own_hand = engine.state().current_round.as_ref().unwrap().hands[&viewer].clone();
        assert_eq!(view.own_hand.len(), 8);
        assert!(own_hand.iter().all(|c| view.own_hand.contains(c)));

        for &opponent in players.iter().filter(|&&p| p != viewer) {
            let opponent_hand = engine.state().current_round.as_ref().unwrap().hands[&opponent].clone();
            for card in opponent_hand {
                let card_json = serde_json::to_string(&card).unwrap();
                // The viewer's own duplicate-free hand cannot contain this
                // card, so its serialized form must be absent entirely.
                assert!(
                    !json.contains(&card_json),
                    "view for {viewer} leaked opponent card {card}"
                );
            }
        }

        // Opponents are visible only as counts and public info.
        assert_eq!(view.opponents.len(), 5);
        assert!(view.opponents.iter().all(|o| o.card_count == 8));
    }
}

#[test]
fn projection_shows_legal_actions_only_for_current_player() {
    let mut engine = engine_with_seed(13);
    engine.start_game().unwrap();

    let bidder = current_player(&engine);
    let other = engine.state().players.iter().find(|p| p.id != bidder).unwrap().id;

    let bidder_view = engine.view_for(bidder).unwrap();
    assert_eq!(bidder_view.legal_actions.legal_bids, (0..=8).collect::<Vec<u8>>());

    let other_view = engine.view_for(other).unwrap();
    assert!(other_view.legal_actions.legal_bids.is_empty());
    assert!(other_view.legal_actions.playable_cards.is_empty());
}

#[test]
fn view_for_unknown_player_is_rejected() {
    let mut engine = engine_with_seed(14);
    engine.start_game().unwrap();
    assert_eq!(engine.view_for(PlayerId::new()), Err(GameError::PlayerNotInGame));
}

#[test]
fn last_trick_of_round_pauses_in_round_scoring_with_reveal() {
    let mut engine = GameEngine::new_with_seed(
        9,
        GameId::new(),
        GameRules {
            trump_rule: TrumpRule::rotating_from(Suit::Spades),
            turn_timeout_seconds: None,
            round_pattern: RoundPattern::Custom { rounds: vec![1, 1] },
            ..GameRules::mvp_for_players(3)
        },
        (0..3)
            .map(|seat| PlayerState::human(PlayerId::new(), format!("P{seat}"), seat))
            .collect(),
    )
    .unwrap();
    engine.start_game().unwrap();
    bid_all(&mut engine);
    while engine.phase() == GamePhase::Playing {
        play_one_card(&mut engine);
    }
    assert_eq!(engine.phase(), GamePhase::RoundScoring);
    let viewer = engine.state().player_ids()[0];
    let view = engine.view_for(viewer).unwrap();
    assert!(view.current_trick.is_empty());
    assert!(
        view.last_completed_trick.is_some(),
        "clients need the last trick while RoundScoring holds"
    );
    assert_eq!(view.round.as_ref().unwrap().round_index, 0);

    engine.advance_from_round_scoring().unwrap();
    assert_eq!(engine.phase(), GamePhase::Bidding);
    assert_eq!(
        engine.state().current_round.as_ref().unwrap().round_index,
        1
    );
}

#[test]
fn projection_keeps_last_completed_trick_until_next_lead() {
    let mut engine = engine_with_seed(21);
    engine.start_game().unwrap();
    bid_all(&mut engine);

    let mut winner = None;
    for _ in 0..6 {
        for event in play_one_card(&mut engine) {
            if let GameEvent::TrickCompleted { winner: w, .. } = event {
                winner = Some(w);
            }
        }
    }
    let winner = winner.expect("trick completed");
    let viewer = engine.state().player_ids()[0];
    let view = engine.view_for(viewer).unwrap();
    assert!(view.current_trick.is_empty());
    let completed = view.last_completed_trick.expect("completed trick projected");
    assert_eq!(completed.winner_id, winner);
    assert_eq!(completed.plays.len(), 6);

    play_one_card(&mut engine);
    let view = engine.view_for(viewer).unwrap();
    assert_eq!(view.current_trick.len(), 1);
    assert!(view.last_completed_trick.is_none());
}

#[test]
fn projection_exposes_round_history_and_leader() {
    let mut engine = GameEngine::new_with_seed(
        3,
        GameId::new(),
        GameRules {
            trump_rule: TrumpRule::rotating_from(Suit::Spades),
            turn_timeout_seconds: None,
            round_pattern: RoundPattern::Custom { rounds: vec![1, 1] },
            ..GameRules::mvp_for_players(3)
        },
        (0..3)
            .map(|seat| PlayerState::human(PlayerId::new(), format!("P{seat}"), seat))
            .collect(),
    )
    .unwrap();
    engine.start_game().unwrap();
    while !engine.is_finished() {
        match engine.phase() {
            GamePhase::Bidding => bid_all(&mut engine),
            GamePhase::Playing => {
                play_one_card(&mut engine);
            }
            GamePhase::RoundScoring => {
                engine.advance_from_round_scoring().unwrap();
            }
            _ => break,
        }
    }
    // After first round scoring, history should be non-empty while game may continue.
    // Re-run a 1-round game and inspect mid-finish.
    let mut engine = GameEngine::new_with_seed(
        4,
        GameId::new(),
        GameRules {
            trump_rule: TrumpRule::rotating_from(Suit::Spades),
            turn_timeout_seconds: None,
            round_pattern: RoundPattern::Custom { rounds: vec![1] },
            ..GameRules::mvp_for_players(3)
        },
        (0..3)
            .map(|seat| {
                PlayerState::human(PlayerId::new(), format!("P{seat}"), seat).with_avatar("fox")
            })
            .collect(),
    )
    .unwrap();
    engine.start_game().unwrap();
    while !engine.is_finished() {
        match engine.phase() {
            GamePhase::Bidding => bid_all(&mut engine),
            GamePhase::Playing => {
                let _ = play_one_card(&mut engine);
            }
            GamePhase::RoundScoring => {
                engine.advance_from_round_scoring().unwrap();
            }
            _ => break,
        }
    }
    let viewer = engine.state().player_ids()[0];
    let view = engine.view_for(viewer).unwrap();
    assert!(!view.round_history.is_empty());
    assert!(view.leader.is_some());
    assert_eq!(view.own_avatar_id.as_deref(), Some("fox"));
}

#[test]
fn ace_high_trick_example() {
    // Deterministic check that within the lead suit the Ace outranks a King:
    // covered exhaustively in trick.rs unit tests, exercised here end-to-end
    // via a full game where invariants (exactly one winner per trick) hold.
    let engine = run_full_game(15);
    let state = engine.state();
    let round = state.current_round.as_ref().unwrap();
    let total_tricks: u32 = round.tricks_won.values().map(|&t| t as u32).sum();
    assert_eq!(total_tricks, round.completed_tricks.len() as u32);
    for suit_check in &round.completed_tricks {
        assert_eq!(suit_check.plays.len(), 6, "every trick has exactly six plays");
    }
}
