<p align="center">
  <img src="./assets/icon.png" alt="Óia app icon" width="128">
</p>
<h1 align="center">Óia</h1>
<p align="center">
  <strong>For your eyes only</strong>
</p>

Óia is a private, local-first home for the things that catch your eye. Save articles, links,
images, videos, screenshots, and quotes from the web, then browse them as a visual library on
your Mac. There are no accounts, no servers, and no telemetry. Your library is a folder of
ordinary Markdown files and local assets that stays useful with or without the app.

## Why I made it

I wanted somewhere quiet to keep the things I find while browsing: not a social feed, not a
cloud service, and not another inbox trying to hold my attention. Óia is the place I can save
something quickly, keep its source, and find it again when it becomes useful.

The app is native SwiftUI, the browser extension captures what is on the page, and a shared Rust
core writes and indexes the library. You choose where that library lives and, if you want it on
more than one device, how it syncs—iCloud Drive, Dropbox, git, or anything else that can sync a
folder.

## The name

**Óia** is pronounced **OY-uh** (`[ˈɔjɐ]`)—two syllables, with the stress on *OY*. It comes from
Brazilian Portuguese *óia*, a playful, colloquial rendering of *olha*: “look!” The name grew out
of the eye icon and the reason the app exists: save what catches your eye so you can look again
later.

In code and file names, Óia becomes `Oia` or `oia`.

## What it does

- Saves cleaned articles, lightweight links, full-page screenshots, selected quotes, and
  right-clicked images or videos with the [browser extension](./extension).
- Accepts links, text, images, and videos pasted or dropped straight onto the macOS board.
- Browses everything together as a visual masonry board with search and tags.
- Keeps the original source and stores captured content locally as Markdown plus assets.
- Accepts iPhone shares through the [Óia! Shortcut](./docs/ios-shortcut.md) when the library is in
  iCloud Drive.

## Build it

You need macOS 14 or later, Xcode 16 or later, [Rust](https://rustup.rs), Node.js/npm, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen).

```bash
brew install xcodegen
rustup target add aarch64-apple-darwin x86_64-apple-darwin
(cd extension && npm install)
make build
```

The Debug app is written to `macos/build/Build/Products/Debug/Óia.app`. Open it once, choose a
library folder, then package the extension:

```bash
open "macos/build/Build/Products/Debug/Óia.app"
cd extension
npm run package
```

Load `extension/unpacked` as an unpacked browser extension. See the
[macOS](./macos), [extension](./extension), and [core](./core) READMEs for focused setup, testing,
and release commands. `make help` lists the repository-wide tasks.

## License

The Rust core, native host, and browser extension are available under the MIT License. The macOS
client is available under GPL-3.0-or-later.

## Thanks

Óia began as a fork of [ReadControl](https://github.com/readcontrol/root), made by Rodrigo
Boniatti. His local-first reading app gave this project a thoughtful foundation. Thank you,
Rodrigo, for building it in the open.
