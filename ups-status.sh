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

# --- Charge threshold settings -------------------------------------------
# 0 disables the corresponding threshold.
WARNING_CHARGE=${WARNING_CHARGE:-20}
CRITICAL_CHARGE=${CRITICAL_CHARGE:-0}

json_escape() {
    local value=$1
    local char
    local code_hex
    local escape
    local code

    value=${value//\\/\\\\}
    value=${value//\"/\\\"}
    value=${value//$'\b'/\\b}
    value=${value//$'\f'/\\f}
    value=${value//$'\n'/\\n}
    value=${value//$'\r'/\\r}
    value=${value//$'\t'/\\t}

    for code in {1..31}; do
        case "$code" in
            8|9|10|12|13)
                continue
                ;;
        esac

        printf -v code_hex "%02x" "$code"
        printf -v char "%b" "\\x$code_hex"
        printf -v escape '\\u%04x' "$code"
        value=${value//"$char"/"$escape"}
    done

    printf '%s' "$value"
}

emit_error() {
    local tooltip=$1
    local text

    text=$(json_escape "$TEXT_ERROR")
    tooltip=$(json_escape "$tooltip")
    printf '{"text": "%s", "alt": "alert", "tooltip": "%s", "class": "critical", "percentage": 0}\n' "$text" "$tooltip"
}

if [[ ! "$WARNING_CHARGE" =~ ^[0-9]{1,3}$ || ! "$CRITICAL_CHARGE" =~ ^[0-9]{1,3}$ ]]; then
    emit_error "UPS: Invalid charge threshold config. WARNING_CHARGE and CRITICAL_CHARGE must be integers from 0 to 100."
    exit 0
fi

WARNING_CHARGE=$((10#$WARNING_CHARGE))
CRITICAL_CHARGE=$((10#$CRITICAL_CHARGE))

if (( WARNING_CHARGE > 100 || CRITICAL_CHARGE > 100 )); then
    emit_error "UPS: Invalid charge threshold config. WARNING_CHARGE and CRITICAL_CHARGE must be integers from 0 to 100."
    exit 0
fi

if (( WARNING_CHARGE != 0 && CRITICAL_CHARGE >= WARNING_CHARGE )); then
    emit_error "UPS: Invalid charge threshold config. CRITICAL_CHARGE must be lower than WARNING_CHARGE, or WARNING_CHARGE must be 0."
    exit 0
fi

# --- Fetch all fields in one call -----------------------------------------

if ! RAW=$(apcaccess 2>&1); then
    APCACCESS_ERROR=$RAW
    RAW=""
else
    APCACCESS_ERROR=""
fi

if [[ -z "$RAW" ]]; then
    if [[ -n "$APCACCESS_ERROR" ]]; then
        emit_error "UPS: Cannot query apcupsd"$'\n'"${APCACCESS_ERROR}"
        exit 0
    fi

    emit_error "UPS: apcaccess returned no status data"
    exit 0
fi

STATUS=""
BCHARGE=""
LOADPCT=""
TIMELEFT=""
LINEV=""
HAS_STATUS_FIELD=0

while IFS=$'\t' read -r key value; do
    case "$key" in
        STATUS)
            STATUS=$value
            HAS_STATUS_FIELD=1
            ;;
        BCHARGE) BCHARGE=$value ;;
        LOADPCT) LOADPCT=$value ;;
        TIMELEFT) TIMELEFT=$value ;;
        LINEV) LINEV=$value ;;
    esac
done < <(
    awk -F':' '
        $1 ~ /^ *(STATUS|BCHARGE|LOADPCT|TIMELEFT|LINEV) *$/ {
            key = $1
            value = substr($0, index($0, ":") + 1)
            gsub(/^ +| +$/, "", key)
            gsub(/^ +| +$/, "", value)
            print key "\t" value
        }
    ' <<< "$RAW"
)

if (( HAS_STATUS_FIELD == 0 )); then
    emit_error "UPS: apcaccess returned malformed status data (missing STATUS field)"
    exit 0
fi

# Strip units (e.g. "100.0 Percent" -> "100.0")
BCHARGE=${BCHARGE%% *}
LOADPCT=${LOADPCT%% *}
TIMELEFT=${TIMELEFT%% *}
LINEV=${LINEV%% *}

# Integer charge for percentage output
CHARGE_RAW=$BCHARGE
CHARGE_INT=0
CHARGE_VALID=0
if [[ "$BCHARGE" =~ ^-?[0-9]+([.][0-9]+)?$ ]]; then
    CHARGE_INT=${BCHARGE%%.*}
    CHARGE_VALID=1
    if [[ "$CHARGE_INT" == -* ]]; then
        CHARGE_INT=0
    else
        CHARGE_INT=$((10#$CHARGE_INT))
        if (( CHARGE_INT > 100 )); then
            CHARGE_INT=100
        fi
    fi
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
    if (( CHARGE_VALID == 1 && CRITICAL_CHARGE != 0 && CHARGE_INT <= CRITICAL_CHARGE )); then
        CLASS="critical"
        WARNINGS+=("Battery charge at or below critical threshold")
    elif (( CHARGE_VALID == 1 && WARNING_CHARGE != 0 && CHARGE_INT <= WARNING_CHARGE )); then
        CLASS="warning"
        WARNINGS+=("Battery charge at or below warning threshold")
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

if (( CHARGE_VALID == 0 )); then
    INFO_MESSAGES+=("Battery charge unavailable.")
fi

if [[ -n "$ALT_OVERRIDE" ]]; then
    ALT=$ALT_OVERRIDE
fi

# --- Debug logging (level 2: always) --------------------------------------
[[ "$DEBUG" -eq 2 ]] && debug_log

# --- Build output ---------------------------------------------------------

if [[ -n "$FALLBACK_TEXT" ]]; then
    TEXT=$FALLBACK_TEXT
elif (( CHARGE_VALID == 1 )); then
    TEXT="${CHARGE_INT}%"
else
    TEXT="$TEXT_UNKNOWN"
fi

TOOLTIP=""

append_tooltip_line() {
    local line=$1

    if [[ -n "$TOOLTIP" ]]; then
        TOOLTIP+=$'\n'
    fi

    TOOLTIP+="$line"
}

# Tooltip with full details
# Note: ⚠ is U+26A0 (Warning Sign), ℹ is U+2139 (Information Source)
for warning in "${WARNINGS[@]}"; do
    append_tooltip_line "⚠ ${warning}"
done
for info in "${INFO_MESSAGES[@]}"; do
    append_tooltip_line "ℹ ${info}"
done
append_tooltip_line "Status: ${STATUS}"
if (( CHARGE_VALID == 1 )); then
    append_tooltip_line "Battery: ${CHARGE_INT}%"
elif [[ -n "$CHARGE_RAW" ]]; then
    append_tooltip_line "Battery: ${CHARGE_RAW}"
else
    append_tooltip_line "Battery: unavailable"
fi
append_tooltip_line "Load: ${LOADPCT}%"
append_tooltip_line "Runtime: ${TIMELEFT} min"
append_tooltip_line "Line: ${LINEV} V"

TEXT=$(json_escape "$TEXT")
TOOLTIP=$(json_escape "$TOOLTIP")

printf '{"text": "%s", "alt": "%s", "tooltip": "%s", "class": "%s", "percentage": %d}\n' \
    "$TEXT" "$ALT" "$TOOLTIP" "$CLASS" "$CHARGE_INT"
