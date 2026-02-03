# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

A custom Waybar module (`ups-status.sh`) that monitors an APC UPS via `apcupsd`. The script queries `apcaccess status`, parses the output, and emits JSON consumed by Waybar's custom module interface (`return-type: "json"`).

## Architecture

Single bash script. No build system, no dependencies beyond `apcupsd`/`apcaccess` and a Nerd Font.

**Output format:** `{"text": "...", "alt": "...", "tooltip": "...", "class": "...", "percentage": N}`

**CSS classes emitted:** `online`, `on-battery`, `warning`, `critical` — these map to Waybar styling and are driven by UPS status and battery charge level.

**Status handling:** The script handles `ONLINE`, `ONBATT`, `LOWBATT`, `OVERLOAD`, `REPLACEBATT`, `NOBATT`, `COMMLOST`, and unknown states. Each maps to an icon set (charging vs discharging Nerd Font battery icons, indexed by charge level in 10% steps) and a CSS class.

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
