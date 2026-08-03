#!/usr/bin/env bash
# Multi-repo task runner for the ReadControl polyrepo.
#
# Drive every sub-repo's git / format / lint / test / build from the umbrella
# directory, so you never have to cd between core/, extension/, macos/, and
# website/ to run the same command five times.
#
# Usage:
#   scripts/repos.sh <command> [repo ...]      # run for all repos, or just the named ones
#   scripts/repos.sh each <shell command ...>  # run an arbitrary command in every repo
#
# Commands:
#   status   git status -sb (branch + changes) for every repo
#   push     git push the current branch of every repo (sets upstream)
#   pull     git pull --ff-only every repo
#   fetch    git fetch --all --prune every repo
#   fmt      auto-format every repo
#   lint     lint every repo
#   test     run unit tests in every repo
#   build    build every repo
#   check    lint + test          (fast pre-push gate)
#   ci       lint + test + build  (full)
#   each     run any shell command in every repo
#   help     this message
#
# Commands whose toolchain is missing (e.g. xcodebuild off a Mac) are skipped
# with a note rather than failing, so the same runner works on your Mac and in
# the Linux sandbox. It continues past failures and reports which repos failed,
# exiting non-zero if any did.
#
# Tip: the root Makefile wraps this — `make push`, `make lint`, `make test`,
# `make REPO=core test`, etc.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

# Repos in run order. "." is this umbrella/meta repo (docs only): it takes part
# in git commands but has nothing to lint/test/build. The rest are siblings.
ALL_REPOS=". core extension macos website"

FAIL=0

# ---- pretty output ---------------------------------------------------------
if [ -t 1 ]; then
  B=$'\033[1m'; DIM=$'\033[2m'; RED=$'\033[31m'; GRN=$'\033[32m'
  YLW=$'\033[33m'; CYN=$'\033[36m'; RST=$'\033[0m'
else
  B=; DIM=; RED=; GRN=; YLW=; CYN=; RST=
fi

label()  { case "$1" in .) echo "root";; *) echo "$1";; esac; }
have()   { command -v "$1" >/dev/null 2>&1; }
is_git() { git -C "$1" rev-parse --git-dir >/dev/null 2>&1; }
head_branch() { git -C "$1" symbolic-ref --short -q HEAD 2>/dev/null || echo "(detached)"; }

# ---- per-repo command mapping ----------------------------------------------
# phase_cmd <repo> <phase> -> the shell command to run, or empty if the repo
# does not participate in that phase.
phase_cmd() {
  case "$1:$2" in
    core:fmt)        echo 'cargo fmt --all' ;;
    core:lint)       echo 'cargo fmt --all --check && cargo clippy --all-targets --all-features -- -D warnings' ;;
    core:test)       echo 'cargo test' ;;
    core:build)      echo 'cargo build' ;;

    extension:fmt)   echo 'npm run lint:fix' ;;
    extension:lint)  echo 'npm run lint' ;;
    extension:test)  echo 'npm test' ;;
    extension:build) echo 'npm run build' ;;

    website:lint)    echo 'npm run lint' ;;
    website:build)   echo 'npm run build' ;;
    # website: no unit tests or format script

    macos:fmt)       echo 'make format' ;;
    macos:lint)      echo 'make format-check && make lint' ;;
    macos:test)      echo 'make test' ;;
    macos:build)     echo 'make all && xcodebuild build -project ReadControl.xcodeproj -scheme ReadControl -configuration Debug CODE_SIGNING_ALLOWED=NO' ;;

    *)               echo '' ;;
  esac
}

# phase_tool <repo> <phase> -> a binary that must be on PATH for the command to
# run; if it is missing the phase is skipped (not failed) for that repo.
phase_tool() {
  case "$1" in
    core)              echo cargo ;;
    extension|website) echo npm ;;
    macos) case "$2" in fmt) echo swiftformat ;; lint) echo swiftlint ;; *) echo xcodebuild ;; esac ;;
    *)                 echo '' ;;
  esac
}

# ---- runners ---------------------------------------------------------------
run_phase() {
  local phase="$1"; shift
  local repos="$*"; [ -z "$repos" ] && repos="$ALL_REPOS"
  local failed=""
  for repo in $repos; do
    local cmd; cmd="$(phase_cmd "$repo" "$phase")"
    [ -z "$cmd" ] && continue                      # repo not part of this phase
    printf '%s\n' "${B}${CYN}==> $(label "$repo") · ${phase}${RST}"
    if ! is_git "$repo"; then
      printf '%s\n\n' "${YLW}  skipped — $repo is not a git repo here${RST}"; continue
    fi
    local tool; tool="$(phase_tool "$repo" "$phase")"
    if [ -n "$tool" ] && ! have "$tool"; then
      printf '%s\n\n' "${YLW}  skipped — '$tool' not found in PATH${RST}"; continue
    fi
    printf '%s\n' "${DIM}  \$ ${cmd}${RST}"
    if ( cd "$repo" && eval "$cmd" ); then
      printf '%s\n\n' "${GRN}  ✓ $(label "$repo") ${phase} ok${RST}"
    else
      failed="$failed $(label "$repo")"
      printf '%s\n\n' "${RED}  ✗ $(label "$repo") ${phase} FAILED${RST}"
    fi
  done
  phase_summary "$phase" "$failed"
}

run_git() {
  local phase="$1"; shift
  local repos="$*"; [ -z "$repos" ] && repos="$ALL_REPOS"
  local failed=""
  for repo in $repos; do
    if ! is_git "$repo"; then continue; fi
    printf '%s\n' "${B}${CYN}==> $(label "$repo") · ${phase} ${DIM}($(head_branch "$repo"))${RST}"
    local rc=0
    case "$phase" in
      status) git -C "$repo" status -sb ;;
      push)   git -C "$repo" push -u origin HEAD || rc=$? ;;
      pull)   git -C "$repo" pull --ff-only || rc=$? ;;
      fetch)  git -C "$repo" fetch --all --prune || rc=$? ;;
    esac
    [ "$rc" -ne 0 ] && { failed="$failed $(label "$repo")"; printf '%s\n' "${RED}  ✗ failed${RST}"; }
    printf '\n'
  done
  phase_summary "$phase" "$failed"
}

run_each() {
  local cmd="$*"
  [ -z "$cmd" ] && { echo "usage: $0 each <shell command>"; exit 2; }
  local failed=""
  for repo in $ALL_REPOS; do
    is_git "$repo" || continue
    printf '%s\n' "${B}${CYN}==> $(label "$repo")${RST}"
    printf '%s\n' "${DIM}  \$ ${cmd}${RST}"
    ( cd "$repo" && eval "$cmd" ) || failed="$failed $(label "$repo")"
    printf '\n'
  done
  phase_summary "each" "$failed"
}

phase_summary() {
  local phase="$1" failed="$2"
  if [ -n "$failed" ]; then
    printf '%s\n' "${B}${RED}✗ ${phase}: failed in:${failed}${RST}"
    FAIL=1
  else
    printf '%s\n' "${B}${GRN}✓ ${phase}: all good${RST}"
  fi
}

usage() {
  cat <<EOF
${B}ReadControl multi-repo runner${RST}  —  scripts/repos.sh <command> [repo ...]

  ${B}git${RST}      status  push  pull  fetch        (all repos, current branch)
  ${B}quality${RST}  fmt  lint  test  build            (per-repo toolchain, below)
  ${B}combos${RST}   check (lint+test)   ci (lint+test+build)
  ${B}escape${RST}   each <shell command...>           run anything in every repo

Repos: root(.)  core  extension  macos  website
Pass repo names after a command to narrow it: ${DIM}scripts/repos.sh lint core extension${RST}

Per-repo mapping:
  core       cargo fmt/clippy · cargo test · cargo build
  extension  npm run lint · npm test · npm run build
  macos      make format-check+lint · make test · xcodebuild        (needs a Mac)
  website    npm run lint · npm run build                           (no unit tests)
  root       git only (docs repo)

Missing toolchains are skipped, not failed — so this works on your Mac and in
the Linux sandbox (where macos build/test are unavailable).
EOF
}

# ---- dispatch --------------------------------------------------------------
cmd="${1:-help}"; shift || true
case "$cmd" in
  status|push|pull|fetch) run_git "$cmd" "$@" ;;
  fmt|format)             run_phase fmt "$@" ;;
  lint)                   run_phase lint "$@" ;;
  test)                   run_phase test "$@" ;;
  build)                  run_phase build "$@" ;;
  check)                  run_phase lint "$@"; run_phase test "$@" ;;
  ci)                     run_phase lint "$@"; run_phase test "$@"; run_phase build "$@" ;;
  each)                   run_each "$@" ;;
  help|-h|--help)         usage ;;
  *)                      echo "unknown command: $cmd"; echo; usage; exit 2 ;;
esac

exit $FAIL
