// SPDX-License-Identifier: MIT

/**
 * A site-specific pre-processor that runs against the cloned document *before*
 * Readability, giving one host a chance to reshape its markup into something the
 * generic extractor handles cleanly.
 *
 * Adapters exist because Readability is tuned for prose-shaped article HTML.
 * Single-page apps (X, and others we'll add later) render content — inline
 * links, mentions, embeds — as structures Readability discards as boilerplate.
 * An adapter normalizes those into plain article markup so nothing is lost.
 *
 * Contract:
 *  - `preprocess` mutates `doc` in place and returns nothing.
 *  - It must be defensive: the registry catches throws so a broken adapter can
 *    never block a save, but adapters should still avoid assuming any given
 *    node exists — real-world markup drifts.
 *  - It should be idempotent, so running twice is harmless.
 */
export interface SiteAdapter {
  /** Stable identifier, used in logs and tests. */
  readonly id: string;

  /** Whether this adapter applies to the page being extracted. */
  matches(url: URL): boolean;

  /** Reshape the cloned document in place, ahead of Readability. */
  preprocess(doc: Document): void;
}
