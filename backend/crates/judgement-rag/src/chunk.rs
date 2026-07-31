//! Chunk curated `rules/*.md` documents with metadata (PLAN.md §18.1).

use std::path::{Path, PathBuf};

use serde::{Deserialize, Serialize};

use crate::error::RagError;

/// Default ruleset stamped into every curated doc.
pub const DEFAULT_RULESET_VERSION: &str = "mvp-1";

/// One embeddable unit of rule text with filterable metadata.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct RuleChunk {
    pub chunk_id: String,
    pub rule_id: String,
    pub ruleset_version: String,
    pub category: String,
    pub player_count: Option<u8>,
    pub variant: Option<String>,
    pub content: String,
    pub source_path: String,
}

/// Parse a single markdown rule file into one or more chunks (H2 sections).
pub fn chunk_markdown(source_path: &str, markdown: &str) -> Result<Vec<RuleChunk>, RagError> {
    let meta = parse_doc_meta(markdown);
    let rule_id = meta.rule_id.ok_or_else(|| {
        RagError::msg(format!("missing rule_id in {source_path}"))
    })?;
    let ruleset_version = meta
        .ruleset_version
        .unwrap_or_else(|| DEFAULT_RULESET_VERSION.to_string());
    let category = meta.category.unwrap_or_else(|| "general".to_string());

    let sections = split_sections(markdown);
    if sections.is_empty() {
        return Ok(vec![RuleChunk {
            chunk_id: rule_id.clone(),
            rule_id,
            ruleset_version,
            category,
            player_count: meta.player_count,
            variant: meta.variant,
            content: strip_meta_lines(markdown).trim().to_string(),
            source_path: source_path.to_string(),
        }]);
    }

    let mut chunks = Vec::new();
    for (idx, (heading, body)) in sections.into_iter().enumerate() {
        let content = if heading.is_empty() {
            body
        } else {
            format!("{heading}\n\n{body}")
        };
        let content = content.trim().to_string();
        if content.is_empty() {
            continue;
        }
        let slug = slugify(&heading);
        let chunk_id = if slug.is_empty() {
            format!("{rule_id}#{idx}")
        } else {
            format!("{rule_id}#{slug}")
        };
        chunks.push(RuleChunk {
            chunk_id,
            rule_id: rule_id.clone(),
            ruleset_version: ruleset_version.clone(),
            category: category.clone(),
            player_count: meta.player_count,
            variant: meta.variant.clone(),
            content,
            source_path: source_path.to_string(),
        });
    }
    if chunks.is_empty() {
        return Err(RagError::msg(format!("no content chunks in {source_path}")));
    }
    Ok(chunks)
}

/// Load and chunk every `*.md` under `rules_dir` except `common_questions.md`
/// (that file remains the Phase 7 FAQ map).
pub fn chunk_rules_dir(rules_dir: impl AsRef<Path>) -> Result<Vec<RuleChunk>, RagError> {
    let rules_dir = rules_dir.as_ref();
    let mut paths: Vec<PathBuf> = std::fs::read_dir(rules_dir)
        .map_err(|e| RagError::msg(format!("read_dir {}: {e}", rules_dir.display())))?
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.extension().and_then(|e| e.to_str()) == Some("md")
                && p.file_name().and_then(|n| n.to_str()) != Some("common_questions.md")
        })
        .collect();
    paths.sort();

    let mut out = Vec::new();
    for path in paths {
        let markdown = std::fs::read_to_string(&path)
            .map_err(|e| RagError::msg(format!("read {}: {e}", path.display())))?;
        let name = path
            .file_name()
            .and_then(|n| n.to_str())
            .unwrap_or("unknown.md");
        out.extend(chunk_markdown(name, &markdown)?);
    }
    Ok(out)
}

#[derive(Default)]
struct DocMeta {
    rule_id: Option<String>,
    ruleset_version: Option<String>,
    category: Option<String>,
    player_count: Option<u8>,
    variant: Option<String>,
}

fn parse_doc_meta(markdown: &str) -> DocMeta {
    let mut meta = DocMeta::default();
    for line in markdown.lines().take(40) {
        if let Some(v) = meta_value(line, "rule_id") {
            meta.rule_id = Some(v);
        } else if let Some(v) = meta_value(line, "ruleset_version") {
            meta.ruleset_version = Some(v);
        } else if let Some(v) = meta_value(line, "category") {
            meta.category = Some(v);
        } else if let Some(v) = meta_value(line, "player_count") {
            meta.player_count = v.parse().ok();
        } else if let Some(v) = meta_value(line, "variant") {
            meta.variant = Some(v);
        }
    }
    meta
}

fn meta_value(line: &str, key: &str) -> Option<String> {
    let prefix = format!("**{key}:**");
    line.trim()
        .strip_prefix(&prefix)
        .map(|rest| rest.trim().trim_matches('`').to_string())
}

fn strip_meta_lines(markdown: &str) -> String {
    markdown
        .lines()
        .filter(|line| {
            let t = line.trim();
            !(t.starts_with("**rule_id:**")
                || t.starts_with("**ruleset_version:**")
                || t.starts_with("**category:**")
                || t.starts_with("**player_count:**")
                || t.starts_with("**variant:**"))
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn split_sections(markdown: &str) -> Vec<(String, String)> {
    let body = strip_meta_lines(markdown);
    let mut sections = Vec::new();
    let mut heading = String::new();
    let mut buf = String::new();
    let mut started = false;

    for line in body.lines() {
        if let Some(rest) = line.strip_prefix("## ") {
            if started || !buf.trim().is_empty() || !heading.is_empty() {
                sections.push((heading.clone(), buf.trim().to_string()));
            }
            heading = rest.trim().to_string();
            buf.clear();
            started = true;
            continue;
        }
        // Skip the H1 title line; keep other content.
        if line.starts_with("# ") && !started && buf.is_empty() {
            continue;
        }
        if !buf.is_empty() {
            buf.push('\n');
        }
        buf.push_str(line);
    }
    if started || !buf.trim().is_empty() {
        sections.push((heading, buf.trim().to_string()));
    }
    sections
}

fn slugify(s: &str) -> String {
    s.chars()
        .map(|c| {
            if c.is_ascii_alphanumeric() {
                c.to_ascii_lowercase()
            } else {
                '-'
            }
        })
        .collect::<String>()
        .split('-')
        .filter(|p| !p.is_empty())
        .collect::<Vec<_>>()
        .join("-")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn chunks_follow_suit_doc() {
        let md = r#"# Following suit

**rule_id:** `follow-suit-001`
**ruleset_version:** `mvp-1`
**category:** play

## Must follow

When a trick is led, follow the suit.

## When you cannot follow

Play any card.
"#;
        let chunks = chunk_markdown("following_suit.md", md).unwrap();
        assert!(chunks.len() >= 2);
        assert!(chunks.iter().all(|c| c.rule_id == "follow-suit-001"));
        assert!(chunks.iter().all(|c| c.ruleset_version == "mvp-1"));
        assert!(chunks.iter().any(|c| c.content.contains("Must follow")));
    }
}
