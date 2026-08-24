// SPDX-License-Identifier: MIT

// Provide a minimal `chrome` global so the content/background modules can be
// imported under happy-dom (where no extension runtime exists). The modules
// register a message listener at import time; this stub keeps that from throwing.
Object.defineProperty(globalThis, "chrome", {
  value: { runtime: { onMessage: { addListener: () => undefined } } },
  configurable: true,
  writable: true,
});
