#!/bin/zsh
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
script_dir=${0:A:h}
exec /usr/bin/python3 "$script_dir/scroll-performance.py" "$@"
