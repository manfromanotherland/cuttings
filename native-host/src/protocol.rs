// SPDX-License-Identifier: MIT

use serde::{Deserialize, Serialize};

/// Incoming save request from the browser extension.
#[derive(Debug, Deserialize)]
pub struct SaveRequest {
    pub protocol_version: u32,
    pub action: String,
    pub metadata: RequestMetadata,
    pub markdown: String,
    pub image_urls: Vec<String>,
}

#[derive(Debug, Deserialize)]
pub struct RequestMetadata {
    pub url: String,
    pub canonical_url: String,
    pub title: String,
    pub author: Option<String>,
    pub site: Option<String>,
    pub lang: Option<String>,
    pub excerpt: Option<String>,
    pub word_count: Option<u32>,
    pub saved_at: String,
}

/// Incoming check request — asks whether a URL is already in the library.
#[derive(Debug, Deserialize)]
pub struct CheckRequest {
    pub protocol_version: u32,
    pub url: String,
}

/// Outgoing response to the browser extension (shared by save and check actions).
#[derive(Debug, Serialize)]
pub struct SaveResponse {
    pub protocol_version: u32,
    pub ok: bool,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub error: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub message: Option<String>,
    /// Present only in responses to a `check` action.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub saved: Option<bool>,
}

impl SaveResponse {
    pub fn success(id: String, path: String) -> Self {
        Self {
            protocol_version: 1,
            ok: true,
            id: Some(id),
            path: Some(path),
            error: None,
            message: None,
            saved: None,
        }
    }

    pub fn error(code: &str, msg: &str) -> Self {
        Self {
            protocol_version: 1,
            ok: false,
            id: None,
            path: None,
            error: Some(code.to_string()),
            message: Some(msg.to_string()),
            saved: None,
        }
    }

    pub fn check(is_saved: bool, id: Option<String>) -> Self {
        Self {
            protocol_version: 1,
            ok: true,
            saved: Some(is_saved),
            id,
            path: None,
            error: None,
            message: None,
        }
    }
}
