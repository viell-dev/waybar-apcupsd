# AGENTS.md

This file is the canonical agent guidance for this repository. `CLAUDE.md` delegates here.

## Project Overview

`waybar-apcupsd` is a small Waybar integration for APC UPS devices managed by `apcupsd`.

- Runtime entrypoint: `ups-status.sh`
- Test suite: `tests/test_ups_status.py`
- CI workflow: `.github/workflows/ci.yml`
- User-facing docs: `README.md`
- Release history: `CHANGELOG.md`

For installation, configuration, output fields, CSS classes, status behavior, and troubleshooting, use `README.md` as the source of truth.

## Testing

Use the test and check commands documented in `README.md`.

The tests mock `apcaccess` by prepending a temporary script to `PATH`. Keep tests focused on the actual script contract rather than refactoring the shell implementation into a separate library.

When behavior changes, update or add focused tests and keep `README.md` and `CHANGELOG.md` in sync.

## Documentation And Release Hygiene

Keep these files in sync with behavior changes:

- `README.md` for installation, configuration, behavior, and test usage
- `CHANGELOG.md` in Keep a Changelog format
- `.github/workflows/ci.yml` when the test entrypoints or required runtimes change

Use `CHANGELOG.md` like this:

- Add ongoing work under `## [Unreleased]`
- Move those entries into the next version section when preparing or tagging a release
- Keep historical entries concise and user-facing

## APCUPSd Reference

The ignored `./apcupsd/` directory contains local source and docs for reference only. It is useful for checking real field names and status-report formatting, but this project does not build or vendor apcupsd.
