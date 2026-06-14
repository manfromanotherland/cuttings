// SPDX-License-Identifier: MIT

import { extractPage } from "./extraction.js";

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.action !== "extract") return;

  const result = extractPage(document, window.location.href);
  if (!result) {
    sendResponse({ error: "Could not extract article content from this page." });
  } else {
    sendResponse(result);
  }
  return true;
});
