//! Structured game highlights from deterministic score facts (PLAN.md §18.8).

use judgement_domain::{PlayerId, RankedPlayer, ScoreTable};
use serde::{Deserialize, Serialize};

use crate::AnalyticsError;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "kind")]
pub enum HighlightFact {
    MostAccurateBidder {
        player_id: PlayerId,
        exact_rounds: u32,
        total_rounds: u32,
    },
    BestSingleRound {
        player_id: PlayerId,
        round_index: usize,
        score: i32,
        bid: u8,
        tricks_won: u8,
    },
    ClosestMiss {
        player_id: PlayerId,
        round_index: usize,
        bid: u8,
        tricks_won: u8,
    },
    BiggestComeback {
        player_id: PlayerId,
        early_score: i32,
        final_score: i32,
    },
    FinalMargin {
        winner_ids: Vec<PlayerId>,
        margin: i32,
    },
    LongestExactBidStreak {
        player_id: PlayerId,
        streak: u32,
    },
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct GameHighlights {
    pub facts: Vec<HighlightFact>,
}

pub fn compute_highlights(
    table: &ScoreTable,
    players: &[PlayerId],
    ranking: &[RankedPlayer],
) -> Result<GameHighlights, AnalyticsError> {
    if table.rounds.is_empty() {
        return Err(AnalyticsError::EmptyGame);
    }

    let mut facts = Vec::new();
    let total_rounds = table.rounds.len() as u32;

    if let Some((pid, exact)) = players
        .iter()
        .map(|&pid| (pid, table.exact_bid_rounds(pid)))
        .max_by_key(|(_, e)| *e)
    {
        facts.push(HighlightFact::MostAccurateBidder {
            player_id: pid,
            exact_rounds: exact,
            total_rounds,
        });
    }

    let mut best_round: Option<(PlayerId, usize, i32, u8, u8)> = None;
    let mut closest_miss: Option<(PlayerId, usize, u8, u8, u32)> = None;
    let mut best_streak: Option<(PlayerId, u32)> = None;
    let mut best_comeback: Option<(PlayerId, i32, i32, i32)> = None; // pid, early, final, gain

    for &pid in players {
        let mut streak = 0u32;
        let mut max_streak = 0u32;
        for (round_index, round) in table.rounds.iter().enumerate() {
            let Some(entry) = round.get(&pid) else {
                continue;
            };
            if entry.exact() {
                streak += 1;
                max_streak = max_streak.max(streak);
            } else {
                streak = 0;
                let miss = entry.tricks_missed();
                closest_miss = Some(match closest_miss {
                    Some(prev) if prev.4 <= miss => prev,
                    _ => (pid, round_index, entry.bid, entry.tricks_won, miss),
                });
            }
            best_round = Some(match best_round {
                Some(prev) if prev.2 >= entry.score => prev,
                _ => (pid, round_index, entry.score, entry.bid, entry.tricks_won),
            });
        }
        best_streak = Some(match best_streak {
            Some(prev) if prev.1 >= max_streak => prev,
            _ => (pid, max_streak),
        });

        if table.rounds.len() >= 2 {
            let early = table.rounds[0].get(&pid).map(|e| e.score).unwrap_or(0);
            let final_score = table.total_score(pid);
            let gain = final_score - early;
            if gain > 0 {
                best_comeback = Some(match best_comeback {
                    Some(prev) if prev.3 >= gain => prev,
                    _ => (pid, early, final_score, gain),
                });
            }
        }
    }

    if let Some((player_id, round_index, score, bid, tricks_won)) = best_round {
        if score > 0 {
            facts.push(HighlightFact::BestSingleRound {
                player_id,
                round_index,
                score,
                bid,
                tricks_won,
            });
        }
    }

    if let Some((player_id, round_index, bid, tricks_won, _)) = closest_miss {
        facts.push(HighlightFact::ClosestMiss {
            player_id,
            round_index,
            bid,
            tricks_won,
        });
    }

    if let Some((player_id, streak)) = best_streak.filter(|(_, s)| *s >= 2) {
        facts.push(HighlightFact::LongestExactBidStreak { player_id, streak });
    }

    if let Some((player_id, early_score, final_score, _)) = best_comeback {
        facts.push(HighlightFact::BiggestComeback {
            player_id,
            early_score,
            final_score,
        });
    }

    if ranking.len() >= 2 {
        let winners: Vec<PlayerId> = ranking
            .iter()
            .filter(|r| r.rank == 1)
            .map(|r| r.player_id)
            .collect();
        let winner_score = ranking.iter().find(|r| r.rank == 1).map(|r| r.total_score).unwrap_or(0);
        let runner = ranking
            .iter()
            .find(|r| r.rank > 1)
            .map(|r| r.total_score)
            .unwrap_or(winner_score);
        facts.push(HighlightFact::FinalMargin {
            winner_ids: winners,
            margin: winner_score - runner,
        });
    }

    Ok(GameHighlights { facts })
}
