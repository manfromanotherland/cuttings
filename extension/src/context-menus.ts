// SPDX-License-Identifier: MIT

export const CONTEXT_MENU_ID = "add-to-cuttings";

export const CONTEXT_MENU: chrome.contextMenus.CreateProperties = {
  id: CONTEXT_MENU_ID,
  title: "Add to Cuttings",
  contexts: ["page", "image", "video", "selection"],
};

export type ContextCaptureTarget =
  | { kind: "article" }
  | { kind: "image" | "video"; mediaUrl?: string }
  | { kind: "quote"; text: string };

/** Route one generic context-menu click to the selected thing. */
export function contextCaptureTarget(
  info: Pick<chrome.contextMenus.OnClickData, "mediaType" | "selectionText" | "srcUrl">,
): ContextCaptureTarget {
  if (info.mediaType === "image" || info.mediaType === "video") {
    return { kind: info.mediaType, mediaUrl: info.srcUrl };
  }

  const text = info.selectionText?.trim();
  if (text) return { kind: "quote", text };

  return { kind: "article" };
}
