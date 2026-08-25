// SPDX-License-Identifier: MIT

import { describe, expect, it, vi } from "vitest";

import { OPEN_PAGE_VIDEO_SOURCE, fetchPageVideoSource } from "./page-video-source.js";

describe("content-side page video source", () => {
  it("exposes the MAIN-world chunks as a pullable Response without whole-video buffering", async () => {
    const prepare = vi.fn(async () => undefined);
    const chunks = [Uint8Array.from([1, 2, 3]), Uint8Array.from([4, 5])];
    let index = 0;
    const targetWindow = {
      postMessage(message: unknown, _origin: string, transfer: Transferable[]) {
        expect(message).toEqual({
          type: OPEN_PAGE_VIDEO_SOURCE,
          url: "blob:https://www.cosmos.so/video",
        });
        const port = transfer[0] as MessagePort;
        port.start();
        port.postMessage({
          type: "ready",
          ok: true,
          contentType: "video/mp4",
          expectedBytes: 5,
        });
        port.onmessage = (event) => {
          if (event.data.type === "next") {
            const value = chunks[index++];
            if (!value) {
              port.postMessage({ type: "done" });
            } else {
              const data = value.slice().buffer;
              port.postMessage({ type: "chunk", data }, [data]);
            }
          }
        };
      },
    } as unknown as Window;

    const response = await fetchPageVideoSource(
      "blob:https://www.cosmos.so/video",
      prepare,
      targetWindow,
    );
    const reader = response.body!.getReader();
    const received: number[] = [];
    while (true) {
      const next = await reader.read();
      if (next.done) break;
      received.push(...next.value);
    }

    expect(prepare).toHaveBeenCalledTimes(1);
    expect(response.headers.get("Content-Type")).toBe("video/mp4");
    expect(response.headers.get("Content-Length")).toBe("5");
    expect(received).toEqual([1, 2, 3, 4, 5]);
  });
});
