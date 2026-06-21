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
3. Click **Load unpacked** and select the `dist/` folder.

The extension will appear in your toolbar. Click it on any page to save it to your library.

> The native messaging host must be installed and running for saves to work — see
> [read-later-core](https://github.com/boniattirodrigo/read-later-core).

## Test & lint

```bash
npm test          # Vitest unit tests
npm run lint      # TypeScript type-check + ESLint + Prettier
npm run lint:fix  # Auto-fix lint and formatting issues
```
