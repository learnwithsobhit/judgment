//! Rebuild a [`ScoreTable`] from persisted round-result JSON.

use std::collections::HashMap;

use judgement_domain::{PlayerId, RoundScoreEntry, ScoreTable};
use serde_json::Value;

use crate::AnalyticsError;

/// Parse one round's `scores` JSON blob into player → entry.
pub fn scores_from_value(value: &Value) -> Result<HashMap<PlayerId, RoundScoreEntry>, AnalyticsError> {
    serde_json::from_value(value.clone())
        .map_err(|e| AnalyticsError::InvalidScores(e.to_string()))
}

/// Rebuild the full score table from ordered `(round_index, scores)` pairs.
pub fn score_table_from_rounds(
    rounds: &[(usize, &Value)],
) -> Result<ScoreTable, AnalyticsError> {
    let mut indexed: Vec<(usize, HashMap<PlayerId, RoundScoreEntry>)> = rounds
        .iter()
        .map(|(idx, value)| Ok((*idx, scores_from_value(value)?)))
        .collect::<Result<_, AnalyticsError>>()?;
    indexed.sort_by_key(|(idx, _)| *idx);

    let mut table = ScoreTable::default();
    for (idx, entries) in indexed {
        while table.rounds.len() < idx {
            table.rounds.push(HashMap::new());
        }
        if table.rounds.len() == idx {
            table.record_round(entries);
        } else {
            table.rounds[idx] = entries;
        }
    }
    Ok(table)
}

/// Convenience: history-style round results.
pub fn score_table_from_history_scores(
    rounds: impl IntoIterator<Item = (usize, Value)>,
) -> Result<ScoreTable, AnalyticsError> {
    let owned: Vec<(usize, Value)> = rounds.into_iter().collect();
    let refs: Vec<(usize, &Value)> = owned.iter().map(|(i, v)| (*i, v)).collect();
    score_table_from_rounds(&refs)
}
