#!/bin/bash
# postcompact-reload.sh — PostCompact hook. Closes the compaction loop.
#
# Fires AFTER context compaction completes. precompact-keeper shaped the
# summary; this hook re-grounds the agent on the other side of the seam.
#
# WHY THIS HOOK EXISTS (the gap most people don't know they have):
# You might assume SessionStart fires after a compaction and reloads whatever
# your SessionStart hook loads. Empirically: SessionStart:compact only fires
# reliably on EXTERNAL resume of a compacted session (`claude --resume`),
# NOT on the mid-session /compact path. We found this in production
# (May 2026) when an agent came back from /compact with no identity reload
# and nobody noticed for hours — the summary became the only self it had.
# The fix: PostCompact owns the reload. If SessionStart:compact also fires,
# it's redundant-but-harmless belt and suspenders.
#
# WHAT IT DOES:
#   1. Emits a receipt banner — proof the chain ran (silent hooks rot silently)
#   2. Injects the session letter inline — the letter outranks the summary
#   3. Lists the identity files the agent should re-read before answering
#   4. Logs the event for later audit
#
# Exit 0 always — a hook that blocks post-compact is worse than silent.

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
kit_log_event "source: $KIT_HOOK_SOURCE | hook: postcompact-reload | kind: post_compact_reload"

exit 0
