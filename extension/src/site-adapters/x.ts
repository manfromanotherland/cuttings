// SPDX-License-Identifier: MIT

import type { SiteAdapter } from "./types.js";

/**
 * X's longform Articles are rendered by a Draft.js editor that wraps every
 * outbound reference link — cited sources, @-mentions — in its own block-level
 * <div> nested inside the paragraph:
 *
 *   <div class="public-DraftStyleDefault-block">
 *     <span><span data-text="true"> and </span></span>
 *     <div class="css-…"><a href="https://…">loops</a></div>   ← block wrapper
 *     <span><span data-text="true">, </span></span>
 *   </div>
 *
 * Readability's conditional-cleaning pass runs over <div>s, and this one is a
 * block whose entire text is a short link, so it scores as boilerplate and is
 * removed. The reference then vanishes — URL and visible label alike — and
 * because the wrapper is block-level it also splits the sentence in two,
 * yielding "… has moved to harnesses and" / ", fleets and software factories."
 *
 * The fix is to unwrap that wrapper *in place*, leaving the anchor as an inline
 * child of the paragraph so it flows with the surrounding text and is kept.
 * In place is the whole point: relocating the node would reorder the sentence.
 *
 * X's media links are left alone — they are root-relative (/user/article/…/media/…)
 * and wrap an <img>, so the image rule keeps handling them as images.
 */
export const xAdapter: SiteAdapter = {
  id: "x",
  matches(url) {
    return /(^|\.)(x|twitter)\.com$/i.test(url.hostname);
  },
  preprocess(doc) {
    // Snapshot first: the loop replaces nodes as it goes.
    for (const anchor of Array.from(doc.querySelectorAll("a[href]"))) {
      inlineReferenceLink(anchor as HTMLAnchorElement);
    }
  },
};

/**
 * Elements that carry meaning of their own, so a wrapper search must never widen
 * into them — unwrapping one would destroy the paragraph, list item, or heading
 * rather than just the anonymous block around a link.
 */
const STRUCTURAL_TAGS = new Set([
  "ARTICLE",
  "MAIN",
  "SECTION",
  "BODY",
  "HTML",
  "P",
  "LI",
  "UL",
  "OL",
  "BLOCKQUOTE",
  "FIGURE",
  "FIGCAPTION",
  "TABLE",
  "TD",
  "TH",
  "H1",
  "H2",
  "H3",
  "H4",
  "H5",
  "H6",
]);

/** Unwrap the block-level wrapper around a reference link, leaving it inline. */
function inlineReferenceLink(a: HTMLAnchorElement): void {
  const href = a.getAttribute("href") ?? "";
  // Reference links are absolute; X's own media links are root-relative and
  // wrap an image. Both checks keep media out of this transform.
  if (!/^https?:\/\//i.test(href)) return;
  if (a.querySelector("img")) return;

  const label = normalize(a.textContent);
  if (!label) return;

  // Widen to the outermost wrapper holding nothing but this link.
  let wrapper: Element = a;
  while (
    wrapper.parentElement &&
    !STRUCTURAL_TAGS.has(wrapper.parentElement.tagName) &&
    normalize(wrapper.parentElement.textContent) === label
  ) {
    wrapper = wrapper.parentElement;
  }

  // Swapping the wrapper for the anchor keeps the link in the exact same spot,
  // inline instead of block-level. No wrapper means it is already inline.
  if (wrapper !== a) wrapper.replaceWith(a);
}

function normalize(text: string | null): string {
  return (text ?? "").replace(/\s+/g, " ").trim();
}
