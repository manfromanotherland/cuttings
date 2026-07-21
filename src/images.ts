// SPDX-License-Identifier: MIT

import type { ImageData } from "./protocol.js";

/** How many images to fetch at once. */
const MAX_CONCURRENCY = 6;

/** Abort a single image fetch that takes longer than this. */
const FETCH_TIMEOUT_MS = 15_000;

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
  const images: ImageData[] = [];
  const unresolved: string[] = [];
  let next = 0;

  async function worker(): Promise<void> {
    while (next < unique.length) {
      const url = unique[next++];
      const image = await fetchImage(url);
      if (image) images.push(image);
      else unresolved.push(url);
    }
  }

  const workers = Array.from({ length: Math.min(MAX_CONCURRENCY, unique.length) }, worker);
  await Promise.all(workers);
  return { images, unresolved };
}

/** Fetch one image and encode it, or return null if it can't be read. */
export async function fetchImage(url: string): Promise<ImageData | null> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), FETCH_TIMEOUT_MS);
  try {
    const response = await fetch(url, { signal: controller.signal });
    if (!response.ok) return null;
    const buffer = await response.arrayBuffer();
    if (buffer.byteLength === 0) return null;
    const content_type = (response.headers.get("content-type") ?? "").split(";")[0].trim();
    return { url, content_type, data_base64: bytesToBase64(new Uint8Array(buffer)) };
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
    const size = Math.floor((image.data_base64.length * 3) / 4);
    if (total + size > maxBytes) continue;
    total += size;
    kept.push(image);
  }
  return kept;
}
