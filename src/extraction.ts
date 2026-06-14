// SPDX-License-Identifier: MIT

import { Readability } from "@mozilla/readability";
import TurndownService from "turndown";

import type { SaveRequestMetadata } from "./protocol.js";

export interface ExtractionResult {
  metadata: SaveRequestMetadata;
  markdown: string;
  image_urls: string[];
}

/**
 * Run Readability against a cloned document and convert the result to Markdown.
 * Returns null if the page doesn't look like an article.
 */
export function extractPage(doc: Document, pageUrl: string): ExtractionResult | null {
  const article = new Readability(doc.cloneNode(true) as Document).parse();
  if (!article?.content) return null;

  const { markdown, imageUrls } = htmlToMarkdown(article.content);

  const author = article.byline ?? undefined;
  const site = article.siteName || new URL(pageUrl).hostname;
  const lang = article.lang || doc.documentElement.lang || undefined;
  const excerpt = article.excerpt ?? undefined;

  const metadata: SaveRequestMetadata = {
    url: pageUrl,
    canonical_url: getCanonicalUrl(doc, pageUrl),
    title: article.title || doc.title,
    saved_at: new Date().toISOString(),
    ...(author ? { author } : {}),
    site,
    ...(lang ? { lang } : {}),
    ...(excerpt ? { excerpt } : {}),
    word_count: countWords(article.textContent ?? ""),
  };

  return { metadata, markdown, image_urls: imageUrls };
}

/** Convert an HTML string to CommonMark Markdown, collecting image URLs. */
export function htmlToMarkdown(html: string): { markdown: string; imageUrls: string[] } {
  const imageUrls: string[] = [];

  const td = new TurndownService({
    headingStyle: "atx",
    codeBlockStyle: "fenced",
    bulletListMarker: "-",
  });

  td.addRule("images", {
    filter: "img",
    replacement(_content, node) {
      const img = node as HTMLImageElement;
      const src = img.getAttribute("src") ?? "";
      const alt = img.getAttribute("alt") ?? "";
      if (src && !src.startsWith("data:")) {
        imageUrls.push(src);
      }
      return src ? `![${alt}](${src})` : "";
    },
  });

  const markdown = td.turndown(html);
  return { markdown, imageUrls };
}

/** Count whitespace-delimited words in a plain-text string. */
export function countWords(text: string): number {
  return text.trim().split(/\s+/).filter(Boolean).length;
}

function getCanonicalUrl(doc: Document, fallback: string): string {
  return (
    doc.querySelector<HTMLLinkElement>("link[rel='canonical']")?.href ||
    doc.querySelector<HTMLMetaElement>("meta[property='og:url']")?.content ||
    fallback
  );
}
