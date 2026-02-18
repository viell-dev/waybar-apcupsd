#!/usr/bin/env bash
#
# UPS status module for waybar.
# Queries apcupsd via apcaccess and outputs JSON for waybar's custom module.
#
# Output fields: text, alt, tooltip, class, percentage

set -euo pipefail

# --- Debug settings -------------------------------------------------------
# 0 = off, 1 = log on unknown/*-branch, 2 = log always
DEBUG=${DEBUG:-0}
# Normalize non-integers to 0
[[ "$DEBUG" =~ ^[0-9]+$ ]] || DEBUG=0
DEBUG_LOG="${DEBUG_LOG:-/tmp/waybar-apcupsd.log}"

debug_log() {
    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    {
        echo "=== $timestamp ==="
        echo "$RAW"
        echo ""
    } >> "$DEBUG_LOG"
}

# --- Fallback text for states without a valid charge ----------------------
TEXT_ERROR="Error"
TEXT_ALERT="Alert"
TEXT_UNKNOWN="Unknown"

# --- Fetch all fields in one call -----------------------------------------

RAW=$(apcaccess status 2>/dev/null) || RAW=""

if [[ -z "$RAW" ]]; then
    printf '{"text": "%s", "alt": "alert", "tooltip": "UPS: Cannot communicate with apcupsd", "class": "critical", "percentage": 0}\n' "$TEXT_ERROR"
    exit 0
fi

get_field() {
    echo "$RAW" | awk -F': ' -v key="$1" '$1 ~ "^"key" *$" { gsub(/^ +| +$/, "", $2); print $2; exit }'
}

STATUS=$(get_field STATUS)
BCHARGE=$(get_field BCHARGE)
LOADPCT=$(get_field LOADPCT)
TIMELEFT=$(get_field TIMELEFT)
LINEV=$(get_field LINEV)

# Strip units (e.g. "100.0 Percent" -> "100.0")
BCHARGE=${BCHARGE%% *}
LOADPCT=${LOADPCT%% *}
TIMELEFT=${TIMELEFT%% *}
LINEV=${LINEV%% *}

# Integer charge for percentage output
CHARGE_INT=${BCHARGE%%.*}
CHARGE_INT=${CHARGE_INT:-0}

# --- Determine state from compound STATUS field --------------------------
# STATUS can contain multiple space-separated flags (e.g., "ONLINE OVERLOAD").
# We check in priority order, with critical states first.

CLASS="online"
ALT=""
WARNING=""
FALLBACK_TEXT=""
INFO_FLAGS=""

# Collect informational flags for tooltip (these don't change primary state)
[[ "$STATUS" == *"CAL"* ]] && INFO_FLAGS="${INFO_FLAGS}Calibration in progress. "
[[ "$STATUS" == *"TRIM"* ]] && INFO_FLAGS="${INFO_FLAGS}Voltage trim active. "
[[ "$STATUS" == *"BOOST"* ]] && INFO_FLAGS="${INFO_FLAGS}Voltage boost active. "
[[ "$STATUS" == *"SLAVE"* && "$STATUS" != *"SLAVEDOWN"* ]] && INFO_FLAGS="${INFO_FLAGS}Running as slave. "
[[ "$STATUS" == *"SLAVEDOWN"* ]] && INFO_FLAGS="${INFO_FLAGS}Slave not responding. "

# Critical states (highest priority) - these override power state detection
if [[ "$STATUS" == "SHUTTING DOWN" ]]; then
    ALT="alert"
    CLASS="critical"
    WARNING="SHUTTING DOWN"
    FALLBACK_TEXT="$TEXT_ALERT"
elif [[ "$STATUS" == *"COMMLOST"* ]]; then
    ALT="unknown"
    CLASS="warning"
    WARNING="COMMUNICATION LOST"
    FALLBACK_TEXT="$TEXT_UNKNOWN"
elif [[ "$STATUS" == *"LOWBATT"* ]]; then
    ALT="alert"
    CLASS="critical"
    WARNING="LOW BATTERY - Shutdown imminent"
elif [[ "$STATUS" == *"REPLACEBATT"* ]]; then
    ALT="alert"
    CLASS="critical"
    WARNING="REPLACE BATTERY"
elif [[ "$STATUS" == *"NOBATT"* ]]; then
    ALT="alert"
    CLASS="critical"
    WARNING="NO BATTERY DETECTED"
    FALLBACK_TEXT="$TEXT_ALERT"
elif [[ "$STATUS" == *"OVERLOAD"* ]]; then
    ALT="alert"
    CLASS="warning"
    WARNING="UPS OVERLOADED"
fi

# If no critical state set ALT, determine primary power state
if [[ -z "$ALT" ]]; then
    if [[ "$STATUS" == *"ONBATT"* ]]; then
        ALT="discharging"
        if (( CHARGE_INT <= 20 )); then
            CLASS="critical"
            WARNING="LOW BATTERY"
        elif (( CHARGE_INT <= 50 )); then
            CLASS="warning"
        else
            CLASS="on-battery"
        fi
    elif [[ "$STATUS" == *"ONLINE"* ]]; then
        ALT="charging"
        CLASS="online"
    else
        # Truly unknown status
        ALT="unknown"
        CLASS="warning"
        WARNING="Unknown status: $STATUS"
        FALLBACK_TEXT="$TEXT_UNKNOWN"
        [[ "$DEBUG" -eq 1 ]] && debug_log
    fi
fi

# --- Debug logging (level 2: always) --------------------------------------
[[ "$DEBUG" -eq 2 ]] && debug_log

# --- Build output ---------------------------------------------------------

TEXT="${FALLBACK_TEXT:-${CHARGE_INT}%}"

# Tooltip with full details
# Note: ⚠ is U+26A0 (Warning Sign), ℹ is U+2139 (Information Source)
TOOLTIP=""
[[ -n "$WARNING" ]] && TOOLTIP="⚠ ${WARNING}\n"
[[ -n "$INFO_FLAGS" ]] && TOOLTIP="${TOOLTIP}ℹ ${INFO_FLAGS}\n"
TOOLTIP="${TOOLTIP}Status: ${STATUS}\nBattery: ${BCHARGE}%\nLoad: ${LOADPCT}%\nRuntime: ${TIMELEFT} min\nLine: ${LINEV} V"

# Escape quotes for JSON
TEXT="${TEXT//\"/\\\"}"
TOOLTIP="${TOOLTIP//\"/\\\"}"

printf '{"text": "%s", "alt": "%s", "tooltip": "%s", "class": "%s", "percentage": %d}\n' \
    "$TEXT" "$ALT" "$TOOLTIP" "$CLASS" "$CHARGE_INT"
