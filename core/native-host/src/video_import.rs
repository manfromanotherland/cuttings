// SPDX-License-Identifier: MIT

use base64::Engine;
use cuttings_core::{
    begin_browser_video_import, BrowserVideoImport, BrowserVideoImportInput, LibraryRoot,
    ReadingKind, SaveDisposition, SaveError,
};

use crate::{
    protocol::{
        SaveResponse, VideoImportBeginRequest, VideoImportChunkRequest, VideoImportEndRequest,
        PROTOCOL_VERSION,
    },
    save::find_library_path,
};

const MAX_DECODED_CHUNK_BYTES: usize = 256 * 1024;

#[derive(Default)]
pub struct VideoImportSession {
    active: Option<ActiveVideoImport>,
}

struct ActiveVideoImport {
    upload_id: String,
    next_sequence: u64,
    importer: BrowserVideoImport,
}

impl VideoImportSession {
    pub fn is_active(&self) -> bool {
        self.active.is_some()
    }

    pub fn abort_active(&mut self) {
        self.active.take();
    }

    pub fn begin(&mut self, request: VideoImportBeginRequest) -> SaveResponse {
        if self.active.take().is_some() {
            return invalid("a browser video upload is already active");
        }
        if let Err(response) = validate_request(
            request.protocol_version,
            &request.action,
            "video_import_begin",
        ) {
            return response;
        }
        if request.upload_id.trim().is_empty() {
            return invalid("upload_id must not be empty");
        }
        if request.metadata.kind != ReadingKind::Video {
            return invalid("video_import_begin requires video metadata");
        }

        let library_path = match find_library_path() {
            Ok(path) => path,
            Err(_) => {
                return SaveResponse::error(
                    "library_not_configured",
                    "No library folder has been set. Open the Cuttings app to configure one.",
                )
            }
        };
        let library = match LibraryRoot::new(library_path) {
            Ok(library) => library,
            Err(error) => return SaveResponse::error("io_error", &error.to_string()),
        };
        let importer = match begin_browser_video_import(
            &library,
            BrowserVideoImportInput {
                content_type: request.content_type,
                expected_bytes: request.expected_bytes,
                origin_url: request.metadata.url,
                canonical_url: request.metadata.canonical_url,
                title: request.metadata.title,
                author: request.metadata.author,
                site: request.metadata.site,
                lang: request.metadata.lang,
                excerpt: request.metadata.excerpt,
                word_count: request.metadata.word_count,
                saved_at: request.metadata.saved_at,
            },
        ) {
            Ok(importer) => importer,
            Err(error) => return core_error(error),
        };

        self.active = Some(ActiveVideoImport {
            upload_id: request.upload_id,
            next_sequence: 0,
            importer,
        });
        SaveResponse::ack()
    }

    pub fn chunk(&mut self, request: VideoImportChunkRequest) -> SaveResponse {
        let Some(mut active) = self.active.take() else {
            return invalid("no browser video upload is active");
        };
        if let Err(response) = validate_request(
            request.protocol_version,
            &request.action,
            "video_import_chunk",
        ) {
            return response;
        }
        if request.upload_id != active.upload_id {
            return invalid("upload_id does not match the active browser video upload");
        }
        if request.sequence != active.next_sequence {
            return invalid(&format!(
                "video chunk sequence must be {}; received {}",
                active.next_sequence, request.sequence
            ));
        }
        let bytes = match base64::engine::general_purpose::STANDARD.decode(request.data_base64) {
            Ok(bytes) => bytes,
            Err(error) => return invalid(&format!("video chunk is not valid base64: {error}")),
        };
        if bytes.is_empty() {
            return invalid("decoded video chunk must not be empty");
        }
        if bytes.len() > MAX_DECODED_CHUNK_BYTES {
            return invalid(&format!(
                "decoded video chunk exceeds the {MAX_DECODED_CHUNK_BYTES} byte limit"
            ));
        }
        if let Err(error) = active.importer.append(&bytes) {
            return core_error(error);
        }
        let Some(next_sequence) = active.next_sequence.checked_add(1) else {
            return invalid("video chunk sequence overflowed");
        };
        active.next_sequence = next_sequence;
        self.active = Some(active);
        SaveResponse::ack()
    }

    pub fn finish(&mut self, request: VideoImportEndRequest) -> SaveResponse {
        let Some(active) = self.active.take() else {
            return invalid("no browser video upload is active");
        };
        if let Err(response) = validate_request(
            request.protocol_version,
            &request.action,
            "video_import_finish",
        ) {
            return response;
        }
        if request.upload_id != active.upload_id {
            return invalid("upload_id does not match the active browser video upload");
        }
        match active.importer.finish() {
            Ok(outcome) if outcome.disposition == SaveDisposition::Duplicate => {
                SaveResponse::error(
                    "duplicate",
                    &format!("This reading already exists (id: {})", outcome.id),
                )
            }
            Ok(outcome) => SaveResponse::success(outcome.id, outcome.path),
            Err(error) => core_error(error),
        }
    }

    pub fn abort(&mut self, request: VideoImportEndRequest) -> SaveResponse {
        let Some(active) = self.active.take() else {
            return invalid("no browser video upload is active");
        };
        if let Err(response) = validate_request(
            request.protocol_version,
            &request.action,
            "video_import_abort",
        ) {
            return response;
        }
        if request.upload_id != active.upload_id {
            return invalid("upload_id does not match the active browser video upload");
        }
        drop(active);
        SaveResponse::ack()
    }
}

fn validate_request(
    protocol_version: u32,
    action: &str,
    expected_action: &str,
) -> Result<(), SaveResponse> {
    if protocol_version != PROTOCOL_VERSION {
        return Err(invalid(&format!(
            "unsupported protocol_version: {protocol_version}"
        )));
    }
    if action != expected_action {
        return Err(invalid(&format!("unknown action: {action}")));
    }
    Ok(())
}

fn core_error(error: SaveError) -> SaveResponse {
    match error {
        SaveError::InvalidRequest(message) => SaveResponse::error("invalid_request", &message),
        SaveError::Storage(error) => SaveResponse::error("io_error", &error.to_string()),
    }
}

fn invalid(message: &str) -> SaveResponse {
    SaveResponse::error("invalid_request", message)
}
