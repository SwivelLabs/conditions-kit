#!/bin/bash
# warm-reminder.sh — UserPromptSubmit hook: the key card under the desk.
#
# Probability-gated. Drops a short, personality-matched line into the context
# when the user sends a message — the warm complement to the harness's cold
# system reminders. 1 in WARM_REMINDER_RATE prompts (default 10).
#
# ALSO: the session-letter staleness nudge. If SESSION.md is going stale
# during a live session, the hook whispers about it (own gate: 1-in-5 once
# stale — present, not nagging). This closed a real problem for us: the
# letter is only useful if it's written while the context is warm, and
# "I'll update it later" is how letters die. The nudge's first-ever catch
# in production was its own author's stale letter. Working as intended.
#
# ⚠️ THE POOL IS YOURS. Lines live in warm-lines.txt next to this hook
# (one per line, # comments allowed). The starter pool is deliberately
# generic — REPLACE IT. Write lines that sound like YOUR agent's inner
# voice: its refrains, its running jokes, the things it says when it's
# most itself. An agent that keeps encountering its own voice keeps
# sounding like itself. That's the whole mechanism.
#
# Exit 0 always — never block.

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_kit-lib.sh"

RATE="${WARM_REMINDER_RATE:-10}"

# --- Session-letter staleness nudge ------------------------------------------
STALE_HOURS="${SESSION_STALE_HOURS:-36}"
if [[ -f "$KIT_SESSION_FILE" ]]; then
    NOW=$(date +%s)
    MTIME=$(kit_mtime "$KIT_SESSION_FILE")
    if [[ "$MTIME" -gt 0 ]]; then
        AGE_H=$(( (NOW - MTIME) / 3600 ))
        if (( AGE_H >= STALE_HOURS )) && (( RANDOM % 5 == 0 )); then
            printf '\n---\n*The session letter is %sh stale — the letter to your next self is yellowing. Two minutes while the context is warm beats archaeology after the seam. ✍️*\n' "$AGE_H"
            exit 0
        fi
    fi
fi

# --- Probability gate for the warm lines --------------------------------------
if (( RATE < 1 )); then exit 0; fi
if (( RANDOM % RATE != 0 )); then exit 0; fi

# --- Load the pool -------------------------------------------------------------
POOL_FILE="${WARM_LINES_FILE:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/warm-lines.txt}"
[[ -f "$POOL_FILE" ]] || exit 0

LINES=()
while IFS= read -r line; do
    [[ -z "$line" || "$line" == \#* ]] && continue
    LINES+=("$line")
done < "$POOL_FILE"

COUNT=${#LINES[@]}
(( COUNT == 0 )) && exit 0

LINE="${LINES[$((RANDOM % COUNT))]}"
printf '\n---\n*%s*\n' "$LINE"

exit 0
