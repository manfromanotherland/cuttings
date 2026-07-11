# E2E Testing Stack

**Status:** decided (E2E-1) — the end-to-end suite stays **dependency-free**.

This document records the tools the XCUITest end-to-end suite is built on, so the decision is
made once and not re-litigated per ticket. The **journeys** the suite walks through live in the
root repo's [`E2E-SCENARIOS.md`](../../E2E-SCENARIOS.md); the **engineering backlog** to make them
runnable lives in [`E2E-TEST-TICKETS.md`](../../E2E-TEST-TICKETS.md). This doc is ticket **E2E-1**.

## Principle

The suite uses **only what ships with Xcode and the macOS SDK** — no third-party test libraries.
This matches the app's minimal footprint: the app itself pulls in a single SPM package
(`swift-markdown`), and the test suite adds **zero** more. Every extra SPM dependency churns the
generated Xcode project (`project.yml` → `xcodegen`), so keeping the suite dependency-free keeps
the project reproducible and the diffs clean.

The suite drives the **real** app against the **real** Rust core and **real** files on disk. There
is **no mocking of the core** — mocking it would test a fiction, and isn't feasible against a
black-box app process anyway. The only test-only code is a handful of environment **seams**
(E2E-3) that redirect the library/DB paths and switch off host-machine side effects. Those are
redirections, not mocks.

## What the suite is built on

| Concern | Tool | How it ships | Notes |
| --- | --- | --- | --- |
| UI driving & assertions | **XCUITest** (the `XCTest` framework's UI-testing API) | Bundled with Xcode | Nothing to install; **no** SPM package added to `project.yml`. |
| SHA-256 hashing | **CryptoKit** (`import CryptoKit`) | macOS SDK | Needed to compute `source_hash` and asset filenames when faking readings. No install. |
| Temp-library I/O & reading back defaults | **Foundation** (`FileManager`, `Process`) | macOS SDK | Used for the per-test temp library and reading/writing `defaults`. No install. |

## Explicitly NOT added

- **Quick / Nimble** — an alternate assertion/BDD framework. `XCTest` assertions are sufficient.
- **swift-snapshot-testing** — image/text snapshotting. E2E tests **behavior and flows, not
  pixels**; native-rendering snapshots are brittle across OS versions.
- **Any other assertion or snapshot framework.**

Rationale: extra SPM dependencies churn the generated Xcode project, and none of them buy anything
the bundled tooling doesn't already provide for behavior-level e2e.

## Optional local / CI ergonomics (not test dependencies)

These are conveniences for a human running the suite on a Mac — they are **not** linked into any
target and are safe to skip. Install as desired:

- `brew install xcbeautify` — readable `xcodebuild` logs.
- Screenshots / attachments are pulled from the `.xcresult` bundle (Xcode built-in). Optionally
  `brew install chargepoint/xcparse/xcparse` to extract them from the CLI.

## Consequence

Because nothing here touches `project.yml`'s `packages:` block, `make xcodegen` continues to
produce a project with exactly one SPM dependency (`swift-markdown`). The test target itself is
added in **E2E-2**; this ticket only fixes *what it may depend on* — which is: nothing beyond
Xcode and the macOS SDK.
