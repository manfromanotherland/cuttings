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

/** Message sent from the extension to the native host. */
export interface SaveRequest {
  protocol_version: 1;
  action: "save";
  metadata: SaveRequestMetadata;
  markdown: string;
  image_urls: string[];
}

export interface SaveResponseSuccess {
  protocol_version: 1;
  ok: true;
  id: string;
  path: string;
}

export interface SaveResponseError {
  protocol_version: 1;
  ok: false;
  error: string;
  message: string;
}

export type SaveResponse = SaveResponseSuccess | SaveResponseError;
