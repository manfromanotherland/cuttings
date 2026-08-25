// SPDX-License-Identifier: MIT

import { readFileSync } from "node:fs";
import { resolve } from "node:path";

import { describe, expect, it } from "vitest";

describe("extension manifest", () => {
  it("uses only the MV3 service worker background declaration", () => {
    const manifest = JSON.parse(readFileSync(resolve(process.cwd(), "manifest.json"), "utf8")) as {
      manifest_version: number;
      background: Record<string, unknown>;
    };

    expect(manifest.manifest_version).toBe(3);
    expect(manifest.background).toEqual({ service_worker: "dist/background.js" });
  });
});
