//! Per-session AI rate limits and soft cost caps (PLAN.md §20).

use std::collections::HashMap;
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// Defaults suitable for local/dev MVP; override via [`AiLimits`].
#[derive(Debug, Clone, Copy)]
pub struct AiLimits {
    /// Max AI requests per session inside the sliding window.
    pub max_requests_per_window: u32,
    pub window: Duration,
    /// Estimated "cost units" (e.g. tokens) allowed per session per window for LLM rewrite.
    pub max_cost_units_per_window: u32,
    /// Cost charged for one optional rewrite attempt.
    pub rewrite_cost_units: u32,
}

impl Default for AiLimits {
    fn default() -> Self {
        Self {
            max_requests_per_window: 30,
            window: Duration::from_secs(60),
            max_cost_units_per_window: 8_000,
            rewrite_cost_units: 400,
        }
    }
}

#[derive(Debug, Default)]
struct Bucket {
    events: Vec<Instant>,
    cost_events: Vec<(Instant, u32)>,
}

/// Thread-safe in-memory limiter keyed by session (or anonymous) id.
#[derive(Debug)]
pub struct AiRateLimiter {
    limits: AiLimits,
    buckets: Mutex<HashMap<String, Bucket>>,
}

impl AiRateLimiter {
    pub fn new(limits: AiLimits) -> Self {
        Self {
            limits,
            buckets: Mutex::new(HashMap::new()),
        }
    }

    /// Reserve a request slot. `Err` means the caller should reject or return a hard fallback.
    pub fn check_request(&self, key: &str) -> Result<(), RateLimitError> {
        let mut guard = self.buckets.lock().expect("ai rate limiter");
        let bucket = guard.entry(key.to_string()).or_default();
        let now = Instant::now();
        bucket.events.retain(|t| now.duration_since(*t) < self.limits.window);
        if bucket.events.len() as u32 >= self.limits.max_requests_per_window {
            return Err(RateLimitError::RequestLimit);
        }
        bucket.events.push(now);
        Ok(())
    }

    /// Returns whether an LLM rewrite is allowed under the cost cap. Does not charge until
    /// [`Self::charge_rewrite`] is called after a successful rewrite.
    pub fn rewrite_allowed(&self, key: &str) -> bool {
        let mut guard = self.buckets.lock().expect("ai rate limiter");
        let bucket = guard.entry(key.to_string()).or_default();
        let now = Instant::now();
        bucket
            .cost_events
            .retain(|(t, _)| now.duration_since(*t) < self.limits.window);
        let spent: u32 = bucket.cost_events.iter().map(|(_, c)| *c).sum();
        spent + self.limits.rewrite_cost_units <= self.limits.max_cost_units_per_window
    }

    pub fn charge_rewrite(&self, key: &str) {
        let mut guard = self.buckets.lock().expect("ai rate limiter");
        let bucket = guard.entry(key.to_string()).or_default();
        bucket
            .cost_events
            .push((Instant::now(), self.limits.rewrite_cost_units));
    }
}

#[derive(Debug, Clone, PartialEq, Eq, thiserror::Error)]
pub enum RateLimitError {
    #[error("AI request rate limit exceeded")]
    RequestLimit,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn enforces_request_limit() {
        let limiter = AiRateLimiter::new(AiLimits {
            max_requests_per_window: 2,
            window: Duration::from_secs(60),
            ..AiLimits::default()
        });
        assert!(limiter.check_request("s1").is_ok());
        assert!(limiter.check_request("s1").is_ok());
        assert_eq!(limiter.check_request("s1"), Err(RateLimitError::RequestLimit));
    }

    #[test]
    fn cost_cap_blocks_rewrite() {
        let limiter = AiRateLimiter::new(AiLimits {
            max_cost_units_per_window: 500,
            rewrite_cost_units: 400,
            ..AiLimits::default()
        });
        assert!(limiter.rewrite_allowed("s1"));
        limiter.charge_rewrite("s1");
        assert!(!limiter.rewrite_allowed("s1"));
    }
}
