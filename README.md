# waybar-apcupsd

[![Version](https://img.shields.io/badge/version-0.1.0-blue)](https://github.com/viell-dev/waybar-apcupsd/releases)

A custom [Waybar](https://github.com/Alexays/Waybar) module for monitoring an APC UPS via [apcupsd](http://www.apcupsd.org/). Displays battery-style icons with color-coded status.

## Prerequisites

- `apcupsd` installed and running (`systemctl status apcupsd`)
- `apcaccess` available (included with apcupsd)

Verify your UPS is communicating:

```bash
apcaccess status
```

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/viell-dev/waybar-apcupsd.git
chmod +x waybar-apcupsd/ups-status.sh
```

### 2. Add the module to your Waybar config

In your Waybar config (e.g. `~/.config/waybar/config.jsonc`), add `"custom/ups"` to your desired module list:

```jsonc
"modules-right": ["custom/ups", ...],
```

Then add the module definition, pointing `exec` at wherever you cloned the script:

```jsonc
"custom/ups": {
  "exec": "/path/to/waybar-apcupsd/ups-status.sh",
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
| `alert` | Error states (LOWBATT, OVERLOAD, etc.) | Single icon |
| `unknown` | Communication lost / unknown status | Single icon |

### Using different icons

Replace the icons in `format-icons` in your Waybar config. Arrays must have entries from low to high — Waybar picks the icon based on the `percentage` value.

```jsonc
"format-icons": {
  // Use any icons your font supports
  "charging": ["", "", "", "", ""],
  "discharging": ["", "", "", "", ""],
  "alert": "",
  "unknown": ""
}
```

### Using text instead of icons

Set `format-icons` to text labels for a setup that doesn't require a Nerd Font:

```jsonc
"format": "{icon} {text}",
"format-icons": {
  "charging": "CHG",
  "discharging": "BAT",
  "alert": "ALT",
  "unknown": "UNK"
}
```

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
system files owned by root and may be overwritten on apcupsd package updates.

You can also trigger a manual refresh at any time:

```bash
pkill -SIGRTMIN+9 waybar
```

## Script Output Reference

The script outputs JSON with these fields:

| Field | Description | Example |
|---|---|---|
| `text` | Battery percentage, or status text for errors | `"75%"` |
| `alt` | State name for icon selection | `"charging"` |
| `tooltip` | Detailed UPS info | `"Status: ONLINE\n..."` |
| `class` | CSS class for styling | `"online"` |
| `percentage` | Battery charge (0-100) | `100` |

### CSS Classes

| CSS Class | Condition |
|---|---|
| `online` | On mains power |
| `on-battery` | On battery, charge > 50% |
| `warning` | On battery, charge 20-50% |
| `critical` | On battery charge < 20%, or any error state |

### Error States

| STATUS | Meaning |
|---|---|
| LOWBATT | Low battery, shutdown imminent |
| OVERLOAD | UPS load exceeds capacity |
| REPLACEBATT | Battery needs replacement |
| NOBATT | No battery detected |
| COMMLOST | Lost communication with UPS |

### Tooltip

Hovering shows detailed info:

```
Status: ONLINE
Battery: 100.0%
Load: 53.0%
Runtime: 8.3 min
Line: 228.0 V
```

Warning messages appear at the top of the tooltip when applicable.

## Troubleshooting

```bash
# Check apcupsd is running
systemctl status apcupsd

# Test apcaccess directly
apcaccess status

# Test the script output (should print valid JSON)
/path/to/waybar-apcupsd/ups-status.sh

# Validate JSON
/path/to/waybar-apcupsd/ups-status.sh | python -m json.tool
```

## AI Disclaimer

This project was generated by [Claude Code](https://claude.ai/code) with iterative refinement based on viell's feedback. The code has been reviewed at a high level but not exhaustively audited.
