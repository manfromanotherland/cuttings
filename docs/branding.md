# Óia naming

The product name is **Óia**, pronounced approximately **OY-uh**. The browser
extension and iOS Shortcut are named **Save to Óia**. Use **save** for the action
and **Saved to Óia** for its confirmation.

Source identifiers, packages, the repository directory, and Xcode targets use
ASCII **Oia** or **oia**. The macOS bundle is **Óia.app**, with an ASCII `Oia`
executable and module. The shared Xcode scheme is `Oia`.

## Compatibility identifiers

The product rename keeps these established identifiers so existing installations,
preferences, browser permissions, and saved files continue to work:

- macOS bundle and preferences domain: `is.edmundo.cuttings`.
- Native-messaging host: `is.edmundo.cuttings.host`; Firefox extension identity:
  `cuttings@edmundo.is`. The Chromium development key also stays unchanged.
- Per-device library pointer: `~/.config/cuttings/library`; existing
  `CUTTINGS_LIBRARY` overrides remain supported.
- Per-device cache directory: `~/Library/Application Support/Cuttings/` and the
  existing private Spotlight index identifiers.
- Durable local identities and asset references: `cuttings://` and
  `cuttings-asset:`. These participate in deduplication and remain format-v1
  contracts, including for newly saved items.
- Inbox archives: `.cuttingscapture.zip`; coordinated library locks and import
  staging: `.cuttings-locks` and `.cuttings-imports`.

These are compatibility details, not product copy. Changing them requires a
separate migration that accounts for older clients and external library writers.
Existing user-owned Markdown files are not rewritten by the rename.

Git remote URLs remain unchanged until the hosted repository is renamed.
Historical naming research remains labelled as historical evidence.
