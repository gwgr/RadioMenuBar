# Tech Debt Tasks

Use this as a small, restartable task ledger for cleanup work that is useful but not urgent. Mark items done as they land, and add notes or commit hashes when helpful.

## Completed

- [x] `TD-001` Split the single Swift file into focused source files.
  - Done in `a7822d9`.
- [x] `TD-002` Surface station config load errors in the menu instead of falling back silently.
  - Done in `a7822d9`.
- [x] `TD-003` Add basic station validation.
  - Done locally; invalid entries now produce config warnings and are skipped before playback.
- [x] `TD-005` Add a small testable station-loading core.
  - Done locally; `StationLoader` covers config search, fallback, defaults, and validation with XCTest coverage.
- [x] `TD-006` Refresh the README feature list.
  - Done locally; README now reflects icon/screenshot context, shortcuts, station-name display, default stations, and config warnings.
- [x] `TD-004` Extract reusable menu row components.
  - Done locally; station rows, toggle rows, reload/config rows, and quit now use shared row primitives.
- [x] `TD-007` Evaluate native launch-at-login support.
  - Done locally; migrated to `SMAppService.mainApp` and kept legacy LaunchAgent cleanup for existing installs.

## Open
