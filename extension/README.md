<p align="center">
  <img src="icons/icon-128.png" alt="Cuttings" width="128">
</p>
<h1 align="center">Cuttings</h1>
<p align="center">
  Keep what you find, with where it came from.
</p>

---

# Browser extension

The Manifest V3 browser extension for **Cuttings**, the local-first native macOS library. It saves
cleaned articles, right-clicked images and videos, and selected-text quotes together with their
origin. Captures travel through the `is.edmundo.cuttings.host` native messaging host and become Markdown
plus local assets in your library folder.

## Build

```bash
npm install
npm run build
```

## Package for the stores

```bash
npm run package
```

Builds a fresh bundle, then zips only the files the manifest ships
(`manifest.json`, `dist/`, `icons/`, `options.html`, `install.html`) into
`artifacts/cuttings-extension-<version>.zip` — ready to upload to the Chrome
Web Store, Edge Add-ons, or [AMO](https://addons.mozilla.org). Bump the
`version` in `manifest.json` before packaging; the stores reject a re-upload of
an existing version. Requires `zip` (preinstalled on macOS).

The packaged manifest drops the `key` field — it pins a stable extension ID for
local unpacked development, but the Chrome Web Store manages signing itself and
rejects any upload that carries `key`. `manifest.json` on disk keeps it.

## Load in the browser

**Chrome / Edge**

1. Open `chrome://extensions` and enable **Developer mode**.
2. **Load unpacked** → select this `extension/` folder (the one with `manifest.json`, **not**
   `dist/`).

After editing source, re-run `npm run build` and click the **reload ↻** icon on the extension
card.

**Firefox**

1. Open `about:debugging#/runtime/this-firefox`.
2. **Load Temporary Add-on…** → select this folder's `manifest.json`.

Temporary add-ons are cleared on restart; a persistent install needs a signed build from
[AMO](https://addons.mozilla.org).

## Wire the extension ID to the native host

Saves travel over Chrome **native messaging**, which only connects extensions whose ID is listed
in the native host's manifest. Until you register your ID, saves silently fail (extraction still
works). To wire it up:

1. Load the unpacked extension (above).
2. On `chrome://extensions`, copy the extension **ID** (32 lowercase letters).
3. Register it with the host (see the [core README](../core/README.md)):

   ```bash
   ../core/target/release/cuttings-native-host --install-manifest --extension-id <your-32-char-id>
   ```

Firefox needs no ID step — it matches the host by the fixed add-on ID baked into the manifest.

> The native messaging host must be installed and running for saves to work.

## Extraction

Saving a page runs three stages in `src/extraction.ts`: DOM pre-processing (including optional
per-host **site adapters** in `src/site-adapters/`), Mozilla Readability to select the main
content, and Turndown to convert it to Markdown.

## Test & lint

```bash
npm test
npm run lint
npm run lint:fix
```
