# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A custom Waybar module (`ups-status.sh`) that monitors an APC UPS via `apcupsd`. The script queries `apcaccess status`, parses the output, and emits JSON consumed by Waybar's custom module interface (`return-type: "json"`).

## Architecture

Single bash script. No build system, no dependencies beyond `apcupsd`/`apcaccess` and a Nerd Font.

**Output format:** `{"text": "...", "alt": "...", "tooltip": "...", "class": "...", "percentage": N}`

**CSS classes emitted:** `online`, `on-battery`, `warning`, `critical` — these map to Waybar styling and are driven by UPS status and battery charge level.

**Status handling:** The apcupsd STATUS field can contain multiple space-separated flags (e.g., `ONLINE OVERLOAD`). The script uses priority-based pattern matching to handle these compound statuses:

1. **Critical states** (highest priority): `SHUTTING DOWN`, `LOWBATT`, `REPLACEBATT`, `NOBATT` — UPS hardware failing or shutdown imminent
2. **Warning states**: `COMMLOST`, `OVERLOAD` — attention needed, but UPS hardware is healthy
3. **Power states**: `ONBATT` (discharging), `ONLINE` (charging)
4. **Informational flags** (shown in tooltip): `CAL`, `TRIM`, `BOOST`, `SLAVE`, `SLAVEDOWN`

Each state maps to an icon set (charging vs discharging Nerd Font battery icons, indexed by charge level in 10% steps) and a CSS class.

## Testing

No test framework. To verify the script manually:

```bash
# Run directly (requires apcupsd running)
./ups-status.sh

# Validate JSON output
./ups-status.sh | python -m json.tool
```

## Waybar Integration

- Polls every 60s by default (`interval: 60`)
- Supports signal-based refresh: `pkill -SIGRTMIN+9 waybar`
- Event-driven updates via apcupsd scripts (`onbattery`, `offbattery`, `commfailure`, `commok`, `changeme`)

## APCUPSd Source Code

The git ignored directory `./apcupsd` ought to contain the source code of APCUPSd. It can also be downloaded from: [SourceForge](https://sourceforge.net/projects/apcupsd/files/apcupsd%20-%20Stable/3.14.14/). The latest official version is 3.14.14 from 2016-05-31. It's basically abandonware at this point, even the homepage just points at their SourceForge page for the package.
