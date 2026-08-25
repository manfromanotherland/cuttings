// SPDX-License-Identifier: MIT

export const PREPARE_PAGE_VIDEO_BRIDGE = "prepare-page-video-bridge";
export const OPEN_PAGE_VIDEO_SOURCE = "cuttings:open-page-video-source:v1";

interface PageVideoReadyMessage {
  type: "ready";
  ok: true;
  contentType: string;
  expectedBytes?: number;
}

interface PageVideoErrorMessage {
  type: "error";
  ok: false;
  message: string;
}

interface PageVideoChunkMessage {
  type: "chunk";
  data: ArrayBuffer;
}

interface PageVideoDoneMessage {
  type: "done";
}

type PageVideoMessage =
  | PageVideoReadyMessage
  | PageVideoErrorMessage
  | PageVideoChunkMessage
  | PageVideoDoneMessage;

interface BridgePreparationResponse {
  ok: boolean;
  message?: string;
}

type PrepareBridge = () => Promise<void>;

/**
 * Read or record a selected video from the page's MAIN execution world. Some
 * WebExtension hosts keep object-URL lookup or element capture isolated from
 * content scripts even though both worlds can see the same `<video>` element.
 *
 * The MAIN-world bridge still streams on demand: one `next` request produces
 * at most one source chunk, so this adapter never materializes the whole video.
 */
export async function fetchPageVideoSource(
  url: string,
  prepareBridge: PrepareBridge = preparePageVideoBridge,
  targetWindow: Window = window,
): Promise<Response> {
  await prepareBridge();

  const channel = new MessageChannel();
  channel.port1.start();
  const readyPromise = receivePageVideoMessage(channel.port1);
  targetWindow.postMessage({ type: OPEN_PAGE_VIDEO_SOURCE, url }, "*", [channel.port2]);

  const ready = await readyPromise;
  if (ready.type === "error") {
    channel.port1.close();
    throw new TypeError(ready.message);
  }
  if (ready.type !== "ready" || !ready.ok) {
    channel.port1.close();
    throw new TypeError("The page did not expose the temporary video source.");
  }

  let closed = false;
  const body = new ReadableStream<Uint8Array>({
    async pull(controller) {
      channel.port1.postMessage({ type: "next" });
      const message = await receivePageVideoMessage(channel.port1);
      if (message.type === "chunk") {
        controller.enqueue(new Uint8Array(message.data));
        return;
      }
      closed = true;
      channel.port1.close();
      if (message.type === "error") {
        controller.error(new Error(message.message));
      } else if (message.type === "done") {
        controller.close();
      } else {
        controller.error(new Error("The page returned an invalid video stream response."));
      }
    },
    cancel() {
      if (closed) return;
      closed = true;
      channel.port1.postMessage({ type: "cancel" });
      channel.port1.close();
    },
  });

  const headers = new Headers({ "Content-Type": ready.contentType });
  if (ready.expectedBytes !== undefined) {
    headers.set("Content-Length", String(ready.expectedBytes));
  }
  return new Response(body, { status: 200, headers });
}

export function isPreparePageVideoBridgeMessage(
  value: unknown,
): value is { action: typeof PREPARE_PAGE_VIDEO_BRIDGE } {
  return (
    Boolean(value) &&
    typeof value === "object" &&
    (value as { action?: unknown }).action === PREPARE_PAGE_VIDEO_BRIDGE
  );
}

function preparePageVideoBridge(): Promise<void> {
  return new Promise((resolve, reject) => {
    chrome.runtime.sendMessage({ action: PREPARE_PAGE_VIDEO_BRIDGE }, (response) => {
      if (chrome.runtime.lastError) {
        reject(new Error(chrome.runtime.lastError.message));
        return;
      }
      const prepared = response as BridgePreparationResponse | undefined;
      if (!prepared?.ok) {
        reject(new Error(prepared?.message || "The page video bridge could not be started."));
        return;
      }
      resolve();
    });
  });
}

function receivePageVideoMessage(port: MessagePort): Promise<PageVideoMessage> {
  return new Promise((resolve, reject) => {
    const handleMessage = (event: MessageEvent<unknown>): void => {
      cleanup();
      resolve(event.data as PageVideoMessage);
    };
    const handleMessageError = (): void => {
      cleanup();
      reject(new Error("The page video stream could not be decoded."));
    };
    const cleanup = (): void => {
      port.removeEventListener("message", handleMessage);
      port.removeEventListener("messageerror", handleMessageError);
    };
    port.addEventListener("message", handleMessage);
    port.addEventListener("messageerror", handleMessageError);
  });
}
