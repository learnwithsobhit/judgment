//! Score bookkeeping and final ranking with the locked tie-break
//! (PLAN.md §0 decision 2, §5.8).

use std::collections::HashMap;

use serde::{Deserialize, Serialize};

use crate::ids::PlayerId;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
pub struct RoundScoreEntry {
    pub bid: u8,
    pub tricks_won: u8,
    pub score: i32,
}

impl RoundScoreEntry {
    pub fn exact(&self) -> bool {
        self.bid == self.tricks_won
    }

    /// Absolute `|bid - won|` for the tie-break.
    pub fn tricks_missed(&self) -> u32 {
        self.bid.abs_diff(self.tricks_won) as u32
    }
}

/// Per-round score entries, one map per completed round.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct ScoreTable {
    pub rounds: Vec<HashMap<PlayerId, RoundScoreEntry>>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RankedPlayer {
    pub player_id: PlayerId,
    /// 1-based competition rank; tied players share a rank (e.g. 1, 1, 3).
    pub rank: u32,
    pub total_score: i32,
    pub exact_bid_rounds: u32,
    pub total_tricks_missed: u32,
}

impl ScoreTable {
    pub fn record_round(&mut self, entries: HashMap<PlayerId, RoundScoreEntry>) {
        self.rounds.push(entries);
    }

    pub fn total_score(&self, player: PlayerId) -> i32 {
        self.rounds
            .iter()
            .filter_map(|round| round.get(&player))
            .map(|entry| entry.score)
            .sum()
    }

    pub fn exact_bid_rounds(&self, player: PlayerId) -> u32 {
        self.rounds
            .iter()
            .filter_map(|round| round.get(&player))
            .filter(|entry| entry.exact())
            .count() as u32
    }

    pub fn total_tricks_missed(&self, player: PlayerId) -> u32 {
        self.rounds
            .iter()
            .filter_map(|round| round.get(&player))
            .map(|entry| entry.tricks_missed())
            .sum()
    }

    /// Final ranking (locked decision 2): highest score, then most exact-bid
    /// rounds, then fewest total tricks missed; still-equal players share rank.
    pub fn final_ranking(&self, players: &[PlayerId]) -> Vec<RankedPlayer> {
        let mut ranked: Vec<RankedPlayer> = players
            .iter()
            .map(|&player_id| RankedPlayer {
                player_id,
                rank: 0,
                total_score: self.total_score(player_id),
                exact_bid_rounds: self.exact_bid_rounds(player_id),
                total_tricks_missed: self.total_tricks_missed(player_id),
            })
            .collect();

        // Better first: score desc, exact rounds desc, missed tricks asc.
        let sort_key = |p: &RankedPlayer| (-(p.total_score as i64), -(p.exact_bid_rounds as i64), p.total_tricks_missed);
        ranked.sort_by_key(sort_key);

        let mut previous_key = None;
        for index in 0..ranked.len() {
            let key = sort_key(&ranked[index]);
            ranked[index].rank = match previous_key {
                Some(prev) if prev == key => ranked[index - 1].rank,
                _ => index as u32 + 1,
            };
            previous_key = Some(key);
        }
        ranked
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(bid: u8, won: u8, score: i32) -> RoundScoreEntry {
        RoundScoreEntry { bid, tricks_won: won, score }
    }

    #[test]
    fn ranking_uses_score_then_exact_rounds_then_missed_tricks() {
        let a = PlayerId::new();
        let b = PlayerId::new();
        let c = PlayerId::new();

        let mut table = ScoreTable::default();
        // Round 1: a exact (12), b exact (12), c misses by 2 (0).
        table.record_round(HashMap::from([
            (a, entry(2, 2, 12)),
            (b, entry(2, 2, 12)),
            (c, entry(2, 4, 0)),
        ]));
        // Round 2: a misses by 1, b misses by 2; equal scores overall.
        table.record_round(HashMap::from([
            (a, entry(1, 2, 0)),
            (b, entry(1, 3, 0)),
            (c, entry(0, 0, 10)),
        ]));

        let ranking = table.final_ranking(&[a, b, c]);
        // a and b both have 12 points and one exact round; a missed fewer tricks.
        assert_eq!(ranking[0].player_id, a);
        assert_eq!(ranking[0].rank, 1);
        assert_eq!(ranking[1].player_id, b);
        assert_eq!(ranking[1].rank, 2);
        assert_eq!(ranking[2].player_id, c);
        assert_eq!(ranking[2].rank, 3);
    }

    #[test]
    fn fully_tied_players_share_rank() {
        let a = PlayerId::new();
        let b = PlayerId::new();
        let c = PlayerId::new();

        let mut table = ScoreTable::default();
        table.record_round(HashMap::from([
            (a, entry(1, 1, 11)),
            (b, entry(1, 1, 11)),
            (c, entry(1, 0, 0)),
        ]));

        let ranking = table.final_ranking(&[a, b, c]);
        assert_eq!(ranking[0].rank, 1);
        assert_eq!(ranking[1].rank, 1);
        assert_eq!(ranking[2].rank, 3, "shared first place skips rank 2");
    }
}
