# Inbox capture format

Inbox is a temporary handoff, not another board scope or a second library format.
The shared Rust importer writes ordinary format-v1 readings; the Shortcut never
writes `article.md` or assigns reading ids.

## Publication

The iOS Shortcut creates one uniquely named `<capture-id>.cuttingscapture.zip`
per shared item and saves it to `<library>/inbox/`. Publish a complete archive;
never append to or overwrite a published capture. One ZIP keeps metadata and
payloads together even when an external sync service delivers files out of order.
No companion manifest or completion marker is needed outside the archive.

The archive contains a root `manifest.json` and any referenced attachment files:

```json
{
  "version": 1,
  "capture_id": "unique-transport-identifier",
  "captured_at": "2026-09-10T12:00:00Z",
  "origin": {
    "url": "https://example.com/page",
    "title": "Page title",
    "canonical_url": "https://example.com/canonical",
    "site_name": "Example"
  },
  "text": "Optional selected text",
  "attachments": [
    {
      "path": "payload.jpg",
      "byte_count": 12345,
      "sha256": "64 hexadecimal characters"
    }
  ]
}
```

`version`, `capture_id` (nonempty, at most 128 bytes), and RFC3339 `captured_at`
are required. Other fields are optional. The example checksum is descriptive;
producers supply the actual SHA-256. The shipped Shortcut always hashes media;
the importer also accepts ZIP producers that omit the optional byte count/hash,
using the ZIP sizes and CRC validation. Capture time is normalized to the
library's fixed-width UTC date representation.

`capture_id` identifies transport only. Normal content-addressed reading ids
still control deduplication. A source must be HTTP(S); local paths never become
an origin. A canonical URL is metadata and does not replace the visited URL.

At least one attachment, nonempty text, or source URL is required. Attachments
become media/text readings; nonempty text becomes a quote, except an exact
HTTP(S) URL uses the shared URL-save facade when no different page origin is
given. A recognized public source becomes a complete local article; every other
source-only capture becomes a lightweight link. Generic page extraction never
occurs in the Inbox path. Available source title/site/canonical data is retained.

## Instagram requests (version 2)

An explicit request contains only `manifest.json`:

```json
{
  "version": 2,
  "capture_id": "unique-transport-identifier",
  "captured_at": "2026-09-22T12:00:00Z",
  "instagram_url": "https://www.instagram.com/p/DdlVpikk5Gj/?img_index=2"
}
```

Version 2 is reserved for selected Instagram media requests. It does not accept
attachments or text, and never falls back to a link. Version-1-only readers reject
and retain it. Rust validates the HTTPS Instagram post/reel URL, interprets the
one-based `img_index` (missing means 1), rejects ambiguous/invalid indices, and
removes tracking parameters from the saved origin. The native app opts into the
external downloader; the ordinary `process_inbox` entry point remains offline.

Instaloader runs in a per-device Python environment, outside the library. It
fetches exactly the selected node, uses video bytes rather than a poster for a
video node, and streams at most 40 MiB per image or 1 GiB per movie to private
temporary storage. Each helper process has a 120-second deadline. Rust validates
the resulting media through the normal importer and verifies the saved asset
before consuming the unchanged request. The original share time is preserved.
No account sessions, browser cookies, CDN URLs, or credentials are stored in the
request or saved card. Network/authentication failures and missing slide indices
stay in Inbox as issues; **Check Inbox** retries them. Other file imports remain
offline. See [setup](ios-shortcut.md#instagram).

## Validation and consumption

- Only direct regular files are considered. Hidden files, symlinks, and folders
  are not traversed. The Inbox itself must be a real directory.
- The Mac requests unavailable iCloud items and defers files whose local copy
  is not current. Rust also skips dataless files and files modified within the
  previous two seconds, then takes a bounded private snapshot.
- ZIP entry names must be safe relative paths; duplicates, special files,
  missing attachments, unknown versions, and unreferenced data are rejected.
  Directory entries must have no payload bytes and their file types must match
  their trailing-slash names.
  Entries are copied to generated temporary filenames, never extracted using
  archive paths. ZIP integrity and declared hashes/sizes are checked before
  importing any attachments.
- Limits: 128 archive entries, 64 attachments, 1 MiB manifest, 40 MiB per image
  or text file, 1 GiB per video, and 1 GiB + 2 MiB for the archive/expanded total.
  The ZIP manifest limit also bounds text embedded in the manifest.
- Saved Markdown and required asset bytes are verified and flushed before
  removal. A duplicate id alone is not sufficient evidence of a complete save.
  Quote text and source identities are checked too, so valid frontmatter alone
  cannot make a truncated or edited quote safe to discard.
  The original source is atomically renamed, without overwriting, to a unique
  visible `recovered-<id>-<original-name>` inside the pinned Inbox directory.
  Its file identity, size, timestamps, and hash are checked again before removal.
  A replacement or interrupted cleanup leaves that recovery file available for
  the next normal import; a new file at the original name is never removed by
  the old capture's cleanup. Recovery names preserve the supported extension
  (including `.cuttingscapture.zip`) and may shorten an unusually long stem.
- Unsupported, invalid, or failed inputs stay intact in Inbox. The app presents
  issues in Settings and can check again. Pending files retry with bounded
  backoff while the Mac app is running; no daemon runs when the app is closed.

This is at-least-once ingestion: a crash after saving but before removal retries
through normal deduplication. A multi-attachment archive can have some readings
saved before a later write fails; the whole archive remains for retry. The
index is reconciled once after the batch. Local locks do not coordinate Macs;
external sync is still responsible for delivery and conflict handling.

Ordinary JPEG, PNG, GIF, WebP, HEIC/HEIF, MP4/MOV/M4V, UTF-8 `.txt`/`.text`/`.md`,
`.url`, and `.webloc` files may also be dropped directly into Inbox. Use unique
filenames and finish copying before leaving files there; do not use Inbox as a
working folder or edit queued files. Raw text has no sealed completion marker,
so this compatibility path uses local file stability rather than the stronger
archive contract. Raw files have no extra source metadata or captured timestamp.

See [iPhone setup](ios-shortcut.md) for the installable Shortcut and device checks.
