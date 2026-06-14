// SPDX-License-Identifier: MIT

mod frontmatter;
mod id;
mod images;
mod types;
mod url_norm;
mod writer;

pub use frontmatter::{parse_reading, render_reading};
pub use id::new_id;
pub use images::download_images;
pub use types::{LibraryRoot, Metadata, Reading};
pub use url_norm::normalize_url;
pub use writer::{find_duplicate, sha256_hex, write_reading};

pub fn version() -> &'static str {
    env!("CARGO_PKG_VERSION")
}
