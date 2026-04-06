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
CHARGE_INT=${CHARGE_INT//[^0-9]/}
if [[ -n "$CHARGE_INT" ]]; then
    CHARGE_INT=$((10#$CHARGE_INT))
else
    CHARGE_INT=0
fi

# --- Determine state from compound STATUS field --------------------------
# STATUS can contain multiple space-separated flags (e.g., "ONLINE OVERLOAD").
# Resolve compound states in three steps:
#   1. Determine the primary power context (ONLINE / ONBATT / unknown)
#   2. Apply context-aware warning and critical modifiers
#   3. Keep informational flags in the tooltip only

STATUS_NORMALIZED=$(awk '{$1=$1; print}' <<< "$STATUS")

declare -A STATUS_FLAGS=()
for token in $STATUS_NORMALIZED; do
    STATUS_FLAGS["$token"]=1
done

has_flag() {
    [[ -n "${STATUS_FLAGS[$1]:-}" ]]
}

severity_rank() {
    case "$1" in
        online) echo 0 ;;
        on-battery) echo 1 ;;
        warning) echo 2 ;;
        critical) echo 3 ;;
        *) echo 0 ;;
    esac
}

set_class_max() {
    local candidate=$1

    if (( $(severity_rank "$candidate") > $(severity_rank "$CLASS") )); then
        CLASS=$candidate
    fi
}

alt_rank() {
    case "$1" in
        "") echo 0 ;;
        unknown) echo 1 ;;
        alert) echo 2 ;;
        *) echo 0 ;;
    esac
}

set_alt_override() {
    local candidate=$1

    if (( $(alt_rank "$candidate") > $(alt_rank "$ALT_OVERRIDE") )); then
        ALT_OVERRIDE=$candidate
    fi
}

CLASS="online"
ALT="unknown"
ALT_OVERRIDE=""
FALLBACK_TEXT=""
WARNINGS=()
INFO_MESSAGES=()
UNKNOWN_TOKENS=()
POWER_STATE="unknown"
HAS_KNOWN_FLAG=0
IS_SHUTTING_DOWN=0

if [[ "$STATUS_NORMALIZED" == *"SHUTTING DOWN"* ]]; then
    IS_SHUTTING_DOWN=1
    HAS_KNOWN_FLAG=1
fi

for token in $STATUS_NORMALIZED; do
    case "$token" in
        ONLINE|ONBATT|LOWBATT|REPLACEBATT|NOBATT|COMMLOST|OVERLOAD|CAL|TRIM|BOOST|SLAVE|SLAVEDOWN)
            HAS_KNOWN_FLAG=1
            ;;
        SHUTTING|DOWN)
            if (( IS_SHUTTING_DOWN )); then
                :
            else
                UNKNOWN_TOKENS+=("$token")
            fi
            ;;
        "")
            ;;
        *)
            UNKNOWN_TOKENS+=("$token")
            ;;
    esac
done

# Collect informational flags for tooltip (these don't change primary state)
has_flag CAL && INFO_MESSAGES+=("Calibration in progress.")
has_flag TRIM && INFO_MESSAGES+=("Voltage trim active.")
has_flag BOOST && INFO_MESSAGES+=("Voltage boost active.")
if has_flag SLAVEDOWN; then
    INFO_MESSAGES+=("Slave not responding.")
elif has_flag SLAVE; then
    INFO_MESSAGES+=("Running as slave.")
fi

# Determine the primary power context first.
if has_flag ONBATT; then
    POWER_STATE="on-battery"
    ALT="discharging"
    if (( CHARGE_INT <= 20 )); then
        CLASS="critical"
        if ! has_flag LOWBATT; then
            WARNINGS+=("LOW BATTERY")
        fi
    elif (( CHARGE_INT <= 50 )); then
        CLASS="warning"
    else
        CLASS="on-battery"
    fi
elif has_flag ONLINE; then
    POWER_STATE="online"
    ALT="charging"
    CLASS="online"
else
    CLASS="warning"
    FALLBACK_TEXT="$TEXT_UNKNOWN"
fi

# Apply context-aware flags on top of the power state.
if (( IS_SHUTTING_DOWN )); then
    set_class_max critical
    set_alt_override alert
    FALLBACK_TEXT="$TEXT_ALERT"
    WARNINGS+=("SHUTTING DOWN")
fi

if has_flag COMMLOST; then
    set_class_max warning
    set_alt_override unknown
    FALLBACK_TEXT="$TEXT_UNKNOWN"
    WARNINGS+=("COMMUNICATION LOST")
fi

if has_flag LOWBATT; then
    case "$POWER_STATE" in
        online)
            set_class_max warning
            WARNINGS+=("Battery low, currently on mains power")
            ;;
        on-battery)
            set_class_max critical
            WARNINGS+=("LOW BATTERY - Shutdown imminent")
            ;;
        *)
            set_class_max critical
            set_alt_override alert
            FALLBACK_TEXT="$TEXT_ALERT"
            WARNINGS+=("LOW BATTERY - Power state unknown")
            ;;
    esac
fi

if has_flag REPLACEBATT; then
    set_class_max warning
    if [[ "$POWER_STATE" == "unknown" ]]; then
        set_alt_override alert
        FALLBACK_TEXT="$TEXT_ALERT"
    fi
    WARNINGS+=("REPLACE BATTERY")
fi

if has_flag NOBATT; then
    set_class_max critical
    set_alt_override alert
    FALLBACK_TEXT="$TEXT_ALERT"
    WARNINGS+=("NO BATTERY DETECTED")
fi

if has_flag OVERLOAD; then
    set_class_max warning
    if [[ "$POWER_STATE" == "unknown" ]]; then
        set_alt_override alert
        FALLBACK_TEXT="$TEXT_ALERT"
    fi
    WARNINGS+=("UPS OVERLOADED")
fi

if (( ${#UNKNOWN_TOKENS[@]} > 0 )); then
    set_class_max warning
    WARNINGS+=("Unknown status flag(s): ${UNKNOWN_TOKENS[*]}")
    [[ "$DEBUG" -eq 1 ]] && debug_log
elif [[ "$POWER_STATE" == "unknown" && "$HAS_KNOWN_FLAG" -eq 0 ]]; then
    WARNINGS+=("Unknown status: ${STATUS:-<empty>}")
    [[ "$DEBUG" -eq 1 ]] && debug_log
fi

if [[ -n "$ALT_OVERRIDE" ]]; then
    ALT=$ALT_OVERRIDE
fi

# --- Debug logging (level 2: always) --------------------------------------
[[ "$DEBUG" -eq 2 ]] && debug_log

# --- Build output ---------------------------------------------------------

TEXT="${FALLBACK_TEXT:-${CHARGE_INT}%}"

# Tooltip with full details
# Note: ⚠ is U+26A0 (Warning Sign), ℹ is U+2139 (Information Source)
TOOLTIP=""
for warning in "${WARNINGS[@]}"; do
    TOOLTIP="${TOOLTIP}⚠ ${warning}\n"
done
for info in "${INFO_MESSAGES[@]}"; do
    TOOLTIP="${TOOLTIP}ℹ ${info}\n"
done
TOOLTIP="${TOOLTIP}Status: ${STATUS}\nBattery: ${BCHARGE}%\nLoad: ${LOADPCT}%\nRuntime: ${TIMELEFT} min\nLine: ${LINEV} V"

# Escape quotes for JSON
TEXT="${TEXT//\"/\\\"}"
TOOLTIP="${TOOLTIP//\"/\\\"}"

printf '{"text": "%s", "alt": "%s", "tooltip": "%s", "class": "%s", "percentage": %d}\n' \
    "$TEXT" "$ALT" "$TOOLTIP" "$CLASS" "$CHARGE_INT"
