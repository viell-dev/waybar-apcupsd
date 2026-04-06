# AGENTS.md

This file is the canonical agent guidance for this repository. `CLAUDE.md` delegates here.

## Project Overview

`waybar-apcupsd` is a small Waybar integration for APC UPS devices managed by `apcupsd`.

- Runtime entrypoint: `ups-status.sh`
- Test suite: `tests/test_ups_status.py`
- CI workflow: `.github/workflows/ci.yml`
- User-facing docs: `README.md`
- Release history: `CHANGELOG.md`

The script runs `apcaccess status`, reads a small subset of fields, and emits Waybar JSON:

```json
{"text":"...","alt":"...","tooltip":"...","class":"...","percentage":42}
```

## Behavior Notes

The script currently reads only these `apcaccess status` fields:

- `STATUS`
- `BCHARGE`
- `LOADPCT`
- `TIMELEFT`
- `LINEV`

`STATUS` may contain multiple flags. The resolver is context-aware:

- Determine the primary power state first: `ONLINE`, `ONBATT`, or unknown
- Apply warning and critical modifiers on top of that power state
- Keep informational flags in the tooltip only

Important expectations:

- `ONLINE LOWBATT` is `warning` with the `charging` icon
- `ONBATT LOWBATT` is `critical` with the `discharging` icon
- `COMMLOST` uses the `unknown` icon
- `SHUTTING DOWN` and `NOBATT` use the `alert` icon

## Testing

Run the unit test suite with:

```bash
python3 -m unittest discover -s tests -v
```

CI runs the same suite plus basic syntax checks in GitHub Actions.

The tests mock `apcaccess` by prepending a temporary script to `PATH`. Keep tests focused on the actual script contract rather than refactoring the shell implementation into a separate library.

When behavior changes, update or add tests for:

- mixed `STATUS` combinations
- power-state precedence
- icon override precedence
- fallback text for error and unknown conditions
- tooltip warning and informational lines

## Documentation And Release Hygiene

Keep these files in sync with behavior changes:

- `README.md` for installation, configuration, behavior, and test usage
- `CHANGELOG.md` in Keep a Changelog format
- `.github/workflows/ci.yml` when the test entrypoints or required runtimes change

Use `CHANGELOG.md` like this:

- Add ongoing work under `## [Unreleased]`
- Move those entries into `0.2.0`, `0.2.1`, etc. when tagged
- Keep historical entries concise and user-facing

## APCUPSd Reference

The ignored `./apcupsd/` directory contains local source and docs for reference only. It is useful for checking real field names and status-report formatting, but this project does not build or vendor apcupsd.
