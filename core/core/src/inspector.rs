// SPDX-License-Identifier: MIT

//! On-demand inspector facts. Presentation never receives an internal asset URL.

use anyhow::Result;
use rusqlite::{Connection, OptionalExtension};

use crate::{
    color_search, list::ReadingRow, visual_index, LibraryRoot, ReadingKind, VisualLabel,
    WeightedColor,
};

#[derive(Debug, uniffi::Record)]
pub struct ReadingInspector {
    pub labels: Vec<String>,
    pub colors: Vec<InspectorColor>,
    pub analysis_available: bool,
    pub file: Option<InspectorFile>,
    pub has_local_file: bool,
}

#[derive(Debug, uniffi::Record)]
pub struct InspectorColor {
    pub red: f64,
    pub green: f64,
    pub blue: f64,
    pub hex: String,
    pub search_query: String,
}

#[derive(Debug, uniffi::Record)]
pub struct InspectorFile {
    pub format: String,
    pub byte_count: u64,
    pub width: Option<u32>,
    pub height: Option<u32>,
}

pub(crate) struct Snapshot {
    row: ReadingRow,
    analysis: Option<(String, bool, String, String)>,
}

impl Snapshot {
    pub(crate) fn read(conn: &Connection, id: &str) -> Result<Option<Self>> {
        let Some((row, _)) = crate::get_reading(conn, id)? else {
            return Ok(None);
        };
        let analysis = conn.query_row(
            "SELECT a.content_hash, a.supported, a.labels_json, a.palette_json
             FROM readings r JOIN visual_analysis a
               ON a.content_hash=r.visual_asset_hash AND a.analyzer_version=r.visual_analyzer_version
             WHERE r.id=?1", [id],
            |r| Ok((r.get(0)?, r.get(1)?, r.get(2)?, r.get(3)?)),
        ).optional()?;
        Ok(Some(Self { row, analysis }))
    }

    /// Filesystem work happens after releasing the database lock. Cached labels
    /// are only displayed when they describe the actual preview bytes on disk.
    pub(crate) fn inspect(self, library: &LibraryRoot) -> ReadingInspector {
        let row = &self.row;
        let media = row
            .media_url
            .as_deref()
            .and_then(|url| url.strip_prefix("cuttings-asset:"));
        let path = media.or(row.preview_asset.as_deref());
        let file = path.and_then(|path| file_facts(library, row, path, media.is_some()));
        let mut result = ReadingInspector {
            labels: Vec::new(),
            colors: Vec::new(),
            analysis_available: false,
            file,
            has_local_file: path.is_some(),
        };
        let Some((hash, supported, labels, palette)) = self.analysis else {
            return result;
        };
        let current = row
            .preview_asset
            .as_deref()
            .and_then(|path| visual_index::inspect_asset(library, &row.id, path).ok());
        if !current.is_some_and(|asset| asset.content_hash == hash) {
            return result;
        }
        result.analysis_available = true;
        if supported {
            result.labels = display_labels(&labels);
            result.colors = display_colors(&palette);
        }
        result
    }
}

fn file_facts(
    library: &LibraryRoot,
    row: &ReadingRow,
    path: &str,
    is_media: bool,
) -> Option<InspectorFile> {
    let binding = if is_media {
        visual_index::AssetBinding::Media(row.media_url.as_deref()?)
    } else {
        visual_index::AssetBinding::Preview(path)
    };
    let mut file = visual_index::open_bound_asset(library, &row.id, path, binding).ok()?;
    let byte_count = file.metadata().ok()?.len();
    let dimensions = if is_media && row.kind == ReadingKind::Video {
        crate::media_dimensions::video_dimensions(&mut file)
    } else {
        crate::media_dimensions::image_dimensions(&mut file)
    };
    let extension = std::path::Path::new(path)
        .extension()?
        .to_str()?
        .to_ascii_uppercase();
    let format = match extension.as_str() {
        "JPG" | "JPEG" => "JPEG".to_owned(),
        "TIF" | "TIFF" => "TIFF".to_owned(),
        _ => extension,
    };
    Some(InspectorFile {
        format,
        byte_count,
        width: dimensions.map(|d| d.width),
        height: dimensions.map(|d| d.height),
    })
}

fn display_labels(json: &str) -> Vec<String> {
    let mut labels = serde_json::from_str::<Vec<VisualLabel>>(json).unwrap_or_default();
    labels.retain(|label| {
        label.confidence >= 0.25
            && label.confidence <= 1.0
            && !matches!(
                label.identifier.as_str(),
                "object" | "structure" | "conveyance" | "portal" | "material" | "decoration"
            )
    });
    labels.sort_by(|a, b| {
        b.confidence
            .total_cmp(&a.confidence)
            .then_with(|| a.identifier.cmp(&b.identifier))
    });
    let mut seen = std::collections::HashSet::new();
    labels
        .into_iter()
        .map(|l| l.identifier)
        .filter(|l| !l.is_empty() && seen.insert(l.clone()))
        .take(6)
        .collect()
}

fn display_colors(json: &str) -> Vec<InspectorColor> {
    let palette = serde_json::from_str::<Vec<WeightedColor>>(json).unwrap_or_default();
    let palette = visual_index::normalize_palette(&palette).unwrap_or_default();
    let mut distinct: Vec<WeightedColor> = Vec::new();
    for color in palette
        .into_iter()
        .filter(|c| c.weight >= color_search::MIN_COVERAGE)
    {
        if distinct
            .iter()
            .all(|c| color_search::distance(c, &color) >= 0.035)
        {
            distinct.push(color);
        }
        if distinct.len() == 5 {
            break;
        }
    }
    distinct
        .into_iter()
        .map(|color| InspectorColor {
            red: color.red,
            green: color.green,
            blue: color.blue,
            hex: color_search::hex(&color),
            search_query: color_search::query(&color),
        })
        .collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{import_image, open_index, rebuild, VisualAnalysisResult};
    use tempfile::TempDir;

    #[test]
    fn inspector_reads_facts_and_rejects_stale_or_escaped_assets() {
        let temp = TempDir::new().unwrap();
        let library = LibraryRoot::new(temp.path()).unwrap();
        let mut png = vec![137, 80, 78, 71, 13, 10, 26, 10, 0, 0, 0, 13, 73, 72, 68, 82];
        png.extend(1280_u32.to_be_bytes());
        png.extend(1924_u32.to_be_bytes());
        png.extend([8, 2, 0, 0, 0]);
        let id = import_image(&library, png.clone(), "image/png", "Room")
            .unwrap()
            .id;
        let db_path = temp.path().join("index.db");
        let conn = open_index(&db_path).unwrap();
        rebuild(&conn, &library).unwrap();
        let cache = visual_index::prepare_visual_cache(&db_path).unwrap();
        let task = visual_index::pending_visual_analysis(&conn, &library, &cache, "test", 1)
            .unwrap()
            .tasks
            .remove(0);
        let analysis = VisualAnalysisResult {
            supported: true,
            labels: vec![
                VisualLabel {
                    identifier: "Cabinet".into(),
                    confidence: 0.9,
                },
                VisualLabel {
                    identifier: "structure".into(),
                    confidence: 0.99,
                },
                VisualLabel {
                    identifier: "noise".into(),
                    confidence: 0.1,
                },
            ],
            palette: vec![color_search::parse("colour:#BCA98E").unwrap()],
        };
        assert!(visual_index::complete_visual_analysis(&conn, &library, &task, &analysis).unwrap());
        let data = Snapshot::read(&conn, &id)
            .unwrap()
            .unwrap()
            .inspect(&library);
        assert_eq!(data.labels, ["cabinet"]);
        assert_eq!(data.colors[0].search_query, "colour:#BCA98E");
        let file = data.file.unwrap();
        assert_eq!((file.width, file.height), (Some(1280), Some(1924)));
        assert_eq!(file.byte_count, png.len() as u64);
        assert_eq!(file.format, "PNG");
        let asset_path = library.reading_dir(&id).join(&task.relative_path);
        std::fs::write(&asset_path, b"externally replaced").unwrap();
        let stale = Snapshot::read(&conn, &id)
            .unwrap()
            .unwrap()
            .inspect(&library);
        assert!(!stale.analysis_available);
        assert!(stale.colors.is_empty() && stale.labels.is_empty());
        std::fs::remove_file(&asset_path).unwrap();
        #[cfg(unix)]
        {
            let outside = temp.path().join("outside.png");
            std::fs::write(&outside, png).unwrap();
            std::os::unix::fs::symlink(outside, &asset_path).unwrap();
        }
        let missing = Snapshot::read(&conn, &id)
            .unwrap()
            .unwrap()
            .inspect(&library);
        assert!(missing.file.is_none());
        assert!(missing.has_local_file);
        assert!(!missing.analysis_available);
    }

    #[test]
    fn swatches_omit_noise_and_merge_near_duplicates() {
        let mut colors = vec![
            color_search::parse("color:#BCA98E").unwrap(),
            color_search::parse("color:#BDA98E").unwrap(),
            color_search::parse("color:#381A0F").unwrap(),
        ];
        colors[2].weight = 0.01;
        let palette = serde_json::to_string(&colors).unwrap();
        let swatches = display_colors(&palette);
        assert_eq!(swatches.len(), 1);
        assert!(display_colors("invalid").is_empty());
    }
}
