// SPDX-License-Identifier: GPL-3.0-or-later

import AppKit
import Foundation

enum ReadingLink {
    /// UTM parameters identifying Cuttings as the referrer, so sites can see
    /// the traffic came from the app.
    private static let utmParameters = [
        URLQueryItem(name: "utm_source", value: "cuttings")
    ]

    /// Returns `url` with Cuttings' UTM reference appended. Existing query
    /// items are preserved; any `utm_source`/`utm_medium` already present are
    /// left untouched so we never double up. Returns `url` unchanged when it
    /// can't be decomposed into components.
    static func tagged(_ url: URL) -> URL {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        var items = components.queryItems ?? []
        let existing = Set(items.map(\.name))
        for parameter in utmParameters where !existing.contains(parameter.name) {
            items.append(parameter)
        }
        components.queryItems = items
        return components.url ?? url
    }

    /// Opens the reading's original URL in the default browser, tagged with the
    /// UTM reference.
    static func open(_ url: URL) {
        NSWorkspace.shared.open(tagged(url))
    }
}
