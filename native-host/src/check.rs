// SPDX-License-Identifier: MIT

use readcontrol_core::{find_by_url, LibraryRoot};

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

    // Content-addressed lookup: hash the normalized URL to its id and stat the
    // single file it would live at — no directory scan, no index. The app's index
    // is a per-device cache the host can't reliably reach; the `articles/` tree is
    // the only source of truth.
    let library = LibraryRoot::new(&library_path)?;
    let id = find_by_url(&library, &req.url)?;
    Ok(SaveResponse::check(id.is_some(), id))
}
