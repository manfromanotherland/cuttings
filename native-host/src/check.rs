// SPDX-License-Identifier: MIT

use rusqlite::OptionalExtension;

use crate::protocol::{CheckRequest, SaveResponse};
use crate::save::find_library_path;

pub fn handle(req: CheckRequest) -> anyhow::Result<SaveResponse> {
    if req.protocol_version != 1 {
        return Ok(SaveResponse::error(
            "invalid_request",
            &format!("unsupported protocol_version: {}", req.protocol_version),
        ));
    }

    let library_path = match find_library_path() {
        Ok(p) => p,
        Err(_) => return Ok(SaveResponse::check(false, None)),
    };

    let db_path = library_path.join("index.db");
    if !db_path.exists() {
        return Ok(SaveResponse::check(false, None));
    }

    let conn = read_later_core::open_index(&db_path)?;
    let id: Option<String> = conn
        .query_row(
            "SELECT id FROM readings WHERE canonical_url = ?1",
            rusqlite::params![req.url],
            |r| r.get(0),
        )
        .optional()?;
    Ok(SaveResponse::check(id.is_some(), id))
}
