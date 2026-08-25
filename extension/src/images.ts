// SPDX-License-Identifier: MIT

import type { ImageData } from "./protocol.js";

/** How many images to fetch at once. */
const MAX_CONCURRENCY = 6;

/** Abort a single image fetch that takes longer than this. */
const FETCH_TIMEOUT_MS = 15_000;

/** Bound one page asset before it is base64 encoded, matching the total envelope. */
const MAX_IMAGE_BYTES = 40 * 1024 * 1024;

/** Bound content-script → worker messages before native-message capping. */
const MAX_FETCH_TOTAL_BYTES = 40 * 1024 * 1024;

/** The outcome of fetching a set of image URLs. */
export interface FetchImagesResult {
  /** Images whose bytes we captured, ready to send to the host. */
  images: ImageData[];
  /** URLs we couldn't read (e.g. cross-origin without CORS) — a caller in a more
   *  privileged context (the background worker) can retry these. */
  unresolved: string[];
}

/**
 * Fetch each distinct URL and return the bytes we could read.
 *
 * The same code runs in two contexts with different reach:
 * - In a **content script** (page origin) a `fetch` reuses the page's HTTP cache,
 *   so an image the browser already loaded comes back with no network request —
 *   readable when the response allows CORS (or is same-origin).
 * - In the **background service worker** (with host permissions) a `fetch` can
 *   read cross-origin bytes regardless of CORS, covering the rest.
 */
export async function fetchImages(urls: string[]): Promise<FetchImagesResult> {
  const unique = [...new Set(urls)];
  const results: Array<ImageData | null> = Array.from({ length: unique.length }, () => null);
  let next = 0;

  async function worker(): Promise<void> {
    while (next < unique.length) {
      const index = next++;
      results[index] = await fetchImage(unique[index]);
    }
  }

  const workers = Array.from({ length: Math.min(MAX_CONCURRENCY, unique.length) }, worker);
  await Promise.all(workers);

  // Preserve candidate order regardless of which concurrent request finished
  // first, and cap before a content script sends the result to the worker.
  const images: ImageData[] = [];
  const unresolved: string[] = [];
  let totalBytes = 0;
  for (let index = 0; index < unique.length; index++) {
    const image = results[index];
    if (!image) {
      unresolved.push(unique[index]);
      continue;
    }
    const size = decodedBase64Size(image.data_base64);
    if (totalBytes + size > MAX_FETCH_TOTAL_BYTES) {
      unresolved.push(unique[index]);
      continue;
    }
    totalBytes += size;
    images.push(image);
  }
  return { images, unresolved };
}

/** Fetch one image and encode it, or return null if it can't be read. */
export async function fetchImage(url: string): Promise<ImageData | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const response = await fetch(url, { signal: controller.signal });
    if (!response.ok) return null;
    if (response.url && !safeResponseUrl(url, response.url)) return null;
    const declaredLength = Number(response.headers.get("content-length"));
    if (Number.isFinite(declaredLength) && declaredLength > MAX_IMAGE_BYTES) return null;
    const content_type = (response.headers.get("content-type") ?? "").split(";")[0].trim();
    if (
      content_type &&
      !content_type.startsWith("image/") &&
      content_type !== "application/octet-stream"
    ) {
      return null;
    }
    const bytes = await readBoundedBytes(response, MAX_IMAGE_BYTES);
    if (!bytes?.byteLength) return null;
    return { url, content_type, data_base64: bytesToBase64(bytes) };
  } catch {
    // Opaque/blocked by CORS, network error, timeout, or abort.
    return null;
  } finally {
    clearTimeout(timer);
  }
}

/** Base64-encode bytes, chunked so a large image can't overflow the call stack. */
export function bytesToBase64(bytes: Uint8Array): string {
  let binary = "";
  const CHUNK = 0x8000;
  for (let i = 0; i < bytes.length; i += CHUNK) {
    binary += String.fromCharCode(...bytes.subarray(i, i + CHUNK));
  }
  return btoa(binary);
}

/**
 * Keep images in order until their cumulative decoded size would exceed
 * `maxBytes`; drop the rest (they'll stay as remote-URL placeholders). Bounds
 * how much we buffer and send in a single native message.
 */
export function capTotalBytes(images: ImageData[], maxBytes: number): ImageData[] {
  const kept: ImageData[] = [];
  let total = 0;
  for (const image of images) {
    // Decoded size is ~3/4 of the base64 length.
    const size = decodedBase64Size(image.data_base64);
    if (total + size > maxBytes) continue;
    total += size;
    kept.push(image);
  }
  return kept;
}

async function readBoundedBytes(response: Response, maxBytes: number): Promise<Uint8Array | null> {
  const reader = response.body?.getReader();
  if (!reader) {
    const buffer = await response.arrayBuffer();
    return buffer.byteLength <= maxBytes ? new Uint8Array(buffer) : null;
  }

  const chunks: Uint8Array[] = [];
  let total = 0;
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    total += value.byteLength;
    if (total > maxBytes) {
      await reader.cancel();
      return null;
    }
    chunks.push(value);
  }

  const bytes = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    bytes.set(chunk, offset);
    offset += chunk.byteLength;
  }
  return bytes;
}

function decodedBase64Size(value: string): number {
  const padding = value.endsWith("==") ? 2 : value.endsWith("=") ? 1 : 0;
  return Math.max(0, Math.floor((value.length * 3) / 4) - padding);
}

function safeResponseUrl(requestedValue: string, responseValue: string): boolean {
  try {
    const requested = new URL(requestedValue);
    const response = new URL(responseValue);
    if (requested.protocol === "http:" || requested.protocol === "https:") {
      return (
        (response.protocol === "http:" || response.protocol === "https:") &&
        !response.username &&
        !response.password
      );
    }
    return (
      (requested.protocol === "blob:" || requested.protocol === "data:") &&
      response.protocol === requested.protocol
    );
  } catch {
    return false;
  }
}
