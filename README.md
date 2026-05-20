# waybar-apcupsd

[![Version](https://img.shields.io/github/v/release/viell-dev/waybar-apcupsd)](https://github.com/viell-dev/waybar-apcupsd/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE-MIT)

A custom [Waybar](https://github.com/Alexays/Waybar) module for monitoring an APC UPS via [apcupsd](https://sourceforge.net/projects/apcupsd/). Displays battery-style icons with color-coded status.

Release notes live in [CHANGELOG.md](CHANGELOG.md).

## Prerequisites

- `apcupsd` installed and running (`systemctl status apcupsd`)
- `apcaccess` available (included with apcupsd)

Verify your UPS is communicating:

```bash
apcaccess
```

## Installation

### 1. Install the script

```bash
cp ups-status.sh /path/to/ups-status.sh
chmod +x /path/to/ups-status.sh
```

Install the script wherever you keep Waybar helper scripts. You can copy
`ups-status.sh` from a cloned repository or from a release archive. The examples
below use `/path/to/ups-status.sh`; replace it with your chosen location.

### 2. Add the module to your Waybar config

In your Waybar config (e.g. `~/.config/waybar/config.jsonc`), add `"custom/ups"` to your desired module list:

```jsonc
"modules-right": ["custom/ups", ...],
```

Then add the module definition, pointing `exec` at the installed script:

```jsonc
"custom/ups": {
  "exec": "/path/to/ups-status.sh",
  "return-type": "json",
  "interval": 60,
  "signal": 9,
  "format": "{icon} {text}",
  "format-icons": {
    "charging": ["󰢟", "󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰂊", "󰢞", "󰂋", "󰂅"],
    "discharging": ["󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"],
    "alert": "󰂃",
    "unknown": "󰂑"
  }
}
```

The script outputs `alt` and `percentage` fields. Waybar uses `alt` to pick the icon set and `percentage` to select the battery level within it. See [Customization](#customization) for how to change icons.

- `interval: 60` — polls every 60 seconds
- `signal: 9` — refreshes immediately on `SIGRTMIN+9` (see [Event-Driven Updates](#event-driven-updates-optional))

### 3. Add CSS styling

Add to your Waybar `style.css`. Adapt the colors to match your theme:

```css
#custom-ups.online {
  color: #9ece6a; /* green */
}

#custom-ups.on-battery {
  color: #e0af68; /* yellow */
}

#custom-ups.warning {
  color: #ff9e64; /* orange */
}

#custom-ups.critical {
  color: #f7768e; /* red */
  animation: blink 1s ease-in-out infinite;
}

@keyframes blink {
  50% { opacity: 0.5; }
}
```

### 4. Restart Waybar

Restart Waybar to pick up the changes. The method depends on your setup — for example:

```bash
killall waybar && waybar &
```

## Customization

Icons are configured entirely in your Waybar config via [`format-icons`](https://github.com/Alexays/Waybar/wiki/Module:-Custom). The script outputs these `alt` values that select the icon set:

| `alt` value | When | Icon selection |
|---|---|---|
| `charging` | UPS online / on mains | Array — picked by percentage (0-100%) |
| `discharging` | UPS on battery | Array — picked by percentage (0-100%) |
| `alert` | Alert-only states with no normal power icon (SHUTTING DOWN, NOBATT, etc.) | Single icon |
| `unknown` | Communication lost / unknown status | Single icon |

### Using different icons

Replace the icons in `format-icons` in your Waybar config. Arrays must be
ordered from low to high charge. Waybar maps the script's `percentage` value
across however many entries you provide, so you can use a coarse set such as 5
icons or a finer set such as 11 icons.

```jsonc
"format-icons": {
  // Use any icons your font supports
  "charging": ["", "", "", "", ""],
  "discharging": ["", "", "", "", ""],
  "alert": "",
  "unknown": ""
}
```

The icon strings can be plain text labels if you do not use a Nerd Font. Keep
`charging` and `discharging` as arrays when you want Waybar to select by
percentage.

### Hiding the icon

Use `{text}` only in the format string to show just the percentage:

```jsonc
"format": "{text}"
```

## Event-Driven Updates (optional)

By default the module polls every 60 seconds. For instant updates on power events,
add the following line to the apcupsd event scripts in `/etc/apcupsd/`:

**Scripts to modify:** `onbattery`, `offbattery`, `commfailure`, `commok`, `changeme`

Add before `exit 0` in each:

```bash
pkill -SIGRTMIN+9 waybar 2>/dev/null
```

This sends a signal to Waybar to immediately re-run the UPS script. These are
root-owned, package-managed system files, so keep local changes in mind when
updating the distro package.

You can also trigger a manual refresh at any time:

```bash
pkill -SIGRTMIN+9 waybar
```

## Script Output Reference

The script outputs JSON with these fields:

| Field | Description | Example |
|---|---|---|
| `text` | Battery percentage, or fallback status text | `"75%"` |
| `alt` | State name for icon selection | `"charging"` |
| `tooltip` | Detailed UPS info | `"Status: ONLINE\n..."` |
| `class` | CSS class for styling | `"online"` |
| `percentage` | Battery charge (0-100) | `100` |

Numeric `BCHARGE` values are clamped into the `0-100` range before output, so
minor over-100 readings from UPS rounding are treated as full charge. If
`BCHARGE` is missing or nonnumeric, the script reports `text: "Unknown"` and
`percentage: 0`, but it does not apply charge-threshold warning or critical
classes from that placeholder value.

### CSS Classes

| CSS Class | Condition |
|---|---|
| `online` | On mains power |
| `on-battery` | On battery, above configured warning/critical charge thresholds |
| `warning` | On battery at or below `WARNING_CHARGE`; `COMMLOST`; hardware warnings; `ONLINE LOWBATT` |
| `critical` | `SHUTTING DOWN`; `NOBATT`; `ONBATT LOWBATT`; `apcaccess` failure; empty `apcaccess` output; on battery at or below configured `CRITICAL_CHARGE` |

### Charge Thresholds

Charge-level CSS classes are configurable with environment variables:

| Variable | Default | Meaning |
|---|---:|---|
| `WARNING_CHARGE` | `20` | On-battery charge at or below this percentage becomes `warning`; use an integer from `0` to `100`; `0` disables the warning threshold |
| `CRITICAL_CHARGE` | `0` | On-battery charge at or below this percentage becomes `critical`; use an integer from `0` to `100`; `0` disables the critical threshold |

If both thresholds are enabled, `CRITICAL_CHARGE` must be lower than
`WARNING_CHARGE`. Invalid threshold config emits a critical `Error` payload so
the Waybar module makes the misconfiguration visible.

Examples:

```jsonc
// Warn at 30%, never make charge level alone critical
"exec": "WARNING_CHARGE=30 /path/to/ups-status.sh"

// Use only a critical threshold
"exec": "WARNING_CHARGE=0 CRITICAL_CHARGE=20 /path/to/ups-status.sh"
```

### Status Flags

The apcupsd STATUS field can contain multiple space-separated flags (e.g., `ONLINE OVERLOAD`). The script parses the flags, determines the primary power context first, then applies context-aware warning and critical modifiers.

`LOWBATT` is context-sensitive:

- `ONBATT LOWBATT` is critical because apcupsd treats the low-battery bit as a shutdown trigger while on battery
- `ONLINE LOWBATT` is downgraded to a warning and keeps the normal charging icon

**Critical states** (shutdown imminent or battery missing):

| Flag | Meaning |
|---|---|
| SHUTTING DOWN | System is shutting down |
| NOBATT | No battery detected |

**Context-dependent states**:

| Flag | Meaning |
|---|---|
| LOWBATT | Critical on battery; warning while `ONLINE` |

**Warning states** (UPS needs attention, but mains power may still be present):

| Flag | Meaning |
|---|---|
| COMMLOST | Lost communication with UPS device (cable/driver issue) |
| OVERLOAD | UPS load exceeds rated capacity |
| REPLACEBATT | Battery needs replacement |

**Power states** (drive the main icon whenever possible):

| Flag | Meaning |
|---|---|
| ONBATT | Running on battery power |
| ONLINE | Running on mains power |

**Informational flags** (shown in tooltip):

| Flag | Meaning |
|---|---|
| CAL | Battery calibration in progress |
| TRIM | Over-voltage correction active |
| BOOST | Under-voltage correction active |
| SLAVE | Running as network slave |
| SLAVEDOWN | Slave not responding |

`COMMLOST` is treated as a warning. Some UPS models briefly stop reporting
status during self-tests, so `COMMLOST` is treated as a temporary communication
warning rather than a critical alert. If `apcaccess` itself exits with an error,
or exits successfully without returning status data, the script reports a
critical `Error` because that usually means apcupsd is not running, the local
query path is misconfigured, or apcupsd returned an unexpected result.

### Tooltip

Hovering shows detailed info:

```
Status: ONLINE
Battery: 100.0%
Load: 53.0%
Runtime: 8.3 min
Line: 228.0 V
```

Warning messages (⚠) and informational messages (ℹ) appear at the top of the tooltip when applicable.

## Troubleshooting

```bash
# Check apcupsd is running
systemctl status apcupsd

# Test apcaccess directly
apcaccess

# Test the script output (should print valid JSON)
/path/to/ups-status.sh

# Validate JSON
/path/to/ups-status.sh | python -m json.tool
```

### Debug logging

To capture the raw `apcaccess` output for troubleshooting, set the `DEBUG` environment variable:

| Value | Behavior |
|---|---|
| `0` | Off (default) |
| `1` | Log only when an unknown status is encountered |
| `2` | Log on every invocation |

Logs are written to `/tmp/waybar-apcupsd.log` (override with `DEBUG_LOG`).

```bash
# Enable logging for unknown statuses in Waybar config
"exec": "DEBUG=1 /path/to/ups-status.sh"

# Or test manually with full logging
DEBUG=2 /path/to/ups-status.sh
cat /tmp/waybar-apcupsd.log
```

## Tests

The test suite mocks `apcaccess` via `PATH` and only emits the fields this script reads: `STATUS`, `BCHARGE`, `LOADPCT`, `TIMELEFT`, and `LINEV`.

```bash
just test
```

This requires `just` and Python 3, but does not require a running UPS or `apcupsd`.

Run the full local check suite with:

```bash
just check
```

The same lint and test checks run in GitHub Actions on pushes to `main` and on pull requests.

## AI Disclaimer

This project was generated by [Claude Code CLI](https://claude.ai/code) and [Codex CLI](https://developers.openai.com/codex/cli)
with iterative refinement based on viell's feedback. The code has been reviewed at a high level but not exhaustively audited.
