//! Ephemeral table audio: curated soundboard ids + short voice-note caps.

/// Shared cooldown for soundboard + freeform voice (per player).
pub const AUDIO_COOLDOWN_MS: u64 = 10_000;
pub const MAX_VOICE_DURATION_MS: u32 = 6_000;
pub const MAX_VOICE_B64_BYTES: usize = 40_000;
pub const MIN_VOICE_DURATION_MS: u32 = 400;

const ALLOWED_SOUNDS: &[(&str, u32)] = &[
    ("laugh", 1800),
    ("clap", 1600),
    ("oh_no", 1800),
    ("nice", 1600),
    ("trump", 2000),
    ("gg", 1600),
    ("airhorn", 2200),
    ("facepalm", 1800),
];

const ALLOWED_VOICE_MIMES: &[&str] = &[
    "audio/webm",
    "audio/webm;codecs=opus",
    "audio/ogg",
    "audio/ogg;codecs=opus",
];

pub fn is_allowed_sound(id: &str) -> bool {
    ALLOWED_SOUNDS.iter().any(|(s, _)| *s == id)
}

pub fn sound_ttl_ms(id: &str) -> Option<u32> {
    ALLOWED_SOUNDS
        .iter()
        .find(|(s, _)| *s == id)
        .map(|(_, ttl)| *ttl)
}

pub fn is_allowed_voice_mime(mime: &str) -> bool {
    let normalized = mime.trim().to_ascii_lowercase();
    ALLOWED_VOICE_MIMES
        .iter()
        .any(|allowed| normalized == *allowed)
}

fn b64_decode_byte(c: u8) -> Option<u8> {
    match c {
        b'A'..=b'Z' => Some(c - b'A'),
        b'a'..=b'z' => Some(c - b'a' + 26),
        b'0'..=b'9' => Some(c - b'0' + 52),
        b'+' => Some(62),
        b'/' => Some(63),
        _ => None,
    }
}

/// Decode up to `max` raw bytes from standard base64 (no padding required for prefix).
fn b64_prefix(audio_b64: &str, max: usize) -> Option<Vec<u8>> {
    let mut out = Vec::with_capacity(max);
    let bytes = audio_b64.as_bytes();
    let mut i = 0;
    while out.len() < max && i + 4 <= bytes.len() {
        let (a, b, c, d) = (bytes[i], bytes[i + 1], bytes[i + 2], bytes[i + 3]);
        i += 4;
        if a == b'=' {
            break;
        }
        let a = b64_decode_byte(a)?;
        let b = b64_decode_byte(b)?;
        out.push((a << 2) | (b >> 4));
        if out.len() >= max || c == b'=' {
            break;
        }
        let c = b64_decode_byte(c)?;
        out.push(((b & 0x0f) << 4) | (c >> 2));
        if out.len() >= max || d == b'=' {
            break;
        }
        let d = b64_decode_byte(d)?;
        out.push(((c & 0x03) << 6) | d);
    }
    if out.is_empty() {
        None
    } else {
        Some(out)
    }
}

fn is_valid_b64_alphabet(s: &str) -> bool {
    if s.is_empty() {
        return false;
    }
    let mut padding = false;
    for (idx, c) in s.bytes().enumerate() {
        match c {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'+' | b'/' => {
                if padding {
                    return false;
                }
            }
            b'=' => {
                if idx == 0 {
                    return false;
                }
                padding = true;
            }
            _ => return false,
        }
    }
    true
}

/// Validate voice payload size / duration / mime.
pub fn validate_voice_note(mime: &str, duration_ms: u32, audio_b64: &str) -> Result<(), String> {
    if !is_allowed_voice_mime(mime) {
        return Err("unsupported voice mime".into());
    }
    if !(MIN_VOICE_DURATION_MS..=MAX_VOICE_DURATION_MS).contains(&duration_ms) {
        return Err(format!(
            "voice duration must be {MIN_VOICE_DURATION_MS}–{MAX_VOICE_DURATION_MS} ms"
        ));
    }
    if audio_b64.len() > MAX_VOICE_B64_BYTES {
        return Err(format!(
            "voice payload too large (max {MAX_VOICE_B64_BYTES} base64 bytes)"
        ));
    }
    if !is_valid_b64_alphabet(audio_b64) {
        return Err("voice payload is not valid base64".into());
    }
    let prefix = b64_prefix(audio_b64, 4).ok_or_else(|| "voice payload empty".to_string())?;
    // Light container sniff: WebM/EBML or Ogg.
    let ok_magic = prefix.starts_with(&[0x1A, 0x45, 0xDF, 0xA3]) // EBML / WebM
        || prefix.starts_with(b"OggS");
    if !ok_magic {
        return Err("voice payload must be WebM or Ogg/Opus".into());
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn sound_allow_list() {
        assert!(is_allowed_sound("laugh"));
        assert!(!is_allowed_sound("boom"));
        assert_eq!(sound_ttl_ms("airhorn"), Some(2200));
    }

    #[test]
    fn voice_caps() {
        // Standard base64 for EBML magic 1A 45 DF A3 + padding bytes.
        let webm = "GkXfowAAAAA=";
        assert!(validate_voice_note("audio/webm;codecs=opus", 1200, webm).is_ok());
        assert!(validate_voice_note("audio/mp3", 1200, webm).is_err());
        assert!(validate_voice_note("audio/webm", 100, webm).is_err());
        let huge = format!("GkXf{}", "A".repeat(MAX_VOICE_B64_BYTES));
        assert!(validate_voice_note("audio/webm", 1200, &huge).is_err());
        assert!(validate_voice_note("audio/webm", 1200, "!!!!").is_err());
    }
}
