// SPDX-License-Identifier: MIT

use readcontrol_core::{find_saved, LibraryRoot};

use crate::protocol::{CheckRequest, SaveResponse, PROTOCOL_VERSION};
use crate::save::find_library_path;

pub fn handle(req: CheckRequest) -> anyhow::Result<SaveResponse> {
    if req.protocol_version != PROTOCOL_VERSION {
        return Ok(SaveResponse::error(
            "invalid_request",
            &format!("unsupported protocol_version: {}", req.protocol_version),
        ));
    }

    let library_path = match find_library_path() {
        Ok(p) => p,
        Err(_) => return Ok(SaveResponse::check(false, None)),
    };

    // Scan the article files directly rather than querying an index. The host
    // never builds an index, and the app's index is a per-device cache the host
    // can't reliably reach — the `articles/` directory is the only source of
    // truth. `find_saved` matches either the visible `url` or the `canonical_url`,
    // because the toolbar only knows the tab URL — it can't run extraction to
    // discover the page's canonical link.
    let library = LibraryRoot::new(&library_path)?;
    let id = find_saved(&library, &req.url)?;
    Ok(SaveResponse::check(id.is_some(), id))
}
