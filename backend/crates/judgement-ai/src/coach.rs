//! Deterministic coaching and highlight narration (PLAN.md §18.5–18.8).
//!
//! Optional LLM rewrite may soften tone only; facts always come from analytics.
//! On timeout / unavailability, return these templates unchanged.

use judgement_analytics::{GameHighlights, HighlightFact, PlayerGameAnalysis, RoundSummary};

use crate::types::ExplanationResponse;

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct CoachingResponse {
    pub player_id: judgement_domain::PlayerId,
    pub headline: String,
    pub overall: String,
    pub strongest_round: Option<String>,
    pub weakest_round: Option<String>,
    pub risk_pattern: String,
    pub improvements: Vec<String>,
    pub positive: String,
    pub evidence: Vec<String>,
    pub analysis: PlayerGameAnalysis,
    pub deterministic: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fallback_reason: Option<String>,
}

#[derive(Debug, Clone, serde::Serialize, serde::Deserialize)]
pub struct HighlightsResponse {
    pub lines: Vec<String>,
    pub facts: GameHighlights,
    pub deterministic: bool,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fallback_reason: Option<String>,
}

/// Render a coaching response solely from verified analytics.
pub fn coach_from_analysis(analysis: &PlayerGameAnalysis) -> CoachingResponse {
    let accuracy = analysis.bid_accuracy;
    let headline = format!(
        "Bid accuracy {}% ({}/{} exact rounds), total score {}{}",
        accuracy,
        analysis.exact_bid_rounds,
        analysis.total_rounds,
        analysis.total_score,
        analysis
            .final_rank
            .map(|r| format!(", finished #{r}"))
            .unwrap_or_default()
    );

    let overall = format!(
        "Across {} rounds you hit {} bids exactly, overshot {} time(s), and fell short {} time(s).",
        analysis.total_rounds,
        analysis.exact_bid_rounds,
        analysis.overbid_rounds,
        analysis.underbid_rounds
    );

    let strongest_round = analysis.strongest_round.map(|idx| {
        let s = analysis
            .round_summaries
            .iter()
            .find(|r| r.round_index == idx);
        match s {
            Some(r) => format!(
                "Strongest round: #{} — bid {}, won {}, scored {}.",
                idx + 1,
                r.bid,
                r.tricks_won,
                r.score
            ),
            None => format!("Strongest round: #{}", idx + 1),
        }
    });

    let weakest_round = analysis.weakest_round.map(|idx| {
        let s = analysis
            .round_summaries
            .iter()
            .find(|r| r.round_index == idx);
        match s {
            Some(r) => format!(
                "Weakest round: #{} — bid {}, won {}, scored {}.",
                idx + 1,
                r.bid,
                r.tricks_won,
                r.score
            ),
            None => format!("Weakest round: #{}", idx + 1),
        }
    });

    let risk_pattern = if analysis.overbid_rounds > analysis.underbid_rounds {
        format!(
            "Risk pattern: you collected extra tricks more often than you fell short ({} over vs {} under). After making your bid, dump winners carefully.",
            analysis.overbid_rounds, analysis.underbid_rounds
        )
    } else if analysis.underbid_rounds > analysis.overbid_rounds {
        format!(
            "Risk pattern: you fell short of your bid more often than you overshot ({} under vs {} over). Count sure winners before bidding.",
            analysis.underbid_rounds, analysis.overbid_rounds
        )
    } else if analysis.exact_bid_rounds == analysis.total_rounds {
        "Risk pattern: perfect exact-bid discipline this game.".into()
    } else {
        format!(
            "Risk pattern: balanced misses ({} over, {} under).",
            analysis.overbid_rounds, analysis.underbid_rounds
        )
    };

    let mut improvements = Vec::new();
    if analysis.overbid_rounds > 0 {
        improvements.push(
            "When your bid is already made, avoid leading remaining winners unless you must follow."
                .into(),
        );
    }
    if analysis.underbid_rounds > 0 {
        improvements.push(
            "Before bidding, tally ace/king winners and trump length; shade bids down when short on entries."
                .into(),
        );
    }
    if analysis.longest_exact_streak >= 2 {
        improvements.push(format!(
            "You strung together {} exact rounds — keep that same bid conservatism on longer hands.",
            analysis.longest_exact_streak
        ));
    }
    improvements.truncate(2);
    if improvements.is_empty() {
        improvements.push("Keep tracking remaining trump and your bid status each trick.".into());
    }

    let positive = if accuracy >= 70 {
        format!(
            "Positive: {accuracy}% exact-bid accuracy is strong for a {}-round match.",
            analysis.total_rounds
        )
    } else if analysis.longest_exact_streak >= 2 {
        format!(
            "Positive: longest exact-bid streak was {} rounds.",
            analysis.longest_exact_streak
        )
    } else if analysis.total_score > 0 {
        format!(
            "Positive: you still banked {} points despite the misses.",
            analysis.total_score
        )
    } else {
        "Positive: every round gives clearer bid feedback — use the round summaries below.".into()
    };

    let mut evidence: Vec<String> = analysis
        .notable_rounds
        .iter()
        .map(|n| format!("Round {}: {}", n.round_index + 1, n.evidence))
        .collect();
    for summary in &analysis.round_summaries {
        if matches!(
            summary.outcome,
            judgement_analytics::RoundOutcome::Exact
        ) {
            continue;
        }
        evidence.extend(summary.evidence.iter().cloned());
    }
    evidence.dedup();
    evidence.truncate(8);

    CoachingResponse {
        player_id: analysis.player_id,
        headline,
        overall,
        strongest_round,
        weakest_round,
        risk_pattern,
        improvements,
        positive,
        evidence,
        analysis: analysis.clone(),
        deterministic: true,
        fallback_reason: None,
    }
}

pub fn narrate_highlights(highlights: &GameHighlights) -> HighlightsResponse {
    let lines = highlights.facts.iter().map(narrate_fact).collect();
    HighlightsResponse {
        lines,
        facts: highlights.clone(),
        deterministic: true,
        fallback_reason: None,
    }
}

pub fn narrate_round_summary(summary: &RoundSummary) -> ExplanationResponse {
    let mut answer = summary.evidence.join(" ");
    if answer.is_empty() {
        answer = format!(
            "Round {}: bid {}, won {}, scored {}.",
            summary.round_index + 1,
            summary.bid,
            summary.tricks_won,
            summary.score
        );
    }
    ExplanationResponse::deterministic(
        answer,
        vec!["scoring-exact-001".into(), "bidding-001".into()],
        0.99,
    )
    .with_suggested_action(summary.suggestion_code.clone())
}

fn narrate_fact(fact: &HighlightFact) -> String {
    match fact {
        HighlightFact::MostAccurateBidder {
            player_id,
            exact_rounds,
            total_rounds,
        } => format!(
            "Most accurate bidder: {player_id} hit {exact_rounds}/{total_rounds} exact bids."
        ),
        HighlightFact::BestSingleRound {
            player_id,
            round_index,
            score,
            bid,
            tricks_won,
        } => format!(
            "Best single round: {player_id} scored {score} in round {} (bid {bid}, won {tricks_won}).",
            round_index + 1
        ),
        HighlightFact::ClosestMiss {
            player_id,
            round_index,
            bid,
            tricks_won,
        } => format!(
            "Closest miss: {player_id} bid {bid} and took {tricks_won} in round {}.",
            round_index + 1
        ),
        HighlightFact::BiggestComeback {
            player_id,
            early_score,
            final_score,
        } => format!(
            "Biggest comeback: {player_id} moved from {early_score} after round 1 to {final_score} overall."
        ),
        HighlightFact::FinalMargin { winner_ids, margin } => {
            let winners = winner_ids
                .iter()
                .map(|id| id.to_string())
                .collect::<Vec<_>>()
                .join(", ");
            format!("Final margin: {winners} won by {margin} point(s).")
        }
        HighlightFact::LongestExactBidStreak { player_id, streak } => {
            format!("Longest exact-bid streak: {player_id} with {streak} consecutive rounds.")
        }
    }
}

/// Documented fallback when an optional LLM rewrite times out.
pub fn coaching_timeout_fallback(analysis: &PlayerGameAnalysis) -> CoachingResponse {
    let mut response = coach_from_analysis(analysis);
    response.fallback_reason = Some("ai_timeout".into());
    response
}

pub fn highlights_timeout_fallback(highlights: &GameHighlights) -> HighlightsResponse {
    let mut response = narrate_highlights(highlights);
    response.fallback_reason = Some("ai_timeout".into());
    response
}

#[cfg(test)]
mod tests {
    use std::collections::HashMap;

    use judgement_analytics::analyse_player;
    use judgement_domain::{PlayerId, RoundScoreEntry, ScoreTable};

    use super::*;

    #[test]
    fn coaching_numbers_match_analysis() {
        let a = PlayerId::new();
        let mut table = ScoreTable::default();
        table.record_round(HashMap::from([(
            a,
            RoundScoreEntry { bid: 1, tricks_won: 2, score: 0 },
        )]));
        table.record_round(HashMap::from([(
            a,
            RoundScoreEntry { bid: 0, tricks_won: 0, score: 10 },
        )]));
        let analysis = analyse_player(&table, a, None).unwrap();
        let coach = coach_from_analysis(&analysis);
        assert!(coach.deterministic);
        assert!(coach.overall.contains("1"));
        assert!(coach.evidence.iter().any(|e| e.contains("bid of 1")));
        assert_eq!(coach.analysis.total_score, 10);
        assert!(coach.fallback_reason.is_none());
    }

    #[test]
    fn timeout_fallback_keeps_facts() {
        let a = PlayerId::new();
        let mut table = ScoreTable::default();
        table.record_round(HashMap::from([(
            a,
            RoundScoreEntry { bid: 1, tricks_won: 1, score: 11 },
        )]));
        let analysis = analyse_player(&table, a, None).unwrap();
        let coach = coaching_timeout_fallback(&analysis);
        assert_eq!(coach.fallback_reason.as_deref(), Some("ai_timeout"));
        assert_eq!(coach.analysis.exact_bid_rounds, 1);
    }
}
