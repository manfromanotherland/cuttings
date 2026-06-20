// SPDX-License-Identifier: MIT

import { beforeEach, describe, expect, it } from "vitest";

import { showToast } from "./content.js";

const HOST_ID = "read-later-toast-host";

describe("showToast", () => {
  beforeEach(() => {
    document.body.innerHTML = "";
  });

  it("renders the title and detail inside an isolated shadow root", () => {
    showToast({
      action: "toast",
      status: "ok",
      title: "Saved to Read Later",
      detail: "My Article",
    });

    const host = document.getElementById(HOST_ID);
    expect(host).not.toBeNull();
    expect(host!.shadowRoot).not.toBeNull();
    expect(host!.shadowRoot!.textContent).toContain("Saved to Read Later");
    expect(host!.shadowRoot!.textContent).toContain("My Article");
  });

  it("escapes page-derived text instead of injecting markup", () => {
    showToast({ action: "toast", status: "ok", title: "<img src=x onerror=alert(1)>" });

    const root = document.getElementById(HOST_ID)!.shadowRoot!;
    expect(root.querySelector("img")).toBeNull();
    expect(root.querySelector(".title")!.textContent).toBe("<img src=x onerror=alert(1)>");
  });

  it("replaces an existing toast rather than stacking", () => {
    showToast({ action: "toast", status: "ok", title: "First" });
    showToast({ action: "toast", status: "error", title: "Second" });

    expect(document.querySelectorAll(`#${HOST_ID}`)).toHaveLength(1);
    expect(document.getElementById(HOST_ID)!.shadowRoot!.textContent).toContain("Second");
  });
});
