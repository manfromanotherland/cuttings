// SPDX-License-Identifier: MIT

import { isToolbarSaveKind, toolbarSaveMessage, type ToolbarSaveKind } from "./toolbar.js";

document.addEventListener("DOMContentLoaded", () => {
  const buttons = Array.from(
    document.querySelectorAll<HTMLButtonElement>("button[data-save-kind]"),
  );

  buttons[0]?.focus();

  for (const button of buttons) {
    button.addEventListener("click", async () => {
      const kind = button.dataset.saveKind;
      if (!isToolbarSaveKind(kind)) return;

      setDisabled(buttons, true);
      try {
        const [tab] = await chrome.tabs.query({ active: true, currentWindow: true });
        if (!tab?.id) throw new Error("The active tab could not be identified.");
        const response = (await chrome.runtime.sendMessage(
          toolbarSaveMessage(kind as ToolbarSaveKind, tab.id),
        )) as { accepted?: boolean } | undefined;
        if (!response?.accepted) throw new Error("The toolbar save was not accepted.");
        window.close();
      } catch {
        setDisabled(buttons, false);
        button.focus();
      }
    });
  }
});

function setDisabled(buttons: HTMLButtonElement[], disabled: boolean): void {
  for (const button of buttons) button.disabled = disabled;
}
