// SPDX-License-Identifier: MIT

import { OPEN_PAGE_VIDEO_SOURCE } from "./page-video-source.js";
import { recordVideoElement } from "./video-element-recorder.js";

const PAGE_VIDEO_BRIDGE_MARKER = "__cuttingsPageVideoBridgeV1";
const MAX_PAGE_VIDEO_CHUNK_BYTES = 256 * 1024;

interface PageVideoPort {
  postMessage(message: unknown, transfer?: Transferable[]): void;
  close(): void;
  start(): void;
  onmessage: ((event: MessageEvent<unknown>) => void) | null;
}

interface PageVideoBridgeWindow extends Window {
  [PAGE_VIDEO_BRIDGE_MARKER]?: true;
}

/** Install the idempotent MAIN-world listener used by the content-side stream. */
export function installPageVideoBridge(
  targetWindow: PageVideoBridgeWindow = window,
  fetchSource: typeof fetch = fetch,
  recordSource: (url: string) => Promise<Response> = (url) =>
    recordVideoElement(targetWindow.document, url),
): void {
  if (targetWindow[PAGE_VIDEO_BRIDGE_MARKER]) return;
  targetWindow[PAGE_VIDEO_BRIDGE_MARKER] = true;

  targetWindow.addEventListener("message", (event) => {
    if (event.source !== targetWindow) return;
    if (!isOpenRequest(event.data)) return;
    const port = event.ports[0] as PageVideoPort | undefined;
    if (!port) return;
    void servePageVideoSource(
      event.data.url,
      port,
      targetWindow.location.origin,
      fetchSource,
      recordSource,
    );
  });
}

/** Serve exactly one selected page video with pull-based backpressure. */
export async function servePageVideoSource(
  url: string,
  port: PageVideoPort,
  pageOrigin: string,
  fetchSource: typeof fetch,
  recordSource: (url: string) => Promise<Response> = (sourceUrl) =>
    recordVideoElement(document, sourceUrl),
): Promise<void> {
  port.start();
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;
  let pendingBytes: Uint8Array | undefined;
  let pendingOffset = 0;
  let reading = false;
  let terminal = false;

  const close = (): void => {
    if (terminal) return;
    terminal = true;
    reader?.releaseLock();
    port.close();
  };

  try {
    const parsed = new URL(url);
    if (parsed.protocol === "blob:" && parsed.origin !== pageOrigin) {
      throw new Error("The temporary video does not belong to this page.");
    }
    if (!isRecordableVideoProtocol(parsed.protocol)) {
      throw new Error("The page video uses an unsupported source.");
    }

    const opened = await openPageVideoSource(url, fetchSource, recordSource);
    reader = opened.reader;
    pendingBytes = opened.firstBytes;
    const sourceReader = reader;
    port.postMessage({
      type: "ready",
      ok: true,
      contentType: opened.contentType,
      ...(opened.expectedBytes === undefined ? {} : { expectedBytes: opened.expectedBytes }),
    });

    port.onmessage = (event): void => {
      const request = event.data as { type?: unknown } | null;
      if (request?.type === "cancel") {
        terminal = true;
        void sourceReader.cancel().finally(() => port.close());
        return;
      }
      if (request?.type !== "next" || reading || terminal) return;
      reading = true;
      void nextTransferableChunk(sourceReader, () => ({ pendingBytes, pendingOffset }))
        .then((next) => {
          pendingBytes = next.pendingBytes;
          pendingOffset = next.pendingOffset;
          if (!next.data) {
            port.postMessage({ type: "done" });
            close();
            return;
          }
          port.postMessage({ type: "chunk", data: next.data }, [next.data]);
        })
        .catch((error: unknown) => {
          port.postMessage({
            type: "error",
            ok: false,
            message: error instanceof Error ? error.message : String(error),
          });
          close();
        })
        .finally(() => {
          reading = false;
        });
    };
  } catch (error) {
    port.postMessage({
      type: "error",
      ok: false,
      message: error instanceof Error ? error.message : String(error),
    });
    close();
  }
}

interface OpenedPageVideoSource {
  reader: ReadableStreamDefaultReader<Uint8Array>;
  firstBytes: Uint8Array;
  contentType: string;
  expectedBytes?: number;
}

async function openPageVideoSource(
  url: string,
  fetchSource: typeof fetch,
  recordSource: (url: string) => Promise<Response>,
): Promise<OpenedPageVideoSource> {
  try {
    return await openNonEmptyResponse(await fetchSource(url));
  } catch {
    return openNonEmptyResponse(await recordSource(url));
  }
}

async function openNonEmptyResponse(response: Response): Promise<OpenedPageVideoSource> {
  if (!response.ok || !response.body) {
    throw new Error("The temporary video could not be read from this page.");
  }

  const reader = response.body.getReader();
  try {
    while (true) {
      const first = await reader.read();
      if (first.done) throw new Error("The temporary video was empty.");
      if (!first.value.byteLength) continue;
      return {
        reader,
        firstBytes: first.value,
        contentType: response.headers.get("Content-Type") || "application/octet-stream",
        expectedBytes: exactContentLength(response.headers.get("Content-Length")),
      };
    }
  } catch (error) {
    await reader.cancel(error).catch(() => undefined);
    reader.releaseLock();
    throw error;
  }
}

interface PendingSourceBytes {
  pendingBytes: Uint8Array | undefined;
  pendingOffset: number;
}

interface TransferableChunk extends PendingSourceBytes {
  data?: ArrayBuffer;
}

async function nextTransferableChunk(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  pending: () => PendingSourceBytes,
): Promise<TransferableChunk> {
  let { pendingBytes, pendingOffset } = pending();

  while (true) {
    if (pendingBytes && pendingOffset < pendingBytes.byteLength) {
      const end = Math.min(pendingOffset + MAX_PAGE_VIDEO_CHUNK_BYTES, pendingBytes.byteLength);
      const data = pendingBytes.slice(pendingOffset, end).buffer as ArrayBuffer;
      pendingOffset = end;
      if (pendingOffset === pendingBytes.byteLength) {
        pendingBytes = undefined;
        pendingOffset = 0;
      }
      return { data, pendingBytes, pendingOffset };
    }

    const next = await reader.read();
    if (next.done) return { pendingBytes: undefined, pendingOffset: 0 };
    if (!next.value.byteLength) continue;
    pendingBytes = next.value;
    pendingOffset = 0;
  }
}

function isOpenRequest(value: unknown): value is { type: string; url: string } {
  if (!value || typeof value !== "object") return false;
  const request = value as { type?: unknown; url?: unknown };
  return request.type === OPEN_PAGE_VIDEO_SOURCE && typeof request.url === "string";
}

function isRecordableVideoProtocol(protocol: string): boolean {
  return (
    protocol === "blob:" || protocol === "http:" || protocol === "https:" || protocol === "data:"
  );
}

function exactContentLength(value: string | null): number | undefined {
  if (!value || !/^\d+$/.test(value)) return undefined;
  const bytes = Number(value);
  return Number.isSafeInteger(bytes) ? bytes : undefined;
}

installPageVideoBridge();
