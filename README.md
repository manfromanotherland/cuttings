<p align="center">
  <img src="https://raw.githubusercontent.com/readcontrol/root/main/assets/icon.png" alt="ReadControl" width="128">
</p>
<h1 align="center">ReadControl</h1>
<p align="center">
  The native macOS reading manager
  <br />
  <a href="https://github.com/readcontrol/macos">macOS</a>
  ·
  <a href="https://github.com/readcontrol/core">core</a>
  ·
  <a href="https://github.com/readcontrol/extension">extension</a>
  ·
  <a href="https://github.com/readcontrol/root">root</a>
</p>

---

# extension

The browser plugin (Manifest V3, TypeScript) for **ReadControl**, the native macOS reading manager. It extracts and cleans the current page (Readability-style extraction + HTML→Markdown)
and hands the result to the native messaging host, which saves it into your library folder.

## Build

```bash
npm install
npm run build
```

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
3. Register it with the host (see [core](https://github.com/readcontrol/core)):

   ```bash
   ./target/release/native-host --install-manifest --extension-id <your-32-char-id>
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
