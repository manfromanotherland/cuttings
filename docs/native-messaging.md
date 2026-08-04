# Native Messaging Protocol

**Version:** `1`

This document defines the JSON message contract between the **browser extension**
(`extension`) and the **native messaging host** (`core/native-host`).

The host is registered under the name `app.readcontrol.host`. Communication uses the standard
[Chrome native messaging protocol][chrome-nm]: each message is prefixed with a 4-byte
little-endian unsigned integer specifying the message length in bytes.

- **Browser → host:** up to 4 GB per message (browser limit).
- **Host → browser:** up to 1 MB per message (browser-enforced hard limit).

[chrome-nm]: https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging

---

## Save request (extension → host)

Sent when the user saves a page.

```json
{
  "protocol_version": 1,
  "action": "save",
  "metadata": {
    "url": "https://blog.example.com/posts/local-first?utm_source=hn",
    "canonical_url": "https://blog.example.com/posts/local-first",
    "title": "Local-First Software",
    "author": "Martin Kleppmann",
    "site": "blog.example.com",
    "lang": "en",
    "excerpt": "An argument for software that works offline.",
    "word_count": 3812,
    "saved_at": "2026-06-13T15:00:00Z"
  },
  "markdown": "## Local-First Software\n\nAn argument…\n\n![Diagram](https://blog.example.com/img/diagram.jpg)\n",
  "images": [
    {
      "url": "https://blog.example.com/img/diagram.jpg",
      "content_type": "image/jpeg",
      "data_base64": "/9j/4AAQSkZJRg…"
    }
  ]
}
```

### Fields

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `protocol_version` | integer | ✅ | Must be `1` |
| `action` | string | ✅ | `"save"` for this request; `"check"` is also supported (see below) |
| `metadata.url` | string | ✅ | Original URL as visited |
| `metadata.canonical_url` | string | ✅ | Normalized URL (see library-format.md § URL normalization) |
| `metadata.title` | string | ✅ | Article title |
| `metadata.author` | string | — | Extracted byline; omit if unknown |
| `metadata.site` | string | — | eTLD+1; omit to let the host derive it |
| `metadata.lang` | string | — | BCP-47 language tag |
| `metadata.excerpt` | string | — | One-sentence summary |
| `metadata.word_count` | integer | — | Word count of the cleaned body |
| `metadata.saved_at` | string | ✅ | ISO-8601 UTC timestamp from the extension |
| `markdown` | string | ✅ | Cleaned article body as Markdown; images still have remote URLs |
| `images` | object[] | ✅ | Images the extension captured from the page (see below); the host writes them and rewrites the links. May be empty |
| `images[].url` | string | ✅ | The image URL exactly as it appears in `markdown`, so the host can rewrite it |
| `images[].content_type` | string | — | The response `Content-Type` the browser saw; used to pick the asset extension |
| `images[].data_base64` | string | ✅ | Standard base64 of the raw image bytes |

The extension fetches each image itself — from the browser's cache where
possible — so the host performs **no** network requests. An image the extension
couldn't capture is simply omitted from `images`; its URL stays in the Markdown
and the reader shows a labelled placeholder.

---

## Save response (host → extension)

### Success

```json
{
  "protocol_version": 1,
  "ok": true,
  "id": "01J9Z8X7Q2VBKN3P4HXYZ01AB",
  "path": "articles/01/01J9Z8X7Q2VBKN3P4HXYZ01AB/article.md"
}
```

### Failure

```json
{
  "protocol_version": 1,
  "ok": false,
  "error": "library_not_configured",
  "message": "No library folder has been set. Open the ReadControl app to configure one."
}
```

### Response fields

| Field | Type | Notes |
|-------|------|-------|
| `protocol_version` | integer | Always `1` |
| `ok` | boolean | `true` on success |
| `id` | string | The ULID assigned to the reading (success only) |
| `path` | string | Relative path from library root (success only) |
| `error` | string | Machine-readable error code (failure only) |
| `message` | string | Human-readable description (failure only) |
| `saved` | boolean | Whether the URL is already saved (`check` responses only) |

### Error codes

| Code | Meaning |
|------|---------|
| `library_not_configured` | No library folder set; user must open the app |
| `duplicate` | A reading with the same `canonical_url` already exists |
| `io_error` | Failed to write to the library folder |
| `invalid_request` | Malformed or missing required fields |

---

## Check request (extension → host)

Asks whether a URL is already in the library — used to reflect saved state in the toolbar.

```json
{
  "protocol_version": 1,
  "action": "check",
  "url": "https://blog.example.com/posts/local-first"
}
```

The host looks the URL up (by `canonical_url`) and replies:

```json
{
  "protocol_version": 1,
  "ok": true,
  "saved": true,
  "id": "01J9Z8X7Q2VBKN3P4HXYZ01AB"
}
```

`saved` is `true` when a reading with that URL exists (`id` is then its ULID), and `false`
otherwise — including when no library is configured (a `check` never errors on that).

---

## Protocol versioning

- `protocol_version` starts at `1`.
- The extension and host must both support the same version; a mismatch should surface an error.
- Version bumps follow the same lockstep rule as the library format: update both repos together.
