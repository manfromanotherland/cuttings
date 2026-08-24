// SPDX-License-Identifier: MIT

import { describe, expect, it } from "vitest";

import { applySiteAdapters } from "./index.js";
import { LOOPS_PARAGRAPH } from "./x.fixture.js";

function makeDoc(body: string): Document {
  const doc = document.implementation.createHTMLDocument("t");
  doc.body.innerHTML = body;
  return doc;
}

/** The block <div> X wraps a reference link in, which the x adapter unwraps. */
function refWrapper(doc: Document): Element | null {
  return doc.querySelector(".public-DraftStyleDefault-block > div");
}

describe("applySiteAdapters", () => {
  it("runs the matching adapter for the page host", () => {
    const doc = makeDoc(LOOPS_PARAGRAPH);
    expect(refWrapper(doc)).not.toBeNull();

    applySiteAdapters(doc, "https://x.com/addyosmani/status/1");

    expect(refWrapper(doc)).toBeNull();
    expect(doc.querySelector(".public-DraftStyleDefault-block > a")).not.toBeNull();
  });

  it("leaves the document untouched for a non-matching host", () => {
    const doc = makeDoc(LOOPS_PARAGRAPH);
    const before = doc.body.innerHTML;
    applySiteAdapters(doc, "https://example.com/post");
    expect(doc.body.innerHTML).toBe(before);
  });

  it("does not throw on a malformed URL", () => {
    const doc = makeDoc(LOOPS_PARAGRAPH);
    const before = doc.body.innerHTML;
    expect(() => applySiteAdapters(doc, "not a url")).not.toThrow();
    expect(doc.body.innerHTML).toBe(before);
  });
});
