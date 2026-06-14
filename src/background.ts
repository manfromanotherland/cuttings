// SPDX-License-Identifier: MIT

chrome.action.onClicked.addListener((tab) => {
  // TODO: EXT-1 — extract page content and send to native host
  console.log("read-later: save triggered for", tab.url);
});
