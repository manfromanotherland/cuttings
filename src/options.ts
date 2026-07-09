// SPDX-License-Identifier: MIT

import { pingHost, type HostStatus } from "./host.js";
import { clearLog, LOG_STORAGE_KEY, readLog, type LogEntry } from "./log.js";

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

// ── Diagnostics log ─────────────────────────────────────────────────────────

function stringify(data: unknown): string {
  if (typeof data === "string") return data;
  try {
    return JSON.stringify(data);
  } catch {
    return String(data);
  }
}

function formatTime(iso: string): string {
  const d = new Date(iso);
  return isNaN(d.getTime()) ? iso : d.toLocaleTimeString();
}

function renderLog(entries: LogEntry[]): void {
  const view = el("log-view");
  view.textContent = "";

  if (!entries.length) {
    const empty = document.createElement("div");
    empty.className = "log-empty";
    empty.textContent = "No activity logged yet.";
    view.appendChild(empty);
    return;
  }

  // Newest first.
  for (const entry of [...entries].reverse()) {
    const row = document.createElement("div");
    row.className = "log-entry " + entry.level;

    const time = document.createElement("span");
    time.className = "log-time";
    time.textContent = formatTime(entry.time);

    const msg = document.createElement("span");
    msg.className = "log-msg";
    msg.textContent =
      entry.data !== undefined ? `${entry.msg} — ${stringify(entry.data)}` : entry.msg;

    row.append(time, msg);
    view.appendChild(row);
  }
}

function logToText(entries: LogEntry[]): string {
  return entries
    .map(
      (e) =>
        `${e.time} [${e.level}] ${e.msg}${e.data !== undefined ? " " + stringify(e.data) : ""}`,
    )
    .join("\n");
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

  // Diagnostics log
  const refreshLog = async () => renderLog(await readLog());
  await refreshLog();

  el<HTMLButtonElement>("log-refresh").addEventListener("click", refreshLog);

  el<HTMLButtonElement>("log-clear").addEventListener("click", async () => {
    await clearLog();
    await refreshLog();
  });

  const copyBtn = el<HTMLButtonElement>("log-copy");
  copyBtn.addEventListener("click", async () => {
    await navigator.clipboard.writeText(logToText(await readLog()));
    const original = copyBtn.textContent;
    copyBtn.textContent = "Copied!";
    setTimeout(() => (copyBtn.textContent = original), 1500);
  });

  // Live-update while the options page is open.
  chrome.storage.onChanged.addListener((changes, area) => {
    if (area === "local" && changes[LOG_STORAGE_KEY]) {
      renderLog((changes[LOG_STORAGE_KEY].newValue as LogEntry[] | undefined) ?? []);
    }
  });
});
