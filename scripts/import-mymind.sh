#!/usr/bin/env bash
# SPDX-License-Identifier: MIT

set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repository_root="$(cd "${script_dir}/.." && pwd)"

# Non-interactive macOS shells may omit rustup's shims even when Rust is
# installed. Match the repository task runner before deciding cargo is absent.
if ! command -v cargo >/dev/null 2>&1; then
  for tool_dir in "$HOME/.cargo/bin" /opt/homebrew/opt/rustup/bin; do
    if [ -x "$tool_dir/cargo" ]; then
      export PATH="$tool_dir:$PATH"
      break
    fi
  done
fi

if ! command -v cargo >/dev/null 2>&1; then
  echo "mymind import requires Rust's cargo command" >&2
  exit 127
fi

exec cargo run \
  --quiet \
  --manifest-path "${repository_root}/core/Cargo.toml" \
  -p cuttings-import-mymind \
  -- "$@"
