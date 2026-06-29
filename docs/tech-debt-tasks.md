# Tech Debt Tasks

Use this as a small, restartable task ledger for cleanup work that is useful but not urgent. Mark items done as they land, and add notes or commit hashes when helpful.

## Completed

- [x] `TD-001` Split the single Swift file into focused source files.
  - Done in `a7822d9`.
- [x] `TD-002` Surface station config load errors in the menu instead of falling back silently.
  - Done in `a7822d9`.

## Open

- [ ] `TD-003` Add basic station validation.
  - Why: `stations.json` is user-editable, so bad entries should fail clearly before playback.
  - Scope: Validate empty station names, unsupported URL schemes, duplicate URLs, and empty station lists.
  - Acceptance: Invalid entries produce a visible config warning while valid entries still load; no playback attempt is made for invalid URLs.

- [ ] `TD-004` Extract reusable menu row components.
  - Why: The menu still repeats the same checkmark gutter, hover background, spacer, and shortcut-hint layout.
  - Scope: Add small reusable views/modifiers for selectable rows and command rows.
  - Acceptance: Station rows, toggle rows, reload/config rows, and quit row use shared row primitives without changing visible behavior.

- [ ] `TD-005` Add a small testable station-loading core.
  - Why: Config search, fallback, and validation are important enough to test outside the SwiftUI app lifecycle.
  - Scope: Move pure station-loading/decoding decisions into a type that can be exercised with temporary fixture files.
  - Acceptance: Tests cover valid config, malformed first config with fallback, no config, duplicate URL warning, empty name warning, and unsupported scheme warning.

- [ ] `TD-006` Refresh the README feature list.
  - Why: The README is behind the current app behavior.
  - Scope: Mention the app icon, screenshot, station-name display toggle, keyboard shortcuts, current default stations, and visible config error warnings.
  - Acceptance: README accurately reflects current behavior without becoming a feature roadmap.

- [ ] `TD-007` Evaluate native launch-at-login support.
  - Why: The current LaunchAgent approach works, but modern macOS apps usually use ServiceManagement for login items.
  - Scope: Check whether this Swift Package app bundle can use `SMAppService` cleanly without adding disproportionate project complexity.
  - Acceptance: Either migrate to native login-item registration or document why the current LaunchAgent approach remains the simpler fit.
