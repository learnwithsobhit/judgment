//! Reason-code templates for invalid moves and trick winners (PLAN.md §18.2–18.3).

use judgement_domain::GameError;
use serde_json::Value;

use crate::types::ExplanationResponse;

/// Render a deterministic explanation from a `GameError` or bare reason code.
pub fn explain_game_error(error: &GameError) -> ExplanationResponse {
    let code = error.reason_code();
    let (answer, refs, suggested) = match error {
        GameError::NotYourTurn => (
            "It is not your turn. Wait until the table highlights you before bidding or playing."
                .to_string(),
            vec!["basic-gameplay-001".into()],
            None,
        ),
        GameError::WrongPhase => (
            "That action is not allowed in the current phase. Bid only while bidding is open, and play cards only during the play phase."
                .to_string(),
            vec!["basic-gameplay-001".into()],
            None,
        ),
        GameError::CardNotInHand { card } => (
            format!("You cannot play {card} because it is not in your hand."),
            vec!["follow-suit-001".into()],
            None,
        ),
        GameError::MustFollowSuit { lead_suit, attempted } => (
            format!(
                "You must follow {lead_suit}. You still hold at least one {lead_suit} card, so {attempted} is illegal."
            ),
            vec!["follow-suit-001".into()],
            None,
        ),
        GameError::BidOutOfRange { bid, max } => (
            format!(
                "Bid {bid} is outside the allowed range. You may bid any integer from 0 through {max} (the number of cards dealt this round)."
            ),
            vec!["bidding-001".into()],
            Some("0".into()),
        ),
        GameError::DealerBidRestriction { bid, tricks_available } => (
            format!(
                "As dealer you cannot bid {bid}: that would make the sum of all bids equal the {tricks_available} tricks available. Choose a different legal bid."
            ),
            vec!["dealer-restriction-001".into(), "bidding-001".into()],
            None,
        ),
        GameError::BidAlreadyPlaced => (
            "You have already placed your bid for this round.".to_string(),
            vec!["bidding-001".into()],
            None,
        ),
        GameError::StaleState { .. } => (
            "Your client is out of date. The table will refresh; please retry your action."
                .to_string(),
            vec!["basic-gameplay-001".into()],
            None,
        ),
        GameError::ActionAlreadyProcessed => (
            "That action was already processed. No further change was applied.".to_string(),
            vec!["basic-gameplay-001".into()],
            None,
        ),
        GameError::PlayerNotInGame => (
            "You are not seated at this table.".to_string(),
            vec!["basic-gameplay-001".into()],
            None,
        ),
        GameError::GameAlreadyFinished => (
            "The match is already finished. Start a rematch from the lobby if you want another game."
                .to_string(),
            vec!["basic-gameplay-001".into()],
            None,
        ),
        GameError::InvalidPlayerCount { required, actual } => (
            format!("This table needs {required} players but currently has {actual}."),
            vec!["multi-player-001".into()],
            None,
        ),
    };

    let mut response = ExplanationResponse::deterministic(answer, refs, 0.98);
    response.suggested_action = suggested;
    let _ = code; // reason_code is available via GameError for callers that want it
    response
}

/// Template lookup when only a reason code string is available (plus optional facts).
pub fn explain_reason_code(reason_code: &str, facts: Option<&Value>) -> Option<ExplanationResponse> {
    let code = reason_code.trim().to_ascii_uppercase();
    let answer = match code.as_str() {
        "NOT_YOUR_TURN" => Some((
            "It is not your turn. Wait for your turn indicator before acting.".to_string(),
            vec!["basic-gameplay-001".into()],
        )),
        "WRONG_PHASE" => Some((
            "That action is not allowed in the current phase.".to_string(),
            vec!["basic-gameplay-001".into()],
        )),
        "CARD_NOT_IN_HAND" => Some((
            format!(
                "You cannot play a card that is not in your hand.{}",
                fact_suffix(facts, &["card", "attempted"])
            ),
            vec!["follow-suit-001".into()],
        )),
        "MUST_FOLLOW_SUIT" => {
            let lead = fact_str(facts, "lead_suit").unwrap_or_else(|| "the lead suit".into());
            let attempted = fact_str(facts, "attempted").unwrap_or_else(|| "that card".into());
            Some((
                format!(
                    "You must follow {lead}. You still hold at least one card of that suit, so {attempted} is illegal."
                ),
                vec!["follow-suit-001".into()],
            ))
        }
        "BID_OUT_OF_RANGE" => {
            let max = fact_str(facts, "max").unwrap_or_else(|| "the cards dealt".into());
            Some((
                format!("That bid is outside 0..={max}. Choose a bid in range."),
                vec!["bidding-001".into()],
            ))
        }
        "DEALER_BID_RESTRICTION" => Some((
            "As dealer, your bid must not make the sum of all bids equal the tricks available."
                .to_string(),
            vec!["dealer-restriction-001".into(), "bidding-001".into()],
        )),
        "BID_ALREADY_PLACED" => Some((
            "You have already placed your bid for this round.".to_string(),
            vec!["bidding-001".into()],
        )),
        "STALE_STATE" => Some((
            "Your client state is stale; resynchronise and try again.".to_string(),
            vec!["basic-gameplay-001".into()],
        )),
        "ACTION_ALREADY_PROCESSED" => Some((
            "That action was already processed.".to_string(),
            vec!["basic-gameplay-001".into()],
        )),
        "PLAYER_NOT_IN_GAME" => Some((
            "You are not part of this game.".to_string(),
            vec!["basic-gameplay-001".into()],
        )),
        "GAME_ALREADY_FINISHED" => Some((
            "The game is already finished.".to_string(),
            vec!["basic-gameplay-001".into()],
        )),
        "TRUMP_BEATS_LEAD_SUIT" => Some(trick_template_trump_beats(facts)),
        "HIGHEST_TRUMP_WINS" => Some((
            format!(
                "The highest trump card won this trick.{}",
                fact_suffix(facts, &["winner", "trump_suit"])
            ),
            vec!["trump-001".into(), "follow-suit-001".into()],
        )),
        "HIGHEST_LEAD_SUIT_WINS" => Some((
            format!(
                "No trump was played, so the highest card of the lead suit won.{}",
                fact_suffix(facts, &["winner", "lead_suit"])
            ),
            vec!["follow-suit-001".into(), "trump-001".into()],
        )),
        _ => None,
    }?;

    Some(ExplanationResponse::deterministic(answer.0, answer.1, 0.95))
}

fn trick_template_trump_beats(facts: Option<&Value>) -> (String, Vec<String>) {
    let trump = fact_str(facts, "trump_suit").unwrap_or_else(|| "trump".into());
    let lead = fact_str(facts, "lead_suit").unwrap_or_else(|| "the lead suit".into());
    let winner = fact_str(facts, "winner").unwrap_or_else(|| "The trump player".into());
    (
        format!(
            "{winner} won because a {trump} trump was played. Trump beats any card of {lead} that is not trump."
        ),
        vec!["trump-001".into(), "follow-suit-001".into()],
    )
}

/// Explain a verified trick-winner payload (§18.3).
pub fn explain_trick(
    reason_code: &str,
    lead_suit: &str,
    trump_suit: Option<&str>,
    winner: &str,
) -> ExplanationResponse {
    let facts = serde_json::json!({
        "lead_suit": lead_suit,
        "trump_suit": trump_suit,
        "winner": winner,
    });
    explain_reason_code(reason_code, Some(&facts)).unwrap_or_else(|| {
        ExplanationResponse::deterministic(
            format!("{winner} won the trick ({reason_code})."),
            vec!["trump-001".into(), "follow-suit-001".into()],
            0.8,
        )
    })
}

fn fact_str(facts: Option<&Value>, key: &str) -> Option<String> {
    facts
        .and_then(|v| v.get(key))
        .and_then(|v| {
            if v.is_null() {
                None
            } else if let Some(s) = v.as_str() {
                Some(s.to_string())
            } else {
                Some(v.to_string().trim_matches('"').to_string())
            }
        })
}

fn fact_suffix(facts: Option<&Value>, keys: &[&str]) -> String {
    let parts: Vec<String> = keys
        .iter()
        .filter_map(|k| fact_str(facts, k).map(|v| format!("{k}={v}")))
        .collect();
    if parts.is_empty() {
        String::new()
    } else {
        format!(" ({})", parts.join(", "))
    }
}

#[cfg(test)]
mod tests {
    use judgement_domain::{CardId, Rank, Suit};

    use super::*;

    #[test]
    fn must_follow_suit_template() {
        let err = GameError::MustFollowSuit {
            lead_suit: Suit::Spades,
            attempted: CardId { suit: Suit::Hearts, rank: Rank::Ace },
        };
        let response = explain_game_error(&err);
        assert!(response.answer.contains("spades"));
        assert!(response.rule_references.contains(&"follow-suit-001".into()));
        assert!(response.deterministic);
    }

    #[test]
    fn trick_trump_template() {
        let response = explain_trick(
            "TRUMP_BEATS_LEAD_SUIT",
            "clubs",
            Some("hearts"),
            "player-2",
        );
        assert!(response.answer.to_lowercase().contains("trump"));
        assert!(response.rule_references.contains(&"trump-001".into()));
    }
}
