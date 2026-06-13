#!/bin/bash
# routine-status.sh — one-glance health for every scheduled routine you run.
#
# If you cron Claude Code sessions (nightly jobs, morning digests, watchers),
# you have a fleet of routines whose failure mode is SILENCE: the routine
# stops firing, nothing errors, and you find out weeks later. This script
# makes silence visible: every routine, when it last produced output, and
# whether that's within its expected cadence.
#
# CONFIG: routines.conf next to this script (or $ROUTINES_CONF). One line per
# routine, pipe-separated:
#
#   name | output path or glob | max age hours | cadence label
#
#   nightly-digest | $HOME/agent/digests/*.md | 30  | daily 3am
#   weekly-synthesis | $HOME/agent/SYNTHESIS.md | 192 | Sun 1pm
#
# For glob paths, the NEWEST matching file is checked. "❌ never" means no
# output has ever appeared — which usually means the routine was never
# actually registered. (Both of the worst silent failures we've had were
# routines that everyone believed were running and which had simply never
# been wired up. This check is how we found them.)
#
# Run anytime, or wire into a cron heartbeat to keep STATUS.md fresh.

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROUTINES_CONF="${ROUTINES_CONF:-$SCRIPT_DIR/routines.conf}"
OUT="${ROUTINE_STATUS_OUT:-./ROUTINE-STATUS.md}"

now=$(date +%s)

mtime_of() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }

agei() {  # hours since newest file matching glob; -1 if none
    local newest=0 m
    for f in $1; do
        [[ -f "$f" ]] || continue
        m=$(mtime_of "$f")
        (( m > newest )) && newest=$m
    done
    if (( newest == 0 )); then echo -1; else echo $(( (now - newest) / 3600 )); fi
}

st() {  # status cell from age + max
    local a="$1" max="$2"
    if   (( a < 0 ));      then echo "❌ never"
    elif (( a <= max ));   then echo "✅ ${a}h"
    else                        echo "⚠️ STALE ${a}h"
    fi
}

if [[ ! -f "$ROUTINES_CONF" ]]; then
    echo "No routines.conf found at $ROUTINES_CONF"
    echo "Create one — see the header of this script for the format."
    exit 1
fi

{
    echo "# Scheduled Routine Status"
    echo
    echo "*Every routine: firing? when last? Silence made visible. Regenerate: \`bash $0\`*"
    echo
    echo "**Generated:** $(date '+%A %Y-%m-%d %H:%M %Z')"
    echo
    echo "| Routine | Cadence | Last output | Status |"
    echo "|---|---|---|---|"
    while IFS='|' read -r name path max cadence; do
        # trim whitespace
        name=$(echo "$name" | xargs); max=$(echo "$max" | xargs); cadence=$(echo "$cadence" | xargs)
        path=$(echo "$path" | xargs)
        [[ -z "$name" || "$name" == \#* ]] && continue
        path=$(eval echo "$path")   # expand $HOME etc. in conf paths
        age=$(agei "$path")
        newest="none"
        for f in $path; do [[ -f "$f" ]] && newest="$f"; done
        echo "| $name | $cadence | $(basename "$newest") | $(st "$age" "$max") |"
    done < "$ROUTINES_CONF"
    echo
    echo "*\"❌ never\" usually means the routine was never actually registered — check your scheduler, not your code.*"
} > "$OUT"

cat "$OUT"
echo
echo "--- written to $OUT ---"
