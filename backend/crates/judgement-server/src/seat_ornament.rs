//! Special seat ornaments for allowlisted signed-in players (never guests).

/// Wire value for Aadarsh's peacock kalgi (F1: plume + gold clasp).
pub const PEACOCK_KALGI: &str = "peacock_kalgi";

/// Table-nick first tokens that map to Aadarsh's special ornament.
/// Includes his account-derived nick (`Aadarsh C`) and chosen alias (`Aadidas`).
const PEACOCK_NICK_TOKENS: &[&str] = &["aadarsh", "aadidas"];

/// Resolve ornament from the table nickname of a **signed-in** seat.
///
/// Guests who spoof the name stay undecorated because callers pass
/// `signed_in == false`.
pub fn for_signed_in_nickname(nickname: &str, signed_in: bool) -> Option<&'static str> {
    if !signed_in {
        return None;
    }
    let n = nickname.trim().to_ascii_lowercase();
    let first = n.split_whitespace().next().unwrap_or("");
    if PEACOCK_NICK_TOKENS.contains(&first) {
        Some(PEACOCK_KALGI)
    } else {
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn aadarsh_and_alias_signed_in_get_kalgi() {
        assert_eq!(
            for_signed_in_nickname("Aadarsh C", true),
            Some(PEACOCK_KALGI)
        );
        assert_eq!(
            for_signed_in_nickname("aadarsh", true),
            Some(PEACOCK_KALGI)
        );
        assert_eq!(
            for_signed_in_nickname("Aadidas", true),
            Some(PEACOCK_KALGI)
        );
        assert_eq!(
            for_signed_in_nickname("Aadidas C", true),
            Some(PEACOCK_KALGI)
        );
    }

    #[test]
    fn guests_and_others_get_none() {
        assert_eq!(for_signed_in_nickname("Aadarsh C", false), None);
        assert_eq!(for_signed_in_nickname("Aadidas", false), None);
        assert_eq!(for_signed_in_nickname("akash C", true), None);
        assert_eq!(for_signed_in_nickname("shobhit C", true), None);
    }
}
