// SPDX-License-Identifier: MIT

import { describe, expect, it } from "vitest";

import { extractPageMetadata } from "./page-metadata.js";

function buildDoc(head: string, title = "Document title"): Document {
  const doc = document.implementation.createHTMLDocument(title);
  doc.head.insertAdjacentHTML("beforeend", head);
  return doc;
}

describe("extractPageMetadata", () => {
  it("collects canonical and social metadata in deterministic priority order", () => {
    const doc = buildDoc(`
      <link rel="canonical" href="/canonical">
      <meta property="og:url" content="https://ignored.example.com/open-graph">
      <meta property="og:title" content="Open Graph title">
      <meta name="twitter:title" content="Twitter title">
      <meta property="og:site_name" content="Example Journal">
      <meta property="og:description" content="Open Graph description">
      <meta name="description" content="Plain description">
      <meta property="og:image:secure_url" content="/secure-social.png">
      <meta property="og:image" content="https://cdn.example.com/social.jpg">
      <meta name="twitter:image" content="/twitter.png">
    `);

    const result = extractPageMetadata(doc, "https://example.com/post?ref=feed");

    expect(result).toMatchObject({
      canonicalUrl: "https://example.com/canonical",
      title: "Open Graph title",
      site: "Example Journal",
      excerpt: "Open Graph description",
    });
    expect(result.socialImageUrls).toEqual([
      "https://example.com/secure-social.png",
      "https://cdn.example.com/social.jpg",
      "https://example.com/twitter.png",
    ]);
  });

  it("prefers the largest declared raster favicon and keeps fallbacks", () => {
    const doc = buildDoc(`
      <link rel="shortcut icon" href="/small.ico" sizes="16x16">
      <link rel="icon" href="/large.png" type="image/png" sizes="64x64">
      <link rel="apple-touch-icon" href="/touch.png" sizes="180x180">
      <link rel="icon" href="/unsafe.svg" type="image/svg+xml" sizes="any">
      <link rel="icon" href="data:image/png;base64,AAAA" sizes="256x256">
    `);

    expect(extractPageMetadata(doc, "https://example.com/post").faviconUrls).toEqual([
      "https://example.com/touch.png",
      "https://example.com/large.png",
      "https://example.com/small.ico",
    ]);
  });

  it("rejects non-http and credential-bearing image metadata", () => {
    const doc = buildDoc(`
      <meta property="og:image" content="file:///tmp/private.png">
      <meta name="twitter:image" content="https://user:secret@example.com/private.png">
      <link rel="icon" href="javascript:alert(1)">
    `);

    const result = extractPageMetadata(doc, "https://example.com/post");
    expect(result.socialImageUrls).toEqual([]);
    expect(result.faviconUrls).toEqual([]);
  });
});
