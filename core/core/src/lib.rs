// SPDX-License-Identifier: MIT

uniffi::setup_scaffolding!();

mod delete;
pub mod ffi;
mod frontmatter;
pub mod highlights;
mod id;
mod images;
pub mod index;
pub mod list;
pub mod rating;
pub mod reconcile;
pub mod scanner;
mod search;
pub mod status;
pub mod tags;
mod time;
mod types;
mod url_norm;
mod writer;

pub use delete::delete_reading;
pub use frontmatter::{parse_reading, read_metadata, render_reading};
pub use highlights::{
    add_highlight, delete_highlight, list_highlights, toggle_highlight, Highlight,
};
pub use id::{media_id, new_id, quote_id, url_id};
pub use images::{first_local_image_asset, write_images, ImageBytes};
pub use index::open as open_index;
pub use list::{
    get_reading, list_readings, sidebar_counts, view_counts, CountScope, ListOptions, ReadingRow,
    SidebarCounts, SortField, View, ViewCounts,
};
pub use rating::{list_ratings, set_rating};
pub use reconcile::{apply_diffs, rebuild};
pub use scanner::{diff, scan_library, ScanDiff, ScannedReading};
pub use status::{set_archived, set_favorite, set_read};
pub use tags::{add_tag, list_tags, remove_tag, MAX_TAG_LEN};
pub use types::{LibraryRoot, Metadata, Reading, ReadingKind};
pub use url_norm::normalize_url;
pub use writer::{find_by_media, find_by_url, sha256_hex, write_reading};

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}
