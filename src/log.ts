// SPDX-License-Identifier: MIT

/** A single diagnostic log entry, persisted to chrome.storage.local. */
export interface LogEntry {
  /** ISO-8601 timestamp of when the entry was recorded. */
  time: string;
  level: "info" | "warn" | "error";
  msg: string;
  /** Optional JSON-serializable context. */
  data?: unknown;
}

export const LOG_STORAGE_KEY = "debugLog";
const MAX_ENTRIES = 200;

/** Serialize writes so concurrent log() calls don't clobber each other's read-modify-write. */
let writeChain: Promise<void> = Promise.resolve();

/**
 * Append an entry to the persistent diagnostic log (a ring buffer capped at
 * MAX_ENTRIES) and mirror it to the console.
 *
 * The service worker's console is ephemeral — it's discarded whenever the
 * worker is torn down — so intermittent save failures are easy to miss. Writing
 * to storage lets the options page surface what happened after the fact.
 */
export function log(level: LogEntry["level"], msg: string, data?: unknown): Promise<void> {
  const entry: LogEntry = { time: new Date().toISOString(), level, msg };
  if (data !== undefined) entry.data = serialize(data);

  const line =
    entry.data !== undefined ? `read-later: ${msg} — ${format(entry.data)}` : `read-later: ${msg}`;
  if (level === "error") console.error(line);
  else if (level === "warn") console.warn(line);
  else console.info(line);

  writeChain = writeChain
    .then(async () => {
      const stored = await chrome.storage.local.get(LOG_STORAGE_KEY);
      const entries = (stored[LOG_STORAGE_KEY] as LogEntry[] | undefined) ?? [];
      entries.push(entry);
      if (entries.length > MAX_ENTRIES) entries.splice(0, entries.length - MAX_ENTRIES);
      await chrome.storage.local.set({ [LOG_STORAGE_KEY]: entries });
    })
    .catch(() => {
      // Storage is best-effort; the console line above is the fallback.
    });

  return writeChain;
}

/** Render a serialized value as a compact one-line string for the console. */
function format(data: unknown): string {
  if (typeof data === "string") return data;
  try {
    return JSON.stringify(data);
  } catch {
    return String(data);
  }
}

/** Reduce an arbitrary value to something JSON-serializable and compact. */
function serialize(data: unknown): unknown {
  if (data instanceof Error) return { name: data.name, message: data.message };
  try {
    JSON.stringify(data);
    return data;
  } catch {
    return String(data);
  }
}

/** Read all persisted log entries, oldest first. */
export async function readLog(): Promise<LogEntry[]> {
  const stored = await chrome.storage.local.get(LOG_STORAGE_KEY);
  return (stored[LOG_STORAGE_KEY] as LogEntry[] | undefined) ?? [];
}

/** Remove all persisted log entries. */
export async function clearLog(): Promise<void> {
  await chrome.storage.local.remove(LOG_STORAGE_KEY);
}
