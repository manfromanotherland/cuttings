// SPDX-License-Identifier: MIT

import { PROTOCOL_VERSION } from "./protocol.js";

export const HOST_ID = "app.readcontrol.host";

// Chrome and Firefox embed one of these phrases in lastError when the native
// host binary is absent, its manifest isn't registered, or the extension isn't
// listed as allowed. The wording differs per browser, so we match both.
export const HOST_MISSING_ERRORS = [
  // Chrome / Chromium
  "Specified native messaging host not found",
  "Access to the specified native messaging host is forbidden",
  "Native host has exited",
  // Firefox
  "No such native application",
  "This extension does not have permission to use native application",
];

export function isHostMissing(err: Error): boolean {
  return HOST_MISSING_ERRORS.some((phrase) => err.message.includes(phrase));
}

export type HostStatus = "connected" | "missing" | "error";

/** Send a lightweight ping to the native host and return its status. */
export function pingHost(): Promise<HostStatus> {
  return new Promise((resolve) => {
    // The host ignores unknown actions and returns an error response,
    // which still means it IS reachable. A Chrome-level error means it isn't.
    chrome.runtime.sendNativeMessage(
      HOST_ID,
      { protocol_version: PROTOCOL_VERSION, action: "ping" },
      () => {
        if (chrome.runtime.lastError) {
          const err = new Error(chrome.runtime.lastError.message ?? "");
          resolve(isHostMissing(err) ? "missing" : "error");
        } else {
          resolve("connected");
        }
      },
    );
  });
}
