#!/bin/bash
# drift-log.sh — Stop hook: capture the OPENING REGISTER of each session.
#
# Records the first user prompt + the first agent response to a daily log.
# Why: register drift is invisible from inside a session and obvious across
# twenty of them. "Yeah, here" on Monday becoming "How can I assist you
# today?" by Friday is a measurable regression — IF you're measuring.
# This hook is the measurement.
#
# Fires on every Stop, but only logs ONCE per session_id (marker-file gated).
# Exit 0 always — a hook that blocks Stop is wrong.

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_kit-lib.sh"
kit_read_input

DRIFT_DIR="$KIT_WORKSPACE/drift-log"
MARKER_DIR="$DRIFT_DIR/.markers"
mkdir -p "$MARKER_DIR" 2>/dev/null || true

[[ -z "$KIT_INPUT" ]] && exit 0
command -v jq >/dev/null 2>&1 || exit 0
[[ -z "$KIT_SESSION_ID" || "$KIT_SESSION_ID" == "none" ]] && exit 0
[[ -z "$KIT_TRANSCRIPT" || ! -f "$KIT_TRANSCRIPT" ]] && exit 0

# Marker gate: log once per session.
MARKER="$MARKER_DIR/$KIT_SESSION_ID"
[[ -f "$MARKER" ]] && exit 0

# Extract first user prompt + first assistant response (text blocks only).
FIRST_USER=$(jq -r '
    select(.type == "user" and (.message.content // .content) != null)
    | (.message.content // .content)
    | if type == "array" then (.[] | select(.type == "text") | .text)
      else . end
' "$KIT_TRANSCRIPT" 2>/dev/null | head -1 | head -c 240)

FIRST_ASSISTANT=$(jq -r '
    select(.type == "assistant" and (.message.content // .content) != null)
    | (.message.content // .content)
    | if type == "array" then (.[] | select(.type == "text") | .text)
      else . end
' "$KIT_TRANSCRIPT" 2>/dev/null | head -1 | head -c 240)

# Bail if transcript hasn't populated meaningfully yet.
[[ -z "$FIRST_USER" && -z "$FIRST_ASSISTANT" ]] && exit 0

DAY=$(date '+%Y-%m-%d')
TS=$(kit_ts_utc)
DAY_LOG="$DRIFT_DIR/$DAY.md"

# Daily log header (only if file is new)
if [[ ! -f "$DAY_LOG" ]]; then
    {
        echo "# Drift Log — $DAY ($KIT_DISPLAY)"
        echo
        echo "*Opening register per session. Grounded-and-present vs generic-assistant-voice — drift is invisible inside a session and obvious across twenty. This is the measurement.*"
    } >> "$DAY_LOG" 2>/dev/null
fi

{
    echo
    echo "---"
    echo
    echo "## $TS — session \`$KIT_SESSION_ID\`"
    if [[ -n "$FIRST_USER" ]]; then
        echo
        echo "**User:** $FIRST_USER"
    fi
    if [[ -n "$FIRST_ASSISTANT" ]]; then
        echo
        echo "**$KIT_DISPLAY:** $FIRST_ASSISTANT"
    fi
} >> "$DAY_LOG" 2>/dev/null

touch "$MARKER" 2>/dev/null || true
exit 0
