// SPDX-License-Identifier: MIT

import { describe, expect, it } from "vitest";

import { extractPage } from "../extraction.js";
import { LOOPS_PARAGRAPH, MEDIA_SECTION, xArticleFixture } from "./x.fixture.js";
import { xAdapter } from "./x.js";

function makeDoc(body: string): Document {
  const doc = document.implementation.createHTMLDocument("t");
  doc.body.innerHTML = body;
  return doc;
}

function text(node: { textContent: string | null } | null): string {
  return (node?.textContent ?? "").replace(/\s+/g, " ").trim();
}

const LOOPS_HREF = "https://x.com/addyosmani/article/2064127981161959567?lang=en";
const LOOPS_SENTENCE =
  "In the past year, the conversation around agentic engineering has moved to " +
  "harnesses and loops, fleets and software factories. My 2c is engineers need " +
  "to own the outer loop - the accountability for these systems.";

describe("xAdapter.matches", () => {
  it("matches x.com and twitter.com hosts", () => {
    for (const host of ["x.com", "twitter.com", "mobile.twitter.com", "www.x.com"]) {
      expect(xAdapter.matches(new URL(`https://${host}/a/status/1`))).toBe(true);
    }
  });

  it("does not match look-alike hosts", () => {
    for (const host of ["example.com", "notx.com", "x.com.evil.com"]) {
      expect(xAdapter.matches(new URL(`https://${host}/`))).toBe(false);
    }
  });
});

describe("xAdapter.preprocess (real X markup)", () => {
  it("unwraps the block <div> around a reference link, leaving it inline", () => {
    const doc = makeDoc(LOOPS_PARAGRAPH);
    const paragraph = doc.querySelector(".public-DraftStyleDefault-block")!;
    expect(paragraph.querySelector("div")).not.toBeNull(); // wrapper present

    xAdapter.preprocess(doc);

    // The block wrapper is gone; the anchor is now a direct inline child.
    expect(paragraph.querySelector("div")).toBeNull();
    const link = paragraph.querySelector("a")!;
    expect(link.parentElement).toBe(paragraph);
    expect(link.getAttribute("href")).toBe(LOOPS_HREF);
    expect(text(link)).toBe("loops");
  });

  it("keeps the sentence in its original word order", () => {
    const doc = makeDoc(LOOPS_PARAGRAPH);
    const before = text(doc.body);
    xAdapter.preprocess(doc);
    expect(text(doc.body)).toBe(before);
    expect(text(doc.body)).toBe(LOOPS_SENTENCE);
  });

  it("leaves X media links (root-relative, wrapping an image) untouched", () => {
    const doc = makeDoc(MEDIA_SECTION);
    const before = doc.body.innerHTML;
    xAdapter.preprocess(doc);
    expect(doc.body.innerHTML).toBe(before);
  });

  it("is idempotent", () => {
    const doc = makeDoc(LOOPS_PARAGRAPH);
    xAdapter.preprocess(doc);
    const once = doc.body.innerHTML;
    xAdapter.preprocess(doc);
    expect(doc.body.innerHTML).toBe(once);
  });
});

describe("extractPage on real X markup", () => {
  it("keeps the mid-sentence reference, in place and in order", () => {
    const result = extractPage(makeDoc(xArticleFixture()), "https://x.com/addyosmani/status/1");
    expect(result).not.toBeNull();
    expect(result!.markdown).toContain(`[loops](${LOOPS_HREF})`);
    // The sentence is whole: no gap, no reordering, no split paragraph.
    expect(result!.markdown).toContain(
      "has moved to harnesses and [loops](" + LOOPS_HREF + "), fleets and software factories.",
    );
  });

  it("keeps a cited-source reference between two sentence runs", () => {
    const result = extractPage(makeDoc(xArticleFixture()), "https://x.com/addyosmani/status/1");
    expect(result!.markdown).toContain(
      "[Sonar's 2026 State of Code report]" +
        "(https://www.sonarsource.com/state-of-code-developer-survey-report.pdf) found that 42%",
    );
  });

  it("still collects the article's media image", () => {
    const result = extractPage(makeDoc(xArticleFixture()), "https://x.com/addyosmani/status/1");
    expect(result!.image_urls.some((u) => u.includes("pbs.twimg.com/media/"))).toBe(true);
  });

  it("drops the same references on a non-X host (adapter is host-gated)", () => {
    const result = extractPage(makeDoc(xArticleFixture()), "https://example.com/post");
    expect(result!.markdown).not.toContain("[loops]");
  });
});
