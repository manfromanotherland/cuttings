// SPDX-License-Identifier: GPL-3.0-or-later

import Foundation

/// Sort field passed to the core listing query. The board uses saved date for
/// browsing and relevance for search.
enum ReadingSort {
    case relevance
    case savedAt
}
