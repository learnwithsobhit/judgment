//! Curated FAQ map loaded from `rules/common_questions.md` (PLAN.md §18.1).

use crate::types::ExplanationResponse;

const FAQ_SOURCE: &str = include_str!("../../../../rules/common_questions.md");

#[derive(Debug, Clone)]
pub struct FaqEntry {
    pub id: String,
    pub aliases: Vec<String>,
    pub rule_references: Vec<String>,
    pub answer: String,
}

#[derive(Debug, Clone)]
pub struct FaqIndex {
    entries: Vec<FaqEntry>,
}

impl Default for FaqIndex {
    fn default() -> Self {
        Self::from_markdown(FAQ_SOURCE)
    }
}

impl FaqIndex {
    pub fn from_markdown(source: &str) -> Self {
        let mut entries = Vec::new();
        let mut current_id: Option<String> = None;
        let mut aliases = Vec::new();
        let mut rule_references = Vec::new();
        let mut body = String::new();

        let flush = |entries: &mut Vec<FaqEntry>,
                     id: &mut Option<String>,
                     aliases: &mut Vec<String>,
                     refs: &mut Vec<String>,
                     body: &mut String| {
            if let Some(faq_id) = id.take() {
                let answer = body.trim().to_string();
                if !answer.is_empty() {
                    entries.push(FaqEntry {
                        id: faq_id,
                        aliases: std::mem::take(aliases),
                        rule_references: std::mem::take(refs),
                        answer,
                    });
                }
            }
            aliases.clear();
            refs.clear();
            body.clear();
        };

        for line in source.lines() {
            if let Some(rest) = line.strip_prefix("## ") {
                flush(
                    &mut entries,
                    &mut current_id,
                    &mut aliases,
                    &mut rule_references,
                    &mut body,
                );
                current_id = Some(rest.trim().to_string());
                continue;
            }
            if current_id.is_none() {
                continue;
            }
            if let Some(rest) = line.strip_prefix("**aliases:**") {
                aliases = rest
                    .split(',')
                    .map(|s| normalize_phrase(s))
                    .filter(|s| !s.is_empty())
                    .collect();
                continue;
            }
            if let Some(rest) = line.strip_prefix("**rule_references:**") {
                rule_references = rest
                    .split(',')
                    .map(|s| s.trim().trim_matches('`').to_string())
                    .filter(|s| !s.is_empty())
                    .collect();
                continue;
            }
            if line.starts_with("---") || line.starts_with('#') {
                continue;
            }
            if !body.is_empty() {
                body.push('\n');
            }
            body.push_str(line.trim());
        }
        flush(
            &mut entries,
            &mut current_id,
            &mut aliases,
            &mut rule_references,
            &mut body,
        );

        Self { entries }
    }

    pub fn entries(&self) -> &[FaqEntry] {
        &self.entries
    }

    /// Score the question against aliases; return best match above threshold.
    pub fn lookup(&self, question: &str) -> Option<ExplanationResponse> {
        let q = normalize_phrase(question);
        if q.is_empty() {
            return None;
        }
        let q_tokens = tokens(&q);

        let mut best: Option<(&FaqEntry, f32)> = None;
        for entry in &self.entries {
            let mut score = 0.0_f32;
            for alias in &entry.aliases {
                if q == *alias {
                    score = score.max(1.0);
                } else if q.contains(alias) || alias.contains(&q) {
                    score = score.max(0.85);
                } else {
                    let overlap = token_overlap(&q_tokens, &tokens(alias));
                    score = score.max(overlap);
                }
            }
            // Light boost from id keywords (e.g. "follow-suit").
            let id_key = entry.id.replace("faq.", "").replace('-', " ");
            score = score.max(token_overlap(&q_tokens, &tokens(&id_key)) * 0.7);

            if score >= 0.45 {
                match best {
                    Some((_, best_score)) if score <= best_score => {}
                    _ => best = Some((entry, score)),
                }
            }
        }

        best.map(|(entry, confidence)| {
            ExplanationResponse::deterministic(
                entry.answer.clone(),
                entry.rule_references.clone(),
                confidence.clamp(0.45, 0.99),
            )
        })
    }
}

fn normalize_phrase(s: &str) -> String {
    s.chars()
        .map(|c| if c.is_ascii_alphanumeric() { c.to_ascii_lowercase() } else { ' ' })
        .collect::<String>()
        .split_whitespace()
        .collect::<Vec<_>>()
        .join(" ")
}

fn tokens(s: &str) -> Vec<String> {
    s.split_whitespace()
        .filter(|t| t.len() > 1)
        .map(|t| t.to_string())
        .collect()
}

fn token_overlap(a: &[String], b: &[String]) -> f32 {
    if a.is_empty() || b.is_empty() {
        return 0.0;
    }
    let mut hits = 0usize;
    for t in a {
        if b.iter().any(|x| x == t) {
            hits += 1;
        }
    }
    hits as f32 / a.len().max(b.len()) as f32
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_bundled_faq() {
        let index = FaqIndex::default();
        assert!(index.entries().len() >= 8);
        assert!(index.entries().iter().any(|e| e.id == "faq.follow-suit"));
    }

    #[test]
    fn matches_follow_suit_question() {
        let index = FaqIndex::default();
        let answer = index.lookup("Must I follow suit?").expect("match");
        assert!(answer.rule_references.contains(&"follow-suit-001".into()));
        assert!(answer.confidence >= 0.45);
    }
}
