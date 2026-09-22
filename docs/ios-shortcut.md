# Save from iPhone with Shortcuts

Use **Óia!** in the iOS share sheet to save images, videos, text, and
links into the `inbox` folder inside your iCloud library. You do not need an iOS
Óia app, a browser extension, an account, or a server.

## Set up

1. Open Óia on your Mac. In Settings → Library, select **Open Inbox**.
   Check that this library is inside iCloud Drive and is visible in Files on your
   iPhone.
2. Open [Óia!.shortcut](../shortcuts/%C3%93ia!.shortcut) in
   Apple's Shortcuts app. Add the Shortcut and, when asked for its destination,
   choose the **inbox** folder inside that same library.
3. If you install on your Mac, enable Shortcuts iCloud Sync on both devices. The
   Shortcut can then appear on your iPhone under the same Apple Account.
   You can also send the signed `.shortcut` file to your iPhone using AirDrop.
4. On your iPhone, open the Shortcut's editor and confirm its final **Save File**
   action points to the right `inbox` folder, **Ask Where to Save** is off, and
   **Overwrite If File Exists** is off. Reselect the folder on the iPhone if
   Shortcuts asks for access.
5. Open an image in Photos, tap Share, and choose **Óia!**. Approve
   Shortcuts' first-use permission prompts. Keep the share sheet open until
   **Saved to Inbox** appears.

Shortcuts supports sharing installed shortcuts across devices through
[iCloud Sync](https://support.apple.com/guide/shortcuts/apdb3a4240b0/ios),
[import questions](https://support.apple.com/guide/shortcuts/apdf330fd3a0/ios),
and [running shortcuts from another app](https://support.apple.com/guide/shortcuts/apd163eb9f95/ios).
The folder permission is yours to grant; the distributed Shortcut contains no
personal paths or folder bookmarks.

To update an existing **Óia!**, import the new file and replace the old Shortcut.
Confirm its final **Save File** destination still points to your library’s `inbox`.

## What is kept

| Shared item | Saved content |
|---|---|
| Safari webpage | Page URL, page title, and selected text when Safari supplies it. With no selection, this becomes a lightweight link. |
| Direct image URL | URLs whose path ends in a supported image extension download into a local image attachment. The shared URL is retained as the available source. |
| Instagram post/reel | Queues the selected image or video for download on the Mac. `img_index` selects one carousel slide; no index means the first. |
| Other URL | A lightweight link. No page is downloaded. |
| Plain or rich text | A quote, or a lightweight link when the entire text is an HTTP(S) URL. Rich text is converted to plain text. |
| Image or video | The file representation and display name supplied by the sharing app, with a checksum. |

Every capture records its share time. Apps choose what they send to Shortcuts:
an image from Photos generally has no webpage URL, and a social app may share a
link rather than video bytes. The Shortcut does not invent a source, inspect your
clipboard, fetch a webpage, or run JavaScript. Direct HTTP(S) image URLs ending
in `.jpg`, `.jpeg`, `.png`, `.gif`, `.webp`, `.heic`, or `.heif` are downloaded
on the sharing device (including URLs with query parameters). Shortcuts may ask
for permission to contact the image host. A failed request or non-image response
stops capture instead of reporting a saved link. Extensionless image URLs remain
links. Instagram post/reel URLs use the explicit Mac download queue described
below. Safari's own **Page URL**, **Name**,
and **Page Selection** properties provide the available page context. Canonical
URLs and site names are supported by the transport but are not extracted by this
Shortcut.

The type comparisons currently use Apple's English names: **Safari Web Page**,
**URL**, **Text**, **Rich Text**, and **Image**. They were validated against the installed
English-language Shortcuts action registry. If your iPhone uses another language,
check these If comparisons against that device's Get Type output before
relying on capture. On-device share-sheet behavior is a separate manual check.

## Instagram

The updated **Óia!** Shortcut queues an explicit media request when Instagram
shares a post/reel URL, including when supplied as plain text or a Safari page
without selected text. A carousel URL with `img_index=2` saves only slide 2. If
Instagram omits the index, the first slide is selected. It never saves the whole
carousel or substitutes a link/preview when retrieval fails.

Install the downloader once on each Mac that will handle these requests:

```sh
scripts/install-instagram-downloader.sh
```

This requires Python 3 with venv/pip and installs pinned Instaloader 4.15.3 under
`~/Library/Application Support/Oia/Instagram`. It is optional for other capture
kinds and is not included in the synced library or installed at app launch.
`OIA_PYTHON` may select the Python executable during setup. Re-run setup if a
Python upgrade invalidates the environment. The app bundles the small transport
adapter, not Python itself.

Keep Óia open on the Mac with internet access. After iCloud delivers the request,
Óia downloads the selected media and imports its local asset. **Saved to Inbox**
on iPhone confirms the request was queued, not that the download finished.
Failures remain visible in Settings → Library; **Check Inbox** retries them.
There is no third-party download service and no automatic account login. Some
posts may require authentication or be unavailable; those remain queued with an
error rather than silently becoming links. Live photo capture has been verified;
video selection/import is covered by fixtures and still needs an iPhone reel test.

## When Óia imports

Each shared item is saved as one `<capture-id>.cuttingscapture.zip` archive.
Keeping the manifest and media together prevents separate files arriving through
iCloud in the wrong order. The Shortcut saves the archive; it does not write
Óia' permanent library files.

Óia imports when the Mac app is open, or after you next open it. It requests
missing iCloud downloads, waits for settled files, verifies the archive and media
checksum, and uses the Rust importer to create the normal Markdown and asset
files. The Inbox copy is removed only after the saved item and local assets have
been verified. An interrupted import can be retried without duplicating cards.

**Saved to Inbox** means the file was saved on your iPhone, not that iCloud has
finished syncing or that Óia has imported it. There is no background Mac
service when Óia is closed.

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
- Long-press a website image and share its direct `.jpg` URL: confirm the card
  is an image and its local asset opens. An ordinary page URL should remain a link.
- A photo, then a short video: open the imported local assets on the Mac.
- Plain text containing quotes, line breaks, and emoji: check the saved text.
- Several photos at once: confirm one archive and one card per item.

Close Óia before one test, then reopen it. The archives should remain in the
Inbox until the import succeeds. Share an identical item again to check that it
deduplicates and leaves no stale Inbox archive.

## Rebuild the Shortcut

The signed file is the installable artifact. The unsigned XML and generator are
kept alongside it so the workflow can be reviewed without importing it.

```sh
swift shortcuts/build-shortcut.swift
swift shortcuts/test-shortcut.swift 'shortcuts/Óia!.unsigned.shortcut'
swift shortcuts/validate-shortcut.swift 'shortcuts/Óia!.unsigned.shortcut'
shortcuts sign --mode anyone \
  --input 'shortcuts/Óia!.unsigned.shortcut' \
  --output 'shortcuts/Óia!.shortcut'
```

The generator uses only Foundation. The developer validator uses Apple's local
Shortcuts action registry to check action identifiers, parameter names, enum
values, retained variable references, If subjects, balanced control flow, and the
destination import question. It also guards two native execution pitfalls:
**Make Archive** can ignore its name field, so the archive is explicitly renamed;
**Set Dictionary Value** unwraps a one-item List, so the attachments array is
created by parsing JSON before setting the other manifest fields.

The validator does not install or run the Shortcut. Signing
uses Apple's `shortcuts sign` helper and may require access outside a restricted
terminal sandbox. A successful signature does not replace the iPhone checks
above.

Before the direct-image-URL change, the generated workflow was also run in Mac Shortcuts with typed text, a URL,
and a PNG. Two runs produced six archives with correct names and JSON types.
The current Rust importer saved three items, recognized the other three as
duplicates, and cleared only the successfully imported temporary Inbox copies.
Replaying all six produced six duplicates and no extra items. The test verified
the source URL, Unicode and line breaks, image display name, and identical source,
archive, and imported-image checksums. Safari, Photos, video sharing, and iCloud
delivery on iPhone still need the device checks above.

The running Mac app's iCloud Inbox watcher also completed a duplicate handoff
automatically after the file settled, without altering the existing reading.
