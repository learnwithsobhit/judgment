//! Optional tone rewrite. MVP path is identity (ADR 0002 / PLAN.md §18.1).

use crate::types::ExplanationResponse;

/// Rewrites deterministic answers for tone only. Must never change legality claims.
pub trait ToneRewriter: Send + Sync {
    fn rewrite(&self, draft: ExplanationResponse) -> ExplanationResponse;
}

/// Pass-through rewriter — always used when Rig is unavailable or cost-capped.
#[derive(Debug, Default, Clone, Copy)]
pub struct IdentityRewriter;

impl ToneRewriter for IdentityRewriter {
    fn rewrite(&self, draft: ExplanationResponse) -> ExplanationResponse {
        draft
    }
}

/// Feature-gated Rig-backed rewriter. Without the `rig` feature this is a no-op alias.
#[cfg(feature = "rig")]
pub mod rig_impl {
    use std::sync::Arc;

    use rig::completion::Prompt;
    use rig::providers::openai;

    use super::ToneRewriter;
    use crate::types::ExplanationResponse;

    /// Soft rewrite via OpenAI through Rig. Failures return the draft unchanged.
    pub struct RigRewriter {
        agent: Arc<openai::CompletionModel>,
        runtime: tokio::runtime::Handle,
    }

    impl RigRewriter {
        /// Builds from `OPENAI_API_KEY`. Returns `None` when the key is missing.
        pub fn from_env() -> Option<Self> {
            let key = std::env::var("OPENAI_API_KEY").ok()?;
            if key.trim().is_empty() {
                return None;
            }
            let client = openai::Client::new(&key);
            let model = client.completion_model("gpt-4o-mini");
            Some(Self {
                agent: Arc::new(model),
                runtime: tokio::runtime::Handle::current(),
            })
        }
    }

    impl ToneRewriter for RigRewriter {
        fn rewrite(&self, draft: ExplanationResponse) -> ExplanationResponse {
            let prompt = format!(
                "Rewrite the following Judgement card-game explanation for a beginner. \
                 Keep every factual claim identical. Do not invent rules. \
                 Keep rule references unchanged. Reply with only the rewritten answer text.\n\n{}",
                draft.answer
            );
            let model = Arc::clone(&self.agent);
            let result = self.runtime.block_on(async move {
                tokio::time::timeout(
                    std::time::Duration::from_secs(4),
                    model.prompt(&prompt),
                )
                .await
            });
            match result {
                Ok(Ok(text)) => {
                    let text = text.trim();
                    if text.is_empty() {
                        draft
                    } else {
                        ExplanationResponse {
                            answer: text.to_string(),
                            deterministic: false,
                            ..draft
                        }
                    }
                }
                _ => draft.with_fallback("llm_unavailable"),
            }
        }
    }
}
