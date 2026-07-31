//! Post-game player analysis (PLAN.md §18.6).

use judgement_domain::{PlayerId, RankedPlayer, ScoreTable};
use serde::{Deserialize, Serialize};

use crate::round::{summarize_round, RoundOutcome, RoundSummary};
use crate::AnalyticsError;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NotableRound {
    pub round_index: usize,
    pub kind: String,
    pub evidence: String,
}

/// Deterministic feature extraction for coaching. Every field is derived from
/// the score table / ranking — never invented by an LLM.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct PlayerGameAnalysis {
    pub player_id: PlayerId,
    pub exact_bid_rounds: u8,
    pub total_rounds: u8,
    pub overbid_rounds: u8,
    pub underbid_rounds: u8,
    pub strongest_round: Option<usize>,
    pub weakest_round: Option<usize>,
    pub longest_exact_streak: u8,
    pub total_score: i32,
    pub final_rank: Option<u32>,
    pub bid_accuracy: u8,
    pub notable_rounds: Vec<NotableRound>,
    pub round_summaries: Vec<RoundSummary>,
}

pub fn analyse_player(
    table: &ScoreTable,
    player_id: PlayerId,
    ranking: Option<&[RankedPlayer]>,
) -> Result<PlayerGameAnalysis, AnalyticsError> {
    if table.rounds.is_empty() {
        return Err(AnalyticsError::EmptyGame);
    }

    let mut exact = 0u8;
    let mut over = 0u8;
    let mut under = 0u8;
    let mut streak = 0u8;
    let mut best_streak = 0u8;
    let mut strongest: Option<(usize, i32)> = None;
    let mut weakest: Option<(usize, i32)> = None;
    let mut summaries = Vec::new();
    let mut notable = Vec::new();

    for (round_index, round) in table.rounds.iter().enumerate() {
        let Some(entry) = round.get(&player_id) else {
            continue;
        };
        let summary = summarize_round(round_index, player_id, entry);
        match summary.outcome {
            RoundOutcome::Exact => {
                exact = exact.saturating_add(1);
                streak = streak.saturating_add(1);
                best_streak = best_streak.max(streak);
            }
            RoundOutcome::Over => {
                over = over.saturating_add(1);
                streak = 0;
                notable.push(NotableRound {
                    round_index,
                    kind: "overbid".into(),
                    evidence: format!(
                        "Won {} with a bid of {} ({} extra).",
                        entry.tricks_won, entry.bid, summary.trick_delta
                    ),
                });
            }
            RoundOutcome::Under => {
                under = under.saturating_add(1);
                streak = 0;
                notable.push(NotableRound {
                    round_index,
                    kind: "underbid".into(),
                    evidence: format!(
                        "Won {} with a bid of {} ({} short).",
                        entry.tricks_won,
                        entry.bid,
                        summary.trick_delta.abs()
                    ),
                });
            }
        }

        strongest = Some(match strongest {
            Some((idx, score)) if score >= entry.score => (idx, score),
            _ => (round_index, entry.score),
        });
        weakest = Some(match weakest {
            Some((idx, score)) if score <= entry.score => (idx, score),
            _ => (round_index, entry.score),
        });

        summaries.push(summary);
    }

    if summaries.is_empty() {
        return Err(AnalyticsError::PlayerNotFound);
    }

    let total_rounds = summaries.len() as u8;
    let bid_accuracy = if total_rounds == 0 {
        0
    } else {
        ((exact as u16 * 100) / total_rounds as u16) as u8
    };

    let final_rank = ranking.and_then(|rows| {
        rows.iter()
            .find(|r| r.player_id == player_id)
            .map(|r| r.rank)
    });

    Ok(PlayerGameAnalysis {
        player_id,
        exact_bid_rounds: exact,
        total_rounds,
        overbid_rounds: over,
        underbid_rounds: under,
        strongest_round: strongest.map(|(i, _)| i),
        weakest_round: weakest.map(|(i, _)| i),
        longest_exact_streak: best_streak,
        total_score: table.total_score(player_id),
        final_rank,
        bid_accuracy,
        notable_rounds: notable,
        round_summaries: summaries,
    })
}
