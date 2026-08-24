# Native Messaging Protocol

**Version:** `2`

This document defines the JSON message contract between the **browser extension**
(`extension`) and the **native messaging host** (`core/native-host`).

The host is registered under the name `is.edmundo.cuttings.host`. Communication uses the standard
[Chrome native messaging protocol][chrome-nm]: each message is prefixed with a 4-byte
little-endian unsigned integer specifying the message length in bytes.

- **Browser → host:** up to 4 GB per message (browser limit).
- **Host → browser:** up to 1 MB per message (browser-enforced hard limit).

[chrome-nm]: https://developer.chrome.com/docs/extensions/develop/concepts/native-messaging

---

## Save request (extension → host)

Sent when the user saves a full page, right-clicked image/video, or selected-text quote. The
request always describes the **origin page** in `metadata.url`/`canonical_url`; a media identity is
additional metadata and never replaces that origin.

```json
{
  "protocol_version": 2,
  "action": "save",
  "metadata": {
    "url": "https://blog.example.com/posts/local-first?utm_source=hn",
    "canonical_url": "https://blog.example.com/posts/local-first",
    "title": "Local-First Software",
    "kind": "article",
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
| `protocol_version` | integer | ✅ | Must be `2` |
| `action` | string | ✅ | `"save"` for this request; `"check"` is also supported (see below) |
| `metadata.url` | string | ✅ | Original URL as visited |
| `metadata.canonical_url` | string | ✅ | Origin page's canonical URL when known; otherwise the visited page URL |
| `metadata.title` | string | ✅ | Origin page/article title |
| `metadata.kind` | string | ✅ | `article`, `image`, `video`, or `quote` |
| `metadata.media_url` | string | — | Durable image/video URL, or an opaque stable reference for a session-local video; origin remains `metadata.url` |
| `metadata.author` | string | — | Extracted byline; omit if unknown |
| `metadata.site` | string | — | eTLD+1; omit to let the host derive it |
| `metadata.lang` | string | — | BCP-47 language tag |
| `metadata.excerpt` | string | — | One-sentence summary |
| `metadata.word_count` | integer | — | Word count of the cleaned body |
| `metadata.saved_at` | string | ✅ | ISO-8601 UTC timestamp from the extension |
| `markdown` | string | ✅ | Cleaned article body as Markdown; images still have remote URLs |
| `images` | object[] | ✅ | Article images, a clicked image, or a video poster captured by the extension; may be empty |
| `images[].url` | string | ✅ | The image URL exactly as it appears in `markdown`, so the host can rewrite it |
| `images[].content_type` | string | — | The response `Content-Type` the browser saw; used to pick the asset extension |
| `images[].data_base64` | string | ✅ | Standard base64 of the raw image bytes |

The extension fetches each article image, clicked image, or video poster itself — from the browser's
cache where possible — so the host performs **no** network requests. An image the extension couldn't
capture is simply omitted from `images`; its URL stays in Markdown and the reader shows a labelled
placeholder. Video bytes are never placed in this message.

Raw `blob:` and `data:` video URLs are never sent. The extension first looks for a durable HTTP(S)
source on the clicked video. If none exists, `media_url` is a compact `cuttings-video:` identity
and the Markdown playback link points to the real origin page.

For a quote, `markdown` contains the full selected text as block quotes and `excerpt` contains the
bounded card preview. For image/video/quote requests, the host derives a kind-specific identity so
several cards can coexist from one origin page.

---

## Save response (host → extension)

### Success

```json
{
  "protocol_version": 2,
  "ok": true,
  "id": "1146c9a93631d1991af3252dbc49ecd8043ab354a4386e397d555d1ca21a7199",
  "path": "articles/11/1146c9a93631d1991af3252dbc49ecd8043ab354a4386e397d555d1ca21a7199/article.md"
}
```

### Failure

```json
{
  "protocol_version": 2,
  "ok": false,
  "error": "library_not_configured",
  "message": "No library folder has been set. Open the Cuttings app to configure one."
}
```

### Response fields

| Field | Type | Notes |
|-------|------|-------|
| `protocol_version` | integer | Always `2` |
| `ok` | boolean | `true` on success |
| `id` | string | The content-addressed id assigned to the reading (success only) |
| `path` | string | Relative path from library root (success only) |
| `error` | string | Machine-readable error code (failure only) |
| `message` | string | Human-readable description (failure only) |
| `saved` | boolean | Whether the URL is already saved (`check` responses only) |

### Error codes

| Code | Meaning |
|------|---------|
| `library_not_configured` | No library folder set; user must open the app |
| `duplicate` | A card with the same kind-specific deterministic identity already exists |
| `io_error` | Failed to write to the library folder |
| `invalid_request` | Malformed or missing required fields |

---

## Check request (extension → host)

Asks whether a URL is already in the library — used to reflect saved state in the toolbar.

```json
{
  "protocol_version": 2,
  "action": "check",
  "url": "https://blog.example.com/posts/local-first"
}
```

The host looks up the article identity for that normalized page URL. This toolbar check deliberately
answers whether the full page is saved; saving only an image, video, or quote from the page does not
make the article icon appear saved.

```json
{
  "protocol_version": 2,
  "ok": true,
  "saved": true,
  "id": "1146c9a93631d1991af3252dbc49ecd8043ab354a4386e397d555d1ca21a7199"
}
```

`saved` is `true` when a reading with that URL exists (`id` is then its content-addressed id), and `false`
otherwise — including when no library is configured (a `check` never errors on that).

---

## Protocol versioning

- Version `1` supported full-page article saves. Version `2` adds first-class card kind and media
  metadata for articles, images, videos, and quotes.
- The extension and host must both support the same version; a mismatch should surface an error.
- Version bumps follow the same lockstep rule as the library format: update both repos together.
