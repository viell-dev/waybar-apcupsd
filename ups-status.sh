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

# --- Determine alt, class, and warning message ----------------------------

CLASS="online"
ALT=""
WARNING=""
FALLBACK_TEXT=""

case "$STATUS" in
    ONLINE)
        ALT="charging"
        CLASS="online"
        ;;
    ONBATT)
        ALT="discharging"
        if (( CHARGE_INT <= 20 )); then
            CLASS="critical"
            WARNING="LOW BATTERY"
        elif (( CHARGE_INT <= 50 )); then
            CLASS="warning"
        else
            CLASS="on-battery"
        fi
        ;;
    LOWBATT)
        ALT="alert"
        CLASS="critical"
        WARNING="LOW BATTERY - Shutdown imminent"
        ;;
    OVERLOAD)
        ALT="alert"
        CLASS="critical"
        WARNING="UPS OVERLOADED"
        ;;
    REPLACEBATT)
        ALT="alert"
        CLASS="critical"
        WARNING="REPLACE BATTERY"
        ;;
    NOBATT)
        ALT="alert"
        CLASS="critical"
        WARNING="NO BATTERY DETECTED"
        FALLBACK_TEXT="$TEXT_ALERT"
        ;;
    COMMLOST)
        ALT="unknown"
        CLASS="critical"
        WARNING="COMMUNICATION LOST"
        FALLBACK_TEXT="$TEXT_UNKNOWN"
        ;;
    *)
        ALT="unknown"
        CLASS="warning"
        WARNING="Unknown status: $STATUS"
        FALLBACK_TEXT="$TEXT_UNKNOWN"
        [[ "$DEBUG" -ge 1 ]] && debug_log
        ;;
esac

# --- Debug logging (level 2: always) --------------------------------------
[[ "$DEBUG" -ge 2 ]] && debug_log

# --- Build output ---------------------------------------------------------

TEXT="${FALLBACK_TEXT:-${CHARGE_INT}%}"

# Tooltip with full details
TOOLTIP=""
[[ -n "$WARNING" ]] && TOOLTIP="⚠ ${WARNING}\n"
TOOLTIP="${TOOLTIP}Status: ${STATUS}\nBattery: ${BCHARGE}%\nLoad: ${LOADPCT}%\nRuntime: ${TIMELEFT} min\nLine: ${LINEV} V"

# Escape quotes for JSON
TEXT="${TEXT//\"/\\\"}"
TOOLTIP="${TOOLTIP//\"/\\\"}"

printf '{"text": "%s", "alt": "%s", "tooltip": "%s", "class": "%s", "percentage": %d}\n' \
    "$TEXT" "$ALT" "$TOOLTIP" "$CLASS" "$CHARGE_INT"
