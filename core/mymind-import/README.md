# Importing a mymind export

This offline importer reads the folder produced by mymind's **Export my mind** action: a
`cards.csv` file plus the media files beside it. It accepts either that folder directly or an
outer folder containing exactly one immediate child with `cards.csv`. It never fetches a remote
URL and never writes a SQLite index.

From the repository root, preview the complete plan first:

```bash
./scripts/import-mymind.sh \
  --export /path/to/mymind \
  --library /path/to/Cuttings
```

The preview reads and hashes the exported media but does not change the Cuttings library. Its
default output contains aggregate counts only. Add `--verbose` to list opaque mymind card IDs and
Cuttings reading IDs without printing private URLs, tags, notes, content, or source paths.

Review the totals and warnings, then run the same command with `--write`:

```bash
./scripts/import-mymind.sh \
  --export /path/to/mymind \
  --library /path/to/Cuttings \
  --write
```

The command is safe to re-run. Core content addressing reports readings already in the destination
as present and leaves their current Cuttings tags and legacy note sidecars untouched. Planning errors,
including conflicting non-empty notes on duplicate source rows, block all writes.

## Mapping

The observed mymind CSV columns are
`id,type,title,url,content,note,tags,created`. The importer maps them as follows:

| mymind export | Cuttings |
| --- | --- |
| Web card with an HTTP(S) URL | Lightweight article, ready for a later full browser capture |
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
