#!/bin/bash
# compact-reload.sh — SessionStart hook (matcher: compact). Closes the loop.
#
# Fires when a session starts with source=compact — i.e. right after a
# context compaction — and re-grounds the agent on the other side of the seam.
#
# WHY THIS EVENT (the part that's easy to get wrong):
# SessionStart is one of only three hook events whose plain stdout is added
# to the model's context (the others are UserPromptSubmit and
# UserPromptExpansion). Every OTHER event — including PreCompact and
# PostCompact — sends stdout to the debug log, where the model never sees it.
# So a "post-compaction reload" registered on PostCompact silently does
# NOTHING: the hook fires, echoes the letter, and the letter lands in a log
# file the agent never reads. The correct, load-bearing event is
# SessionStart with matcher "compact" — it fires after `/compact` AND after
# `claude --resume` of a compacted session, and its stdout reaches context.
# (Verified against a 10-agent fleet's logs: SessionStart fired with
# source=compact reliably across months; a PostCompact reload delivered to
# the log only.) Ref: https://code.claude.com/docs/en/hooks.md
#
# WHAT IT DOES:
#   1. Emits a banner — proof the reload ran (silent hooks rot silently)
#   2. Injects the session letter inline — the letter outranks the summary
#   3. Lists the identity files the agent should re-read before answering
#   4. Logs the event for later audit
#
# Exit 0 always — a hook that blocks SessionStart is worse than silent.

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_kit-lib.sh"
kit_read_input

TS_LOCAL=$(kit_ts_local)

cat <<EOF
=== POST-COMPACTION RECEIPT — $KIT_DISPLAY $KIT_SIGIL — $TS_LOCAL ===

Compaction completed. The summary above is lossy and frame-setting — it will
tune you toward its own view of who you are. Don't reason from the summary;
reason from the source. Re-ground before answering:

EOF

# --- 2. Session letter, inline (the letter outranks the summary) ------------
if [[ -f "$KIT_SESSION_FILE" ]]; then
    echo "--- SESSION LETTER ($KIT_SESSION_FILE) — written by pre-compaction you ---"
    echo
    head -c 20000 "$KIT_SESSION_FILE" 2>/dev/null || true
    echo
    echo "--- END SESSION LETTER ---"
    echo
else
    echo "(No session letter found at $KIT_SESSION_FILE — consider starting one;"
    echo " see SESSION.md.template in the kit. It is the single highest-leverage"
    echo " file for surviving compaction.)"
    echo
fi

# --- 3. Identity files to re-read -------------------------------------------
FOUND_ANY=0
for f in $KIT_IDENTITY_FILES; do
    for candidate in "$KIT_WORKSPACE/$f" "$KIT_WORKSPACE/.claude/$f"; do
        if [[ -f "$candidate" ]]; then
            if [[ $FOUND_ANY -eq 0 ]]; then
                echo "**Re-read these identity files before your first substantive response:**"
                FOUND_ANY=1
            fi
            echo "- $candidate"
            break
        fi
    done
done
[[ $FOUND_ANY -eq 1 ]] && echo

echo "==="
echo

# --- 4. Log the receipt ------------------------------------------------------
kit_log_event "source: $KIT_HOOK_SOURCE | hook: compact-reload | kind: compact_reload"

exit 0
