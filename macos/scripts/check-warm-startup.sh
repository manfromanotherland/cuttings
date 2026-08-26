#!/bin/zsh

# SPDX-License-Identifier: GPL-3.0-or-later

set -euo pipefail
zmodload zsh/datetime

script_dir=${0:A:h}
repo_root=${script_dir:h:h}
app_executable="$repo_root/macos/build/Build/Products/Debug/Cuttings.app/Contents/MacOS/Cuttings"

if [[ ! -x "$app_executable" ]]; then
    print -u2 "Build the normal Debug app before running this check."
    exit 2
fi

probe_root=$(mktemp -d "${TMPDIR:-/tmp}/cuttings-warm-check.XXXXXX")
library_path="$probe_root/library"
articles_path="$library_path/articles"
database_path="$probe_root/index.db"
defaults_suite="is.edmundo.cuttings.warm-check.$$.${RANDOM}"
app_pid=""

cleanup() {
    if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
        kill "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
    fi
    defaults delete "$defaults_suite" >/dev/null 2>&1 || true
    rm -rf -- "$probe_root"
}
trap cleanup EXIT INT TERM

fail() {
    print -u2 "FAIL: $1"
    if [[ -n "${2:-}" && -f "$2" ]]; then
        sed -n '1,160p' "$2" >&2
    fi
    exit 1
}

write_article() {
    local id=$1
    local title=$2
    local saved_at=$3
    local tag=$4
    local prefix=${id[1,2]}
    local reading_dir="$articles_path/$prefix/$id"
    mkdir -p "$reading_dir"
    printf '%s' "---
format_version: 1
id: \"$id\"
url: \"https://example.com/$id\"
canonical_url: \"https://example.com/$id\"
title: \"$title\"
saved_at: \"$saved_at\"
archived: false
favorite: false
tags: [\"$tag\"]
source_hash: \"sha256:$id\"
---

# $title

Deterministic warm-start fixture content for $title.
" >"$reading_dir/article.md"
}

mkdir -p "$articles_path"
for index in {0..511}; do
    prefix=$(printf '%02x' $(( index % 256 )))
    suffix=$(printf '%062x' $index)
    id="$prefix$suffix"
    write_article "$id" "Startup fixture $index" "2026-01-01T12:00:00.000Z" "tag-$(( index % 16 ))"
done

old_newest_id="ff$(printf '%062x' 511)"
new_newest_id="ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"

launch_app() {
    local label=$1
    local reconciliation_delay_ms=$2
    local events_dir="$probe_root/$label-events"
    local log_path="$probe_root/$label.log"
    mkdir -p "$events_dir"

    env \
        CUTTINGS_TEST_LIBRARY="$library_path" \
        CUTTINGS_TEST_DB="$database_path" \
        CUTTINGS_TEST_DEFAULTS="$defaults_suite" \
        CUTTINGS_TEST_LIBRARY_RECONCILIATION_DELAY_MS="$reconciliation_delay_ms" \
        CUTTINGS_TEST_STARTUP_EVENTS_DIR="$events_dir" \
        "$app_executable" --ui-testing >"$log_path" 2>&1 &
    app_pid=$!
}

stop_app() {
    if [[ -n "$app_pid" ]] && kill -0 "$app_pid" 2>/dev/null; then
        kill "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
    fi
    app_pid=""
}

# Prime a real cache through the normal cold rebuild path.
cold_started=$EPOCHREALTIME
launch_app cold 0
cold_events="$probe_root/cold-events"
for _ in {1..400}; do
    if [[ -f "$cold_events/reconcile-finished" \
        && -f "$cold_events/card-visible-$old_newest_id" ]]; then
        break
    fi
    if ! kill -0 "$app_pid" 2>/dev/null; then
        fail "Cuttings exited during the cold launch" "$probe_root/cold.log"
    fi
    sleep 0.05
done
[[ -f "$cold_events/reconcile-finished" ]] \
    || fail "cold launch did not finish reconciliation" "$probe_root/cold.log"
[[ -f "$cold_events/card-visible-$old_newest_id" ]] \
    || fail "cold launch did not show its newest card" "$probe_root/cold.log"
cold_elapsed=$(( EPOCHREALTIME - cold_started ))
stop_app

# Change files while the app is closed. Warm launch must first show the old
# cached board, then reconcile to the new file truth after the forced delay.
rm "$articles_path/${old_newest_id[1,2]}/$old_newest_id/article.md"
write_article "$new_newest_id" "New warm-start fixture" "2026-01-02T12:00:00.000Z" "tag-new"

warm_started=$EPOCHREALTIME
launch_app warm 3000
warm_events="$probe_root/warm-events"

for _ in {1..30}; do
    if [[ -f "$warm_events/toolbar" \
        && -f "$warm_events/cached-snapshot" \
        && -f "$warm_events/card-visible-$old_newest_id" ]]; then
        break
    fi
    if ! kill -0 "$app_pid" 2>/dev/null; then
        fail "Cuttings exited during the warm launch" "$probe_root/warm.log"
    fi
    sleep 0.05
done

[[ -f "$warm_events/toolbar" ]] \
    || fail "toolbar was not available within 1.5 seconds" "$probe_root/warm.log"
[[ -f "$warm_events/cached-snapshot" ]] \
    || fail "cached snapshot was not published within 1.5 seconds" "$probe_root/warm.log"
[[ -f "$warm_events/card-visible-$old_newest_id" ]] \
    || fail "cached newest card was not visible within 1.5 seconds" "$probe_root/warm.log"
[[ ! -f "$warm_events/reconcile-finished" ]] \
    || fail "warm launch waited for reconciliation before showing cached cards"

cached_count=$(sed -n '1p' "$warm_events/cached-snapshot")
cached_first=$(sed -n '2p' "$warm_events/cached-snapshot")
[[ "$cached_count" == "512" ]] || fail "cached snapshot count was $cached_count, expected 512"
[[ "$cached_first" == "$old_newest_id" ]] \
    || fail "cached snapshot did not retain the pre-reconciliation newest card"
cached_elapsed=$(( EPOCHREALTIME - warm_started ))

for _ in {1..300}; do
    if [[ -f "$warm_events/reconcile-finished" \
        && -f "$warm_events/reconciled-snapshot" \
        && -f "$warm_events/card-visible-$new_newest_id" ]]; then
        break
    fi
    if ! kill -0 "$app_pid" 2>/dev/null; then
        fail "Cuttings exited before reconciliation completed" "$probe_root/warm.log"
    fi
    sleep 0.05
done

[[ -f "$warm_events/reconcile-finished" ]] \
    || fail "warm reconciliation did not finish" "$probe_root/warm.log"
[[ -f "$warm_events/reconciled-snapshot" ]] \
    || fail "reconciled snapshot was not published" "$probe_root/warm.log"
[[ -f "$warm_events/card-visible-$new_newest_id" ]] \
    || fail "new newest card was not visible after reconciliation" "$probe_root/warm.log"

final_count=$(sed -n '1p' "$warm_events/reconciled-snapshot")
final_first=$(sed -n '2p' "$warm_events/reconciled-snapshot")
final_ids=$(sed -n '3p' "$warm_events/reconciled-snapshot")
[[ "$final_count" == "512" ]] || fail "reconciled snapshot count was $final_count, expected 512"
[[ "$final_first" == "$new_newest_id" ]] \
    || fail "reconciled snapshot did not put the new file first"
[[ ",$final_ids," != *",$old_newest_id,"* ]] \
    || fail "reconciled snapshot retained the file deleted while closed"
[[ ",$final_ids," == *",$new_newest_id,"* ]] \
    || fail "reconciled snapshot omitted the file added while closed"

reconciled_elapsed=$(( EPOCHREALTIME - warm_started ))
stop_app

# Replacing the DB while leaving its ready marker behind must invalidate the
# cache. A recreated empty index may show the toolbar, but never an empty cached
# board that falsely claims to be this library's last complete snapshot.
mv "$database_path" "$database_path.before-replacement"
for suffix in -wal -shm; do
    if [[ -e "$database_path$suffix" ]]; then
        mv "$database_path$suffix" "$database_path$suffix.before-replacement"
    fi
done
touch "$database_path"

replacement_started=$EPOCHREALTIME
launch_app replacement 3000
replacement_events="$probe_root/replacement-events"
for _ in {1..30}; do
    [[ -f "$replacement_events/toolbar" ]] && break
    if ! kill -0 "$app_pid" 2>/dev/null; then
        fail "Cuttings exited after the cache DB was replaced" "$probe_root/replacement.log"
    fi
    sleep 0.05
done
[[ -f "$replacement_events/toolbar" ]] \
    || fail "toolbar was not available after the cache DB was replaced"
[[ ! -f "$replacement_events/cached-snapshot" ]] \
    || fail "a replacement DB was incorrectly trusted as a complete cache"
[[ ! -f "$replacement_events/card-visible-$new_newest_id" ]] \
    || fail "replacement DB showed a card before file reconciliation"

for _ in {1..300}; do
    if [[ -f "$replacement_events/reconcile-finished" \
        && -f "$replacement_events/card-visible-$new_newest_id" ]]; then
        break
    fi
    if ! kill -0 "$app_pid" 2>/dev/null; then
        fail "Cuttings exited while rebuilding a replacement DB" "$probe_root/replacement.log"
    fi
    sleep 0.05
done
[[ -f "$replacement_events/reconcile-finished" ]] \
    || fail "replacement DB did not finish rebuilding" "$probe_root/replacement.log"
[[ -f "$replacement_events/card-visible-$new_newest_id" ]] \
    || fail "replacement DB did not show the rebuilt library" "$probe_root/replacement.log"
replacement_elapsed=$(( EPOCHREALTIME - replacement_started ))
stop_app

printf 'PASS: cold card %.3fs, cached warm card %.3fs, reconciled %.3fs, replacement %.3fs\n' \
    "$cold_elapsed" "$cached_elapsed" "$reconciled_elapsed" "$replacement_elapsed"
