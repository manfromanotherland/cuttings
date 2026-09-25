# Collapsed macOS toolbar search

Research date: 2026-09-24; availability rechecked 2026-09-25 against Apple's current documentation and the public Xcode 27.0 / macOS 27 SDK interfaces and compiler.

## Conclusion

The Mac-native control is [`NSSearchToolbarItem`](https://developer.apple.com/documentation/appkit/nssearchtoolbaritem), not a separate search button plus a conditionally mounted SwiftUI search field. It owns the compressed magnifying-glass representation, the field, and the expansion transition. Apple documents that it collapses automatically when toolbar space is low and expands when clicked.

Xcode 26 introduced the `SearchToolbarBehavior` type and the `searchToolbarBehavior(_:)` modifier on native macOS 26. That does **not** make every behavior value available on macOS. The exact member that requests a button-like resting search control, `SearchToolbarBehavior.minimize`, is available on iOS, iPadOS, Mac Catalyst, and visionOS 26, but is explicitly unavailable on a native macOS target. Native macOS receives `.automatic` only. This remains true in the current Xcode 27 SDK and compiler. [`searchToolbarBehavior(_:)`](https://developer.apple.com/documentation/swiftui/view/searchtoolbarbehavior%28_%3A%29), [`.automatic`](https://developer.apple.com/documentation/swiftui/searchtoolbarbehavior/automatic), [`.minimize`](https://developer.apple.com/documentation/swiftui/searchtoolbarbehavior/minimize).

There is therefore still no named public force-minimize setting for a native macOS toolbar search item. `DefaultToolbarItem(kind: .search)` only repositions the system search item, and `ToolbarSpacer` only supplies fixed or flexible space; neither requests compact search behavior.

For an always-compact resting state at a wide window size, an AppKit layout workaround can give the owned `NSSearchField` a default-low-priority square-width constraint. The SDK header permits configuring the search field's width constraint; keeping it at `.defaultLow` lets `NSSearchToolbarItem` temporarily override the compact preference with `preferredWidthForSearchField` during a search interaction.

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

In an isolated macOS 27 check, that configuration produced:

- inactive: the native item is 36 × 36 and displays the magnifying glass;
- click or `searchItem.beginSearchInteraction()`: the same item animates to 240 points and focuses its field;
- with an empty query, focus loss or `searchItem.endSearchInteraction()` animates it back to 36 × 36;
- with a nonempty query, AppKit keeps the field expanded after focus loss so the active filter remains visible.

Use `beginSearchInteraction()` for Command-F and `endSearchInteraction()` for an explicit Escape command. `resignsFirstResponderWithCancel` defaults to `true`, so the field's native cancel action clears the query and gives up first responder, allowing the empty field to collapse. The item handles an ordinary click itself. Apple describes `beginSearchInteraction()` and `endSearchInteraction()` as the supported way to control search programmatically. [Begin interaction](https://developer.apple.com/documentation/appkit/nssearchtoolbaritem/beginsearchinteraction%28%29), [end interaction](https://developer.apple.com/documentation/appkit/nssearchtoolbaritem/endsearchinteraction%28%29), and [cancel behavior](https://developer.apple.com/documentation/appkit/nssearchtoolbaritem/resignsfirstresponderwithcancel).

The width-equals-height recipe composes public APIs and uses the customization point called out by Apple's SDK header, but Apple does not document this recipe as a formal always-minimized mode. Treat it as an isolated layout workaround, not a guaranteed semantic API, and check it manually in Óia on every supported macOS release. The user's current Óia check still showed the field expanded, so the isolated result is not product acceptance. The native low-space collapse itself is the documented contract.

## Why the SwiftUI attempts stayed expanded

[`searchable(text:placement:prompt:)`](https://developer.apple.com/documentation/swiftui/view/searchable%28text%3Aplacement%3Aprompt%3A%29) places a search field at the trailing edge of a macOS toolbar. Apple says its precise appearance depends on platform, location, and configuration, but exposes no macOS compact-rest option through this modifier.

The overload with `isPresented` controls activation, not the resting representation. Apple describes it as programmatic presentation and says that on macOS setting it presents and focuses search, while dismissing unfocuses it. Keeping this modifier mounted avoids rebuilding the board, but does not force its toolbar field to become a magnifying-glass button. [`searchable(text:isPresented:placement:prompt:)`](https://developer.apple.com/documentation/swiftui/view/searchable%28text%3Aispresented%3Aplacement%3Aprompt%3A%29), [Managing search interface activation](https://developer.apple.com/documentation/swiftui/managing-search-interface-activation).

`searchFocused` is narrower still: it binds keyboard focus to the search field. It does not control toolbar presentation or compactness. [`searchFocused(_:)`](https://developer.apple.com/documentation/swiftui/view/searchfocused%28_%3A%29).

## Native macOS 26 and 27 API audit

The installed SwiftUI public interface records the following:

| API | macOS availability | What it controls |
| --- | --- | --- |
| `.searchable(..., placement: .toolbar)` | macOS 12+ | Adds the trailing toolbar search field. |
| `.searchable(..., isPresented:)` | macOS 14+ | Programmatic search activation and dismissal. |
| `.searchFocused(...)` | macOS 15+ | Focus only. |
| `.searchToolbarBehavior(_:)` | macOS 26+ | Applies a `SearchToolbarBehavior`; native macOS can pass `.automatic`. |
| `SearchToolbarBehavior.automatic` | macOS 26+ | Automatic behavior. |
| `SearchToolbarBehavior.minimize` | **Unavailable on native macOS** | Button-like inactive search on iOS, iPadOS, Mac Catalyst, and visionOS 26+. |
| `DefaultToolbarItem(kind: .search, placement:)` | macOS 26+ | Repositions the system-provided search item. |
| `ToolbarSpacer` | macOS 26+ | Fixed or flexible toolbar spacing. |
| `.toolbarMinimizationBehavior(_:for:)` | macOS 27+ | A separate whole-toolbar scrolling API, not search-item presentation. |
| `NSSearchToolbarItem` | macOS 11+ | Native Mac search item, including low-space compression and begin/end interaction. |

The decisive installed declaration is:

```swift
@available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
public struct SearchToolbarBehavior {
    public static var automatic: SearchToolbarBehavior { get }

    @available(iOS 26.0, visionOS 26.0, *)
    @available(macOS, unavailable)
    @available(tvOS, unavailable)
    @available(watchOS, unavailable)
    public static var minimize: SearchToolbarBehavior { get }
}

extension View {
    @available(iOS 26.0, macOS 26.0, tvOS 26.0, watchOS 26.0, visionOS 26.0, *)
    public func searchToolbarBehavior(_ behavior: SearchToolbarBehavior) -> some View
}
```

Apple's current documentation metadata agrees with the SDK: the modifier and type list macOS 26, while the `.minimize` symbol omits macOS and lists Mac Catalyst instead. Mac Catalyst availability does not make the member callable from Óia's native `platform: macOS` target.

A direct type-check with the installed Xcode 27 compiler used the complete modifier chain for arm64 and x86_64 targets on both macOS 26 and macOS 27:

```swift
Text("Content")
    .searchable(text: .constant(""), placement: .toolbar)
    .searchToolbarBehavior(.minimize)
```

All four checks fail with `'minimize' is unavailable in macOS`; replacing `.minimize` with `.automatic` succeeds for all four. This rules out deployment-target and architecture ambiguity. An `if #available(macOS 26, *)` branch cannot bypass an explicit platform-unavailable annotation.

The relevant installed first-party interfaces are:

- `SwiftUI.swiftinterface` lines 7286–7312 (`searchable(..., isPresented:)`), 7493–7502 (`searchFocused`), 8088–8106 and 22463–22486 (`DefaultToolbarItem` and `.search`), 14254–14286 (`ToolbarMinimizationBehavior`), 26195–26215 (`SearchToolbarBehavior`), and 29506–29531 (`ToolbarSpacer`).
- `AppKit.framework/Headers/NSSearchToolbarItem.h` lines 20–63 (`searchField`, width-constraint guidance, `preferredWidthForSearchField`, and begin/end interaction).
- Xcode's first-party `IDEIntelligenceChat.framework/Resources/AdditionalDocumentation/SwiftUI-New-Toolbar-Features.md` puts the explicit `.minimize` recommendation under iOS and iPadOS; its separate macOS section does not recommend that member.

Apple's design guidance matches AppKit's adaptive contract: on iPad and Mac, a toolbar search field can scale or collapse into a button according to available space; activation expands it and may move other items into overflow. [Build a SwiftUI app with the new design, WWDC25](https://developer.apple.com/videos/play/wwdc2025/323/), [Design intuitive search experiences, WWDC26](https://developer.apple.com/videos/play/wwdc2026/292/). The WWDC25 session also introduces `searchToolbarBehavior(.minimize)`, but the target-specific SDK declaration and current symbol metadata limit that explicit value to iOS, iPadOS, Mac Catalyst, and visionOS. The supplied Photos recording has a 490-pixel-wide frame, so its compact rest state is consistent with native Mac's documented low-space behavior; it does not by itself establish a native-macOS force-minimize API.

## Not `toolbarMinimizationBehavior`

`toolbarMinimizationBehavior(_:for:)` is a different SwiftUI API introduced across Apple SDKs in version 27. It controls how an entire toolbar or navigation bar minimizes in response to scrolling; it does not choose the resting representation of a search item.

Apple documents `.navigationBar` as the only supported placement. That placement, along with `.onScrollDown`, `.onScrollUp`, and `.never`, is unavailable on native macOS in the Xcode 27 interface. The type and `.automatic` member are nominally present on macOS 27, but this API provides no native-Mac replacement for `SearchToolbarBehavior.minimize`. [`toolbarMinimizationBehavior(_:for:)`](https://developer.apple.com/documentation/swiftui/view/toolbarminimizationbehavior%28_%3Afor%3A%29), [`ToolbarMinimizationBehavior`](https://developer.apple.com/documentation/swiftui/toolbarminimizationbehavior).

## Recommendation for Óia

Use exactly one persistent `NSSearchToolbarItem`. Óia can keep `.searchable` as the owner of that native item and its query binding, then configure the generated item through the window toolbar when AppKit adds it. Apply the default-low square-width constraint once and keep `.searchFocused` as the Command-F bridge; AppKit continues to own clicking, Escape/cancel, focus loss, and the expansion animation. There is no need to replace the rest of the SwiftUI toolbar or add a second search control. Do not conditionally attach `.searchable`, use private SwiftUI symbols, or use spacing as an implicit compactness switch.

This keeps the system control and animation while requesting a compact resting width. It still requires manual verification on macOS 15, 26, and 27 because Óia declares macOS 15 as its deployment target and the current product integration has not passed the requested visual behavior.
