# read-later-extension

The browser plugin (Manifest V3, TypeScript) for **read-later**, a local-first read-it-later
system. It extracts and cleans the current page (Readability-style extraction + HTML→Markdown)
and hands the result to the native messaging host, which saves it into your library folder.

**License:** MIT — see [LICENSE](./LICENSE).

Part of the **read-later** project →
[github.com/boniattirodrigo/read-later-main](https://github.com/boniattirodrigo/read-later-main)
(architecture, library-format contract, design, and backlog). The native messaging host lives in
[read-later-core](https://github.com/boniattirodrigo/read-later-core).

## Prerequisites

- [Node.js](https://nodejs.org) 18 or later
- npm (bundled with Node.js)

## Install dependencies

```bash
npm install
```

## Build

```bash
npm run build
```

Bundles the extension into `dist/`.

## Load in the browser

1. Open `chrome://extensions` (or `edge://extensions`).
2. Enable **Developer mode**.
3. Click **Load unpacked** and select the **extension root** (this `read-later-extension/`
   folder) — **not** `dist/`.

`manifest.json` lives at the root and references the built bundles inside `dist/`
(`dist/background.js`, `dist/content.js`), while `options.html` sits at the root. Chrome loads
the folder that contains `manifest.json`, so pointing it at `dist/` (which has no manifest) fails.

```
read-later-extension/      ← select THIS folder
├── manifest.json          ← Chrome needs this here
├── options.html
└── dist/                  ← build output, referenced by the manifest
    ├── background.js
    ├── content.js
    └── options.js
```

The extension will appear in your toolbar. Click it on any page to save it to your library.

After editing source, re-run `npm run build` (or `npm run build -- --watch`) and click the
**reload ↻** icon on the extension card to pick up changes.

## Wire the extension ID to the native host

Saves travel over Chrome **native messaging**, which only connects extensions whose ID is listed
in the native host's manifest (`allowed_origins`). Until you register your ID, the host ships a
placeholder origin and the connection is rejected — the extension loads and extracts fine, but
saves silently fail.

Unpacked extensions get an ID derived from the folder's absolute path (stable as long as you
don't move the folder, but unique per machine). To wire it up:

1. Load the unpacked extension (above).
2. On `chrome://extensions`, copy the **ID** shown on the extension card (32 lowercase letters).
3. Register the native host with that ID — see
   [read-later-core](https://github.com/boniattirodrigo/read-later-core)'s "Native messaging host"
   section:

   ```bash
   ./target/release/native-host --install-manifest --extension-id <your-32-char-id>
   ```

Re-run that command whenever the ID changes (e.g. you moved the folder) or you rebuilt the host
binary at a new path.

### Optional: pin a stable extension ID

The path-derived ID changes if you move the folder or load on another machine, forcing a host
re-register each time. To pin a deterministic ID, embed a public `key` in `manifest.json`. The ID
is then derived from that key, identical everywhere.

1. Generate a private key (keep it **out of git**):

   ```bash
   openssl genrsa 2048 | openssl pkcs8 -topk8 -nocrypt -out key.pem
   ```

2. Derive the `manifest.json` `key` value (base64 of the DER public key):

   ```bash
   openssl rsa -in key.pem -pubout -outform DER 2>/dev/null | openssl base64 -A
   ```

   Add it to `manifest.json` as a top-level field:

   ```json
   {
     "manifest_version": 3,
     "key": "<base64-output-from-above>",
     ...
   }
   ```

3. Compute the resulting (fixed) extension ID — wire this into the native host once:

   ```bash
   openssl rsa -in key.pem -pubout -outform DER 2>/dev/null | sha256sum | head -c 32 | tr 0-9a-f a-p
   ```

After reloading the unpacked extension, `chrome://extensions` shows this ID regardless of folder
path or machine. Register it once with the host (`--install-manifest --extension-id <id>`) and
it stays valid. The same `key`/ID carries over to a published build, so the host registration
keeps working after you publish.

> Keep `key.pem` private and never commit it — anyone with it can ship an extension under your
> ID. It is already covered by `.gitignore`.

> The native messaging host must be installed and running for saves to work — see
> [read-later-core](https://github.com/boniattirodrigo/read-later-core).

## Extraction pipeline

Saving a page runs three stages in `src/extraction.ts`:

1. **DOM pre-processing** — the live document is cloned, then reshaped so the
   generic extractor handles it well. Two kinds of fixes live here:
   - _Global_ tweaks that apply to every page (e.g. `preserveHeadings`, which
     neutralises class names that would otherwise trip Readability's filters).
   - _Site adapters_ (`src/site-adapters/`) — host-scoped fixes for pages whose
     markup Readability mishandles. See below.
2. **Readability** — Mozilla Readability selects the main article content and
   drops boilerplate.
3. **Turndown** — the article HTML is converted to Markdown
   (`htmlToMarkdown`), with a few per-element rules (in-page anchors, images).

These are three different layers, and a fix belongs in the one that matches the
problem:

| You want to…                                        | Layer                          |
| :-------------------------------------------------- | :----------------------------- |
| Change how one **HTML element renders** as Markdown | a Turndown rule (`addRule`)    |
| Fix **one host's markup** before content selection  | a **site adapter** (see below) |
| Change extraction **for every page**                | a global step in `extractPage` |

Turndown's own rule/plugin API only decides how nodes that survive Readability
are _rendered_; it can't restore content Readability removed or restructure the
DOM. Site fixes that need to run **before** Readability therefore live in the
adapter layer, not in Turndown.

### Site adapters

A `SiteAdapter` (`src/site-adapters/types.ts`) is a host-scoped pre-processor
that mutates the cloned document before Readability runs:

```ts
export interface SiteAdapter {
  readonly id: string;
  matches(url: URL): boolean;
  preprocess(doc: Document): void;
}
```

The bundled `x` adapter fixes X (Twitter) longform Articles, where inline
citations and @-mentions are rendered as standalone link nodes that Readability
strips as boilerplate — dropping the reference's URL _and_ its visible text. The
adapter folds each such link into adjacent prose so it survives extraction. (An
`options`-level Readability knob, `linkDensityModifier`, was ruled out: it can't
rescue short labels at all and, set high enough to help, disables link-density
cleaning for the whole page across every site.)

**To add a new site:**

1. Create `src/site-adapters/<site>.ts` exporting a `SiteAdapter`. Scope
   `matches` tightly to the host(s), and keep `preprocess` defensive — assume
   markup drifts and never assume a node exists.
2. Register it in the `ADAPTERS` array in `src/site-adapters/index.ts`.
3. Add tests in `src/site-adapters/<site>.test.ts` — cover host matching (incl.
   look-alike hosts that must _not_ match), the transform itself, and an
   end-to-end `extractPage` assertion.

Adapters are best-effort: a throw from one is caught by the registry so it can
never block a save.

## Test & lint

```bash
npm test          # Vitest unit tests
npm run lint      # TypeScript type-check + ESLint + Prettier
npm run lint:fix  # Auto-fix lint and formatting issues
```
