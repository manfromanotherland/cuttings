// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// User-selectable sort field for the reading list. Mirrors the core's sort
/// field; persisted as its `rawValue` in `UserDefaults`.
enum ReadingSort: String, CaseIterable, Identifiable {
    case relevance
    case savedAt
    case readAt
    case rating
    case timeToRead

    var id: String {
        rawValue
    }

    /// Label shown in the sort-field picker.
    var label: String {
        switch self {
        case .relevance: "Relevance"
        case .savedAt: "Date saved"
        case .readAt: "Date read"
        case .rating: "Rating"
        case .timeToRead: "Time to read"
        }
    }

    /// Direction label tailored to the field (e.g. "Newest first" vs
    /// "Highest rated"), for the ascending/descending picker.
    func directionLabel(ascending: Bool) -> String {
        switch self {
        case .relevance: "Most relevant first"
        case .savedAt: ascending ? "Oldest first" : "Newest first"
        case .readAt: ascending ? "Read least recently" : "Read most recently"
        case .rating: ascending ? "Lowest rated" : "Highest rated"
        case .timeToRead: ascending ? "Shortest first" : "Longest first"
        }
    }

    /// Sort options offered in the UI. Relevance only makes sense while a search
    /// is active, so it's excluded otherwise.
    static func options(searching: Bool) -> [ReadingSort] {
        searching ? allCases : allCases.filter { $0 != .relevance }
    }
}
