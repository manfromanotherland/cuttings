# Save from iPhone with Shortcuts

Use **Save to Cuttings** in the iOS share sheet to save images, videos, text, and
links into the `inbox` folder inside your iCloud library. You do not need an iOS
Cuttings app, a browser extension, an account, or a server.

## Set up

1. Open Cuttings on your Mac. In Settings → Library, select **Open Inbox**.
   Check that this library is inside iCloud Drive and is visible in Files on your
   iPhone.
2. Open [Save to Cuttings.shortcut](../shortcuts/Save%20to%20Cuttings.shortcut) in
   Apple's Shortcuts app. Add the Shortcut and, when asked for its destination,
   choose the **inbox** folder inside that same library.
3. If you install on your Mac, enable Shortcuts iCloud Sync on both devices. The
   Shortcut can then appear on your iPhone under the same Apple Account.
   You can also send the signed `.shortcut` file to your iPhone using AirDrop.
4. On your iPhone, open the Shortcut's editor and confirm its final **Save File**
   action points to the right `inbox` folder, **Ask Where to Save** is off, and
   **Overwrite If File Exists** is off. Reselect the folder on the iPhone if
   Shortcuts asks for access.
5. Open an image in Photos, tap Share, and choose **Save to Cuttings**. Approve
   Shortcuts' first-use permission prompts. Keep the share sheet open until
   **Saved to Inbox** appears.

Shortcuts supports sharing installed shortcuts across devices through
[iCloud Sync](https://support.apple.com/guide/shortcuts/apdb3a4240b0/ios),
[import questions](https://support.apple.com/guide/shortcuts/apdf330fd3a0/ios),
and [running shortcuts from another app](https://support.apple.com/guide/shortcuts/apd163eb9f95/ios).
The folder permission is yours to grant; the distributed Shortcut contains no
personal paths or folder bookmarks.

## What is kept

| Shared item | Saved content |
|---|---|
| Safari webpage | Page URL, page title, and selected text when Safari supplies it. With no selection, this becomes a lightweight link. |
| URL | A lightweight link. No page or media is downloaded. |
| Plain or rich text | A quote, or a lightweight link when the entire text is an HTTP(S) URL. Rich text is converted to plain text. |
| Image or video | The file representation and filename supplied by the sharing app, with a checksum. |

Every capture records its share time. Apps choose what they send to Shortcuts:
an image from Photos generally has no webpage URL, and a social app may share a
link rather than video bytes. The Shortcut does not invent a source, inspect your
clipboard, fetch a webpage, or run JavaScript. Safari's own **Page URL**, **Name**,
and **Page Selection** properties provide the available page context. Canonical
URLs and site names are supported by the transport but are not extracted by this
Shortcut.

The type comparisons currently use Apple's English names: **Safari Web Page**,
**URL**, **Text**, and **Rich Text**. They were validated against the installed
English-language Shortcuts action registry. If your iPhone uses another language,
check these four If comparisons against that device's Get Type output before
relying on capture. On-device share-sheet behavior is a separate manual check.

## When Cuttings imports

Each shared item is saved as one `<capture-id>.cuttingscapture.zip` archive.
Keeping the manifest and media together prevents separate files arriving through
iCloud in the wrong order. The Shortcut saves the archive; it does not write
Cuttings' permanent library files.

Cuttings imports when the Mac app is open, or after you next open it. It requests
missing iCloud downloads, waits for settled files, verifies the archive and media
checksum, and uses the Rust importer to create the normal Markdown and asset
files. The Inbox copy is removed only after the saved item and local assets have
been verified. An interrupted import can be retried without duplicating cards.

**Saved to Inbox** means the file was saved on your iPhone, not that iCloud has
finished syncing or that Cuttings has imported it. There is no background Mac
service when Cuttings is closed.

Use Settings → Library → **Check Inbox** to retry. Files that cannot be imported
stay in the Inbox, with an explanation in Settings; they are not deleted.
Unsupported files and folders are not silently converted. Ordinary supported
image, video, text, `.url`, and `.webloc` files can also be saved directly into
`inbox` with Files or Finder, without the Shortcut's extra source metadata.

## Manual check on iPhone

Before relying on this workflow, share one of each:

- A Safari page with no selected text: source URL and title should be retained.
- Selected text in Safari: check the quote and its source URL. Some share paths
  provide only plain text, in which case the source is unavailable.
- A photo, then a short video: open the imported local assets on the Mac.
- Plain text containing quotes, line breaks, and emoji: check the saved text.
- Several photos at once: confirm one archive and one card per item.

Close Cuttings before one test, then reopen it. The archives should remain in the
Inbox until the import succeeds. Share an identical item again to check that it
deduplicates and leaves no stale Inbox archive.

## Rebuild the Shortcut

The signed file is the installable artifact. The unsigned XML and generator are
kept alongside it so the workflow can be reviewed without importing it.

```sh
swift shortcuts/build-shortcut.swift
swift shortcuts/validate-shortcut.swift 'shortcuts/Save to Cuttings.unsigned.shortcut'
shortcuts sign --mode anyone \
  --input 'shortcuts/Save to Cuttings.unsigned.shortcut' \
  --output 'shortcuts/Save to Cuttings.shortcut'
```

The generator uses only Foundation. The developer validator uses Apple's local
Shortcuts action registry to check action identifiers, parameter names, enum
values, retained variable references, If subjects, balanced control flow, and the
destination import question. It does not install or run the Shortcut. Signing
uses Apple's `shortcuts sign` helper and may require access outside a restricted
terminal sandbox. A successful signature does not replace the iPhone checks
above.
