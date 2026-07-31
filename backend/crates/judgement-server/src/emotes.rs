//! Curated text → emoji / mood / sticker mapping and avatar allow-list (cosmetic).

use std::sync::OnceLock;

pub const MAX_EMOTE_TEXT_LEN: usize = 40;
pub const REACTION_COOLDOWN_MS: u64 = 2000;

const ALLOWED_AVATARS: &[&str] = &[
    "fox", "owl", "dragon", "cat", "dog", "panda", "tiger", "lion", "monkey", "frog",
    "robot", "alien", "ghost", "fire", "star", "crown", "spade", "heart", "diamond", "club",
    "wizard", "ninja", "pirate", "unicorn",
];

const ALLOWED_EMOJIS: &[&str] = &[
    "🔥", "😂", "👏", "😱", "😎", "💀", "🎯", "🙌", "😤", "👀", "💪", "✨",
];

/// Moods accepted for manual avatar flash.
const ALLOWED_AVATAR_MOODS: &[&str] = &["cheer", "laugh", "facepalm", "fire"];

const ALLOWED_STICKERS: &[&str] = &[
    "slam", "laugh", "crown", "facepalm", "fire", "target", "flex", "oops",
];

pub fn is_allowed_avatar(id: &str) -> bool {
    ALLOWED_AVATARS.contains(&id)
}

pub fn is_allowed_emoji(emoji: &str) -> bool {
    ALLOWED_EMOJIS.contains(&emoji)
}

pub fn is_allowed_mood(mood: &str) -> bool {
    ALLOWED_AVATAR_MOODS.contains(&mood)
}

pub fn is_allowed_sticker(id: &str) -> bool {
    ALLOWED_STICKERS.contains(&id)
}

/// Resolved style for a typed vibe. Original text is never rewritten.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct EmoteStyle {
    pub emojis: Vec<String>,
    pub mood: String,
    pub sticker_id: Option<String>,
}

#[derive(Clone, Copy)]
struct LexEntry {
    key: &'static str,
    mood: &'static str,
    sticker: Option<&'static str>,
    emojis: &'static [&'static str],
}

fn lexicon() -> &'static [LexEntry] {
    static ENTRIES: OnceLock<Vec<LexEntry>> = OnceLock::new();
    ENTRIES.get_or_init(|| {
        vec![
            // Longer / more specific keys first for contains-match order.
            LexEntry {
                key: "yeh mara",
                mood: "roast",
                sticker: Some("slam"),
                emojis: &["💀", "🔥"],
            },
            LexEntry {
                key: "ye mara",
                mood: "roast",
                sticker: Some("slam"),
                emojis: &["💀", "🔥"],
            },
            LexEntry {
                key: "zabardast",
                mood: "flex",
                sticker: Some("crown"),
                emojis: &["💪", "✨"],
            },
            LexEntry {
                key: "come on",
                mood: "flex",
                sticker: Some("flex"),
                emojis: &["💪", "😤"],
            },
            LexEntry {
                key: "lets go",
                mood: "fire",
                sticker: Some("fire"),
                emojis: &["🔥", "💪"],
            },
            LexEntry {
                key: "oh no",
                mood: "oops",
                sticker: Some("oops"),
                emojis: &["😱", "💀"],
            },
            LexEntry {
                key: "unlucky",
                mood: "oops",
                sticker: Some("facepalm"),
                emojis: &["💀"],
            },
            LexEntry {
                key: "exact",
                mood: "gg",
                sticker: Some("target"),
                emojis: &["🎯", "✨"],
            },
            LexEntry {
                key: "trump",
                mood: "fire",
                sticker: Some("target"),
                emojis: &["🎯", "🔥"],
            },
            LexEntry {
                key: "steal",
                mood: "roast",
                sticker: Some("slam"),
                emojis: &["😎", "💀"],
            },
            LexEntry {
                key: "clutch",
                mood: "gg",
                sticker: Some("crown"),
                emojis: &["👏", "🔥"],
            },
            LexEntry {
                key: "solid",
                mood: "flex",
                sticker: Some("crown"),
                emojis: &["💪", "✨"],
            },
            LexEntry {
                key: "mast",
                mood: "flex",
                sticker: Some("crown"),
                emojis: &["💪", "✨"],
            },
            LexEntry {
                key: "arey",
                mood: "oops",
                sticker: Some("oops"),
                emojis: &["😱", "💀"],
            },
            LexEntry {
                key: "arre",
                mood: "oops",
                sticker: Some("facepalm"),
                emojis: &["😱", "💀"],
            },
            LexEntry {
                key: "mara",
                mood: "roast",
                sticker: Some("slam"),
                emojis: &["💀", "🔥"],
            },
            LexEntry {
                key: "nice",
                mood: "gg",
                sticker: Some("laugh"),
                emojis: &["🔥", "👏"],
            },
            LexEntry {
                key: "oops",
                mood: "oops",
                sticker: Some("facepalm"),
                emojis: &["😱", "💀"],
            },
            LexEntry {
                key: "haha",
                mood: "laugh",
                sticker: Some("laugh"),
                emojis: &["😂"],
            },
            LexEntry {
                key: "lmao",
                mood: "laugh",
                sticker: Some("laugh"),
                emojis: &["😂", "💀"],
            },
            LexEntry {
                key: "lol",
                mood: "laugh",
                sticker: Some("laugh"),
                emojis: &["😂"],
            },
            LexEntry {
                key: "wow",
                mood: "flex",
                sticker: Some("fire"),
                emojis: &["😱", "✨"],
            },
            LexEntry {
                key: "good",
                mood: "gg",
                sticker: Some("laugh"),
                emojis: &["👏"],
            },
            LexEntry {
                key: "bad",
                mood: "oops",
                sticker: Some("facepalm"),
                emojis: &["😤"],
            },
            LexEntry {
                key: "fire",
                mood: "fire",
                sticker: Some("fire"),
                emojis: &["🔥"],
            },
            LexEntry {
                key: "cool",
                mood: "flex",
                sticker: Some("flex"),
                emojis: &["😎"],
            },
            LexEntry {
                key: "bid",
                mood: "gg",
                sticker: None,
                emojis: &["👀"],
            },
            LexEntry {
                key: "gg",
                mood: "gg",
                sticker: Some("laugh"),
                emojis: &["🙌", "✨"],
            },
        ]
    })
}

/// Map free text to emojis + mood + optional sticker. Does not alter the text.
pub fn resolve_emote_text(text: &str) -> EmoteStyle {
    let normalized = text.trim().to_lowercase();
    if normalized.is_empty() {
        return EmoteStyle {
            emojis: vec!["✨".into()],
            mood: "gg".into(),
            sticker_id: None,
        };
    }
    for entry in lexicon() {
        if normalized.contains(entry.key) {
            return EmoteStyle {
                emojis: entry
                    .emojis
                    .iter()
                    .take(3)
                    .map(|e| (*e).to_string())
                    .collect(),
                mood: entry.mood.into(),
                sticker_id: entry.sticker.map(str::to_string),
            };
        }
    }
    // Silly fallback — art-text only, no sticker.
    let (mood, emojis) = match normalized.chars().next().unwrap_or('j') as u32 % 4 {
        0 => ("flex", vec!["👀", "✨"]),
        1 => ("fire", vec!["🔥"]),
        2 => ("laugh", vec!["😂", "🙌"]),
        _ => ("roast", vec!["🎯", "😎"]),
    };
    EmoteStyle {
        emojis: emojis.into_iter().map(str::to_string).collect(),
        mood: mood.into(),
        sticker_id: None,
    }
}

/// Back-compat helper for callers that only need emojis.
pub fn text_to_emojis(text: &str) -> Vec<String> {
    resolve_emote_text(text).emojis
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn lexicon_maps_ye_mara() {
        let style = resolve_emote_text("ye mara");
        assert_eq!(style.mood, "roast");
        assert_eq!(style.sticker_id.as_deref(), Some("slam"));
        assert!(style.emojis.contains(&"💀".to_string()) || style.emojis.contains(&"🔥".to_string()));
    }

    #[test]
    fn lexicon_maps_nice_trump() {
        let style = resolve_emote_text("nice trump");
        assert!(style.emojis.contains(&"🔥".to_string()) || style.emojis.contains(&"🎯".to_string()));
        assert!(style.sticker_id.is_some());
    }

    #[test]
    fn fallback_has_no_sticker() {
        let style = resolve_emote_text("xyzzyq");
        assert!(style.sticker_id.is_none());
        assert!(!style.emojis.is_empty());
    }

    #[test]
    fn avatar_allow_list() {
        assert!(is_allowed_avatar("fox"));
        assert!(!is_allowed_avatar("photo_upload"));
    }
}
