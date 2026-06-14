// SPDX-License-Identifier: MIT

import type { ExtractionResult } from "./extraction.js";
import type { SaveRequest, SaveResponse } from "./protocol.js";

const HOST_ID = "com.readlater.host";

chrome.action.onClicked.addListener(async (tab) => {
  if (!tab.id || !tab.url) return;
  const tabId = tab.id;

  let extraction: ExtractionResult;
  try {
    const result = await chrome.tabs.sendMessage(tabId, { action: "extract" });
    if (result?.error) {
      await showBadge(tabId, "error");
      console.error("read-later: extraction failed:", result.error);
      return;
    }
    extraction = result as ExtractionResult;
  } catch (err) {
    await showBadge(tabId, "error");
    console.error("read-later: could not reach content script:", err);
    return;
  }

  const request: SaveRequest = {
    protocol_version: 1,
    action: "save",
    metadata: extraction.metadata,
    markdown: extraction.markdown,
    image_urls: extraction.image_urls,
  };

  let response: SaveResponse;
  try {
    response = await sendNativeMessage(request);
  } catch (err) {
    await showBadge(tabId, "error");
    console.error("read-later: native host error:", err);
    return;
  }

  if (response.ok) {
    await showBadge(tabId, "ok");
  } else {
    await showBadge(tabId, "error");
    console.error("read-later: save failed:", response.error, response.message);
  }
});

function sendNativeMessage(message: SaveRequest): Promise<SaveResponse> {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendNativeMessage(HOST_ID, message, (response: SaveResponse) => {
      if (chrome.runtime.lastError) {
        reject(new Error(chrome.runtime.lastError.message));
      } else {
        resolve(response);
      }
    });
  });
}

async function showBadge(tabId: number, status: "ok" | "error"): Promise<void> {
  const text = status === "ok" ? "✓" : "✗";
  const color = status === "ok" ? "#4CAF50" : "#F44336";
  await chrome.action.setBadgeText({ text, tabId });
  await chrome.action.setBadgeBackgroundColor({ color, tabId });
  setTimeout(() => chrome.action.setBadgeText({ text: "", tabId }), 3000);
}
