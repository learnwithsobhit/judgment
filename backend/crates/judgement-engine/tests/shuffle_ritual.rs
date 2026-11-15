//! Dealer shuffle ritual: flag off = instant deal; flag on = hold + reshuffle + deal.

use judgement_domain::{GameId, GameRules, PlayerId, PlayerState};
use judgement_engine::{GameEngine, GameEvent, GamePhase};

fn four_players() -> Vec<PlayerState> {
    (0..4)
        .map(|seat| PlayerState::human(PlayerId::new(), format!("P{seat}"), seat))
        .collect()
}

#[test]
fn flag_off_starts_in_bidding_with_hands() {
    let rules = GameRules {
        dealer_shuffle_ritual: false,
        table_sfx: false,
        turn_timeout_seconds: None,
        bid_timeout_seconds: None,
        ..GameRules::mvp_for_players(4)
    };
    let mut engine = GameEngine::new_with_seed(11, GameId::new(), rules, four_players()).unwrap();
    let events = engine.start_game().unwrap();
    assert!(events.iter().any(|e| matches!(e, GameEvent::CardsDealt { .. })));
    assert!(events
        .iter()
        .all(|e| !matches!(e, GameEvent::ShuffleReady { .. })));
    assert_eq!(engine.phase(), GamePhase::Bidding);
    let viewer = engine.state().players[0].id;
    let view = engine.view_for(viewer).unwrap();
    assert!(view.shuffle.is_none());
    assert!(!view.own_hand.is_empty());
}

#[test]
fn flag_on_holds_dealing_until_deal() {
    let rules = GameRules {
        dealer_shuffle_ritual: true,
        table_sfx: false,
        turn_timeout_seconds: None,
        bid_timeout_seconds: None,
        ..GameRules::mvp_for_players(4)
    };
    let mut engine = GameEngine::new_with_seed(22, GameId::new(), rules, four_players()).unwrap();
    let events = engine.start_game().unwrap();
    assert!(events
        .iter()
        .any(|e| matches!(e, GameEvent::ShuffleReady { .. })));
    assert!(events
        .iter()
        .all(|e| !matches!(e, GameEvent::CardsDealt { .. })));
    assert_eq!(engine.phase(), GamePhase::Dealing);

    let dealer = engine.state().dealer;
    let other = engine
        .state()
        .players
        .iter()
        .map(|p| p.id)
        .find(|id| *id != dealer)
        .unwrap();

    assert!(engine.reshuffle_deck(other).is_err());
    assert!(engine.deal_cards(other).is_err());

    let before = engine.state().deck.clone();
    engine.reshuffle_deck(dealer).unwrap();
    assert_ne!(engine.state().deck, before);
    assert_eq!(engine.state().shuffle_index, 2);

    let view = engine.view_for(dealer).unwrap();
    assert!(view.own_hand.is_empty());
    let shuffle = view.shuffle.expect("ritual view");
    assert!(shuffle.can_deal);
    assert!(shuffle.can_shuffle);
    assert_eq!(shuffle.shuffle_index, 2);

    engine.deal_cards(dealer).unwrap();
    assert_eq!(engine.phase(), GamePhase::Bidding);
    let after = engine.view_for(dealer).unwrap();
    assert!(after.shuffle.is_none());
    assert!(!after.own_hand.is_empty());
}

#[test]
fn auto_deal_commits_without_dealer_command() {
    let rules = GameRules {
        dealer_shuffle_ritual: true,
        table_sfx: false,
        turn_timeout_seconds: None,
        bid_timeout_seconds: None,
        ..GameRules::mvp_for_players(4)
    };
    let mut engine = GameEngine::new_with_seed(33, GameId::new(), rules, four_players()).unwrap();
    engine.start_game().unwrap();
    engine.auto_deal_cards().unwrap();
    assert_eq!(engine.phase(), GamePhase::Bidding);
}
