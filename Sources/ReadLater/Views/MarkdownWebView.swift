// SPDX-License-Identifier: GPL-3.0-or-later

import SwiftUI
import WebKit

// Custom URL scheme used to serve local article assets.
// Registered once per WKWebView; the handler is updated with the current
// library URL before each page load.
private let assetScheme = "readlater"

final class AssetSchemeHandler: NSObject, WKURLSchemeHandler, WKNavigationDelegate {
    var libraryURL: URL?

    // ── Link handling ─────────────────────────────────────────────────────
    // Open external links in the user's browser instead of navigating inside
    // the reader. In-page anchor jumps (footnotes, etc.) are left to WebKit.
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        if navigationAction.navigationType == .linkActivated,
           let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" || scheme == "mailto" {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        decisionHandler(.allow)
    }

    func webView(_ webView: WKWebView, start task: WKURLSchemeTask) {
        guard
            let libraryURL,
            let url = task.request.url,
            url.scheme == assetScheme
        else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        // URL is readlater://assets/<id>/<filename>
        // url.host = "assets", url.path = "/<id>/<filename>"
        let relative = url.path.hasPrefix("/") ? String(url.path.dropFirst()) : url.path
        let fileURL = libraryURL
            .appendingPathComponent("assets")
            .appendingPathComponent(relative)

        guard let data = try? Data(contentsOf: fileURL) else {
            task.didFailWithError(URLError(.fileDoesNotExist))
            return
        }

        let mime: String
        switch fileURL.pathExtension.lowercased() {
        case "png":  mime = "image/png"
        case "gif":  mime = "image/gif"
        case "webp": mime = "image/webp"
        case "svg":  mime = "image/svg+xml"
        default:     mime = "image/jpeg"
        }

        let response = URLResponse(
            url: url, mimeType: mime,
            expectedContentLength: data.count,
            textEncodingName: nil
        )
        task.didReceive(response)
        task.didReceive(data)
        task.didFinish()
    }

    func webView(_ webView: WKWebView, stop task: WKURLSchemeTask) {}
}

struct MarkdownWebView: NSViewRepresentable {
    let html: String
    let libraryURL: URL?
    var font: ReaderFont = .system
    var fontSize: ReaderFontSize = .medium

    func makeCoordinator() -> AssetSchemeHandler {
        AssetSchemeHandler()
    }

    func makeNSView(context: Context) -> WKWebView {
        let prefs = WKWebpagePreferences()
        prefs.allowsContentJavaScript = false

        let config = WKWebViewConfiguration()
        config.defaultWebpagePreferences = prefs
        config.setURLSchemeHandler(context.coordinator, forURLScheme: assetScheme)

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.setValue(false, forKey: "drawsBackground")
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.libraryURL = libraryURL
        webView.loadHTMLString(wrappedHTML, baseURL: nil)
    }

    // ── HTML template ─────────────────────────────────────────────────────

    private var wrappedHTML: String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
          :root { color-scheme: light dark; }
          *, *::before, *::after { box-sizing: border-box; }
          body {
            font-family: \(font.cssFamily);
            font-size: \(fontSize.rawValue)px;
            line-height: 1.75;
            max-width: 680px;
            margin: 0 auto;
            padding: 24px 20px 80px;
            color: #1a1a1a;
            background: transparent;
            word-wrap: break-word;
          }
          @media (prefers-color-scheme: dark) {
            body { color: #e0e0e0; }
            pre, code { background: rgba(255,255,255,.08); }
            blockquote { border-color: rgba(255,255,255,.2); color: #aaa; }
          }
          h1, h2, h3, h4 { line-height: 1.3; margin-top: 1.5em; }
          h1 { font-size: 1.6em; }
          h2 { font-size: 1.3em; }
          h3 { font-size: 1.1em; }
          a { color: #0066cc; text-decoration: none; }
          a:hover { text-decoration: underline; }
          img { max-width: 100%; height: auto; border-radius: 6px; display: block; margin: 1em 0; }
          pre {
            overflow-x: auto;
            background: rgba(0,0,0,.04);
            padding: 14px 16px;
            border-radius: 8px;
            font-size: 0.88em;
          }
          code {
            font-family: 'SF Mono', ui-monospace, monospace;
            font-size: 0.9em;
            background: rgba(0,0,0,.06);
            padding: 2px 5px;
            border-radius: 4px;
          }
          pre code { background: none; padding: 0; font-size: inherit; }
          blockquote {
            margin: 1em 0;
            padding-left: 16px;
            border-left: 3px solid rgba(0,0,0,.2);
            color: #666;
          }
          table { border-collapse: collapse; width: 100%; margin: 1em 0; }
          th, td { border: 1px solid rgba(0,0,0,.15); padding: 8px 12px; text-align: left; }
          th { background: rgba(0,0,0,.04); }
          hr { border: none; border-top: 1px solid rgba(0,0,0,.1); margin: 2em 0; }
        </style>
        </head>
        <body>\(html)</body>
        </html>
        """
    }
}
