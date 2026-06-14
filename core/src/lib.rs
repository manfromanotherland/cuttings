// SPDX-License-Identifier: MIT

mod frontmatter;
mod id;
mod images;
pub mod index;
pub mod reconcile;
pub mod scanner;
pub mod search;
mod types;
mod url_norm;
mod writer;

pub use frontmatter::{parse_reading, render_reading};
pub use id::new_id;
pub use images::download_images;
pub use index::open as open_index;
pub use reconcile::{apply_diffs, rebuild};
pub use scanner::{diff, scan_library, ScanDiff, ScannedReading};
pub use search::{search, SearchResult};
pub use types::{LibraryRoot, Metadata, Reading};
pub use url_norm::normalize_url;
pub use writer::{find_duplicate, sha256_hex, write_reading};

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}
