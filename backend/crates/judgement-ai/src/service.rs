//! Orchestrates FAQ / templates / optional RAG / optional rewrite with rate + cost gates.

use std::sync::Arc;

use judgement_domain::GameError;
use judgement_rag::{RetrievalFilter, RuleRetriever};

use crate::faq::FaqIndex;
use crate::rate_limit::{AiLimits, AiRateLimiter, RateLimitError};
use crate::rewrite::{IdentityRewriter, ToneRewriter};
use crate::templates::{explain_game_error, explain_reason_code, explain_trick};
use crate::types::{ExplanationResponse, RulesQueryRequest};

/// Central AI/explanation service used by the HTTP layer.
pub struct ExplanationService {
    faq: FaqIndex,
    limiter: AiRateLimiter,
    rewriter: Arc<dyn ToneRewriter>,
    /// `None` ⇒ Phase 7 behaviour (FAQ / templates only).
    retriever: Option<Arc<dyn RuleRetriever>>,
    retrieval_filter: RetrievalFilter,
}

impl Default for ExplanationService {
    fn default() -> Self {
        Self::new(AiLimits::default(), Arc::new(IdentityRewriter), None)
    }
}

impl ExplanationService {
    pub fn new(
        limits: AiLimits,
        rewriter: Arc<dyn ToneRewriter>,
        retriever: Option<Arc<dyn RuleRetriever>>,
    ) -> Self {
        Self {
            faq: FaqIndex::default(),
            limiter: AiRateLimiter::new(limits),
            rewriter,
            retriever,
            retrieval_filter: RetrievalFilter::default(),
        }
    }

    pub fn with_identity_limits(limits: AiLimits) -> Self {
        Self::new(limits, Arc::new(IdentityRewriter), None)
    }

    pub fn with_retriever(mut self, retriever: Arc<dyn RuleRetriever>) -> Self {
        self.retriever = Some(retriever);
        self
    }

    pub fn with_retrieval_filter(mut self, filter: RetrievalFilter) -> Self {
        self.retrieval_filter = filter;
        self
    }

    pub fn rag_enabled(&self) -> bool {
        self.retriever.is_some()
    }

    pub fn explain_error(
        &self,
        key: &str,
        error: &GameError,
    ) -> Result<ExplanationResponse, RateLimitError> {
        self.limiter.check_request(key)?;
        Ok(self.maybe_rewrite(key, explain_game_error(error)))
    }

    pub async fn query(
        &self,
        key: &str,
        request: &RulesQueryRequest,
    ) -> Result<ExplanationResponse, RateLimitError> {
        self.limiter.check_request(key)?;

        if let Some(trick) = &request.trick {
            let draft = explain_trick(
                &trick.reason_code,
                trick.lead_suit.name(),
                trick.trump_suit.map(|s| s.name()),
                &trick.winner.to_string(),
            );
            return Ok(self.maybe_rewrite(key, draft));
        }

        if let Some(code) = request.reason_code.as_deref().filter(|c| !c.is_empty()) {
            if let Some(draft) = explain_reason_code(code, request.facts.as_ref()) {
                return Ok(self.maybe_rewrite(key, draft));
            }
        }

        if let Some(question) = request.question.as_deref().filter(|q| !q.trim().is_empty()) {
            if let Some(draft) = self.faq.lookup(question) {
                return Ok(self.maybe_rewrite(key, draft));
            }

            if let Some(retriever) = &self.retriever {
                match retriever.retrieve(question, &self.retrieval_filter).await {
                    Ok(Some(hit)) => {
                        let draft = ExplanationResponse::deterministic(
                            hit.answer,
                            hit.rule_references,
                            hit.confidence,
                        );
                        return Ok(self.maybe_rewrite(key, draft));
                    }
                    Ok(None) => {}
                    Err(err) => {
                        tracing::warn!(error = %err, "RAG retrieve failed; falling back");
                    }
                }
            }

            return Ok(ExplanationResponse::deterministic(
                "I could not find a curated answer for that question. Try asking about bidding, follow suit, trump, or scoring.",
                vec!["basic-gameplay-001".into()],
                0.2,
            ));
        }

        Ok(ExplanationResponse::deterministic(
            "Ask a rules question, or provide a reason_code / trick payload to explain.",
            vec!["basic-gameplay-001".into()],
            0.1,
        ))
    }

    fn maybe_rewrite(&self, key: &str, draft: ExplanationResponse) -> ExplanationResponse {
        if !self.limiter.rewrite_allowed(key) {
            return draft.with_fallback("cost_cap");
        }
        let rewritten = self.rewriter.rewrite(draft);
        if !rewritten.deterministic {
            self.limiter.charge_rewrite(key);
        }
        rewritten
    }
}
