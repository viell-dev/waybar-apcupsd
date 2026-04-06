# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-04-06

### Added

- A Python `unittest` suite that mocks `apcaccess` through `PATH` and exercises the real Waybar script end to end.
- Coverage for compound status handling, informational tooltip flags, error fallbacks, and communication-loss precedence.
- This changelog and release-history baseline.
- A GitHub Actions workflow that runs shell syntax checks and the mocked unit test suite on pushes and pull requests.

### Changed

- Reworked compound `STATUS` handling from a simple priority ladder to a context-aware resolver.
- `ONLINE LOWBATT` now resolves to a warning with the normal charging icon instead of a critical alert.
- Repository guidance and README maintenance docs now reflect the current test and release workflow.

### Fixed

- Prevented mixed mains-power states from being overstated as shutdown-imminent critical alerts.
- Normalized padded battery percentages such as `095.0 Percent` so Bash arithmetic does not fail on leading zeroes.
- Restored the intended `DEBUG=2` behavior so unknown statuses are logged once, not twice.

## [0.1.3] - 2026-02-18

### Changed

- Reclassified `OVERLOAD` and `COMMLOST` from critical states to warnings.
- Clarified the internal status-resolution comments to match the implemented behavior.

## [0.1.2] - 2026-02-11

### Added

- MIT license file and README license badge.

## [0.1.1] - 2026-02-11

### Added

- Debug logging for capturing raw `apcaccess` output while troubleshooting unknown UPS states.
- README troubleshooting docs for the debug workflow.
- Support for compound `STATUS` values such as `ONLINE OVERLOAD`.
- Informational tooltip messages for `CAL`, `TRIM`, `BOOST`, `SLAVE`, and `SLAVEDOWN`.
- Repository metadata files including source-reference notes and mailmap/gitignore housekeeping.

### Fixed

- Normalized invalid `DEBUG` values to avoid Bash integer-comparison noise.
- Stopped unknown-status debug logging from firing twice when `DEBUG=2`.

## [0.1.0] - 2026-02-03

### Added

- Initial Waybar UPS module implemented as a single Bash script.
- Battery percentage output, battery-style icon selection, and color-coded CSS classes.
- Tooltips showing UPS status, charge, load, runtime, and line voltage.
- Manual and signal-driven Waybar refresh instructions in the README.

[Unreleased]: https://github.com/viell-dev/waybar-apcupsd/compare/0.2.0...HEAD
[0.2.0]: https://github.com/viell-dev/waybar-apcupsd/compare/0.1.3...0.2.0
[0.1.3]: https://github.com/viell-dev/waybar-apcupsd/compare/0.1.2...0.1.3
[0.1.2]: https://github.com/viell-dev/waybar-apcupsd/compare/0.1.1...0.1.2
[0.1.1]: https://github.com/viell-dev/waybar-apcupsd/compare/0.1.0...0.1.1
[0.1.0]: https://github.com/viell-dev/waybar-apcupsd/compare/a2272be...0.1.0
