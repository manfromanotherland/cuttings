// SPDX-License-Identifier: MIT

import { extractPage } from "./extraction.js";
import { fetchImages } from "./images.js";
import type { ImageData, SaveRequestMetadata } from "./protocol.js";

/** An optional action button on a toast. Clicking it messages the background
 *  worker (which alone can open extension pages) and dismisses the toast. */
export interface ToastCta {
  label: string;
  command: "open-install";
}

/** In-page toast request sent by the background worker after a save attempt. */
export interface ToastMessage {
  action: "toast";
  status: "ok" | "error" | "loading";
  title: string;
  detail?: string;
  cta?: ToastCta;
}

/**
 * Result of extracting a page and capturing its images. Images the content
 * script could read (same-origin or CORS-enabled, served from the browser cache)
 * come back in `images`; the rest are listed in `unresolved` for the background
 * worker to retry with its cross-origin reach.
 */
export interface PageCapture {
  metadata: SaveRequestMetadata;
  markdown: string;
  images: ImageData[];
  unresolved: string[];
}

chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg?.action === "extract") {
    void (async () => {
      const result = extractPage(document, window.location.href);
      if (!result) {
        sendResponse({ error: "Could not extract article content from this page." });
        return;
      }
      // Fetch images here first: in the page's context these reuse the browser's
      // cache, so images the browser already loaded need no network request.
      const { images, unresolved } = await fetchImages(result.image_urls);
      const capture: PageCapture = {
        metadata: result.metadata,
        markdown: result.markdown,
        images,
        unresolved,
      };
      sendResponse(capture);
    })();
    return true; // keep the message channel open for the async sendResponse
  }

  if (msg?.action === "toast") {
    showToast(msg as ToastMessage);
  }
});

const TOAST_HOST_ID = "readcontrol-toast-host";

/**
 * Show or update the toast. If a loading toast is already present and the new
 * status is ok/error, the existing toast transitions in place instead of being
 * replaced. If the loading toast was already dismissed by the user, a fresh
 * toast is created with the result status.
 */
export function showToast({ status, title, detail, cta }: ToastMessage): void {
  const existingHost = document.getElementById(TOAST_HOST_ID) as HTMLElement | null;

  if (status !== "loading" && existingHost?.dataset.status === "loading") {
    existingHost.dataset.status = status;
    updateToast(existingHost, status, title, detail, cta);
    return;
  }

  existingHost?.remove();

  const isLoading = status === "loading";
  // ReadControl paper/ink palette (shared with the website); heart red for errors.
  const accent = status === "ok" ? "#22C55E" : isLoading ? "#17181A" : "#FF5F57";
  const icon = status === "ok" ? "✓" : "✕";

  const host = document.createElement("div");
  host.id = TOAST_HOST_ID;
  host.dataset.status = status;
  host.style.cssText =
    "all: initial; position: fixed; top: 16px; right: 16px; z-index: 2147483647;";

  const root = host.attachShadow({ mode: "open" });
  root.innerHTML = `
    <style>
      @keyframes rl-in { from { opacity: 0; transform: translateY(-8px); } to { opacity: 1; transform: none; } }
      @keyframes rl-out { from { opacity: 1; } to { opacity: 0; transform: translateY(-8px); } }
      @keyframes rl-spin { to { transform: rotate(360deg); } }
      .toast {
        display: flex; align-items: center; gap: 10px;
        box-sizing: border-box; max-width: 340px;
        padding: 12px 14px;
        font: 500 13px/1.45 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif;
        color: #17181A; background: #FDFCFB;
        border: 1px solid rgba(23, 24, 26, 0.12); border-left: 4px solid ${accent};
        border-radius: 8px; box-shadow: 0 8px 24px rgba(23, 24, 26, 0.18);
        animation: rl-in 180ms ease-out;
        transition: border-left-color 250ms ease;
      }
      .toast.hide { animation: rl-out 200ms ease-in forwards; }
      .badge {
        flex: 0 0 auto; width: 20px; height: 20px; border-radius: 50%;
        display: grid; place-items: center;
        color: #FFFFFF; font-size: 12px; font-weight: 700;
      }
      .spinner {
        flex: 0 0 auto; box-sizing: border-box; width: 20px; height: 20px;
        border-radius: 50%; border: 2.5px solid ${accent}; border-top-color: transparent;
        animation: rl-spin 700ms linear infinite;
      }
      .text { min-width: 0; flex: 1; }
      .title { font-weight: 600; }
      .detail {
        margin-top: 2px; color: #55565A; font-weight: 400;
        overflow: hidden; text-overflow: ellipsis; white-space: nowrap;
      }
      .close {
        cursor: pointer; background: none; border: none; padding: 0; font-family: inherit;
        flex: 0 0 auto; width: 20px; height: 20px; border-radius: 4px;
        display: grid; place-items: center;
        color: #85868B; font-size: 16px; line-height: 1;
      }
      .close:hover { color: #17181A; background: #EEEDEC; }
      .cta {
        margin-top: 8px; cursor: pointer;
        background: #17181A; color: #F7F6F4; border: none;
        border-radius: 6px; padding: 6px 12px;
        font: 600 12px/1 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Arial, sans-serif;
      }
      .cta:hover { background: #35363A; }
    </style>
    <div class="toast">
      ${
        isLoading
          ? '<div class="spinner"></div>'
          : `<div class="badge" style="background:${accent}">${icon}</div>`
      }
      <div class="text">
        <div class="title"></div>
        ${detail ? '<div class="detail"></div>' : ""}
      </div>
      <button class="close" aria-label="Close">×</button>
    </div>
  `;

  // Page-derived strings go in via textContent, never innerHTML, to avoid injection.
  root.querySelector(".title")!.textContent = title;
  if (detail) root.querySelector(".detail")!.textContent = detail;
  root.querySelector(".close")!.addEventListener("click", () => host.remove());
  renderCta(root, host, cta);

  (document.body ?? document.documentElement).appendChild(host);

  // A toast with an action stays until the user acts on or dismisses it, the
  // way a "needs your attention" prompt should.
  if (!isLoading && !cta) {
    scheduleDismiss(host);
  }
}

/** Add (or clear) the action button and wire its click to the background. */
function renderCta(root: ShadowRoot, host: HTMLElement, cta?: ToastCta): void {
  root.querySelector(".cta")?.remove();
  if (!cta) return;

  const button = document.createElement("button");
  button.className = "cta";
  button.type = "button";
  button.textContent = cta.label;
  button.addEventListener("click", () => {
    // The content script can't open an extension page; the worker does it.
    void chrome.runtime.sendMessage({ action: "toast-cta", command: cta.command });
    host.remove();
  });
  root.querySelector(".text")!.appendChild(button);
}

function updateToast(
  host: HTMLElement,
  status: "ok" | "error",
  title: string,
  detail?: string,
  cta?: ToastCta,
): void {
  const root = host.shadowRoot!;
  const accent = status === "ok" ? "#22C55E" : "#FF5F57";
  const icon = status === "ok" ? "✓" : "✕";

  const toastEl = root.querySelector<HTMLElement>(".toast")!;
  toastEl.style.borderLeftColor = accent;

  const spinner = root.querySelector(".spinner");
  if (spinner) {
    const badge = document.createElement("div");
    badge.className = "badge";
    badge.style.background = accent;
    badge.textContent = icon;
    spinner.replaceWith(badge);
  }

  root.querySelector(".title")!.textContent = title;

  const textEl = root.querySelector(".text")!;
  let detailEl = root.querySelector(".detail");
  if (detail) {
    if (!detailEl) {
      detailEl = document.createElement("div");
      detailEl.className = "detail";
      textEl.appendChild(detailEl);
    }
    detailEl.textContent = detail;
  } else {
    detailEl?.remove();
  }

  renderCta(root, host, cta);

  // Keep an actionable toast on screen until the user responds to it.
  if (!cta) scheduleDismiss(host);
}

function scheduleDismiss(host: HTMLElement): void {
  const toast = host.shadowRoot!.querySelector(".toast")!;
  const dismiss = () => host.remove();
  setTimeout(() => {
    toast.classList.add("hide");
    toast.addEventListener("animationend", dismiss, { once: true });
    setTimeout(dismiss, 400); // fallback in case animationend doesn't fire
  }, 3200);
}
