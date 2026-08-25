// SPDX-License-Identifier: MIT

import {
  PROTOCOL_VERSION,
  type VideoImportAbortRequest,
  type VideoImportRequest,
  type VideoImportResponse,
} from "./protocol.js";

interface ListenerEvent<T extends (...args: never[]) => void> {
  addListener(listener: T): void;
  removeListener(listener: T): void;
}

/** Runtime/native Port surface used by the service-worker relay. */
export interface RelayPort {
  postMessage(message: unknown): void;
  disconnect(): void;
  onMessage: ListenerEvent<(message: unknown) => void>;
  onDisconnect: ListenerEvent<() => void>;
}

/**
 * Relay one tab-owned video upload over one persistent native connection.
 * Messages are serialized: even a misbehaving tab cannot put the next chunk on
 * the native port until the preceding request has received its acknowledgement.
 */
export function relayVideoImportPort(
  tabPort: RelayPort,
  connectNative: () => RelayPort,
  nativeDisconnectMessage: () => string | undefined = () => undefined,
): void {
  let nativePort: RelayPort;
  try {
    nativePort = connectNative();
  } catch (error) {
    postError(tabPort, error);
    tabPort.disconnect();
    return;
  }

  const queued: VideoImportRequest[] = [];
  let pending: VideoImportRequest | undefined;
  let uploadId: string | undefined;
  let tabDisconnected = false;
  let uploadTerminal = false;
  let abortQueued = false;

  const flush = (): void => {
    if (pending) return;

    if (tabDisconnected && uploadId && !uploadTerminal && !abortQueued) {
      const abort: VideoImportAbortRequest = {
        protocol_version: PROTOCOL_VERSION,
        action: "video_import_abort",
        upload_id: uploadId,
      };
      queued.length = 0;
      queued.push(abort);
      abortQueued = true;
    }

    const next = queued.shift();
    if (!next) {
      if (tabDisconnected) nativePort.disconnect();
      return;
    }

    pending = next;
    try {
      nativePort.postMessage(next);
    } catch (error) {
      pending = undefined;
      if (!tabDisconnected) postError(tabPort, error);
      nativePort.disconnect();
    }
  };

  const handleTabMessage = (value: unknown): void => {
    if (!isVideoImportRequest(value)) {
      postError(tabPort, new Error("The tab sent an invalid video import message."));
      return;
    }
    if (value.action === "video_import_begin") uploadId = value.upload_id;
    queued.push(value);
    flush();
  };

  const handleNativeMessage = (value: unknown): void => {
    const completed = pending;
    pending = undefined;
    if (completed?.action === "video_import_finish" || completed?.action === "video_import_abort") {
      uploadTerminal = true;
    }
    if (!tabDisconnected) tabPort.postMessage(value as VideoImportResponse);
    flush();
  };

  const handleTabDisconnect = (): void => {
    tabDisconnected = true;
    queued.length = 0;
    flush();
  };

  const handleNativeDisconnect = (): void => {
    pending = undefined;
    queued.length = 0;
    if (!tabDisconnected) {
      postError(
        tabPort,
        new Error(
          nativeDisconnectMessage() ?? "The Cuttings app closed the video import connection.",
        ),
      );
      tabPort.disconnect();
    }
  };

  tabPort.onMessage.addListener(handleTabMessage);
  tabPort.onDisconnect.addListener(handleTabDisconnect);
  nativePort.onMessage.addListener(handleNativeMessage);
  nativePort.onDisconnect.addListener(handleNativeDisconnect);
}

function isVideoImportRequest(value: unknown): value is VideoImportRequest {
  if (!value || typeof value !== "object") return false;
  const message = value as Partial<VideoImportRequest>;
  return (
    message.protocol_version === PROTOCOL_VERSION &&
    typeof message.upload_id === "string" &&
    (message.action === "video_import_begin" ||
      message.action === "video_import_chunk" ||
      message.action === "video_import_finish" ||
      message.action === "video_import_abort")
  );
}

function postError(port: RelayPort, error: unknown): void {
  try {
    port.postMessage({
      protocol_version: PROTOCOL_VERSION,
      ok: false,
      error: "native_connection",
      message: error instanceof Error ? error.message : String(error),
    } satisfies VideoImportResponse);
  } catch {
    // The tab may already be gone; there is nowhere left to surface the error.
  }
}
