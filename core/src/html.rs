// SPDX-License-Identifier: MIT

use pulldown_cmark::{html, Options, Parser};

/// Convert a Markdown string to an HTML fragment.
pub fn markdown_to_html(markdown: &str) -> String {
    let opts = Options::ENABLE_STRIKETHROUGH
        | Options::ENABLE_TABLES
        | Options::ENABLE_FOOTNOTES
        | Options::ENABLE_TASKLISTS;
    let parser = Parser::new_ext(markdown, opts);
    let mut out = String::with_capacity(markdown.len() * 2);
    html::push_html(&mut out, parser);
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn converts_heading() {
        let html = markdown_to_html("# Hello");
        assert!(html.contains("<h1>Hello</h1>"));
    }

    #[test]
    fn converts_link() {
        let html = markdown_to_html("[text](https://example.com)");
        assert!(html.contains("href=\"https://example.com\""));
    }

    #[test]
    fn preserves_image_src() {
        let html = markdown_to_html("![alt](../assets/id/img.jpg)");
        assert!(html.contains("src=\"../assets/id/img.jpg\""));
    }
}
