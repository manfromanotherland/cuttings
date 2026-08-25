// SPDX-License-Identifier: MIT

import { beforeEach, describe, expect, it, vi } from "vitest";

import { bytesToBase64, capTotalBytes, fetchImage, fetchImages } from "./images.js";

function mockResponse(
  bytes: number[],
  contentType = "image/png",
  ok = true,
  contentLength?: number,
  responseUrl = "",
) {
  return {
    ok,
    url: responseUrl,
    headers: {
      get: (key: string) => {
        if (key.toLowerCase() === "content-type") return contentType;
        if (key.toLowerCase() === "content-length" && contentLength !== undefined) {
          return String(contentLength);
        }
        return null;
      },
    },
    arrayBuffer: async () => new Uint8Array(bytes).buffer,
  } as unknown as Response;
}

describe("bytesToBase64", () => {
  it("encodes bytes to standard base64", () => {
    expect(bytesToBase64(new Uint8Array([104, 105]))).toBe("aGk="); // "hi"
  });

  it("returns empty string for empty input", () => {
    expect(bytesToBase64(new Uint8Array([]))).toBe("");
  });
});

describe("fetchImage", () => {
  beforeEach(() => vi.restoreAllMocks());

  it("returns url, trimmed content type, and base64 bytes on success", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(mockResponse([104, 105], "image/png; charset=binary")),
    );
    expect(await fetchImage("https://e.com/a.png")).toEqual({
      url: "https://e.com/a.png",
      content_type: "image/png",
      data_base64: "aGk=",
    });
  });

  it("returns null on a non-ok response", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(mockResponse([1], "image/png", false)));
    expect(await fetchImage("https://e.com/a.png")).toBeNull();
  });

  it("returns null when the fetch throws (CORS block, abort, network)", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("Failed to fetch")));
    expect(await fetchImage("https://e.com/a.png")).toBeNull();
  });

  it("returns null for an empty body", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(mockResponse([], "image/png")));
    expect(await fetchImage("https://e.com/a.png")).toBeNull();
  });

  it("rejects oversized and non-image responses before encoding", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(mockResponse([1], "image/png", true, 41 * 1024 * 1024)),
    );
    expect(await fetchImage("https://e.com/huge.png")).toBeNull();

    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(mockResponse([1], "text/html")));
    expect(await fetchImage("https://e.com/not-an-image.png")).toBeNull();
  });

  it("allows page-local image responses but rejects unsafe HTTP redirects", async () => {
    const blobUrl = "blob:https://e.com/page-image";
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(mockResponse([1, 2], "image/png", true, 2, blobUrl)),
    );
    expect(await fetchImage(blobUrl)).toMatchObject({ url: blobUrl, data_base64: "AQI=" });

    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(mockResponse([1], "image/png", true, 1, "data:image/png,A")),
    );
    expect(await fetchImage("https://e.com/redirect.png")).toBeNull();
  });
});

describe("fetchImages", () => {
  beforeEach(() => vi.restoreAllMocks());

  it("dedupes URLs and splits readable from unresolved", async () => {
    vi.stubGlobal(
      "fetch",
      vi
        .fn()
        .mockImplementation((url: string) =>
          url.includes("bad")
            ? Promise.reject(new TypeError("cors"))
            : Promise.resolve(mockResponse([104, 105], "image/png")),
        ),
    );
    const { images, unresolved } = await fetchImages([
      "https://e.com/a.png",
      "https://e.com/a.png", // duplicate — fetched once
      "https://e.com/bad.png",
    ]);
    expect(images.map((i) => i.url)).toEqual(["https://e.com/a.png"]);
    expect(unresolved).toEqual(["https://e.com/bad.png"]);
  });

  it("preserves candidate order when concurrent fetches finish out of order", async () => {
    let resolveFirst!: (value: ReturnType<typeof mockResponse>) => void;
    vi.stubGlobal(
      "fetch",
      vi.fn().mockImplementation((url: string) => {
        if (url.endsWith("first.png")) {
          return new Promise((resolve) => {
            resolveFirst = resolve;
          });
        }
        return Promise.resolve(mockResponse([2]));
      }),
    );

    const pending = fetchImages(["https://e.com/first.png", "https://e.com/second.png"]);
    await Promise.resolve();
    resolveFirst(mockResponse([1]));

    expect((await pending).images.map((image) => image.url)).toEqual([
      "https://e.com/first.png",
      "https://e.com/second.png",
    ]);
  });
});

describe("capTotalBytes", () => {
  const img = (url: string, base64Len: number) => ({
    url,
    content_type: "image/png",
    data_base64: "A".repeat(base64Len),
  });

  it("keeps images in order until the byte budget would be exceeded", () => {
    // base64 length 8 → ~6 decoded bytes each; budget 12 fits two.
    const kept = capTotalBytes([img("a", 8), img("b", 8), img("c", 8)], 12);
    expect(kept.map((i) => i.url)).toEqual(["a", "b"]);
  });

  it("keeps everything when under budget", () => {
    expect(capTotalBytes([img("a", 4)], 1000)).toHaveLength(1);
  });
});
