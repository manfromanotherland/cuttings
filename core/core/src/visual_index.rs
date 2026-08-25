// SPDX-License-Identifier: MIT

//! Disposable, device-local visual analysis derived from reading assets.
//!
//! The platform client performs image decoding and Vision classification. This
//! module owns every durable semantic decision: safe asset discovery, byte
//! identity, confidence policy, identifier normalization, colour families, and
//! the analyzer-versioned cache.

use std::{
    collections::{BTreeMap, HashSet},
    fs,
    io::Read as _,
};

use anyhow::{bail, Result};
use rusqlite::{params, Connection, OptionalExtension};
use rustix::fs::{Mode, OFlags};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::LibraryRoot;

const MIN_LABEL_CONFIDENCE: f64 = 0.15;
const MAX_LABELS: usize = 32;
const MAX_CACHED_OBSERVATIONS: usize = 128;
const MAX_PALETTE_CLUSTERS: usize = 32;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VisualAsset {
    pub reading_id: String,
    pub title: String,
    pub relative_path: String,
    pub absolute_file_path: String,
    pub content_hash: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct VisualAnalysisTask {
    pub reading_id: String,
    pub relative_path: String,
    pub absolute_file_path: String,
    pub content_hash: String,
    pub analyzer_version: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct VisualLabel {
    pub identifier: String,
    pub confidence: f64,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WeightedColor {
    pub red: f64,
    pub green: f64,
    pub blue: f64,
    pub weight: f64,
}

#[derive(Debug, Clone, PartialEq)]
pub struct VisualAnalysisResult {
    pub supported: bool,
    pub labels: Vec<VisualLabel>,
    pub palette: Vec<WeightedColor>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PredominantColor {
    Red,
    Orange,
    Yellow,
    Green,
    Blue,
    Purple,
    Pink,
    Brown,
    Black,
    Gray,
    White,
}

impl PredominantColor {
    pub fn as_str(self) -> &'static str {
        match self {
            Self::Red => "red",
            Self::Orange => "orange",
            Self::Yellow => "yellow",
            Self::Green => "green",
            Self::Blue => "blue",
            Self::Purple => "purple",
            Self::Pink => "pink",
            Self::Brown => "brown",
            Self::Black => "black",
            Self::Gray => "gray",
            Self::White => "white",
        }
    }
}

#[derive(Debug, Clone, Default)]
pub(crate) struct CachedVisualProjection {
    pub analyzer_version: Option<String>,
    pub visual_terms: String,
    pub predominant_color: Option<String>,
}

struct NormalizedAnalysis {
    labels: Vec<VisualLabel>,
    palette: Vec<WeightedColor>,
    visual_terms: String,
    predominant_color: Option<String>,
}

/// Open the selected preview one component at a time, reject symlinks below
/// the chosen library root, and hash the bytes actually read from the pinned FD.
pub(crate) fn inspect_asset(
    library: &LibraryRoot,
    reading_id: &str,
    relative_path: &str,
) -> Result<VisualAsset> {
    validate_reading_id(reading_id)?;
    let file_name = validate_asset_path(relative_path)?;
    let directory_flags = OFlags::RDONLY | OFlags::DIRECTORY | OFlags::CLOEXEC | OFlags::NOFOLLOW;
    let root = rustix::fs::open(
        library.path(),
        OFlags::RDONLY | OFlags::DIRECTORY | OFlags::CLOEXEC,
        Mode::empty(),
    )?;
    let articles = rustix::fs::openat(&root, "articles", directory_flags, Mode::empty())?;
    let prefix = reading_id.get(..2).unwrap_or(reading_id);
    let bucket = rustix::fs::openat(&articles, prefix, directory_flags, Mode::empty())?;
    let reading_dir = rustix::fs::openat(&bucket, reading_id, directory_flags, Mode::empty())?;

    // Validate the public file contract while the directory is pinned. A stale
    // DB row must not turn this into an arbitrary asset reader.
    let article_fd = rustix::fs::openat(
        &reading_dir,
        "article.md",
        OFlags::RDONLY | OFlags::CLOEXEC | OFlags::NOFOLLOW,
        Mode::empty(),
    )?;
    let mut article = fs::File::from(article_fd);
    if !article.metadata()?.is_file() {
        bail!("article is not a regular file for {reading_id}");
    }
    let mut markdown = String::new();
    article.read_to_string(&mut markdown)?;
    let metadata = crate::parse_reading(&markdown)?.metadata;
    if metadata.id != reading_id || metadata.preview_asset.as_deref() != Some(relative_path) {
        bail!("preview asset no longer belongs to reading {reading_id}");
    }

    let assets = rustix::fs::openat(&reading_dir, "assets", directory_flags, Mode::empty())?;
    let asset_fd = rustix::fs::openat(
        &assets,
        file_name,
        OFlags::RDONLY | OFlags::CLOEXEC | OFlags::NOFOLLOW,
        Mode::empty(),
    )?;
    let mut file = fs::File::from(asset_fd);
    if !file.metadata()?.is_file() {
        bail!("preview asset is not a regular file for {reading_id}");
    }
    let mut hasher = Sha256::new();
    let mut buffer = [0_u8; 64 * 1024];
    loop {
        let read = file.read(&mut buffer)?;
        if read == 0 {
            break;
        }
        hasher.update(&buffer[..read]);
    }
    let absolute = library.reading_dir(reading_id).join(relative_path);
    Ok(VisualAsset {
        reading_id: reading_id.to_string(),
        title: String::new(),
        relative_path: relative_path.to_string(),
        absolute_file_path: absolute.to_string_lossy().into_owned(),
        content_hash: hex::encode(hasher.finalize()),
    })
}

fn validate_reading_id(reading_id: &str) -> Result<()> {
    if reading_id.is_empty() || !reading_id.chars().all(|c| c.is_ascii_alphanumeric()) {
        bail!("invalid reading id: {reading_id:?}");
    }
    Ok(())
}

fn validate_asset_path(path: &str) -> Result<&str> {
    let mut parts = path.split('/');
    let first = parts.next();
    let file = parts.next();
    if first != Some("assets")
        || file.is_none_or(|name| {
            name.is_empty() || name == "." || name == ".." || name.contains(['\\', '\0'])
        })
        || parts.next().is_some()
    {
        bail!("preview asset must be a direct child of assets/");
    }
    Ok(file.expect("checked above"))
}

pub fn current_visual_assets(conn: &Connection, library: &LibraryRoot) -> Result<Vec<VisualAsset>> {
    let mut stmt = conn.prepare(
        "SELECT id, title, visual_asset_path, visual_asset_hash FROM readings
         WHERE visual_asset_path IS NOT NULL AND visual_asset_hash IS NOT NULL ORDER BY id",
    )?;
    let rows = stmt
        .query_map([], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
            ))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;

    let mut assets = Vec::new();
    for (id, title, path, content_hash) in rows {
        // These columns exist only after the scanner safely opened and hashed
        // the asset. Revalidate the lexical contract cheaply; completion does
        // the intentional second byte read before accepting platform output.
        if validate_reading_id(&id).is_err() || validate_asset_path(&path).is_err() {
            continue;
        }
        assets.push(VisualAsset {
            absolute_file_path: library
                .reading_dir(&id)
                .join(&path)
                .to_string_lossy()
                .into_owned(),
            reading_id: id,
            title,
            relative_path: path,
            content_hash,
        });
    }
    Ok(assets)
}

/// Return analyzer-versioned work, hydrating exact cache hits as a side effect.
pub fn pending_visual_analysis(
    conn: &Connection,
    library: &LibraryRoot,
    analyzer_version: &str,
    limit: usize,
) -> Result<Vec<VisualAnalysisTask>> {
    if analyzer_version.trim().is_empty() {
        bail!("analyzer version must not be blank");
    }
    let tx = conn.unchecked_transaction()?;
    // Exact cache hits need no file I/O: the indexed hash was produced by the
    // scanner's safe open, and completion also revalidated it. This makes
    // repeated small batches O(batch), not O(library size) asset reads.
    conn.execute(
        "UPDATE readings SET
           visual_analyzer_version=?1,
           visual_terms=COALESCE((
             SELECT CASE WHEN supported=1 THEN visual_terms ELSE '' END
             FROM visual_analysis a
             WHERE a.content_hash=readings.visual_asset_hash
               AND a.analyzer_version=?1
           ), ''),
           predominant_color=(
             SELECT CASE WHEN supported=1 THEN predominant_color ELSE NULL END
             FROM visual_analysis a
             WHERE a.content_hash=readings.visual_asset_hash
               AND a.analyzer_version=?1
           )
         WHERE visual_asset_hash IS NOT NULL AND EXISTS (
           SELECT 1 FROM visual_analysis a
           WHERE a.content_hash=readings.visual_asset_hash
             AND a.analyzer_version=?1
         )",
        params![analyzer_version],
    )?;
    let mut stmt = conn.prepare(
        "SELECT id, title, visual_asset_path, visual_asset_hash
         FROM readings r
         WHERE visual_asset_path IS NOT NULL AND visual_asset_hash IS NOT NULL
           AND NOT EXISTS (
             SELECT 1 FROM visual_analysis a
             WHERE a.content_hash=r.visual_asset_hash AND a.analyzer_version=?1
           )
           AND r.id=(
             SELECT MIN(r2.id) FROM readings r2
             WHERE r2.visual_asset_hash=r.visual_asset_hash
               AND r2.visual_asset_path IS NOT NULL
           )
         ORDER BY id LIMIT ?2",
    )?;
    let candidates = stmt
        .query_map(params![analyzer_version, limit as i64], |row| {
            Ok((
                row.get::<_, String>(0)?,
                row.get::<_, String>(1)?,
                row.get::<_, String>(2)?,
                row.get::<_, String>(3)?,
            ))
        })?
        .collect::<rusqlite::Result<Vec<_>>>()?;
    drop(stmt);
    let mut pending = Vec::new();

    for (id, _title, path, content_hash) in candidates {
        if validate_reading_id(&id).is_err() || validate_asset_path(&path).is_err() {
            continue;
        }
        pending.push(VisualAnalysisTask {
            absolute_file_path: library
                .reading_dir(&id)
                .join(&path)
                .to_string_lossy()
                .into_owned(),
            reading_id: id,
            relative_path: path,
            content_hash,
            analyzer_version: analyzer_version.to_string(),
        });
    }
    tx.commit()?;
    Ok(pending)
}

/// Complete a task only if the same safe path still contains the same bytes.
/// Returns `false` for ordinary stale work so clients can simply discard it.
pub fn complete_visual_analysis(
    conn: &Connection,
    library: &LibraryRoot,
    task: &VisualAnalysisTask,
    result: &VisualAnalysisResult,
) -> Result<bool> {
    if task.analyzer_version.trim().is_empty() {
        bail!("analyzer version must not be blank");
    }
    let current = match inspect_asset(library, &task.reading_id, &task.relative_path) {
        Ok(asset) if asset.content_hash == task.content_hash => asset,
        Ok(_) | Err(_) => return Ok(false),
    };

    let normalized = if result.supported {
        normalize_result(result)?
    } else {
        NormalizedAnalysis {
            labels: Vec::new(),
            palette: Vec::new(),
            visual_terms: String::new(),
            predominant_color: None,
        }
    };
    let labels_json = serde_json::to_string(&normalized.labels)?;
    let palette_json = serde_json::to_string(&normalized.palette)?;
    let tx = conn.unchecked_transaction()?;
    conn.execute(
        "INSERT INTO visual_analysis
         (content_hash, analyzer_version, supported, labels_json, palette_json,
          visual_terms, predominant_color, completed_at)
         VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, unixepoch())
         ON CONFLICT(content_hash, analyzer_version) DO UPDATE SET
           supported=excluded.supported,
           labels_json=excluded.labels_json,
           palette_json=excluded.palette_json,
           visual_terms=excluded.visual_terms,
           predominant_color=excluded.predominant_color,
           completed_at=excluded.completed_at",
        params![
            current.content_hash,
            task.analyzer_version,
            result.supported as i32,
            labels_json,
            palette_json,
            normalized.visual_terms,
            normalized.predominant_color
        ],
    )?;
    sync_asset_identity(conn, &current)?;
    conn.execute(
        "UPDATE readings SET visual_analyzer_version=?2, visual_terms=?3,
             predominant_color=?4
         WHERE id=?1 AND visual_asset_path=?5 AND visual_asset_hash=?6",
        params![
            current.reading_id,
            task.analyzer_version,
            normalized.visual_terms,
            normalized.predominant_color,
            current.relative_path,
            current.content_hash
        ],
    )?;
    tx.commit()?;
    Ok(true)
}

fn normalize_result(result: &VisualAnalysisResult) -> Result<NormalizedAnalysis> {
    if result
        .labels
        .iter()
        .any(|label| !label.confidence.is_finite() || !(0.0..=1.0).contains(&label.confidence))
    {
        bail!("label confidences must be finite values from 0...1");
    }
    let mut labels: Vec<VisualLabel> = result
        .labels
        .iter()
        .filter_map(|label| {
            let normalized = normalize_identifier(&label.identifier);
            (!normalized.is_empty()).then_some(VisualLabel {
                identifier: normalized,
                confidence: label.confidence,
            })
        })
        .collect();
    labels.sort_by(|a, b| {
        b.confidence
            .total_cmp(&a.confidence)
            .then_with(|| a.identifier.as_str().cmp(b.identifier.as_str()))
    });
    let mut seen = HashSet::new();
    let labels: Vec<VisualLabel> = labels
        .into_iter()
        .filter(|label| seen.insert(label.identifier.clone()))
        .take(MAX_CACHED_OBSERVATIONS)
        .collect();
    let palette = normalize_palette(&result.palette)?;
    let color = predominant_color(&palette)?.map(|value| value.as_str().to_string());
    let mut terms: Vec<String> = labels
        .iter()
        .filter(|label| label.confidence >= MIN_LABEL_CONFIDENCE)
        .take(MAX_LABELS)
        .map(|label| label.identifier.clone())
        .collect();
    if let Some(color) = color.as_ref() {
        terms.push(color.clone());
    }
    Ok(NormalizedAnalysis {
        labels,
        palette,
        visual_terms: terms.join(" "),
        predominant_color: color,
    })
}

fn normalize_palette(palette: &[WeightedColor]) -> Result<Vec<WeightedColor>> {
    for sample in palette {
        validate_color(sample)?;
    }
    let mut palette: Vec<WeightedColor> = palette
        .iter()
        .filter(|sample| sample.weight > 0.0)
        .take(MAX_PALETTE_CLUSTERS)
        .cloned()
        .collect();
    let total: f64 = palette.iter().map(|sample| sample.weight).sum();
    if total > 0.0 {
        for sample in &mut palette {
            sample.weight /= total;
        }
    }
    Ok(palette)
}

fn normalize_identifier(identifier: &str) -> String {
    identifier
        .split(|c: char| !c.is_alphanumeric())
        .filter(|part| !part.is_empty())
        .map(|part| part.to_lowercase())
        .collect::<Vec<_>>()
        .join(" ")
}

pub fn predominant_color(palette: &[WeightedColor]) -> Result<Option<PredominantColor>> {
    let mut weights: BTreeMap<&'static str, (PredominantColor, f64)> = BTreeMap::new();
    for sample in palette {
        validate_color(sample)?;
        if sample.weight == 0.0 {
            continue;
        }
        let family = color_family(sample.red, sample.green, sample.blue);
        weights
            .entry(family.as_str())
            .and_modify(|(_, weight)| *weight += sample.weight)
            .or_insert((family, sample.weight));
    }
    Ok(weights
        .into_values()
        .max_by(|a, b| {
            a.1.total_cmp(&b.1)
                .then_with(|| b.0.as_str().cmp(a.0.as_str()))
        })
        .map(|(family, _)| family))
}

fn validate_color(sample: &WeightedColor) -> Result<()> {
    if !sample.red.is_finite()
        || !sample.green.is_finite()
        || !sample.blue.is_finite()
        || !sample.weight.is_finite()
        || !(0.0..=1.0).contains(&sample.red)
        || !(0.0..=1.0).contains(&sample.green)
        || !(0.0..=1.0).contains(&sample.blue)
        || sample.weight < 0.0
    {
        bail!("palette values must be finite RGB 0...1 with nonnegative weights");
    }
    Ok(())
}

fn color_family(red: f64, green: f64, blue: f64) -> PredominantColor {
    let max = red.max(green).max(blue);
    let min = red.min(green).min(blue);
    let delta = max - min;
    let saturation = if max == 0.0 { 0.0 } else { delta / max };
    if max <= 0.14 {
        return PredominantColor::Black;
    }
    if min >= 0.88 && saturation <= 0.12 {
        return PredominantColor::White;
    }
    if saturation <= 0.16 {
        return PredominantColor::Gray;
    }
    let mut hue = if max == red {
        60.0 * ((green - blue) / delta)
    } else if max == green {
        60.0 * (((blue - red) / delta) + 2.0)
    } else {
        60.0 * (((red - green) / delta) + 4.0)
    };
    if hue < 0.0 {
        hue += 360.0;
    }
    if (15.0..55.0).contains(&hue) && max < 0.68 {
        PredominantColor::Brown
    } else if !(15.0..345.0).contains(&hue) {
        PredominantColor::Red
    } else if hue < 45.0 {
        PredominantColor::Orange
    } else if hue < 70.0 {
        PredominantColor::Yellow
    } else if hue < 165.0 {
        PredominantColor::Green
    } else if hue < 255.0 {
        PredominantColor::Blue
    } else if hue < 300.0 {
        PredominantColor::Purple
    } else {
        PredominantColor::Pink
    }
}

fn sync_asset_identity(conn: &Connection, asset: &VisualAsset) -> Result<()> {
    conn.execute(
        "UPDATE readings SET
           visual_asset_path=?2,
           visual_asset_hash=?3,
           visual_analyzer_version=CASE
             WHEN visual_asset_hash=?3 THEN visual_analyzer_version ELSE NULL END,
           visual_terms=CASE WHEN visual_asset_hash=?3 THEN visual_terms ELSE '' END,
           predominant_color=CASE
             WHEN visual_asset_hash=?3 THEN predominant_color ELSE NULL END
         WHERE id=?1 AND preview_asset=?2",
        params![asset.reading_id, asset.relative_path, asset.content_hash],
    )?;
    Ok(())
}

/// Latest supported projection for a content hash, used while rebuilding the
/// readings table. Exact-version pending work can subsequently replace it.
pub(crate) fn cached_projection(
    conn: &Connection,
    content_hash: &str,
) -> Result<CachedVisualProjection> {
    conn.query_row(
        "SELECT analyzer_version,
                CASE WHEN supported=1 THEN visual_terms ELSE '' END,
                CASE WHEN supported=1 THEN predominant_color ELSE NULL END
         FROM visual_analysis
         WHERE content_hash=?1
         ORDER BY completed_at DESC, analyzer_version DESC LIMIT 1",
        params![content_hash],
        |row| {
            Ok(CachedVisualProjection {
                analyzer_version: row.get(0)?,
                visual_terms: row.get(1)?,
                predominant_color: row.get(2)?,
            })
        },
    )
    .optional()
    .map(|value| value.unwrap_or_default())
    .map_err(Into::into)
}

#[cfg(test)]
mod tests {
    use super::*;
    use tempfile::TempDir;

    use crate::{
        apply_diffs, diff, import_image, list_readings, open_index, rebuild, scan_library,
        ListOptions, PredominantColor,
    };

    fn setup_image(bytes: &[u8]) -> (TempDir, LibraryRoot, Connection, String) {
        let dir = TempDir::new().unwrap();
        let library = LibraryRoot::new(dir.path()).unwrap();
        let imported = import_image(&library, bytes.to_vec(), "image/png", "Dining setup").unwrap();
        let conn = open_index(&dir.path().join("index.db")).unwrap();
        rebuild(&conn, &library).unwrap();
        (dir, library, conn, imported.id)
    }

    fn supported_result() -> VisualAnalysisResult {
        VisualAnalysisResult {
            supported: true,
            labels: vec![
                VisualLabel {
                    identifier: "Dining_Room".into(),
                    confidence: 0.92,
                },
                VisualLabel {
                    identifier: "chair".into(),
                    confidence: 0.81,
                },
                VisualLabel {
                    identifier: "weak_noise".into(),
                    confidence: 0.01,
                },
            ],
            palette: vec![
                WeightedColor {
                    red: 0.1,
                    green: 0.25,
                    blue: 0.9,
                    weight: 3.0,
                },
                WeightedColor {
                    red: 0.9,
                    green: 0.1,
                    blue: 0.1,
                    weight: 1.0,
                },
            ],
        }
    }

    #[test]
    fn normalizes_vision_identifiers_and_applies_confidence_floor() {
        let result = VisualAnalysisResult {
            supported: true,
            labels: vec![
                VisualLabel {
                    identifier: "Dining_Room".into(),
                    confidence: 0.9,
                },
                VisualLabel {
                    identifier: "CHAIR".into(),
                    confidence: 0.8,
                },
                VisualLabel {
                    identifier: "noise".into(),
                    confidence: 0.149,
                },
            ],
            palette: vec![],
        };
        let normalized = normalize_result(&result).unwrap();
        assert_eq!(
            normalized
                .labels
                .iter()
                .map(|label| label.identifier.as_str())
                .collect::<Vec<_>>(),
            ["dining room", "chair", "noise"]
        );
        assert_eq!(normalized.labels[0].confidence, 0.9);
        assert_eq!(normalized.visual_terms, "dining room chair");
    }

    #[test]
    fn palette_weights_choose_stable_family() {
        let palette = vec![
            WeightedColor {
                red: 0.95,
                green: 0.1,
                blue: 0.1,
                weight: 0.2,
            },
            WeightedColor {
                red: 0.1,
                green: 0.25,
                blue: 0.9,
                weight: 0.5,
            },
            WeightedColor {
                red: 0.2,
                green: 0.35,
                blue: 0.8,
                weight: 0.4,
            },
        ];
        assert_eq!(
            predominant_color(&palette).unwrap(),
            Some(PredominantColor::Blue)
        );
    }

    #[test]
    fn scanner_hashes_raw_bytes_and_exposes_only_safe_assets() {
        let (_dir, library, conn, id) = setup_image(b"raw preview bytes");
        let assets = current_visual_assets(&conn, &library).unwrap();
        assert_eq!(assets.len(), 1);
        assert_eq!(assets[0].reading_id, id);
        assert_eq!(
            assets[0].content_hash,
            crate::sha256_hex(b"raw preview bytes")
        );
        assert!(assets[0].relative_path.starts_with("assets/"));
    }

    #[test]
    fn completion_indexes_labels_and_color_and_rebuild_reuses_cache() {
        let (_dir, library, conn, id) = setup_image(b"semantic image");
        let task = pending_visual_analysis(&conn, &library, "vision-r2", 10)
            .unwrap()
            .pop()
            .unwrap();
        assert!(complete_visual_analysis(&conn, &library, &task, &supported_result()).unwrap());
        let cached_labels: String = conn
            .query_row(
                "SELECT labels_json FROM visual_analysis WHERE content_hash=?1",
                params![task.content_hash],
                |row| row.get(0),
            )
            .unwrap();
        let cached_labels: Vec<VisualLabel> = serde_json::from_str(&cached_labels).unwrap();
        assert_eq!(cached_labels[0].identifier, "dining room");
        assert_eq!(cached_labels[0].confidence, 0.92);
        let cached_palette: String = conn
            .query_row(
                "SELECT palette_json FROM visual_analysis WHERE content_hash=?1",
                params![task.content_hash],
                |row| row.get(0),
            )
            .unwrap();
        let cached_palette: Vec<WeightedColor> = serde_json::from_str(&cached_palette).unwrap();
        assert_eq!(cached_palette.len(), 2);
        assert_eq!(cached_palette[0].blue, 0.9);
        assert_eq!(cached_palette[0].weight, 0.75);
        assert_eq!(cached_palette[1].weight, 0.25);

        let chair = list_readings(
            &conn,
            &ListOptions {
                query: Some("chair".into()),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(chair.iter().map(|row| &row.id).collect::<Vec<_>>(), [&id]);
        let blue = list_readings(
            &conn,
            &ListOptions {
                predominant_color: Some(PredominantColor::Blue),
                ..Default::default()
            },
        )
        .unwrap();
        assert_eq!(blue.iter().map(|row| &row.id).collect::<Vec<_>>(), [&id]);

        rebuild(&conn, &library).unwrap();
        assert!(pending_visual_analysis(&conn, &library, "vision-r2", 10)
            .unwrap()
            .is_empty());
        let cache_count: i64 = conn
            .query_row("SELECT COUNT(*) FROM visual_analysis", [], |row| row.get(0))
            .unwrap();
        assert_eq!(cache_count, 1);
        assert_eq!(
            list_readings(
                &conn,
                &ListOptions {
                    query: Some("dining room".into()),
                    ..Default::default()
                }
            )
            .unwrap()
            .len(),
            1
        );
    }

    #[test]
    fn unsupported_hash_is_not_retried_until_analyzer_changes() {
        let (_dir, library, conn, _id) = setup_image(b"unsupported image");
        let older = pending_visual_analysis(&conn, &library, "vision-r1", 1)
            .unwrap()
            .pop()
            .unwrap();
        assert!(complete_visual_analysis(&conn, &library, &older, &supported_result()).unwrap());
        let task = pending_visual_analysis(&conn, &library, "vision-r2", 1)
            .unwrap()
            .pop()
            .unwrap();
        let unsupported = VisualAnalysisResult {
            supported: false,
            labels: vec![],
            palette: vec![],
        };
        assert!(complete_visual_analysis(&conn, &library, &task, &unsupported).unwrap());
        assert!(pending_visual_analysis(&conn, &library, "vision-r2", 1)
            .unwrap()
            .is_empty());
        assert_eq!(
            pending_visual_analysis(&conn, &library, "vision-r3", 1)
                .unwrap()
                .len(),
            1
        );
        rebuild(&conn, &library).unwrap();
        assert!(list_readings(
            &conn,
            &ListOptions {
                query: Some("chair".into()),
                ..Default::default()
            }
        )
        .unwrap()
        .is_empty());
    }

    #[test]
    fn changed_or_deleted_asset_invalidates_projection_and_stale_completion() {
        let (_dir, library, conn, id) = setup_image(b"old bytes");
        let old_scan = scan_library(&library).unwrap();
        let task = pending_visual_analysis(&conn, &library, "vision-r2", 1)
            .unwrap()
            .pop()
            .unwrap();
        std::fs::write(&task.absolute_file_path, b"new bytes").unwrap();
        let new_scan = scan_library(&library).unwrap();
        apply_diffs(&conn, &diff(&old_scan, &new_scan)).unwrap();
        assert!(!complete_visual_analysis(&conn, &library, &task, &supported_result()).unwrap());
        let replacement = pending_visual_analysis(&conn, &library, "vision-r2", 1)
            .unwrap()
            .pop()
            .unwrap();
        assert_ne!(replacement.content_hash, task.content_hash);

        std::fs::remove_file(&replacement.absolute_file_path).unwrap();
        let after_delete = scan_library(&library).unwrap();
        apply_diffs(&conn, &diff(&new_scan, &after_delete)).unwrap();
        let state: (Option<String>, String) = conn
            .query_row(
                "SELECT visual_asset_hash, visual_terms FROM readings WHERE id=?1",
                params![id],
                |row| Ok((row.get(0)?, row.get(1)?)),
            )
            .unwrap();
        assert_eq!(state, (None, String::new()));
        assert!(current_visual_assets(&conn, &library).unwrap().is_empty());
    }
}
