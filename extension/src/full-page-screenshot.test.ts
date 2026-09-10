// SPDX-License-Identifier: MIT

import { afterEach, describe, expect, it, vi } from "vitest";

import {
  captureFullPageScreenshot,
  composeFullPageScreenshot,
  screenshotOutputGeometry,
  type ScreenshotComposition,
  type ScreenshotPageState,
} from "./full-page-screenshot.js";

afterEach(() => {
  vi.unstubAllGlobals();
});

describe("full-page screenshot", () => {
  it("captures the full page rather than only the visible viewport", async () => {
    const initial: ScreenshotPageState = {
      sessionId: "session-1",
      url: "https://example.com/long-page",
      viewportWidth: 800,
      viewportHeight: 600,
      documentHeight: 1_500,
      scrollY: 250,
    };
    const scrollTo = vi.fn(
      async (
        _sessionId: string,
        scrollY: number,
        _hideFixed: boolean,
      ): Promise<ScreenshotPageState> => ({
        ...initial,
        scrollY,
      }),
    );
    const captureViewport = vi.fn(async () => "data:image/png;base64,AQID");
    const lifecycle: string[] = [];
    const compose = vi.fn(async (_input: ScreenshotComposition) => {
      lifecycle.push("compose");
      return "data:image/png;base64,BAUG";
    });
    const finish = vi.fn(async () => {
      lifecycle.push("finish");
    });

    const result = await captureFullPageScreenshot({
      begin: async () => initial,
      scrollTo,
      captureViewport,
      compose,
      finish,
      minimumCaptureIntervalMs: 0,
    });

    expect(scrollTo.mock.calls.map(([, scrollY]) => scrollY)).toEqual([0, 600, 900]);
    expect(scrollTo.mock.calls.map(([, , hideFixed]) => hideFixed)).toEqual([false, true, true]);
    expect(captureViewport).toHaveBeenCalledTimes(3);
    expect(compose).toHaveBeenCalledWith({
      documentHeight: 1_500,
      viewportWidth: 800,
      viewportHeight: 600,
      tiles: [
        expect.objectContaining({ scrollY: 0, dataUrl: "data:image/png;base64,AQID" }),
        expect.objectContaining({ scrollY: 600, dataUrl: "data:image/png;base64,AQID" }),
        expect.objectContaining({ scrollY: 900, dataUrl: "data:image/png;base64,AQID" }),
      ],
    });
    expect(finish).toHaveBeenCalledWith("session-1");
    expect(lifecycle).toEqual(["finish", "compose"]);
    expect(result).toBe("data:image/png;base64,BAUG");
  });

  it("restores the page when a viewport capture fails", async () => {
    const state: ScreenshotPageState = {
      sessionId: "session-1",
      url: "https://example.com/long-page",
      viewportWidth: 800,
      viewportHeight: 600,
      documentHeight: 1_500,
      scrollY: 0,
    };
    const finish = vi.fn(async () => Promise.resolve());

    await expect(
      captureFullPageScreenshot({
        begin: async () => state,
        scrollTo: async (_sessionId, scrollY) => ({ ...state, scrollY }),
        captureViewport: async () => {
          throw new Error("capture failed");
        },
        compose: async () => "unreachable",
        finish,
        minimumCaptureIntervalMs: 0,
      }),
    ).rejects.toThrow("capture failed");

    expect(finish).toHaveBeenCalledWith("session-1");
  });

  it("paces viewport captures to stay inside the browser rate limit", async () => {
    const initial: ScreenshotPageState = {
      sessionId: "session-1",
      url: "https://example.com/long-page",
      viewportWidth: 800,
      viewportHeight: 600,
      documentHeight: 1_500,
      scrollY: 0,
    };
    let clock = 0;
    const waits: number[] = [];

    await captureFullPageScreenshot({
      begin: async () => initial,
      scrollTo: async (_sessionId, scrollY) => ({ ...initial, scrollY }),
      captureViewport: async () => "data:image/png;base64,AQID",
      compose: async () => "data:image/png;base64,BAUG",
      finish: async () => undefined,
      now: () => clock,
      wait: async (milliseconds) => {
        waits.push(milliseconds);
        clock += milliseconds;
      },
    });

    expect(waits).toEqual([550, 550]);
  });

  it("rejects a scroll jump that would leave a gap in the long screenshot", async () => {
    const initial: ScreenshotPageState = {
      sessionId: "session-1",
      url: "https://example.com/long-page",
      viewportWidth: 800,
      viewportHeight: 600,
      documentHeight: 1_500,
      scrollY: 0,
    };
    let scrollCount = 0;
    const finish = vi.fn(async () => undefined);

    await expect(
      captureFullPageScreenshot({
        begin: async () => initial,
        scrollTo: async (_sessionId, scrollY) => ({
          ...initial,
          scrollY: scrollCount++ === 0 ? scrollY : 700,
        }),
        captureViewport: async () => "data:image/png;base64,AQID",
        compose: async () => "unreachable",
        finish,
        minimumCaptureIntervalMs: 0,
      }),
    ).rejects.toThrow("skipped part of its content");

    expect(finish).toHaveBeenCalledWith("session-1");
  });

  it("stops before retained viewport PNGs can exhaust worker memory", async () => {
    const initial: ScreenshotPageState = {
      sessionId: "session-1",
      url: "https://example.com/long-page",
      viewportWidth: 800,
      viewportHeight: 600,
      documentHeight: 1_500,
      scrollY: 0,
    };
    const finish = vi.fn(async () => undefined);

    await expect(
      captureFullPageScreenshot({
        begin: async () => initial,
        scrollTo: async (_sessionId, scrollY) => ({ ...initial, scrollY }),
        captureViewport: async () => "data:image/png;base64,AQID",
        compose: async () => "unreachable",
        finish,
        minimumCaptureIntervalMs: 0,
        maximumCapturedTileBytes: 2,
      }),
    ).rejects.toThrow("too much memory");

    expect(finish).toHaveBeenCalledWith("session-1");
  });

  it("continues when the document grows during a later tile capture", async () => {
    const initial: ScreenshotPageState = {
      sessionId: "session-1",
      url: "https://example.com/lazy-page",
      viewportWidth: 800,
      viewportHeight: 600,
      documentHeight: 1_200,
      scrollY: 0,
    };
    let currentScrollY = 0;
    let captureCount = 0;
    const scrollTo = vi.fn(async (_sessionId: string, scrollY: number) => {
      currentScrollY = scrollY;
      return { ...initial, scrollY };
    });
    const compose = vi.fn(async () => "data:image/png;base64,BAUG");

    await captureFullPageScreenshot({
      begin: async () => initial,
      scrollTo,
      captureViewport: async () => {
        captureCount += 1;
        return "data:image/png;base64,AQID";
      },
      measure: async () => ({
        ...initial,
        url: `${initial.url}#visible-section`,
        documentHeight: captureCount >= 2 ? 1_800 : 1_200,
        scrollY: currentScrollY,
      }),
      compose,
      finish: async () => undefined,
      minimumCaptureIntervalMs: 0,
    });

    expect(scrollTo.mock.calls.map(([, scrollY]) => scrollY)).toEqual([0, 600, 1_200]);
    expect(compose).toHaveBeenCalledWith(expect.objectContaining({ documentHeight: 1_800 }));
  });

  it("rejects a tile when the page moves during the browser capture", async () => {
    const state: ScreenshotPageState = {
      sessionId: "session-1",
      url: "https://example.com/long-page",
      viewportWidth: 800,
      viewportHeight: 600,
      documentHeight: 1_500,
      scrollY: 0,
    };
    const finish = vi.fn(async () => undefined);

    await expect(
      captureFullPageScreenshot({
        begin: async () => state,
        scrollTo: async () => state,
        captureViewport: async () => "data:image/png;base64,AQID",
        measure: async () => ({ ...state, scrollY: 10 }),
        compose: async () => "unreachable",
        finish,
        minimumCaptureIntervalMs: 0,
      }),
    ).rejects.toThrow("page moved");

    expect(finish).toHaveBeenCalledWith("session-1");
  });

  it("keeps retina detail when the long canvas fits safely", () => {
    expect(
      screenshotOutputGeometry(
        { documentHeight: 1_500, viewportWidth: 800, viewportHeight: 600 },
        1_600,
        1_200,
      ),
    ).toEqual({ width: 1_600, height: 3_000, scale: 2 });
  });

  it("crops overlapping viewport tiles into one long PNG", async () => {
    const drawImage = vi.fn();
    const close = vi.fn();
    const bitmaps = Array.from({ length: 3 }, () => ({ width: 1_600, height: 1_200, close }));
    vi.stubGlobal(
      "createImageBitmap",
      vi.fn(async () => bitmaps.shift()),
    );

    let canvasSize: [number, number] | undefined;
    class FakeOffscreenCanvas {
      constructor(width: number, height: number) {
        canvasSize = [width, height];
      }

      getContext(): object {
        return { drawImage, imageSmoothingEnabled: false, imageSmoothingQuality: "low" };
      }

      async convertToBlob(): Promise<Blob> {
        return new Blob([Uint8Array.of(1, 2, 3).buffer], { type: "image/png" });
      }
    }
    vi.stubGlobal("OffscreenCanvas", FakeOffscreenCanvas);

    const tile = (scrollY: number) => ({
      sessionId: "session-1",
      url: "https://example.com/long-page",
      viewportWidth: 800,
      viewportHeight: 600,
      documentHeight: 1_500,
      scrollY,
      dataUrl: "data:image/png;base64,AQID",
    });
    const result = await composeFullPageScreenshot({
      documentHeight: 1_500,
      viewportWidth: 800,
      viewportHeight: 600,
      tiles: [tile(0), tile(600), tile(900)],
    });

    expect(canvasSize).toEqual([1_600, 3_000]);
    expect(drawImage).toHaveBeenNthCalledWith(
      1,
      expect.any(Object),
      0,
      0,
      1_600,
      1_200,
      0,
      0,
      1_600,
      1_200,
    );
    expect(drawImage).toHaveBeenNthCalledWith(
      2,
      expect.any(Object),
      0,
      0,
      1_600,
      1_200,
      0,
      1_200,
      1_600,
      1_200,
    );
    expect(drawImage).toHaveBeenNthCalledWith(
      3,
      expect.any(Object),
      0,
      600,
      1_600,
      600,
      0,
      2_400,
      1_600,
      600,
    );
    expect(close).toHaveBeenCalledTimes(3);
    expect(result).toBe("data:image/png;base64,AQID");
  });

  it("keeps fractional-DPR overlap crops inside the source bitmap", async () => {
    const drawImage = vi.fn();
    const close = vi.fn();
    const bitmaps = Array.from({ length: 2 }, () => ({ width: 1_200, height: 900, close }));
    vi.stubGlobal(
      "createImageBitmap",
      vi.fn(async () => bitmaps.shift()),
    );
    vi.stubGlobal(
      "OffscreenCanvas",
      class {
        getContext(): object {
          return { drawImage, imageSmoothingEnabled: false, imageSmoothingQuality: "low" };
        }

        async convertToBlob(): Promise<Blob> {
          return new Blob([Uint8Array.of(1, 2, 3).buffer], { type: "image/png" });
        }
      },
    );

    const tile = (scrollY: number) => ({
      sessionId: "session-1",
      url: "https://example.com/long-page",
      viewportWidth: 800,
      viewportHeight: 600,
      documentHeight: 899,
      scrollY,
      dataUrl: "data:image/png;base64,AQID",
    });
    await composeFullPageScreenshot({
      documentHeight: 899,
      viewportWidth: 800,
      viewportHeight: 600,
      tiles: [tile(0), tile(299)],
    });

    expect(drawImage).toHaveBeenNthCalledWith(
      2,
      expect.any(Object),
      0,
      452,
      1_200,
      448,
      0,
      900,
      1_200,
      448,
    );
  });

  it("fills a tolerated subpixel scroll gap without leaving a blank device row", async () => {
    const drawImage = vi.fn();
    const bitmaps = Array.from({ length: 2 }, () => ({
      width: 1_200,
      height: 900,
      close: vi.fn(),
    }));
    vi.stubGlobal(
      "createImageBitmap",
      vi.fn(async () => bitmaps.shift()),
    );
    vi.stubGlobal(
      "OffscreenCanvas",
      class {
        getContext(): object {
          return { drawImage, imageSmoothingEnabled: false, imageSmoothingQuality: "low" };
        }

        async convertToBlob(): Promise<Blob> {
          return new Blob([Uint8Array.of(1, 2, 3).buffer], { type: "image/png" });
        }
      },
    );

    const tile = (scrollY: number) => ({
      sessionId: "session-1",
      url: "https://example.com/long-page",
      viewportWidth: 800,
      viewportHeight: 600,
      documentHeight: 1_200,
      scrollY,
      dataUrl: "data:image/png;base64,AQID",
    });
    await composeFullPageScreenshot({
      documentHeight: 1_200,
      viewportWidth: 800,
      viewportHeight: 600,
      tiles: [tile(0), tile(600.4)],
    });

    expect(drawImage).toHaveBeenNthCalledWith(
      2,
      expect.any(Object),
      0,
      0,
      1_200,
      899,
      0,
      900,
      1_200,
      900,
    );
  });
});
