# Importing a mymind export

This migration adapter reads the folder produced by mymind's **Export my mind** action: a
`cards.csv` file plus the media files beside it. It accepts either that folder directly or an
outer folder containing exactly one immediate child with `cards.csv`. Planning is always offline,
and the importer never writes a SQLite index.

From the repository root, preview the complete plan first:

```bash
./scripts/import-mymind.sh \
  --export /path/to/mymind \
  --library /path/to/Cuttings
```

The preview reads and hashes the exported media but does not fetch any links or change the Cuttings
library. It reports how many link metadata fetches the subsequent write would attempt. Its default
output contains aggregate counts only. Add `--verbose` to list opaque mymind card IDs and Cuttings
reading IDs without printing private URLs, tags, notes, content, or source paths.

Review the totals and warnings, then run the same command with `--write`:

```bash
./scripts/import-mymind.sh \
  --export /path/to/mymind \
  --library /path/to/Cuttings \
  --write
```

Writes enrich HTTP(S) link rows by default. The importer fetches live page metadata plus a bounded
social preview and favicon, then gives the captured metadata and bytes to `cuttings-core`. This is
the network adapter at the import boundary; the shared core itself remains network-free.

To prohibit network access and write URL-only lightweight links from the export data, add
`--offline`:

```bash
./scripts/import-mymind.sh \
  --export /path/to/mymind \
  --library /path/to/Cuttings \
  --write \
  --offline
```

The command is safe to re-run. Core content addressing reports readings already in the destination
as present and leaves their current Cuttings tags and legacy note sidecars untouched. Planning errors,
including conflicting non-empty notes on duplicate source rows, block all writes.

## Link enrichment

For each web link, the default write path may capture the canonical URL, title, site, author,
language, excerpt, and the website's declared theme colour. The core validates the theme colour and
stores supported values as optional lowercase `#rrggbb` `theme_color` metadata for card
presentation. Unsupported or absent colours are simply omitted.

Fetched social-preview and favicon bytes are stored inside the reading's own `assets/` directory.
Frontmatter refers to them through the local relative `preview_asset: assets/<file>` and
`favicon_asset: assets/<file>` fields, so the resulting card remains usable offline. A page metadata
fetch failure is reported as a warning. Reachable pages that reject inspection fall back to the
export's URL and title; a confirmed 404/410 or an origin that remains unreachable after a retry is
not imported. An unavailable preview or favicon is simply omitted.

### Enriching links already in a library

The separate migration script snapshots lightweight links that have neither a preview nor favicon.
It previews by default and reports an aggregate count plus a digest of sorted opaque reading IDs:

```bash
./scripts/enrich-link-metadata.sh --library /path/to/Cuttings
```

Apply the same snapshot with `--write`. For a one-off audited migration, `--expect-count` and
`--expect-digest` make the command abort before network access or writes if the target changed:

```bash
./scripts/enrich-link-metadata.sh \
  --library /path/to/Cuttings \
  --write \
  --expect-count 123 \
  --expect-digest <sha256>
```

Successful captures enrich the existing files while preserving their body, save date, user state,
tags, and note sidecar. During this explicit existing-library migration, links returning HTTP 404 or
410 are permanently deleted. Origins still unreachable after two attempts are also deleted unless
the batch resembles a local or network-wide outage (no server was reached, or more than a quarter
of a batch of at least 20 links was unreachable). Rejected, rate-limited, oversized, and non-HTML
responses are reachable and remain in the library.

## Mapping

The observed mymind CSV columns are
`id,type,title,url,content,note,tags,created`. The importer maps them as follows:

| mymind export | Cuttings |
| --- | --- |
| Web card with an HTTP(S) URL | Lightweight article, enriched on write unless `--offline`, and ready for a later full browser capture |
| `Content` snippet with text | Quote, retaining its HTTP(S) origin when present |
| `Note` content | Source-less quote |
| Image/video file whose stem exactly matches the row ID | Local media card; HTTP(S) origin retained when present |
| `note` attached to a row | Legacy `note.md` sidecar, preserved in the files but not shown by the current macOS app |
| Comma-separated `tags` | Lowercase, hyphenated Cuttings tags |
| `created` | Original UTC `saved_at` |

Media is identified by its bytes, not its opaque export filename or a repeated URL. Rows that map
to the same Cuttings identity are coalesced before writing: the earliest save date is retained, the
latest non-empty title is used, and valid tags are combined. This prevents duplicate handling from
silently dropping source metadata.

Tags over Cuttings' 20-character limit are counted and omitted rather than truncated. Cuttings has
no PDF card kind, so exported PDF bytes are counted as skipped; a document's valid source URL is
still preserved as a lightweight article. Source-less screenshots and empty quotation rows with no
surviving source URL are also skipped because this export does not contain their missing payloads.
Symbolic links, unknown file types, and source paths outside the export folder are never imported.

The source export layout is documented by
[mymind's export guide](https://mymind.helpscoutdocs.com/article/18-can-i-export).
