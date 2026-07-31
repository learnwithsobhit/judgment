//! Structured AI / explanation responses (PLAN.md §18.1).

use serde::{Deserialize, Serialize};

/// Advisory response shape returned by every explanation path.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ExplanationResponse {
    pub answer: String,
    pub rule_references: Vec<String>,
    pub confidence: f32,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub suggested_action: Option<String>,
    /// True when the answer came from templates/FAQ without an LLM rewrite.
    #[serde(default)]
    pub deterministic: bool,
    /// Populated when rate/cost limits forced a fallback or blocked rewrite.
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub fallback_reason: Option<String>,
}

impl ExplanationResponse {
    pub fn deterministic(
        answer: impl Into<String>,
        rule_references: Vec<String>,
        confidence: f32,
    ) -> Self {
        Self {
            answer: answer.into(),
            rule_references,
            confidence,
            suggested_action: None,
            deterministic: true,
            fallback_reason: None,
        }
    }

    pub fn with_suggested_action(mut self, action: impl Into<String>) -> Self {
        self.suggested_action = Some(action.into());
        self
    }

    pub fn with_fallback(mut self, reason: impl Into<String>) -> Self {
        self.fallback_reason = Some(reason.into());
        self
    }
}

/// Request body for `POST /api/v1/ai/rules/query`.
#[derive(Debug, Clone, Default, Deserialize, Serialize)]
pub struct RulesQueryRequest {
    /// Free-text question (FAQ path).
    #[serde(default)]
    pub question: Option<String>,
    /// Engine reason code for invalid-move explanations (§18.2).
    #[serde(default)]
    pub reason_code: Option<String>,
    /// Optional structured facts for template filling (never includes hidden cards).
    #[serde(default)]
    pub facts: Option<serde_json::Value>,
    /// Completed-trick facts for winner explanation (§18.3).
    #[serde(default)]
    pub trick: Option<TrickQuery>,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct TrickQuery {
    pub lead_suit: judgement_domain::Suit,
    #[serde(default)]
    pub trump_suit: Option<judgement_domain::Suit>,
    pub plays: Vec<TrickPlayQuery>,
    pub winner: judgement_domain::PlayerId,
    pub reason_code: String,
}

#[derive(Debug, Clone, Deserialize, Serialize)]
pub struct TrickPlayQuery {
    pub player_id: judgement_domain::PlayerId,
    pub card: judgement_domain::CardId,
}
