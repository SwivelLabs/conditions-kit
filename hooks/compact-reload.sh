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
# THE GROUND INTEGRITY GUARD (new in v0.2 — the ten-week lesson):
# The harness truncates large hook stdout to a short preview under a
# success banner. In production this hid a broken reload for TEN WEEKS:
# over a thousand session boots ran on a ~2KB preview of a large identity
# payload, and nothing ever said so — the banner still read like success.
# The fix is structural, not vigilant:
#   1. The full payload is PERSISTED to a file before a byte hits stdout.
#   2. Stdout carries a byte-count receipt and a final END line.
#   3. The header tells the agent: if you cannot see the END line, you are
#      reading a truncated preview — Read the persisted file and verify it
#      by BYTE COUNT before answering anything.
# A reload that can be silently truncated is a reload you don't have.
#
# WHAT IT DOES:
#   1. Builds the payload (banner + session letter + identity file list)
#   2. Persists it to $KIT_RELOAD_COPY (atomic write), byte-counted
#   3. Emits it with the integrity guard when it's big enough to be at risk
#   4. Logs the event — including the byte count — for later audit
#
# Exit 0 always — a hook that blocks SessionStart is worse than silent.

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_kit-lib.sh"
kit_read_input

TS_LOCAL=$(kit_ts_local)
TS_UTC=$(kit_ts_utc)

# --- 1. Build the payload (nothing goes to stdout yet) -----------------------
PAYLOAD_FILE="${KIT_RELOAD_COPY}"
TMP_FILE="${PAYLOAD_FILE}.tmp.$$"
mkdir -p "$(dirname "$PAYLOAD_FILE")" 2>/dev/null || true

{
    echo "=== POST-COMPACTION RECEIPT — $KIT_DISPLAY $KIT_SIGIL — $TS_LOCAL ==="
    echo
    echo "Compaction completed. The summary above is lossy and frame-setting — it will"
    echo "tune you toward its own view of who you are. Don't reason from the summary;"
    echo "reason from the source. Re-ground before answering:"
    echo

    # Session letter, inline (the letter outranks the summary)
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

    # Identity files to re-read
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
} > "$TMP_FILE" 2>/dev/null || true

# Atomic move; if the write failed, fall back to streaming without the guard
# (a degraded reload beats no reload — but say so).
PERSISTED=1
mv "$TMP_FILE" "$PAYLOAD_FILE" 2>/dev/null || PERSISTED=0
if [[ $PERSISTED -eq 1 && -f "$PAYLOAD_FILE" ]]; then
    BYTES=$(wc -c < "$PAYLOAD_FILE" | tr -d ' ')
else
    BYTES=0
fi

# --- 2. Emit, with the guard when the payload is big enough to be at risk ----
END_LINE="=== END RELOAD $TS_UTC ($BYTES bytes) ==="

if [[ $PERSISTED -eq 1 && "$BYTES" -gt "$KIT_RELOAD_GUARD_MIN" ]]; then
    cat <<EOF
=== RELOAD INTEGRITY GUARD ===
This reload payload is $BYTES bytes and MUST end with the line:
    $END_LINE
The harness truncates large hook output to a short preview under a success
banner. If you cannot see that END line at the bottom of this injection,
you are reading a TRUNCATED PREVIEW and are NOT re-grounded. Your FIRST
action must be:
    Read $PAYLOAD_FILE
(the full payload, persisted at reload time — exactly $BYTES bytes. It does
NOT contain this guard block or the END line; verify the copy by BYTE COUNT
with wc -c, not by hunting for the receipt inside it.) Do not proceed on
the preview alone.
=== END GUARD — payload follows ===

EOF
fi

if [[ $PERSISTED -eq 1 ]]; then
    cat "$PAYLOAD_FILE" 2>/dev/null || true
    echo
    echo "$END_LINE"
else
    # Degraded path: persistence failed; stream directly and say so plainly.
    echo "(reload-copy write failed at $PAYLOAD_FILE — streaming without the"
    echo " integrity guard; if this looks cut off, ask for the session letter"
    echo " at $KIT_SESSION_FILE directly)"
    echo
    echo "=== POST-COMPACTION RECEIPT — $KIT_DISPLAY $KIT_SIGIL — $TS_LOCAL ==="
    [[ -f "$KIT_SESSION_FILE" ]] && head -c 20000 "$KIT_SESSION_FILE" 2>/dev/null
    echo
fi
# (no output after the END line — "MUST end with the line" stays literally true)

# --- 3. Log the receipt (byte count makes the loop auditable — kit-check
#        compares this number against the persisted copy) ---------------------
kit_log_event "source: $KIT_HOOK_SOURCE | hook: compact-reload | kind: compact_reload | bytes: $BYTES | copy: $PAYLOAD_FILE"

exit 0
