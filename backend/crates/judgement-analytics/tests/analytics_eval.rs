//! Analytics evaluation: numbers match the score table; no invented facts.

use std::collections::HashMap;

use judgement_analytics::{
    analyse_player, compute_highlights, summarize_round, HighlightFact, RoundOutcome,
};
use judgement_domain::{PlayerId, RoundScoreEntry, ScoreTable};

fn entry(bid: u8, won: u8, score: i32) -> RoundScoreEntry {
    RoundScoreEntry { bid, tricks_won: won, score }
}

fn sample_table() -> (ScoreTable, PlayerId, PlayerId, PlayerId) {
    let a = PlayerId::new();
    let b = PlayerId::new();
    let c = PlayerId::new();
    let mut table = ScoreTable::default();
    table.record_round(HashMap::from([
        (a, entry(2, 2, 12)),
        (b, entry(1, 2, 0)),
        (c, entry(0, 0, 10)),
    ]));
    table.record_round(HashMap::from([
        (a, entry(1, 0, 0)),
        (b, entry(2, 2, 12)),
        (c, entry(1, 1, 11)),
    ]));
    table.record_round(HashMap::from([
        (a, entry(0, 0, 10)),
        (b, entry(1, 1, 11)),
        (c, entry(2, 3, 0)),
    ]));
    (table, a, b, c)
}

#[test]
fn round_summary_evidence_matches_entry() {
    let pid = PlayerId::new();
    let summary = summarize_round(2, pid, &entry(2, 3, 0));
    assert_eq!(summary.outcome, RoundOutcome::Over);
    assert_eq!(summary.trick_delta, 1);
    assert_eq!(summary.score, 0);
    assert!(summary.evidence.iter().any(|e| e.contains("bid 2")));
    assert_eq!(summary.suggestion_code, "avoid_extra_tricks");
}

#[test]
fn player_analysis_counts_exact_over_under() {
    let (table, a, _, _) = sample_table();
    let ranking = table.final_ranking(&[a]);
    let analysis = analyse_player(&table, a, Some(&ranking)).unwrap();
    assert_eq!(analysis.total_rounds, 3);
    assert_eq!(analysis.exact_bid_rounds, 2); // rounds 0 and 2
    assert_eq!(analysis.underbid_rounds, 1); // round 1
    assert_eq!(analysis.overbid_rounds, 0);
    assert_eq!(analysis.total_score, 22);
    assert_eq!(analysis.bid_accuracy, 66);
    assert_eq!(analysis.strongest_round, Some(0));
    assert_eq!(analysis.weakest_round, Some(1));
}

#[test]
fn highlights_trace_to_scores() {
    let (table, a, b, c) = sample_table();
    let players = [a, b, c];
    let ranking = table.final_ranking(&players);
    let highlights = compute_highlights(&table, &players, &ranking).unwrap();

    assert!(highlights.facts.iter().any(|f| matches!(
        f,
        HighlightFact::MostAccurateBidder { exact_rounds: 2, .. }
    )));
    assert!(highlights.facts.iter().any(|f| matches!(
        f,
        HighlightFact::FinalMargin { margin, .. } if *margin >= 0
    )));
    assert!(highlights.facts.iter().any(|f| matches!(
        f,
        HighlightFact::BestSingleRound { score: 12, .. }
    )));
}

#[test]
fn coaching_inputs_never_exceed_recorded_rounds() {
    let (table, a, b, c) = sample_table();
    for pid in [a, b, c] {
        let analysis = analyse_player(&table, pid, None).unwrap();
        assert_eq!(
            analysis.exact_bid_rounds + analysis.overbid_rounds + analysis.underbid_rounds,
            analysis.total_rounds
        );
        for notable in &analysis.notable_rounds {
            assert!(notable.round_index < table.rounds.len());
        }
    }
}
