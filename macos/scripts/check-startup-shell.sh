#!/bin/zsh

# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail

script_dir=${0:A:h}
repo_root=${script_dir:h:h}
app_executable="$repo_root/macos/build/Build/Products/Debug/Cuttings.app/Contents/MacOS/Cuttings"

if [[ ! -x "$app_executable" ]]; then
    print -u2 "Build the normal Debug app before running this check."
    exit 2
fi

probe_root=$(mktemp -d "${TMPDIR:-/tmp}/cuttings-startup.XXXXXX")
library_path="$probe_root/library"
event_path="$probe_root/startup-event"
database_path="$probe_root/index.db"
defaults_suite="is.edmundo.cuttings.startup-probe.$$.${RANDOM}"
app_pid=""

mkdir -p "$library_path/articles"

cleanup() {
    if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
        kill "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
    fi
    defaults delete "$defaults_suite" >/dev/null 2>&1 || true
    rm -rf -- "$probe_root"
}
trap cleanup EXIT INT TERM

env \
    CUTTINGS_TEST_LIBRARY="$library_path" \
    CUTTINGS_TEST_DB="$database_path" \
    CUTTINGS_TEST_DEFAULTS="$defaults_suite" \
    CUTTINGS_TEST_LIBRARY_HYDRATION_DELAY_MS=3000 \
    CUTTINGS_TEST_STARTUP_EVENT_PATH="$event_path" \
    "$app_executable" --ui-testing >"$probe_root/app.log" 2>&1 &
app_pid=$!

# The toolbar must be present well before the deliberately delayed library work
# can finish. This checks first-frame structure, not visual styling.
for _ in {1..30}; do
    if [[ -f "$event_path" ]] && [[ "$(<"$event_path")" == "toolbar" ]]; then
        print "PASS: toolbar appeared before library hydration"
        exit 0
    fi
    if ! kill -0 "$app_pid" 2>/dev/null; then
        print -u2 "FAIL: Cuttings exited before showing its toolbar"
        sed -n '1,120p' "$probe_root/app.log" >&2
        exit 1
    fi
    sleep 0.05
done

print -u2 "FAIL: toolbar did not appear within 1.5 seconds"
sed -n '1,120p' "$probe_root/app.log" >&2
exit 1
