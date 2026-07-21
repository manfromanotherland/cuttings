// SPDX-License-Identifier: MIT

/** Metadata sent alongside the Markdown body in a save request. */
export interface SaveRequestMetadata {
  url: string;
  canonical_url: string;
  title: string;
  author?: string;
  site?: string;
  lang?: string;
  excerpt?: string;
  word_count?: number;
  saved_at: string;
  /** Default tags to apply on save. Ignored by host versions that don't support it. */
  tags?: string[];
}

/** The wire protocol version shared with the native host. */
export const PROTOCOL_VERSION = 1;

/**
 * One image the extension captured from the page (reusing the browser's cache),
 * base64-encoded so it can ride inside the JSON save message. The host decodes
 * and writes these; it never downloads anything itself.
 */
export interface ImageData {
  /** The URL exactly as it appears in the Markdown, so the host can rewrite it. */
  url: string;
  /** The response's `Content-Type`, used by the host to pick a file extension. */
  content_type: string;
  /** Standard base64 of the raw image bytes. */
  data_base64: string;
}

/** Message sent from the extension to the native host. */
export interface SaveRequest {
  protocol_version: typeof PROTOCOL_VERSION;
  action: "save";
  metadata: SaveRequestMetadata;
  markdown: string;
  images: ImageData[];
}

export interface SaveResponseSuccess {
  protocol_version: typeof PROTOCOL_VERSION;
  ok: true;
  id: string;
  path: string;
}

export interface SaveResponseError {
  protocol_version: typeof PROTOCOL_VERSION;
  ok: false;
  error: string;
  message: string;
}

export type SaveResponse = SaveResponseSuccess | SaveResponseError;

/** Message sent from the extension to check whether a URL is already saved. */
export interface CheckRequest {
  protocol_version: typeof PROTOCOL_VERSION;
  action: "check";
  url: string;
}

export interface CheckResponse {
  protocol_version: typeof PROTOCOL_VERSION;
  ok: true;
  saved: boolean;
  id?: string;
}
