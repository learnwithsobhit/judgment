//! Per-round explanation facts (PLAN.md §18.5).

use judgement_domain::{PlayerId, RoundScoreEntry};
use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum RoundOutcome {
    Exact,
    Over,
    Under,
}

impl RoundOutcome {
    pub fn from_entry(entry: &RoundScoreEntry) -> Self {
        match entry.tricks_won.cmp(&entry.bid) {
            std::cmp::Ordering::Equal => Self::Exact,
            std::cmp::Ordering::Greater => Self::Over,
            std::cmp::Ordering::Less => Self::Under,
        }
    }
}

/// Deterministic round summary for one player.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RoundSummary {
    pub round_index: usize,
    pub player_id: PlayerId,
    pub bid: u8,
    pub tricks_won: u8,
    pub score: i32,
    /// `tricks_won as i16 - bid as i16`.
    pub trick_delta: i16,
    pub outcome: RoundOutcome,
    /// Stable suggestion code for templating (never LLM-invented).
    pub suggestion_code: String,
    pub evidence: Vec<String>,
}

pub fn summarize_round(
    round_index: usize,
    player_id: PlayerId,
    entry: &RoundScoreEntry,
) -> RoundSummary {
    let outcome = RoundOutcome::from_entry(entry);
    let trick_delta = entry.tricks_won as i16 - entry.bid as i16;
    let (suggestion_code, evidence) = match outcome {
        RoundOutcome::Exact => (
            "keep_exact_discipline".into(),
            vec![format!(
                "Round {}: bid {} and took exactly {} trick(s) for {} point(s).",
                round_index + 1,
                entry.bid,
                entry.tricks_won,
                entry.score
            )],
        ),
        RoundOutcome::Over => (
            "avoid_extra_tricks".into(),
            vec![
                format!(
                    "Round {}: bid {} but won {} ({} over).",
                    round_index + 1,
                    entry.bid,
                    entry.tricks_won,
                    trick_delta
                ),
                "Once your bid is made, prefer safe undertricks over collecting extras."
                    .into(),
            ],
        ),
        RoundOutcome::Under => (
            "protect_needed_tricks".into(),
            vec![
                format!(
                    "Round {}: bid {} but won only {} ({} under).",
                    round_index + 1,
                    entry.bid,
                    entry.tricks_won,
                    trick_delta.abs()
                ),
                "Count sure winners before bidding; lead winners earlier when short."
                    .into(),
            ],
        ),
    };

    RoundSummary {
        round_index,
        player_id,
        bid: entry.bid,
        tricks_won: entry.tricks_won,
        score: entry.score,
        trick_delta,
        outcome,
        suggestion_code,
        evidence,
    }
}
