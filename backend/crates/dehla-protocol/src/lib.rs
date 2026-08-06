//! Dehla wire protocol (REST + WS). Own version space — not Judgement's.

mod rest;
mod ws;

pub use rest::*;
pub use ws::*;

/// Bump only with a documented migration path.
pub const PROTOCOL_VERSION: u16 = 1;
