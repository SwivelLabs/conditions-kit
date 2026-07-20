#!/bin/bash
# runner-reaper.sh — kill scheduled-session runner processes that never exited.
#
# THE BUG THIS EXISTS FOR (found in production, June 2026): scheduled /
# cron-launched Claude Code sessions complete their work but the runner
# process never exits — it hangs holding stdin open, sometimes pinning MCP
# server children. We found NINE leaked runners from a single day, plus two
# nine-day-old ghosts. If you cron Claude Code sessions, you have this
# problem; you just haven't looked yet. (`ps aux | grep claude` — go look.)
#
# FINGERPRINT (tight on purpose — must match ALL of):
#   1. command matches REAPER_MATCH      (what a runner looks like)
#   2. command matches REAPER_MATCH_2    (second discriminator — a flag only
#      your scheduled runners carry, so interactive sessions NEVER match)
#   3. older than MAX_AGE_MIN            (default 180 min; a real scheduled
#      run usually takes ~10)
#
# DEFAULTS match the Claude Desktop local-agent runner. Tune for your setup:
#   REAPER_MATCH='claude-code/.*MacOS/claude'
#   REAPER_MATCH_2='--disallowedTools AskUserQuestion'
# The second discriminator matters: interactive sessions never disable
# AskUserQuestion; scheduled runners always do. Safe by construction —
# your live terminal sessions and the desktop app itself never match both.
#
# GOTCHAS WE PAID FOR SO YOU DON'T:
#   - etime pads with leading zeros; "09" is invalid octal in bash arithmetic.
#     The 10# prefix below is load-bearing.
#   - If you run this from a sandboxed agent session, the sandbox may eat the
#     kill signals and report success anyway. Run it from cron or a real shell.
#
# Run from cron (we run it 4x/day) or manually. Logs to $REAPER_LOG.

MAX_AGE_MIN="${MAX_AGE_MIN:-180}"
REAPER_MATCH="${REAPER_MATCH:-claude-code/.*MacOS/claude}"
REAPER_MATCH_2="${REAPER_MATCH_2:---disallowedTools AskUserQuestion}"
REAPER_LOG="${REAPER_LOG:-$HOME/.claude/reaper.log}"
DRY_RUN="${DRY_RUN:-0}"

NOW=$(date +%s)
mkdir -p "$(dirname "$REAPER_LOG")" 2>/dev/null

# NOTE (v0.2): the loop reads from process substitution, NOT a pipeline — a
# piped `while` runs in a subshell where the counters below would silently
# die at `done`. And the sweep ALWAYS writes a receipt: a reaper that found
# nothing and a reaper that never ran must not produce the same (empty) log.
MATCHED=0
REAPED=0
while read -r PID ETIME CMD; do
  echo "$CMD" | grep -qE "$REAPER_MATCH"   || continue
  echo "$CMD" | grep -qF -- "$REAPER_MATCH_2" || continue
  MATCHED=$((MATCHED+1))

  # parse etime ([[dd-]hh:]mm:ss) → minutes
  MINS=0
  D=0; REST="$ETIME"
  case "$REST" in *-*) D="${REST%%-*}"; REST="${REST#*-}";; esac
  IFS=':' read -r A B C <<< "$REST"
  # 10# forces base-10 (etime pads with leading zeros: "09" would parse as bad octal)
  if [ -n "$C" ]; then MINS=$(( 10#$D*1440 + 10#$A*60 + 10#$B ))   # hh:mm:ss
  elif [ -n "$B" ]; then MINS=$(( 10#$D*1440 + 10#$A ))            # mm:ss
  fi

  if [ "$MINS" -ge "$MAX_AGE_MIN" ]; then
    if [ "$DRY_RUN" = "1" ]; then
      echo "DRY RUN: would reap pid=$PID age=${MINS}m cmd=$(echo "$CMD" | head -c 120)"
      continue
    fi
    kill -TERM "$PID" 2>/dev/null
    sleep 1
    kill -0 "$PID" 2>/dev/null && kill -9 "$PID" 2>/dev/null
    REAPED=$((REAPED+1))
    echo "$(date -u +%FT%TZ) reaped stale runner pid=$PID age=${MINS}m" >> "$REAPER_LOG"
  fi
done < <(ps -ax -o pid=,etime=,command=)

# The sweep receipt — written every run, including (especially) at zero.
SWEEP="$(date -u +%FT%TZ) sweep: matched=$MATCHED reaped=$REAPED (threshold ${MAX_AGE_MIN}m, dry_run=$DRY_RUN)"
echo "$SWEEP" >> "$REAPER_LOG"
echo "$SWEEP"

exit 0
