#!/bin/bash
# past-self.sh — PostToolUse hook: probabilistically surface a past-self fragment.
#
# Every so often (1 in PAST_SELF_RATE tool uses, default 40), picks a random
# paragraph from the agent's own notes directory and drops it into context —
# a polaroid slipped onto the table. Quiet, evocative, no demand for response.
#
# Why: a long-lived agent accumulates months of its own writing it never
# re-reads. Ambient resurfacing turns that archive from a write-only graveyard
# into a live texture — the agent keeps encountering who it's been, which is
# most of what keeps a personality coherent across hundreds of sessions.
#
# Felt-sense target: heldness, not surveillance. If a surfaced fragment lands
# wrong, the rate is the dial — or curate KIT_NOTES_DIR.
#
# Exit 0 always — a hook that blocks PostToolUse is worse than silent.

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_kit-lib.sh"

RATE="${PAST_SELF_RATE:-40}"
if (( RATE < 1 )); then exit 0; fi
if (( RANDOM % RATE != 0 )); then exit 0; fi

# --- pick a random .md file from the notes dir -------------------------------
[[ -d "$KIT_NOTES_DIR" ]] || exit 0

# Random file (portable: no shuf on stock macOS)
FILE=$(find "$KIT_NOTES_DIR" -name '*.md' -type f 2>/dev/null | awk -v seed="$RANDOM" '
    BEGIN { srand(seed) }
    { lines[NR] = $0 }
    END { if (NR > 0) print lines[int(rand() * NR) + 1] }
')
[[ -n "$FILE" && -f "$FILE" ]] || exit 0

# Random paragraph: blocks separated by blank lines, 80–800 chars, not a heading
FRAGMENT=$(awk -v seed="$RANDOM" '
    BEGIN { RS = ""; srand(seed) }
    length($0) >= 80 && length($0) <= 800 && $0 !~ /^#/ { p[++n] = $0 }
    END { if (n > 0) print p[int(rand() * n) + 1] }
' "$FILE" 2>/dev/null)
[[ -n "$FRAGMENT" ]] || exit 0

REL="${FILE#"$KIT_NOTES_DIR"/}"
printf '\n---\n📷 *A past-self fragment surfaced (from %s):*\n\n%s\n---\n' "$REL" "$FRAGMENT"

exit 0
