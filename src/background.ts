// SPDX-License-Identifier: MIT

import type { PageCapture, ToastMessage } from "./content.js";
import type { CheckRequest, CheckResponse, SaveRequest, SaveResponse } from "./protocol.js";
import { PROTOCOL_VERSION } from "./protocol.js";
import { capTotalBytes, fetchImages } from "./images.js";
import { HOST_ID, isHostMissing } from "./host.js";
import { log } from "./log.js";

const CONTEXT_MENU_ID = "save-page";
const NOTIF_HOST_MISSING = "host-missing";

/** Cap on the total decoded image bytes inlined into one save message. Images
 *  beyond this stay as remote-URL placeholders so a save can't buffer unbounded. */
const MAX_TOTAL_IMAGE_BYTES = 40 * 1024 * 1024;

// ── Icon ──────────────────────────────────────────────────────────────────────

type IconState = "default" | "saved";

/** The saved state is the same artwork carrying a green check badge. */
function iconPaths(state: IconState): Record<number, string> {
  const stem = state === "saved" ? "icons/icon-saved" : "icons/icon";
  return { 16: `${stem}-16.png`, 32: `${stem}-32.png`, 48: `${stem}-48.png` };
}

async function setIcon(state: IconState = "default", tabId?: number): Promise<void> {
  const path = iconPaths(state);
  if (tabId !== undefined) {
    await chrome.action.setIcon({ path, tabId });
  } else {
    await chrome.action.setIcon({ path });
  }
}

// ── Saved-URL cache ───────────────────────────────────────────────────────────

/** In-memory cache: normalized URL → is it saved? Populated by check and save. */
const savedCache = new Map<string, boolean>();

function normalizeUrl(raw: string): string {
  return raw.split("#")[0];
}

// ── Tab icon check ────────────────────────────────────────────────────────────

async function checkAndSetIcon(tabId: number, rawUrl: string): Promise<void> {
  if (!rawUrl || rawUrl.startsWith("chrome://") || rawUrl.startsWith("about:")) return;

  const url = normalizeUrl(rawUrl);

  if (savedCache.has(url)) {
    await setIcon(savedCache.get(url)! ? "saved" : "default", tabId);
    return;
  }

  try {
    const response = await sendNativeMessage<CheckRequest, CheckResponse>({
      protocol_version: PROTOCOL_VERSION,
      action: "check",
      url,
    });
    const isSaved = response.saved ?? false;
    savedCache.set(url, isSaved);
    await setIcon(isSaved ? "saved" : "default", tabId);
  } catch {
    // Native host not installed or unreachable — silently skip.
  }
}

// ── Startup ───────────────────────────────────────────────────────────────────

chrome.runtime.onInstalled.addListener(() => {
  void setIcon();
  chrome.contextMenus.create({
    id: CONTEXT_MENU_ID,
    title: "Save to Read Control",
    contexts: ["page"],
  });
});

chrome.runtime.onStartup.addListener(() => {
  void setIcon();
});

// ── Tab navigation listeners ──────────────────────────────────────────────────

chrome.tabs.onActivated.addListener(({ tabId }) => {
  void chrome.tabs.get(tabId, (tab) => {
    if (tab.url) void checkAndSetIcon(tabId, tab.url);
  });
});

chrome.tabs.onUpdated.addListener((tabId, changeInfo, tab) => {
  if (changeInfo.status === "complete" && tab.url) {
    void checkAndSetIcon(tabId, tab.url);
  }
});

// ── Save pipeline ─────────────────────────────────────────────────────────────

/**
 * Ask the content script to extract the page. The content script is normally
 * injected by the manifest, but only into tabs that navigate *after* the
 * extension loads — a tab that was already open when the extension was
 * installed or reloaded has no content script and won't answer. When the first
 * message fails, inject the script programmatically (allowed on the active tab
 * via the `activeTab` grant from the user's click) and retry once.
 */
async function requestExtraction(tabId: number): Promise<PageCapture | { error: string }> {
  try {
    return await chrome.tabs.sendMessage(tabId, { action: "extract" });
  } catch {
    await chrome.scripting.executeScript({ target: { tabId }, files: ["dist/content.js"] });
    return await chrome.tabs.sendMessage(tabId, { action: "extract" });
  }
}

async function savePage(tab: chrome.tabs.Tab): Promise<void> {
  const tabId = tab.id;
  if (!tabId || !tab.url) {
    await log("warn", "Save ignored: no active tab id or URL", { tabId, url: tab.url });
    return;
  }

  await log("info", "Save triggered", { url: tab.url });
  await showToast(tabId, "loading", "Saving…");

  let capture: PageCapture;
  try {
    const result = await requestExtraction(tabId);
    if (result && "error" in result && result.error) {
      await showBadge(tabId, "error");
      await showToast(tabId, "error", "Couldn't save page", result.error);
      await log("error", "Extraction failed", { url: tab.url, error: result.error });
      return;
    }
    capture = result as PageCapture;
  } catch (err) {
    await showBadge(tabId, "error");
    await showToast(
      tabId,
      "error",
      "Couldn't save page",
      "This page can't be read (it may be a browser or store page).",
    );
    await log("error", "Could not reach content script", { url: tab.url, error: err });
    return;
  }

  // The content script captured images it could read from the page cache. Images
  // it couldn't (cross-origin without CORS) are retried here in the background
  // worker, which can read them via host permissions. The host writes them all —
  // it never downloads anything.
  const fallback = await fetchImages(capture.unresolved);
  const images = capTotalBytes([...capture.images, ...fallback.images], MAX_TOTAL_IMAGE_BYTES);
  await log("info", "Captured images", {
    fromPage: capture.images.length,
    fromBackground: fallback.images.length,
    sent: images.length,
    requested: capture.images.length + capture.unresolved.length,
  });

  const request: SaveRequest = {
    protocol_version: PROTOCOL_VERSION,
    action: "save",
    metadata: capture.metadata,
    markdown: capture.markdown,
    images,
  };

  let response: SaveResponse;
  try {
    response = await sendNativeMessage<SaveRequest, SaveResponse>(request);
  } catch (err) {
    if (err instanceof Error && isHostMissing(err)) {
      await log("warn", "Native host not found", { error: err });
      await notifyHostMissing(tabId);
    } else {
      await showBadge(tabId, "error");
      await showToast(tabId, "error", "Couldn't save page", "The native helper returned an error.");
      await log("error", "Native host error", { url: tab.url, error: err });
    }
    return;
  }

  if (response.ok) {
    await showBadge(tabId, "ok");
    await showToast(tabId, "ok", "Saved to Read Control", capture.metadata.title);
    markSaved(tabId, tab.url, capture.metadata.canonical_url);
    await log("info", "Saved", { url: tab.url, title: capture.metadata.title });
  } else if (response.error === "duplicate") {
    await showBadge(tabId, "ok");
    await showToast(tabId, "ok", "Already in Reading List", capture.metadata.title);
    markSaved(tabId, tab.url, capture.metadata.canonical_url);
    await log("info", "Already saved (duplicate)", { url: tab.url });
  } else {
    await showBadge(tabId, "error");
    await showToast(tabId, "error", "Couldn't save page", response.message || response.error);
    await log("error", "Save failed", {
      url: tab.url,
      error: response.error,
      message: response.message,
    });
  }
}

/** Update the cache and flip the icon to "saved" immediately after a save. */
function markSaved(tabId: number, tabUrl: string, canonicalUrl: string): void {
  savedCache.set(normalizeUrl(tabUrl), true);
  savedCache.set(normalizeUrl(canonicalUrl), true);
  void setIcon("saved", tabId);
}

// ── Triggers ──────────────────────────────────────────────────────────────────

chrome.action.onClicked.addListener((tab) => void savePage(tab));

chrome.contextMenus.onClicked.addListener((info, tab) => {
  if (info.menuItemId === CONTEXT_MENU_ID && tab) void savePage(tab);
});

chrome.commands.onCommand.addListener((command) => {
  if (command === "save-page") {
    chrome.tabs.query({ active: true, currentWindow: true }, ([tab]) => {
      if (tab) void savePage(tab);
    });
  }
});

// ── Host-missing notification ─────────────────────────────────────────────────

async function notifyHostMissing(tabId: number): Promise<void> {
  await showBadge(tabId, "error");
  await showToast(
    tabId,
    "error",
    "Native helper not installed",
    "Click the notification to see how to install it.",
  );
  try {
    await chrome.notifications.create(NOTIF_HOST_MISSING, {
      type: "basic",
      iconUrl: chrome.runtime.getURL("icons/icon-128.png"),
      title: "Read Control — Native Host Not Found",
      message:
        "The native helper isn't installed yet. Click this notification to see how to install it.",
      requireInteraction: true,
    });
  } catch (err) {
    // A failed notification must never bubble up as an unhandled rejection; the
    // toast and badge above already convey the problem.
    await log("error", "Could not show host-missing notification", { error: err });
  }
}

chrome.notifications.onClicked.addListener((id) => {
  if (id === NOTIF_HOST_MISSING) {
    void chrome.tabs.create({ url: chrome.runtime.getURL("install.html") });
    void chrome.notifications.clear(id);
  }
});

// ── Helpers ───────────────────────────────────────────────────────────────────

function sendNativeMessage<TReq, TRes>(message: TReq): Promise<TRes> {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendNativeMessage(HOST_ID, message as object, (response: TRes) => {
      if (chrome.runtime.lastError) {
        reject(new Error(chrome.runtime.lastError.message));
      } else {
        resolve(response);
      }
    });
  });
}

async function showToast(
  tabId: number,
  status: ToastMessage["status"],
  title: string,
  detail?: string,
): Promise<void> {
  const message: ToastMessage = { action: "toast", status, title, detail };
  try {
    await chrome.tabs.sendMessage(tabId, message);
  } catch {
    // Tab closed/navigated or no content script reachable; the badge still conveys status.
  }
}

async function showBadge(tabId: number, status: "ok" | "error"): Promise<void> {
  const text = status === "ok" ? "✓" : "✗";
  const color = status === "ok" ? "#22C55E" : "#EF4444";
  await chrome.action.setBadgeText({ text, tabId });
  await chrome.action.setBadgeBackgroundColor({ color, tabId });
  setTimeout(() => chrome.action.setBadgeText({ text: "", tabId }), 3000);
}
