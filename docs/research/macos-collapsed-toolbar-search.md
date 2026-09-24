# Collapsed macOS toolbar search

Research date: 2026-09-24. Checked against Apple documentation, Apple sessions, and the public Xcode 27.0 / macOS 27 SDK interfaces.

## Conclusion

The Mac-native control is [`NSSearchToolbarItem`](https://developer.apple.com/documentation/appkit/nssearchtoolbaritem), not a separate search button plus a conditionally mounted SwiftUI search field. It owns the compressed magnifying-glass representation, the field, and the expansion transition. Apple documents that it collapses automatically when toolbar space is low and expands when clicked.

There is no named public `collapsed` or `minimized` property on macOS. SwiftUI's API that explicitly requests a button-like resting search control, `SearchToolbarBehavior.minimize`, is unavailable on macOS in the macOS 27 SDK. `DefaultToolbarItem(kind: .search)` only repositions the system search item, and `ToolbarSpacer` only supplies fixed or flexible space; neither requests compact search behavior.

For an always-compact resting state at a wide window size, a public AppKit layout seam works on macOS 27: give the owned `NSSearchField` a default-low-priority square-width constraint. The SDK header explicitly permits configuring the search field's width constraint; keeping it at `.defaultLow` lets `NSSearchToolbarItem` temporarily override the compact preference with `preferredWidthForSearchField` during a search interaction.

```swift
let searchItem = NSSearchToolbarItem(
    itemIdentifier: NSToolbarItem.Identifier("com.oia.search")
)
let searchField = searchItem.searchField
searchField.placeholderString = "Search Óia"

let compactWidth = searchField.widthAnchor.constraint(
    equalTo: searchField.heightAnchor
)
compactWidth.priority = .defaultLow
compactWidth.isActive = true

// The default is 240 points; set this only if Óia needs another active width.
searchItem.preferredWidthForSearchField = 240
```

With that configuration, the verified macOS 27 behavior is:

- inactive: the native item is 36 × 36 and displays the magnifying glass;
- click or `searchItem.beginSearchInteraction()`: the same item animates to 240 points and focuses its field;
- with an empty query, focus loss or `searchItem.endSearchInteraction()` animates it back to 36 × 36;
- with a nonempty query, AppKit keeps the field expanded after focus loss so the active filter remains visible.

Use `beginSearchInteraction()` for Command-F and `endSearchInteraction()` for an explicit Escape command. `resignsFirstResponderWithCancel` defaults to `true`, so the field's native cancel action clears the query and gives up first responder, allowing the empty field to collapse. The item handles an ordinary click itself. Apple describes `beginSearchInteraction()` and `endSearchInteraction()` as the supported way to control search programmatically. [Begin interaction](https://developer.apple.com/documentation/appkit/nssearchtoolbaritem/beginsearchinteraction%28%29), [end interaction](https://developer.apple.com/documentation/appkit/nssearchtoolbaritem/endsearchinteraction%28%29), and [cancel behavior](https://developer.apple.com/documentation/appkit/nssearchtoolbaritem/resignsfirstresponderwithcancel).

The width-equals-height recipe composes public APIs and uses the customization point called out by Apple's SDK header, but Apple does not document it as a formal always-minimized mode. It therefore needs a manual check on every supported macOS release. The native low-space collapse itself is the documented contract; the low-priority constraint makes the item's resting natural width select that representation even when the toolbar is wide.

## Why the SwiftUI attempts stayed expanded

[`searchable(text:placement:prompt:)`](https://developer.apple.com/documentation/swiftui/view/searchable%28text%3Aplacement%3Aprompt%3A%29) places a search field at the trailing edge of a macOS toolbar. Apple says its precise appearance depends on platform, location, and configuration, but exposes no macOS compact-rest option through this modifier.

The overload with `isPresented` controls activation, not the resting representation. Apple describes it as programmatic presentation and says that on macOS setting it presents and focuses search, while dismissing unfocuses it. Keeping this modifier mounted avoids rebuilding the board, but does not force its toolbar field to become a magnifying-glass button. [`searchable(text:isPresented:placement:prompt:)`](https://developer.apple.com/documentation/swiftui/view/searchable%28text%3Aispresented%3Aplacement%3Aprompt%3A%29), [Managing search interface activation](https://developer.apple.com/documentation/swiftui/managing-search-interface-activation).

`searchFocused` is narrower still: it binds keyboard focus to the search field. It does not control toolbar presentation or compactness. [`searchFocused(_:)`](https://developer.apple.com/documentation/swiftui/view/searchfocused%28_%3A%29).

## macOS 27 API audit

The installed SwiftUI public interface records the following:

| API | macOS availability | What it controls |
| --- | --- | --- |
| `.searchable(..., placement: .toolbar)` | macOS 12+ | Adds the trailing toolbar search field. |
| `.searchable(..., isPresented:)` | macOS 14+ | Programmatic search activation and dismissal. |
| `.searchFocused(...)` | macOS 15+ | Focus only. |
| `SearchToolbarBehavior.automatic` | macOS 26+ | Automatic behavior. |
| `SearchToolbarBehavior.minimize` | **Unavailable on macOS** | Button-like inactive search on iOS and visionOS 26+. |
| `DefaultToolbarItem(kind: .search, placement:)` | macOS 26+ | Repositions the system-provided search item. |
| `ToolbarSpacer` | macOS 26+ | Fixed or flexible toolbar spacing. |
| `NSSearchToolbarItem` | macOS 11+ | Native Mac search item, including low-space compression and begin/end interaction. |

The relevant installed first-party interfaces are:

- `SwiftUI.swiftinterface` lines 7286–7312 (`searchable(..., isPresented:)`), 7493–7502 (`searchFocused`), 8088–8106 and 22463–22486 (`DefaultToolbarItem` and `.search`), 26195–26215 (`SearchToolbarBehavior`), and 29506–29531 (`ToolbarSpacer`).
- `AppKit.framework/Headers/NSSearchToolbarItem.h` lines 20–63 (`searchField`, width-constraint guidance, `preferredWidthForSearchField`, and begin/end interaction).

Apple's current design guidance matches AppKit's adaptive contract: on iPad and Mac, a toolbar search field can scale or collapse into a button according to available space; activation expands it and may move other items into overflow. [Design intuitive search experiences, WWDC26](https://developer.apple.com/videos/play/wwdc2026/292/). The supplied Photos recording has a 490-pixel-wide frame, so its compact rest state is consistent with this documented low-space behavior; it does not by itself establish an always-compact API.

## Recommendation for Óia

Use exactly one persistent `NSSearchToolbarItem`. Óia can keep `.searchable` as the owner of that native item and its query binding, then configure the generated item through the window toolbar when AppKit adds it. Apply the default-low square-width constraint once and keep `.searchFocused` as the Command-F bridge; AppKit continues to own clicking, Escape/cancel, focus loss, and the expansion animation. There is no need to replace the rest of the SwiftUI toolbar or add a second search control. Do not conditionally attach `.searchable`, use private SwiftUI symbols, or use spacing as an implicit compactness switch.

This preserves the system control and animation while making the requested compact resting width explicit. Verify it manually on macOS 15, 26, and 27 because Óia still declares macOS 15 as its deployment target and the always-compact constraint recipe was directly verified only on macOS 27.
