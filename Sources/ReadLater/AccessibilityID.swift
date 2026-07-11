import Foundation

/// Stable accessibility identifiers shared by the app and the XCUITest suite, so
/// tests locate controls by identifier rather than by (localizable, ambiguous)
/// on-screen wording.
///
/// This file is compiled into **both** the `ReadLater` app target and the
/// `ReadLaterUITests` target (it lives under `Sources/ReadLater/`, and the test
/// target lists it explicitly) so the two sides agree on one source of truth.
///
/// Wired up in E2E-2; the full set of namespaced identifier constants
/// (`Onboarding`, `Sidebar`, `List`, `Detail`, `Toolbar`, `RatingFooter`,
/// `TagPicker`, `Highlights`, `Shortcuts`, `Settings`) is added in E2E-4. Kept
/// intentionally empty until then so the test target has a real source to build.
enum A11y {}
