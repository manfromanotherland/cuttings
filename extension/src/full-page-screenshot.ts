// SPDX-License-Identifier: MIT

import { bytesToBase64 } from "./images.js";

export const MINIMUM_SCREENSHOT_CAPTURE_INTERVAL_MS = 550;
const MAX_CAPTURE_DURATION_MS = 60_000;
const MAX_SCREENSHOT_TILES = 60;
const MAX_CANVAS_DIMENSION = 32_767;
const MAX_CANVAS_PIXELS = 32_000_000;
const MAX_SCREENSHOT_PNG_BYTES = 40 * 1024 * 1024;
const MAX_CAPTURED_TILE_BYTES = 32 * 1024 * 1024;
const DIMENSION_TOLERANCE = 0.5;

export interface ScreenshotPageState {
  sessionId: string;
  url: string;
  viewportWidth: number;
  viewportHeight: number;
  documentHeight: number;
  scrollY: number;
}

export interface ScreenshotTile extends ScreenshotPageState {
  dataUrl: string;
}

export interface ScreenshotComposition {
  documentHeight: number;
  viewportWidth: number;
  viewportHeight: number;
  tiles: ScreenshotTile[];
}

export interface FullPageScreenshotDependencies {
  begin(): Promise<ScreenshotPageState>;
  scrollTo(sessionId: string, scrollY: number, hideFixed: boolean): Promise<ScreenshotPageState>;
  captureViewport(): Promise<string>;
  measure?(sessionId: string): Promise<ScreenshotPageState>;
  compose(input: ScreenshotComposition): Promise<string>;
  finish(sessionId: string): Promise<void>;
  minimumCaptureIntervalMs?: number;
  maximumCapturedTileBytes?: number;
  now?: () => number;
  wait?: (milliseconds: number) => Promise<void>;
}

/**
 * Coordinate a top-to-bottom capture of one browser document. The page-facing
 * driver owns scrolling and restoration; this function owns the capture order,
 * browser rate limit, growth bound, and guaranteed cleanup.
 */
export async function captureFullPageScreenshot(
  dependencies: FullPageScreenshotDependencies,
): Promise<string> {
  const now = dependencies.now ?? Date.now;
  const wait = dependencies.wait ?? delay;
  const minimumCaptureIntervalMs =
    dependencies.minimumCaptureIntervalMs ?? MINIMUM_SCREENSHOT_CAPTURE_INTERVAL_MS;
  const maximumCapturedTileBytes = dependencies.maximumCapturedTileBytes ?? MAX_CAPTURED_TILE_BYTES;
  const startedAt = now();
  let session: ScreenshotPageState | undefined;
  let composition: ScreenshotComposition | undefined;
  let failed = false;
  let captureError: unknown;

  try {
    session = await dependencies.begin();
    assertPageState(session);

    const initialUrl = session.url;
    const initialViewportWidth = session.viewportWidth;
    const initialViewportHeight = session.viewportHeight;
    const tiles: ScreenshotTile[] = [];
    const capturedOffsets = new Set<number>();
    let requestedScrollY = 0;
    let documentHeight = session.documentHeight;
    let lastCaptureStartedAt: number | undefined;
    let capturedTileBytes = 0;

    while (tiles.length < MAX_SCREENSHOT_TILES) {
      if (now() - startedAt > MAX_CAPTURE_DURATION_MS) {
        throw new Error("The full-page screenshot took too long to capture.");
      }

      const state = await dependencies.scrollTo(
        session.sessionId,
        requestedScrollY,
        tiles.length > 0,
      );
      assertSameDocument(
        state,
        session.sessionId,
        initialUrl,
        initialViewportWidth,
        initialViewportHeight,
      );
      documentHeight = state.documentHeight;

      const previousTile = tiles.at(-1);
      if (
        (!previousTile && state.scrollY > DIMENSION_TOLERANCE) ||
        (previousTile &&
          state.scrollY > previousTile.scrollY + previousTile.viewportHeight + DIMENSION_TOLERANCE)
      ) {
        throw new Error("The page skipped part of its content while scrolling for the screenshot.");
      }

      const offsetKey = Math.round(state.scrollY * 1_000);
      if (capturedOffsets.has(offsetKey)) {
        throw new Error("The page would not scroll far enough to finish the screenshot.");
      }
      capturedOffsets.add(offsetKey);

      // Pace after scrolling so lazy content gets the browser's rate-limit
      // window to render before the visible viewport is captured.
      if (lastCaptureStartedAt !== undefined && minimumCaptureIntervalMs > 0) {
        const remaining = minimumCaptureIntervalMs - (now() - lastCaptureStartedAt);
        if (remaining > 0) await wait(remaining);
      }

      lastCaptureStartedAt = now();

      const dataUrl = await dependencies.captureViewport();
      assertPngDataUrl(dataUrl);
      capturedTileBytes += decodedPngDataUrlSize(dataUrl);
      if (capturedTileBytes > maximumCapturedTileBytes) {
        throw new Error("The page screenshot needs too much memory to assemble safely.");
      }

      const measuredState = dependencies.measure
        ? await dependencies.measure(session.sessionId)
        : state;
      assertSameDocument(
        measuredState,
        session.sessionId,
        initialUrl,
        initialViewportWidth,
        initialViewportHeight,
      );
      if (Math.abs(measuredState.scrollY - state.scrollY) > DIMENSION_TOLERANCE) {
        throw new Error("The page moved while a screenshot tile was being captured.");
      }
      documentHeight = measuredState.documentHeight;
      tiles.push({ ...state, documentHeight, dataUrl });

      const coveredBottom = state.scrollY + state.viewportHeight;
      if (coveredBottom >= documentHeight - DIMENSION_TOLERANCE) break;

      const maximumScrollY = Math.max(0, documentHeight - state.viewportHeight);
      requestedScrollY = Math.min(coveredBottom, maximumScrollY);
      if (requestedScrollY <= state.scrollY + DIMENSION_TOLERANCE) {
        throw new Error("The page would not scroll far enough to finish the screenshot.");
      }
    }

    const lastTile = tiles.at(-1);
    if (
      !lastTile ||
      lastTile.scrollY + lastTile.viewportHeight < documentHeight - DIMENSION_TOLERANCE
    ) {
      throw new Error("The page is too long to capture as one screenshot.");
    }

    composition = {
      documentHeight,
      viewportWidth: initialViewportWidth,
      viewportHeight: initialViewportHeight,
      tiles,
    };
  } catch (error) {
    failed = true;
    captureError = error;
  }

  if (session) {
    try {
      await dependencies.finish(session.sessionId);
    } catch (finishError) {
      if (!failed) {
        failed = true;
        captureError = finishError;
      }
    }
  }

  if (failed) throw captureError;
  if (composition === undefined) throw new Error("The browser produced no full-page screenshot.");
  return dependencies.compose(composition);
}

export interface ScreenshotOutputGeometry {
  width: number;
  height: number;
  scale: number;
}

/** Pick the highest useful output scale that stays within conservative canvas bounds. */
export function screenshotOutputGeometry(
  composition: Pick<ScreenshotComposition, "documentHeight" | "viewportWidth" | "viewportHeight">,
  bitmapWidth: number,
  bitmapHeight: number,
): ScreenshotOutputGeometry {
  const { documentHeight, viewportWidth, viewportHeight } = composition;
  assertPositiveFinite(viewportWidth, "viewport width");
  assertPositiveFinite(viewportHeight, "viewport height");
  assertPositiveFinite(documentHeight, "document height");
  assertPositiveFinite(bitmapWidth, "captured width");
  assertPositiveFinite(bitmapHeight, "captured height");

  const scaleX = bitmapWidth / viewportWidth;
  const scaleY = bitmapHeight / viewportHeight;
  if (Math.abs(scaleX - scaleY) / Math.max(scaleX, scaleY) > 0.02) {
    throw new Error("The browser changed screenshot scale during capture.");
  }

  const sourceScale = Math.min(scaleX, scaleY);
  const dimensionScale = Math.min(
    MAX_CANVAS_DIMENSION / viewportWidth,
    MAX_CANVAS_DIMENSION / documentHeight,
  );
  const pixelScale = Math.sqrt(MAX_CANVAS_PIXELS / (viewportWidth * documentHeight));
  const scale = Math.min(sourceScale, dimensionScale, pixelScale);
  const width = Math.max(1, Math.floor(viewportWidth * scale));
  const height = Math.max(1, Math.floor(documentHeight * scale));

  return { width, height, scale };
}

/** Stitch captured viewport PNGs into one long PNG in the extension worker. */
export async function composeFullPageScreenshot(
  composition: ScreenshotComposition,
): Promise<string> {
  if (!composition.tiles.length) throw new Error("The browser returned no screenshot tiles.");

  const tiles = [...composition.tiles].sort((left, right) => left.scrollY - right.scrollY);
  const firstBitmap = await decodePng(tiles[0].dataUrl);
  try {
    const geometry = screenshotOutputGeometry(composition, firstBitmap.width, firstBitmap.height);
    if (typeof OffscreenCanvas === "undefined") {
      throw new Error("This browser cannot assemble a full-page screenshot.");
    }

    const canvas = new OffscreenCanvas(geometry.width, geometry.height);
    const context = canvas.getContext("2d", { alpha: false });
    if (!context) throw new Error("The browser could not create the screenshot canvas.");
    context.imageSmoothingEnabled = true;
    context.imageSmoothingQuality = "high";

    let coveredUntil = 0;
    for (let index = 0; index < tiles.length; index += 1) {
      const tile = tiles[index];
      const bitmap = index === 0 ? firstBitmap : await decodePng(tile.dataUrl);
      try {
        assertTileBitmap(bitmap, firstBitmap, tile, composition);
        if (tile.scrollY > coveredUntil + DIMENSION_TOLERANCE) {
          throw new Error("The page skipped part of its content while assembling the screenshot.");
        }
        // Anchor tiny subpixel scroll gaps to the prior tile's end. Scaling a
        // fraction of a CSS pixel is preferable to leaving a blank device row.
        const segmentStart = coveredUntil;
        const segmentEnd = Math.min(composition.documentHeight, tile.scrollY + tile.viewportHeight);
        const segmentHeight = segmentEnd - segmentStart;
        if (segmentHeight <= DIMENSION_TOLERANCE) continue;

        const sourceScaleY = bitmap.height / tile.viewportHeight;
        const sourceY = Math.max(
          0,
          Math.min(bitmap.height, Math.round((segmentStart - tile.scrollY) * sourceScaleY)),
        );
        const sourceEnd = Math.max(
          sourceY,
          Math.min(bitmap.height, Math.round((segmentEnd - tile.scrollY) * sourceScaleY)),
        );
        const sourceHeight = sourceEnd - sourceY;
        const destinationY = Math.round(segmentStart * geometry.scale);
        const destinationEnd =
          index === tiles.length - 1 ? geometry.height : Math.round(segmentEnd * geometry.scale);
        const destinationHeight = destinationEnd - destinationY;
        if (destinationHeight <= 0 || sourceHeight <= 0) continue;

        context.drawImage(
          bitmap,
          0,
          sourceY,
          bitmap.width,
          sourceHeight,
          0,
          destinationY,
          geometry.width,
          destinationHeight,
        );
        coveredUntil = segmentEnd;
      } finally {
        if (bitmap !== firstBitmap) bitmap.close();
      }
    }

    if (coveredUntil < composition.documentHeight - DIMENSION_TOLERANCE) {
      throw new Error("The page screenshot could not be assembled without a gap.");
    }

    const blob = await canvas.convertToBlob({ type: "image/png" });
    if (!blob.size) throw new Error("The browser produced an empty full-page screenshot.");
    if (blob.size > MAX_SCREENSHOT_PNG_BYTES) {
      throw new Error("The full-page screenshot is too large to save locally.");
    }
    const bytes = new Uint8Array(await blob.arrayBuffer());
    return `data:image/png;base64,${bytesToBase64(bytes)}`;
  } finally {
    firstBitmap.close();
  }
}

function assertPageState(state: ScreenshotPageState): void {
  if (!state.sessionId || !state.url) throw new Error("The page screenshot session was invalid.");
  assertPositiveFinite(state.viewportWidth, "viewport width");
  assertPositiveFinite(state.viewportHeight, "viewport height");
  assertPositiveFinite(state.documentHeight, "document height");
  if (!Number.isFinite(state.scrollY) || state.scrollY < 0) {
    throw new Error("The page returned an invalid scroll position.");
  }
}

function assertSameDocument(
  state: ScreenshotPageState,
  sessionId: string,
  url: string,
  viewportWidth: number,
  viewportHeight: number,
): void {
  assertPageState(state);
  if (state.sessionId !== sessionId || urlWithoutFragment(state.url) !== urlWithoutFragment(url)) {
    throw new Error("The active page changed while the screenshot was being captured.");
  }
  if (
    Math.abs(state.viewportWidth - viewportWidth) > DIMENSION_TOLERANCE ||
    Math.abs(state.viewportHeight - viewportHeight) > DIMENSION_TOLERANCE
  ) {
    throw new Error("The browser viewport changed while the screenshot was being captured.");
  }
}

function urlWithoutFragment(value: string): string {
  return value.split("#", 1)[0];
}

function assertPositiveFinite(value: number, name: string): void {
  if (!Number.isFinite(value) || value <= 0) {
    throw new Error(`The page returned an invalid ${name}.`);
  }
}

function assertPngDataUrl(value: string): void {
  if (!/^data:image\/png;base64,[a-z\d+/=]+$/i.test(value.trim())) {
    throw new Error("The browser did not return a PNG screenshot.");
  }
}

function decodedPngDataUrlSize(value: string): number {
  const base64 = value.slice(value.indexOf(",") + 1);
  const padding = base64.endsWith("==") ? 2 : base64.endsWith("=") ? 1 : 0;
  return Math.floor((base64.length * 3) / 4) - padding;
}

function assertTileBitmap(
  bitmap: ImageBitmap,
  firstBitmap: ImageBitmap,
  tile: ScreenshotTile,
  composition: ScreenshotComposition,
): void {
  if (bitmap.width !== firstBitmap.width || bitmap.height !== firstBitmap.height) {
    throw new Error("The browser viewport changed while the screenshot was being captured.");
  }
  if (
    Math.abs(tile.viewportWidth - composition.viewportWidth) > DIMENSION_TOLERANCE ||
    Math.abs(tile.viewportHeight - composition.viewportHeight) > DIMENSION_TOLERANCE
  ) {
    throw new Error("The browser viewport changed while the screenshot was being captured.");
  }
}

async function decodePng(dataUrl: string): Promise<ImageBitmap> {
  assertPngDataUrl(dataUrl);
  if (typeof createImageBitmap !== "function") {
    throw new Error("This browser cannot decode full-page screenshot tiles.");
  }
  const base64 = dataUrl.slice(dataUrl.indexOf(",") + 1);
  const binary = atob(base64);
  const bytes = Uint8Array.from(binary, (character) => character.charCodeAt(0));
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return createImageBitmap(new Blob([copy.buffer], { type: "image/png" }));
}

function delay(milliseconds: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, milliseconds));
}
