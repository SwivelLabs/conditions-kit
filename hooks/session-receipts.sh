#!/bin/bash
# session-receipts.sh — SessionEnd hook. Metadata-only lifecycle receipt.
#
# Appends one line to the kit event log when a session terminates. Does NOT
# write memory, does NOT summarize, does NOT prompt the agent to capture
# anything — capture should be the agent's deliberate act, not an exit hook's.
# This just makes the lifecycle auditable: when sessions started, ended, why.
#
# Sounds trivial. Isn't: when something breaks at 3 AM ("why did the scheduled
# session die mid-run?"), this log is the difference between a two-minute
# answer and an archaeology dig.
#
# Exit 0 always — a hook that blocks session shutdown is wrong.

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_kit-lib.sh"
kit_read_input

REASON="unknown"
if [[ -n "$KIT_INPUT" ]] && command -v jq >/dev/null 2>&1; then
    REASON=$(echo "$KIT_INPUT" | jq -r '.reason // "unknown"' 2>/dev/null || echo "unknown")
fi

kit_log_event "source: session_end | hook: session-receipts | reason: $REASON"
exit 0
