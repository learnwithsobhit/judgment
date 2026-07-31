//! Explanation evaluation dataset (PLAN.md §22 / Phase 7 exit criteria).

use judgement_ai::{
    explain_game_error, explain_trick, ExplanationService, FaqIndex, RulesQueryRequest,
};
use judgement_domain::{CardId, GameError, Rank, Suit};
use judgement_engine::{explain_trick_winner, PlayedCard};
use judgement_domain::{Card, PlayerId};

#[test]
fn faq_core_questions_resolve_with_citations() {
    let index = FaqIndex::default();
    let cases = [
        ("How do points work?", "scoring-exact-001"),
        ("Must I follow suit?", "follow-suit-001"),
        ("How is trump chosen?", "trump-001"),
        ("What can I bid?", "bidding-001"),
        ("Does trump beat ace?", "trump-001"),
    ];
    for (question, expected_ref) in cases {
        let answer = index.lookup(question).unwrap_or_else(|| panic!("no FAQ for {question}"));
        assert!(
            answer.rule_references.iter().any(|r| r == expected_ref),
            "question {question:?} missing citation {expected_ref}; got {:?}",
            answer.rule_references
        );
        assert!(answer.confidence >= 0.45);
        assert!(!answer.answer.is_empty());
    }
}

#[test]
fn invalid_move_templates_cover_reason_codes() {
    let errors = [
        GameError::NotYourTurn,
        GameError::WrongPhase,
        GameError::MustFollowSuit {
            lead_suit: Suit::Spades,
            attempted: CardId { suit: Suit::Hearts, rank: Rank::Ace },
        },
        GameError::BidOutOfRange { bid: 9, max: 8 },
        GameError::DealerBidRestriction { bid: 3, tricks_available: 8 },
        GameError::CardNotInHand {
            card: CardId { suit: Suit::Clubs, rank: Rank::Two },
        },
    ];
    for err in errors {
        let response = explain_game_error(&err);
        assert!(!response.rule_references.is_empty(), "{err:?}");
        assert!(response.deterministic);
        assert!(response.confidence >= 0.9);
    }
}

#[test]
fn trick_winner_explanation_matches_engine_facts() {
    let (a, b, c) = (PlayerId::new(), PlayerId::new(), PlayerId::new());
    let plays = [
        PlayedCard {
            player_id: a,
            card: Card::new(Suit::Clubs, Rank::Ace),
        },
        PlayedCard {
            player_id: b,
            card: Card::new(Suit::Hearts, Rank::Two),
        },
        PlayedCard {
            player_id: c,
            card: Card::new(Suit::Clubs, Rank::King),
        },
    ];
    let facts = explain_trick_winner(Suit::Clubs, Some(Suit::Hearts), &plays).expect("ok");
    assert_eq!(facts.winner, b);
    assert_eq!(facts.reason_code, "TRUMP_BEATS_LEAD_SUIT");

    let response = explain_trick(
        &facts.reason_code,
        facts.lead_suit.name(),
        facts.trump_suit.map(|s| s.name()),
        &facts.winner.to_string(),
    );
    assert!(response.rule_references.contains(&"trump-001".into()));
    assert!(response.answer.to_lowercase().contains("trump"));
}

#[tokio::test]
async fn service_query_faq_path() {
    let service = ExplanationService::default();
    assert!(!service.rag_enabled());
    let response = service
        .query(
            "session-a",
            &RulesQueryRequest {
                question: Some("Can I bid zero?".into()),
                ..Default::default()
            },
        )
        .await
        .expect("rate ok");
    assert!(response.rule_references.contains(&"bidding-001".into()));
}

#[tokio::test]
async fn cost_cap_keeps_deterministic_answer() {
    use std::sync::Arc;

    use judgement_ai::{AiLimits, ExplanationService, ToneRewriter};

    struct CountingRewriter;
    impl ToneRewriter for CountingRewriter {
        fn rewrite(
            &self,
            mut draft: judgement_ai::ExplanationResponse,
        ) -> judgement_ai::ExplanationResponse {
            draft.deterministic = false;
            draft.answer = format!("rewritten: {}", draft.answer);
            draft
        }
    }

    let limits = AiLimits {
        max_cost_units_per_window: 400,
        rewrite_cost_units: 400,
        max_requests_per_window: 100,
        ..AiLimits::default()
    };
    let service = ExplanationService::new(limits, Arc::new(CountingRewriter), None);
    let first = service
        .query(
            "cap",
            &RulesQueryRequest {
                question: Some("Must I follow suit?".into()),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    assert!(!first.deterministic);
    assert!(first.answer.starts_with("rewritten:"));

    let second = service
        .query(
            "cap",
            &RulesQueryRequest {
                question: Some("Must I follow suit?".into()),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    assert!(second.deterministic);
    assert_eq!(second.fallback_reason.as_deref(), Some("cost_cap"));
    assert!(!second.answer.starts_with("rewritten:"));
}

#[tokio::test]
async fn rate_limit_rejects_excess_requests() {
    use judgement_ai::{AiLimits, ExplanationService};

    let service = ExplanationService::with_identity_limits(AiLimits {
        max_requests_per_window: 2,
        ..AiLimits::default()
    });
    let req = RulesQueryRequest {
        question: Some("What is trump?".into()),
        ..Default::default()
    };
    assert!(service.query("rl", &req).await.is_ok());
    assert!(service.query("rl", &req).await.is_ok());
    assert!(service.query("rl", &req).await.is_err());
}

#[tokio::test]
async fn flag_off_does_not_use_rag_for_unknown_question() {
    let service = ExplanationService::default();
    let response = service
        .query(
            "no-rag",
            &RulesQueryRequest {
                question: Some("What is the xyzzy plugh ruleset for quantum bids?".into()),
                ..Default::default()
            },
        )
        .await
        .unwrap();
    assert!(response.confidence <= 0.25);
    assert!(response.answer.contains("could not find"));
}
