// SPDX-License-Identifier: MIT

import { extractStandaloneMedia } from "./media.js";
import { fetchPageVideoSource } from "./page-video-source.js";
import {
  PROTOCOL_VERSION,
  type SaveRequestMetadata,
  type SaveResponse,
  type VideoImportAbortRequest,
  type VideoImportChunkRequest,
  type VideoImportMetadata,
  type VideoImportRequest,
  type VideoImportResponse,
} from "./protocol.js";
import { recordVideoElement as recordRenderedVideoElement } from "./video-element-recorder.js";

export const VIDEO_IMPORT_PORT_NAME = "cuttings-video-import";
export const MAX_VIDEO_IMPORT_CHUNK_BYTES = 256 * 1024;

export class VideoImportError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "VideoImportError";
  }
}

interface ListenerEvent<T extends (...args: never[]) => void> {
  addListener(listener: T): void;
  removeListener(listener: T): void;
}

/** The small runtime.Port surface used by the document-side uploader. Keeping
 * it structural makes the streaming contract testable without a browser. */
export interface VideoImportPort {
  postMessage(message: VideoImportRequest): void;
  disconnect(): void;
  onMessage: ListenerEvent<(message: VideoImportResponse) => void>;
  onDisconnect: ListenerEvent<() => void>;
}

export interface VideoImportOptions {
  doc: Document;
  pageUrl: string;
  mediaUrl: string;
  fetchVideo?: (url: string) => Promise<Response>;
  fetchPageVideo?: (url: string) => Promise<Response>;
  recordVideoElement?: (doc: Document, url: string) => Promise<Response>;
  connect?: (name: string) => VideoImportPort;
  createUploadId?: () => string;
  savedAt?: string;
}

export interface VideoImportResult {
  metadata: VideoImportMetadata;
  response: SaveResponse;
}

/** Compatibility shape retained for the focused object-URL tests. Production
 * video captures use the protocol-agnostic `VideoImportOptions` path below. */
export interface BlobVideoImportOptions extends Omit<
  VideoImportOptions,
  "mediaUrl" | "fetchVideo" | "fetchPageVideo"
> {
  blobUrl: string;
  fetchBlob?: (url: string) => Promise<Response>;
  fetchPageBlob?: (url: string) => Promise<Response>;
}

export type BlobVideoImportResult = VideoImportResult;

interface OpenedDocumentVideo {
  reader: ReadableStreamDefaultReader<Uint8Array>;
  initial: { chunks: Uint8Array[]; signature: Uint8Array };
  contentType: string;
  expectedBytes?: number;
}

class VideoSourceUnavailableError extends Error {}

/**
 * Fetch or record a video inside its owning tab and relay the body to the
 * worker one bounded chunk at a time. Reading the next stream value waits for
 * the native acknowledgement of every chunk already derived from the current
 * value, keeping memory bounded and providing end-to-end backpressure.
 */
export async function importVideo({
  doc,
  pageUrl,
  mediaUrl,
  fetchVideo = (url) => fetch(url),
  fetchPageVideo = fetchPageVideoSource,
  recordVideoElement = recordRenderedVideoElement,
  connect = (name) => chrome.runtime.connect({ name }) as VideoImportPort,
  createUploadId = () => crypto.randomUUID(),
  savedAt = new Date().toISOString(),
}: VideoImportOptions): Promise<VideoImportResult> {
  const uploadId = createUploadId();
  const port = connect(VIDEO_IMPORT_PORT_NAME);
  const client = new VideoImportPortClient(port);
  let reader: ReadableStreamDefaultReader<Uint8Array> | undefined;

  try {
    const opened = await openDocumentVideo(
      doc,
      mediaUrl,
      fetchVideo,
      fetchPageVideo,
      recordVideoElement,
    );
    reader = opened.reader;
    const extracted = extractStandaloneMedia(doc, pageUrl, "video", mediaUrl, savedAt);
    const metadata = importMetadata(extracted.metadata);

    await requireAck(
      client.request({
        protocol_version: PROTOCOL_VERSION,
        action: "video_import_begin",
        upload_id: uploadId,
        metadata,
        content_type: opened.contentType,
        ...(opened.expectedBytes === undefined ? {} : { expected_bytes: opened.expectedBytes }),
      }),
    );

    let sequence = 0;
    for (const bytes of opened.initial.chunks) {
      sequence = await sendBytes(client, uploadId, sequence, bytes);
    }
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      if (next.value?.byteLength) {
        sequence = await sendBytes(client, uploadId, sequence, next.value);
      }
    }

    const finish = await client.request({
      protocol_version: PROTOCOL_VERSION,
      action: "video_import_finish",
      upload_id: uploadId,
    });
    if (!finish.ok) {
      if (finish.error === "duplicate") return { metadata, response: finish };
      throw new VideoImportError(finish.error, finish.message || finish.error);
    }
    if (!("id" in finish) || !("path" in finish)) {
      throw new Error("The Cuttings app returned an incomplete video save response.");
    }

    return { metadata, response: finish };
  } catch (error) {
    client.abort(uploadId);
    if (reader) await cancelReader(reader, error);
    throw error;
  } finally {
    reader?.releaseLock();
    client.close();
  }
}

export function importBlobVideo({
  blobUrl,
  fetchBlob,
  fetchPageBlob,
  ...options
}: BlobVideoImportOptions): Promise<BlobVideoImportResult> {
  return importVideo({
    ...options,
    mediaUrl: blobUrl,
    fetchVideo: fetchBlob,
    fetchPageVideo: fetchPageBlob,
  });
}

async function openDocumentVideo(
  doc: Document,
  mediaUrl: string,
  fetchVideo: (url: string) => Promise<Response>,
  fetchPageVideo: (url: string) => Promise<Response>,
  recordVideoElement: (doc: Document, url: string) => Promise<Response>,
): Promise<OpenedDocumentVideo> {
  try {
    return await probeVideoResponse(await fetchVideo(mediaUrl));
  } catch (contentError) {
    if (!isFallbackVideoSourceError(contentError)) throw contentError;
  }

  try {
    return await probeVideoResponse(await fetchPageVideo(mediaUrl));
  } catch {
    // A MAIN-world stream can still fail for an inaccessible source, and some
    // WebExtension hosts may not support MAIN injection. The exact rendered
    // element in the isolated world is the final capability-based fallback.
  }

  return probeVideoResponse(await recordVideoElement(doc, mediaUrl));
}

async function probeVideoResponse(response: Response): Promise<OpenedDocumentVideo> {
  if (!response.ok || !response.body) {
    throw new VideoSourceUnavailableError("The temporary video could not be read from this page.");
  }

  const reader = response.body.getReader();
  try {
    const declaredContentType = response.headers.get("Content-Type");
    const initial = await readInitialVideoChunks(reader, declaredContentType);
    return {
      reader,
      initial,
      contentType: resolveVideoContentType(declaredContentType, initial.signature),
      expectedBytes: parseExpectedBytes(response.headers.get("Content-Length")),
    };
  } catch (error) {
    await cancelReader(reader, error);
    reader.releaseLock();
    throw error;
  }
}

function isFallbackVideoSourceError(error: unknown): boolean {
  return error instanceof TypeError || error instanceof VideoSourceUnavailableError;
}

async function cancelReader(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  reason: unknown,
): Promise<void> {
  const cancellable = reader as ReadableStreamDefaultReader<Uint8Array> & {
    cancel?: (reason?: unknown) => Promise<void>;
  };
  if (typeof cancellable.cancel === "function") {
    await cancellable.cancel(reason).catch(() => undefined);
  }
}

async function sendBytes(
  client: VideoImportPortClient,
  uploadId: string,
  firstSequence: number,
  bytes: Uint8Array,
): Promise<number> {
  let sequence = firstSequence;
  for (let offset = 0; offset < bytes.byteLength; offset += MAX_VIDEO_IMPORT_CHUNK_BYTES) {
    const chunk = bytes.subarray(
      offset,
      Math.min(offset + MAX_VIDEO_IMPORT_CHUNK_BYTES, bytes.byteLength),
    );
    const request: VideoImportChunkRequest = {
      protocol_version: PROTOCOL_VERSION,
      action: "video_import_chunk",
      upload_id: uploadId,
      sequence,
      data_base64: encodeBase64(chunk),
    };
    await requireAck(client.request(request));
    sequence += 1;
  }
  return sequence;
}

async function requireAck(responsePromise: Promise<VideoImportResponse>): Promise<void> {
  const response = await responsePromise;
  if (!response.ok) throw new VideoImportError(response.error, response.message || response.error);
}

function parseExpectedBytes(value: string | null): number | undefined {
  if (!value || !/^\d+$/.test(value)) return undefined;
  const bytes = Number(value);
  return Number.isSafeInteger(bytes) ? bytes : undefined;
}

function importMetadata(metadata: SaveRequestMetadata): VideoImportMetadata {
  const retained = { ...metadata };
  delete retained.media_url;
  return { ...retained, kind: "video" } as VideoImportMetadata;
}

async function readInitialVideoChunks(
  reader: ReadableStreamDefaultReader<Uint8Array>,
  declared: string | null,
): Promise<{ chunks: Uint8Array[]; signature: Uint8Array }> {
  const chunks: Uint8Array[] = [];
  const signature = new Uint8Array(12);
  let signatureBytes = 0;
  const needsSniffing = isGenericContentType(declared);

  while (true) {
    const next = await reader.read();
    if (next.done) break;
    if (!next.value?.byteLength) continue;
    chunks.push(next.value);

    if (signatureBytes < signature.byteLength) {
      const copied = Math.min(signature.byteLength - signatureBytes, next.value.byteLength);
      signature.set(next.value.subarray(0, copied), signatureBytes);
      signatureBytes += copied;
    }

    if (!needsSniffing || sniffVideoContentType(signature.subarray(0, signatureBytes))) break;
    if (signatureBytes === signature.byteLength) break;
  }

  if (chunks.length === 0) {
    throw new VideoSourceUnavailableError("The temporary video was empty.");
  }
  return { chunks, signature: signature.subarray(0, signatureBytes) };
}

function resolveVideoContentType(declared: string | null, bytes: Uint8Array): string {
  const normalized = declared?.split(";", 1)[0].trim().toLowerCase();
  if (normalized?.startsWith("video/")) return normalized;

  if (isGenericContentType(declared)) {
    const sniffed = sniffVideoContentType(bytes);
    if (sniffed) return sniffed;
  }
  throw new VideoSourceUnavailableError("The temporary source did not contain a supported video.");
}

function isGenericContentType(declared: string | null): boolean {
  const normalized = declared?.split(";", 1)[0].trim().toLowerCase();
  return (
    !normalized || normalized === "application/octet-stream" || normalized === "binary/octet-stream"
  );
}

function sniffVideoContentType(bytes: Uint8Array): string | undefined {
  if (bytes.byteLength >= 12 && ascii(bytes, 4, 8) === "ftyp") {
    return ascii(bytes, 8, 12) === "qt  " ? "video/quicktime" : "video/mp4";
  }
  if (
    bytes.byteLength >= 4 &&
    bytes[0] === 0x1a &&
    bytes[1] === 0x45 &&
    bytes[2] === 0xdf &&
    bytes[3] === 0xa3
  ) {
    return "video/webm";
  }
  return undefined;
}

function ascii(bytes: Uint8Array, start: number, end: number): string {
  return String.fromCharCode(...bytes.subarray(start, end));
}

function encodeBase64(bytes: Uint8Array): string {
  let binary = "";
  const stride = 0x8000;
  for (let offset = 0; offset < bytes.byteLength; offset += stride) {
    binary += String.fromCharCode(
      ...bytes.subarray(offset, Math.min(offset + stride, bytes.byteLength)),
    );
  }
  return btoa(binary);
}

class VideoImportPortClient {
  private pending:
    | {
        resolve: (response: VideoImportResponse) => void;
        reject: (error: Error) => void;
      }
    | undefined;
  private closed = false;
  private terminalError: VideoImportError | undefined;

  constructor(private readonly port: VideoImportPort) {
    port.onMessage.addListener(this.handleMessage);
    port.onDisconnect.addListener(this.handleDisconnect);
  }

  request(message: VideoImportRequest): Promise<VideoImportResponse> {
    if (this.terminalError) return Promise.reject(this.terminalError);
    if (this.closed) {
      return Promise.reject(
        new VideoImportError("native_connection", "The video import connection closed."),
      );
    }
    if (this.pending)
      return Promise.reject(new Error("A video import request is already pending."));

    return new Promise((resolve, reject) => {
      this.pending = { resolve, reject };
      try {
        this.port.postMessage(message);
      } catch (error) {
        this.pending = undefined;
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  }

  abort(uploadId: string): void {
    if (this.closed || this.pending) return;
    const request: VideoImportAbortRequest = {
      protocol_version: PROTOCOL_VERSION,
      action: "video_import_abort",
      upload_id: uploadId,
    };
    try {
      this.port.postMessage(request);
    } catch {
      // The relay may already be gone; its disconnect handler also aborts a
      // native upload that had reached the host.
    }
  }

  close(): void {
    if (this.closed) return;
    this.closed = true;
    this.port.onMessage.removeListener(this.handleMessage);
    this.port.onDisconnect.removeListener(this.handleDisconnect);
    this.pending?.reject(new Error("The video import connection closed."));
    this.pending = undefined;
    this.port.disconnect();
  }

  private readonly handleMessage = (response: VideoImportResponse): void => {
    const pending = this.pending;
    if (!pending) {
      if (!response.ok) {
        this.terminalError = new VideoImportError(
          response.error,
          response.message || response.error,
        );
      }
      return;
    }
    this.pending = undefined;
    pending.resolve(response);
  };

  private readonly handleDisconnect = (): void => {
    if (this.closed) return;
    this.closed = true;
    this.terminalError ??= new VideoImportError(
      "native_connection",
      "The Cuttings app closed the video import connection.",
    );
    this.pending?.reject(this.terminalError);
    this.pending = undefined;
  };
}
