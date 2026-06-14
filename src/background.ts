// SPDX-License-Identifier: MIT

import type { ExtractionResult } from "./extraction.js";
import type { SaveRequest, SaveResponse } from "./protocol.js";

const HOST_ID = "com.readlater.host";
const CONTEXT_MENU_ID = "save-page";
const NOTIF_HOST_MISSING = "host-missing";

// Substrings Chrome uses when the native host binary is absent or unregistered.
const HOST_MISSING_ERRORS = [
  "Specified native messaging host not found",
  "Access to the specified native messaging host is forbidden",
  "Native host has exited",
];

function isHostMissing(err: Error): boolean {
  return HOST_MISSING_ERRORS.some((phrase) => err.message.includes(phrase));
}

// ── Icon ──────────────────────────────────────────────────────────────────────

function drawIcon(size: number, active: boolean): ImageData {
  const canvas = new OffscreenCanvas(size, size);
  const ctx = canvas.getContext("2d")!;

  const r = size * 0.15;
  ctx.fillStyle = active ? "#2563EB" : "#3B82F6";
  ctx.beginPath();
  ctx.roundRect(0, 0, size, size, r);
  ctx.fill();

  // Bookmark shape
  const pad = size * 0.22;
  const bw = size - pad * 2;
  const bh = size - pad * 1.5;
  const notchY = size - pad * 0.6;
  const midX = pad + bw / 2;

  ctx.fillStyle = "rgba(255,255,255,0.95)";
  ctx.beginPath();
  ctx.moveTo(pad, pad);
  ctx.lineTo(pad + bw, pad);
  ctx.lineTo(pad + bw, notchY);
  ctx.lineTo(midX, notchY - bh * 0.2);
  ctx.lineTo(pad, notchY);
  ctx.closePath();
  ctx.fill();

  return ctx.getImageData(0, 0, size, size);
}

async function setIcon(active = false): Promise<void> {
  await chrome.action.setIcon({
    imageData: {
      16: drawIcon(16, active),
      32: drawIcon(32, active),
      48: drawIcon(48, active),
    },
  });
}

// ── Startup ───────────────────────────────────────────────────────────────────

chrome.runtime.onInstalled.addListener(() => {
  setIcon();
  chrome.contextMenus.create({
    id: CONTEXT_MENU_ID,
    title: "Save to Read Later",
    contexts: ["page"],
  });
});

chrome.runtime.onStartup.addListener(() => {
  setIcon();
});

// ── Save pipeline ─────────────────────────────────────────────────────────────

async function savePage(tab: chrome.tabs.Tab): Promise<void> {
  const tabId = tab.id;
  if (!tabId || !tab.url) return;

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
    if (err instanceof Error && isHostMissing(err)) {
      await notifyHostMissing(tabId);
    } else {
      await showBadge(tabId, "error");
      console.error("read-later: native host error:", err);
    }
    return;
  }

  if (response.ok) {
    await showBadge(tabId, "ok");
  } else {
    await showBadge(tabId, "error");
    console.error("read-later: save failed:", response.error, response.message);
  }
}

// ── Triggers ──────────────────────────────────────────────────────────────────

chrome.action.onClicked.addListener((tab) => savePage(tab));

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === CONTEXT_MENU_ID && tab) savePage(tab);
});

chrome.commands.onCommand.addListener((command) => {
  if (command === "save-page") {
    chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
      if (tab) savePage(tab);
    });
  }
});

// ── Host-missing notification ────────────────────────────────────────────────

const NOTIF_ICON =
  "data:image/svg+xml;charset=utf-8," +
  encodeURIComponent(
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48">' +
      '<rect width="48" height="48" rx="8" fill="#3B82F6"/>' +
      '<path d="M14 12h20v28l-10-7-10 7z" fill="white"/>' +
      "</svg>",
  );

async function notifyHostMissing(tabId: number): Promise<void> {
  await showBadge(tabId, "error");
  await chrome.notifications.create(NOTIF_HOST_MISSING, {
    type: "basic",
    iconUrl: NOTIF_ICON,
    title: "Read Later — Native Host Not Found",
    message:
      "The native helper isn't installed yet. Click this notification to see how to install it.",
    requireInteraction: true,
  });
}

chrome.notifications.onClicked.addListener((id) => {
  if (id === NOTIF_HOST_MISSING) {
    void chrome.tabs.create({ url: chrome.runtime.getURL("install.html") });
    void chrome.notifications.clear(id);
  }
});

// ── Helpers ───────────────────────────────────────────────────────────────────

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
  const color = status === "ok" ? "#22C55E" : "#EF4444";
  await chrome.action.setBadgeText({ text, tabId });
  await chrome.action.setBadgeBackgroundColor({ color, tabId });
  setTimeout(() => chrome.action.setBadgeText({ text: "", tabId }), 3000);
}
