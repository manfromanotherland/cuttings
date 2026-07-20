// SPDX-License-Identifier: MIT

import type { SiteAdapter } from "./types.js";
import { xAdapter } from "./x.js";

export type { SiteAdapter } from "./types.js";

/**
 * The ordered registry of site adapters. To support a new site, implement a
 * {@link SiteAdapter} in its own module and add it here — nothing else changes.
 */
const ADAPTERS: readonly SiteAdapter[] = [xAdapter];

/**
 * Run every adapter that matches `pageUrl` against the cloned document, in
 * registration order. Adapters mutate `doc` in place. A throw from one adapter
 * is contained so it can never block a save; the rest still run.
 */
export function applySiteAdapters(doc: Document, pageUrl: string): void {
  let url: URL;
  try {
    url = new URL(pageUrl);
  } catch {
    return; // A malformed URL can't match any adapter.
  }

  for (const adapter of ADAPTERS) {
    if (!adapter.matches(url)) continue;
    try {
      adapter.preprocess(doc);
    } catch (err) {
      console.warn(`readcontrol: site adapter "${adapter.id}" failed`, err);
    }
  }
}
