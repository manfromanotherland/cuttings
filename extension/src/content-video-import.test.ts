// SPDX-License-Identifier: MIT

import { describe, expect, it, vi } from "vitest";

import { captureStandaloneMediaRequest } from "./content.js";
import { VideoImportError } from "./video-import.js";

describe("content media capture", () => {
  it("streams a direct Cosmos MP4 into the local video import instead of saving only its poster", async () => {
    const pageUrl = "https://www.cosmos.so/e/1929290737";
    const videoUrl = "https://cdn.cosmos.so/22861d6e-e15e-4eb6-8fbc-8cf8d07e9f2f.mp4";
    const doc = document.implementation.createHTMLDocument();
    doc.head.innerHTML = "<title>For You / Cosmos</title>";
    doc.body.innerHTML = `<video data-testid="element-view-video" src="${videoUrl}"></video>`;
    const importVideo = vi.fn(async () => ({
      metadata: {
        kind: "video" as const,
        url: pageUrl,
        canonical_url: "https://www.cosmos.so/",
        title: "For You / Cosmos",
        saved_at: "2026-08-25T17:57:52.847Z",
      },
      response: {
        protocol_version: 4 as const,
        ok: true as const,
        id: "local-cosmos-video-id",
        path: "articles/lo/local-cosmos-video-id/article.md",
      },
    }));

    const result = await captureStandaloneMediaRequest(
      doc,
      { action: "capture-media", kind: "video", mediaUrl: videoUrl, pageUrl },
      importVideo,
    );

    expect(importVideo).toHaveBeenCalledWith({ doc, pageUrl, mediaUrl: videoUrl });
    expect(result).toMatchObject({
      video_import: true,
      metadata: { kind: "video", url: pageUrl },
      response: { ok: true, id: "local-cosmos-video-id" },
    });
    expect(result).not.toHaveProperty("markdown");
  });

  it("routes the exact Cosmos blob through video import instead of returning an ordinary save", async () => {
    const pageUrl = "https://www.cosmos.so/e/2035271300";
    const blobUrl = "blob:https://www.cosmos.so/3f7de4c2-d242-4cac-96dd-c04459f564b2";
    const doc = document.implementation.createHTMLDocument();
    doc.head.innerHTML = "<title>Cosmos</title>";
    doc.body.innerHTML = `<video data-testid="element-view-video" src="${blobUrl}"></video>`;
    const importVideo = vi.fn(async () => ({
      metadata: {
        kind: "video" as const,
        url: pageUrl,
        canonical_url: pageUrl,
        title: "Cosmos",
        saved_at: "2026-08-25T15:00:00.000Z",
      },
      response: {
        protocol_version: 4 as const,
        ok: true as const,
        id: "saved-video-id",
        path: "articles/sa/saved-video-id/article.md",
      },
    }));

    const result = await captureStandaloneMediaRequest(
      doc,
      { action: "capture-media", kind: "video", mediaUrl: blobUrl, pageUrl },
      importVideo,
    );

    expect(importVideo).toHaveBeenCalledWith({ doc, pageUrl, mediaUrl: blobUrl });
    expect(result).toMatchObject({
      video_import: true,
      metadata: { kind: "video", url: pageUrl, title: "Cosmos" },
      response: { ok: true, id: "saved-video-id" },
    });
    expect(result).not.toHaveProperty("markdown");
    expect(JSON.stringify(result)).not.toContain("cuttings-video:");
    expect(JSON.stringify(result)).not.toContain(blobUrl);
  });

  it("preserves a missing-native-host signal for the existing install guidance", async () => {
    const blobUrl = "blob:https://www.cosmos.so/missing-host";
    const doc = document.implementation.createHTMLDocument();
    doc.body.innerHTML = `<video data-testid="element-view-video" src="${blobUrl}"></video>`;

    const result = await captureStandaloneMediaRequest(
      doc,
      {
        action: "capture-media",
        kind: "video",
        mediaUrl: blobUrl,
        pageUrl: "https://www.cosmos.so/e/2035271300",
      },
      async () => {
        throw new VideoImportError(
          "native_connection",
          "Specified native messaging host not found.",
        );
      },
    );

    expect(result).toEqual({
      error: "Specified native messaging host not found.",
      error_code: "native_connection",
    });
  });
});
