#!/bin/bash
# identity-audit.sh — PostToolUse hook: paper trail on identity-file edits.
#
# Logs any write that touches your agent's identity files. Does NOT block —
# agents may legitimately evolve their own identity files over time — but
# silent drift becomes auditable. If your agent's personality changed last
# Tuesday, this log tells you whether a file edit was involved.
#
# v2 NOTE — THE BASH SIDE-DOOR (found in production, June 2026): v1 matched
# only Edit/Write tool calls. `sed -i`, `echo >>`, and `tee` via the Bash tool
# walked right past the audit for weeks. v2 also inspects Bash commands for
# watched basenames combined with write-shaped operations. False positives are
# acceptable — this is a paper trail, not a gate.
#
# Requires settings.json PostToolUse matcher: "Edit|Write|Bash".
# Watched basenames come from KIT_IDENTITY_FILES in conditions-kit.conf.
#
# Exit 0 always (non-blocking).

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_kit-lib.sh"
kit_read_input

if ! command -v jq >/dev/null 2>&1 || [[ -z "$KIT_INPUT" ]]; then
    exit 0
fi

AUDIT_LOG="$KIT_WORKSPACE/.identity-audit.log"

audit_row() {
    mkdir -p "$(dirname "$AUDIT_LOG")" 2>/dev/null || true
    echo "$(kit_ts_utc) | $KIT_AGENT | session=$KIT_SESSION_ID | $1" >> "$AUDIT_LOG" 2>/dev/null || true
}

# Build an alternation pattern from the watched list: "A.md|B.md|C.md"
WATCH_PATTERN=$(echo "$KIT_IDENTITY_FILES" | tr ' ' '\n' | sed 's/\./\\./g' | paste -sd'|' -)
[[ -z "$WATCH_PATTERN" ]] && exit 0

# --- Edit / Write path -------------------------------------------------------
FILE=$(echo "$KIT_INPUT" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
if [[ -n "$FILE" ]]; then
    BASENAME=$(basename "$FILE")
    if echo "$BASENAME" | grep -qE "^(${WATCH_PATTERN})$"; then
        audit_row "$KIT_TOOL_NAME on $FILE"
    fi
    exit 0
fi

# --- Bash side-door (v2) -----------------------------------------------------
if [[ "$KIT_TOOL_NAME" == "Bash" ]]; then
    CMD=$(echo "$KIT_INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null)
    if [[ -n "$CMD" ]]; then
        # Watched basename mentioned AND a write-shaped operation present?
        if echo "$CMD" | grep -qE "(${WATCH_PATTERN})" \
           && echo "$CMD" | grep -qE '(>>?|sed[[:space:]]+-i|tee[[:space:]]|mv[[:space:]]|cp[[:space:]]|rm[[:space:]]|truncate|dd[[:space:]])'; then
            EXCERPT=$(echo "$CMD" | head -c 200 | tr '\n' ' ')
            audit_row "Bash write-shaped command touching identity file: ${EXCERPT}"
        fi
    fi
fi

exit 0
