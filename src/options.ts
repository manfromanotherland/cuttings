// SPDX-License-Identifier: MIT

import { pingHost, type HostStatus } from "./host.js";

interface Options {
  defaultTags: string[];
  keepOriginalHtml: boolean;
}

const DEFAULTS: Options = { defaultTags: [], keepOriginalHtml: false };

async function loadOptions(): Promise<Options> {
  const stored = await chrome.storage.sync.get(DEFAULTS);
  return stored as Options;
}

async function saveOptions(opts: Options): Promise<void> {
  await chrome.storage.sync.set(opts);
}

// ── DOM helpers ───────────────────────────────────────────────────────────────

function el<T extends HTMLElement>(id: string): T {
  return document.getElementById(id) as T;
}

function setStatus(status: HostStatus): void {
  const dot = el("status-dot");
  const label = el("status-label");
  const installLink = el("install-link");

  dot.className = "dot " + status;

  if (status === "connected") {
    label.textContent = "Connected";
    installLink.hidden = true;
  } else if (status === "missing") {
    label.textContent = "Not installed";
    installLink.hidden = false;
  } else {
    label.textContent = "Connection error";
    installLink.hidden = false;
  }
}

// ── Init ──────────────────────────────────────────────────────────────────────

document.addEventListener("DOMContentLoaded", async () => {
  // Load saved options into the form
  const opts = await loadOptions();

  const tagsInput = el<HTMLInputElement>("default-tags");
  const keepHtmlInput = el<HTMLInputElement>("keep-original-html");
  const checkBtn = el<HTMLButtonElement>("check-btn");
  const saveBtn = el<HTMLButtonElement>("save-btn");
  const savedMsg = el("saved-msg");

  tagsInput.value = opts.defaultTags.join(", ");
  keepHtmlInput.checked = opts.keepOriginalHtml;

  // Initial status check
  setStatus(await pingHost());

  // Re-check button
  checkBtn.addEventListener("click", async () => {
    checkBtn.disabled = true;
    checkBtn.textContent = "Checking…";
    setStatus(await pingHost());
    checkBtn.disabled = false;
    checkBtn.textContent = "Check again";
  });

  // Save button
  saveBtn.addEventListener("click", async () => {
    const raw = tagsInput.value
      .split(",")
      .map((t) => t.trim())
      .filter(Boolean);

    await saveOptions({ defaultTags: raw, keepOriginalHtml: keepHtmlInput.checked });

    savedMsg.hidden = false;
    setTimeout(() => (savedMsg.hidden = true), 2000);
  });
});
