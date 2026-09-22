#!/usr/bin/env bash
# SPDX-License-Identifier: MIT
# One-time, per-device setup; never installs into the synced library.
set -euo pipefail
runtime="$HOME/Library/Application Support/Oia/Instagram"
python="${OIA_PYTHON:-$(command -v python3)}"
"$python" -m venv "$runtime"
"$runtime/bin/python3" -m pip install --disable-pip-version-check 'instaloader==4.15.3'
echo "Instagram downloader installed. Use Check Inbox in Óia to retry waiting shares."
