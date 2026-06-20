// SPDX-License-Identifier: MIT

import { extractPage } from "./extraction.js";

/** In-page toast request sent by the background worker after a save attempt. */
export interface ToastMessage {
  action: "toast";
  status: "ok" | "error";
  title: string;
  detail?: string;
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg?.action === "extract") {
    const result = extractPage(document, window.location.href);
    sendResponse(result ?? { error: "Could not extract article content from this page." });
    return true;
  }

  if (msg?.action === "toast") {
    showToast(msg as ToastMessage);
  }
});

const TOAST_HOST_ID = "read-later-toast-host";

/**
 * Render a transient toast in the top-right corner of the page. The toast lives
 * inside a Shadow DOM so the host page's CSS can't restyle or hide it, and any
 * existing toast is replaced rather than stacked.
 */
export function showToast({ status, title, detail }: ToastMessage): void {
  document.getElementById(TOAST_HOST_ID)?.remove();

  const host = document.createElement("div");
  host.id = TOAST_HOST_ID;
  host.style.cssText =
    "all: initial; position: fixed; top: 16px; right: 16px; z-index: 2147483647;";

  const accent = status === "ok" ? "#22C55E" : "#EF4444";
  const icon = status === "ok" ? "✓" : "✕";

  const root = host.attachShadow({ mode: "open" });
  root.innerHTML = `
    <style>
      @keyframes rl-in { from { opacity: 0; transform: translateY(-8px); } to { opacity: 1; transform: none; } }
      @keyframes rl-out { from { opacity: 1; } to { opacity: 0; transform: translateY(-8px); } }
      .toast {
        display: flex; align-items: center; gap: 10px;
        box-sizing: border-box; max-width: 340px;
        padding: 12px 14px;
        font: 500 13px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif;
        color: #0F172A; background: #FFFFFF;
        border: 1px solid #E2E8F0; border-left: 4px solid ${accent};
        border-radius: 8px; box-shadow: 0 8px 24px rgba(15, 23, 42, 0.18);
        animation: rl-in 180ms ease-out;
      }
      .toast.hide { animation: rl-out 200ms ease-in forwards; }
      .badge {
        flex: 0 0 auto; width: 20px; height: 20px; border-radius: 50%;
        display: grid; place-items: center;
        background: ${accent}; color: #FFFFFF; font-size: 12px; font-weight: 700;
      }
      .text { min-width: 0; }
      .title { font-weight: 600; }
      .detail {
        margin-top: 2px; color: #64748B; font-weight: 400;
        overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
      }
    </style>
    <div class="toast">
      <div class="badge">${icon}</div>
      <div class="text">
        <div class="title"></div>
        ${detail ? '<div class="detail"></div>' : ""}
      </div>
    </div>
  `;

  // Page-derived strings go in via textContent, never innerHTML, to avoid injection.
  root.querySelector(".title")!.textContent = title;
  if (detail) root.querySelector(".detail")!.textContent = detail;

  (document.body ?? document.documentElement).appendChild(host);

  const toast = root.querySelector(".toast")!;
  const dismiss = () => host.remove();
  setTimeout(() => {
    toast.classList.add("hide");
    toast.addEventListener("animationend", dismiss, { once: true });
    setTimeout(dismiss, 400); // fallback in case animationend doesn't fire
  }, 3200);
}
