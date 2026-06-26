// SPDX-License-Identifier: MIT

import { describe, expect, it } from "vitest";

import { countWords, extractPage, htmlToMarkdown } from "./extraction.js";

describe("htmlToMarkdown", () => {
  it("converts h1 headings", () => {
    const { markdown } = htmlToMarkdown("<h1>Title</h1>");
    expect(markdown.trim()).toBe("# Title");
  });

  it("converts h2 headings", () => {
    const { markdown } = htmlToMarkdown("<h2>Section</h2>");
    expect(markdown.trim()).toBe("## Section");
  });

  it("converts paragraphs", () => {
    const { markdown } = htmlToMarkdown("<p>Hello world</p>");
    expect(markdown.trim()).toBe("Hello world");
  });

  it("converts bold and italic", () => {
    const { markdown } = htmlToMarkdown("<p><strong>bold</strong> and <em>italic</em></p>");
    expect(markdown).toContain("**bold**");
    expect(markdown).toContain("_italic_");
  });

  it("converts links", () => {
    const { markdown } = htmlToMarkdown('<a href="https://example.com">Example</a>');
    expect(markdown.trim()).toBe("[Example](https://example.com)");
  });

  it("unwraps in-page anchor links to plain text", () => {
    const { markdown } = htmlToMarkdown('<a href="#section">Jump to section</a>');
    expect(markdown.trim()).toBe("Jump to section");
  });

  it("keeps text around an unwrapped in-page anchor", () => {
    const { markdown } = htmlToMarkdown('<p>See <a href="#notes">the notes</a> below.</p>');
    expect(markdown.trim()).toBe("See the notes below.");
  });

  it("still converts external links normally", () => {
    const { markdown } = htmlToMarkdown(
      '<p><a href="#local">here</a> and <a href="https://example.com">there</a></p>',
    );
    expect(markdown.trim()).toBe("here and [there](https://example.com)");
  });

  it("converts fenced code blocks", () => {
    const { markdown } = htmlToMarkdown("<pre><code>const x = 1;</code></pre>");
    expect(markdown).toContain("```");
    expect(markdown).toContain("const x = 1;");
  });

  it("converts unordered lists", () => {
    const { markdown } = htmlToMarkdown("<ul><li>one</li><li>two</li></ul>");
    expect(markdown).toMatch(/^-\s+one/m);
    expect(markdown).toMatch(/^-\s+two/m);
  });

  it("collects image URLs and converts to markdown image syntax", () => {
    const { markdown, imageUrls } = htmlToMarkdown(
      '<img src="https://example.com/img.jpg" alt="A photo">',
    );
    expect(imageUrls).toContain("https://example.com/img.jpg");
    expect(markdown).toContain("![A photo](https://example.com/img.jpg)");
  });

  it("skips data: URIs from imageUrls", () => {
    const { imageUrls } = htmlToMarkdown('<img src="data:image/png;base64,abc" alt="">');
    expect(imageUrls).toHaveLength(0);
  });

  it("collects multiple distinct image URLs", () => {
    const { imageUrls } = htmlToMarkdown(
      '<img src="https://example.com/a.jpg"><img src="https://example.com/b.png">',
    );
    expect(imageUrls).toHaveLength(2);
    expect(imageUrls).toContain("https://example.com/a.jpg");
    expect(imageUrls).toContain("https://example.com/b.png");
  });
});

describe("extractPage", () => {
  function buildDoc(body: string): Document {
    const doc = document.implementation.createHTMLDocument("Test Article");
    doc.body.innerHTML = body;
    return doc;
  }

  // A long article body so Readability accepts it; section headings carry a
  // class whose name trips Readability's "header" unlikely-candidate filter.
  const para =
    "<p>" +
    "This is a sufficiently long paragraph of article prose so that Readability " +
    "treats the surrounding container as the main content and does not bail out. ".repeat(6) +
    "</p>";
  const article =
    "<article>" +
    para +
    '<h2 class="header-anchor-post">First section</h2>' +
    para +
    '<h2 class="header-anchor-post">Second section</h2>' +
    para +
    "</article>";

  it("keeps in-article headings whose class trips the 'header' filter", () => {
    const result = extractPage(buildDoc(article), "https://example.com/post");
    expect(result).not.toBeNull();
    expect(result!.markdown).toContain("First section");
    expect(result!.markdown).toContain("Second section");
    expect(result!.markdown).toMatch(/^##\s+.*First section/m);
    expect(result!.markdown).toMatch(/^##\s+.*Second section/m);
  });
});

describe("countWords", () => {
  it("counts simple words", () => {
    expect(countWords("hello world foo")).toBe(3);
  });

  it("handles multiple spaces and newlines", () => {
    expect(countWords("  hello\n  world  ")).toBe(2);
  });

  it("returns 0 for empty string", () => {
    expect(countWords("")).toBe(0);
  });

  it("returns 0 for whitespace-only string", () => {
    expect(countWords("   ")).toBe(0);
  });
});
