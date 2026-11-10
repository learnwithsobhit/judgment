//! Wire protocol for client/server communication (PLAN.md §13).
//!
//! REST models for non-live operations; WebSocket envelope and messages for
//! game actions and live state. MVP is snapshot-only (locked decision 6).

pub mod rest;
pub mod ws;

pub use rest::*;
pub use ws::*;

/// Bump only with a documented migration path (PLAN.md §29.2: never silently
/// change protocol schemas).
pub const PROTOCOL_VERSION: u16 = 1;

/// Keep in sync with Flutter `festival_catalog.dart`.
pub const FESTIVAL_IDS: &[&str] = &[
    "off",
    "diwali",
    "christmas",
    "holi",
    "halloween",
    "new_year",
    "eid",
];

pub fn festival_id_allowed(id: &str) -> bool {
    FESTIVAL_IDS.iter().any(|known| *known == id)
}
