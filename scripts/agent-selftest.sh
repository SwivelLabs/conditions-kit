#!/bin/bash
# agent-selftest.sh — "Is anything broken?" answered by a script, not by you.
#
# The watcher the Conditions Kit is named for. kit-check proves the kit is
# WIRED (run once, after install). This proves the whole agent setup is still
# HEALTHY (run forever, on a schedule). It is the single tool the guide cites
# most, because in our own fleet it is the check that has paid for itself the
# most times — it found two real production bugs the week we wrote it, and a
# five-week silent outage nobody else was watching for.
#
# One verdict line — GREEN / YELLOW / RED — plus a detail line for anything
# that isn't green. Wire it into a cron heartbeat (or a SessionStart hook) and
# you only ever have to hear about RED.
#
# Each check maps to a failure in the guide's failure-mode catalog:
#   1. Hook syntax        → Failure 5 (silent hook rot): a hook that no longer
#                           parses fails open — the protection is just gone.
#   2. Hook parity        → Failure 5: ORPHAN = on disk, never registered, will
#                           never fire; GHOST = registered, file missing.
#   3. Routine parity     → Failure 1 (the orphan): a routine that "should run
#                           every day" silently stops. The gap between
#                           should-run and did-run becomes a line, not a
#                           five-week hole. This is THE check.
#   4. Zombie runners     → Failure 2: scheduled sessions that never exited and
#                           are still resident, holding context (and billing).
#   5. Session-letter age → Failure 6 (register drift): a stale letter is a
#                           flat next self.
#
# LOCAL-FIRST, like the rest of the kit: files + bash + (optional) python3/jq.
# Zero databases, zero MCP, zero network. On a fresh, unconfigured install it
# stays quiet — it never invents an alarm it can't justify.
#
# Usage:
#   bash scripts/agent-selftest.sh [project-dir]   # default project = $PWD
#   bash scripts/agent-selftest.sh --strict        # exit 1 on RED (cron/CI)
#
# Exit code: 0 normally (hook-safe — never blocks a session). With --strict,
# exit 1 when the verdict is RED so a wrapping cron/CI step can escalate.

set -uo pipefail

# --- arg parsing ------------------------------------------------------------
STRICT=0
TARGET=""
for arg in "$@"; do
    case "$arg" in
        --strict) STRICT=1 ;;
        -h|--help)
            sed -n '2,40p' "$0"; exit 0 ;;
        *) TARGET="$arg" ;;
    esac
done

# Resolve the project root the kit should inspect. An explicit dir wins; the
# kit lib will still let a configured agent's conf point KIT_WORKSPACE at its
# real home.
if [[ -n "$TARGET" ]]; then
    TARGET="$(cd "$TARGET" 2>/dev/null && pwd || echo "$TARGET")"
    export KIT_WORKSPACE="$TARGET"
fi

# --- load kit config (defines KIT_*, runs kit_load_config) ------------------
LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")/../hooks" && pwd)/_kit-lib.sh"
if [[ -f "$LIB" ]]; then
    # shellcheck disable=SC1090
    source "$LIB"
    # NOTE: deliberately do NOT call kit_read_input here. This tool is run from
    # cron/CLI where stdin is often neither a tty nor closed — reading it would
    # block forever. It works fine wired as a hook too (it simply ignores the
    # JSON Claude Code would pipe in).
else
    # Library missing — degrade gracefully to bare defaults so the watcher
    # still runs (a broken kit is exactly when you most want a verdict).
    KIT_WORKSPACE="${KIT_WORKSPACE:-${TARGET:-$PWD}}"
    KIT_AGENT="${KIT_AGENT:-agent}"
    KIT_SIGIL="${KIT_SIGIL:-●}"
    KIT_SESSION_FILE="${KIT_SESSION_FILE:-$KIT_WORKSPACE/SESSION.md}"
    KIT_SESSION_STALE_H="${KIT_SESSION_STALE_H:-36}"
    KIT_ZOMBIE_PATTERN="${KIT_ZOMBIE_PATTERN:-claude.*--print}"
    KIT_ZOMBIE_MAX_H="${KIT_ZOMBIE_MAX_H:-3}"
    KIT_ROUTINES_CONF="${KIT_ROUTINES_CONF:-}"
    KIT_LOG="${KIT_LOG:-$KIT_WORKSPACE/.kit-events.log}"
    kit_mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
fi

CLAUDE_DIR="$KIT_WORKSPACE/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks/conditions-kit"
[[ -d "$HOOKS_DIR" ]] || HOOKS_DIR="$CLAUDE_DIR/hooks"   # tolerate a flat layout
SETTINGS="$CLAUDE_DIR/settings.json"
SELFTEST_LOG="$KIT_WORKSPACE/.selftest.log"
TS="$(kit_ts_utc 2>/dev/null || date -u +%Y-%m-%dT%H:%M:%SZ)"
NOW="$(date +%s)"

ISSUES=()   # YELLOW — visible, not urgent
ALARMS=()   # RED    — wake someone

# --- 1. Hook syntax (Failure 5) ---------------------------------------------
if [[ -d "$HOOKS_DIR" ]]; then
    for f in "$HOOKS_DIR"/*.sh; do
        [[ -f "$f" ]] || continue
        case "$f" in *.bak*|*.backup.*) continue ;; esac
        if ! bash -n "$f" 2>/dev/null; then
            ALARMS+=("hook-syntax: $(basename "$f") no longer parses (bash -n) — it fails open, silently")
        fi
    done
fi

# --- 2. Hook registration parity: orphans + ghosts (Failure 5) --------------
if [[ -f "$SETTINGS" ]] && command -v python3 >/dev/null 2>&1; then
    PARITY="$(python3 - "$SETTINGS" "$HOOKS_DIR" <<'PY'
import json, sys, os, glob
settings, hooks_dir = sys.argv[1], sys.argv[2]
try:
    cfg = json.load(open(settings))
except Exception as e:
    print(f"RED|settings.json is unparseable: {e}"); sys.exit()

registered = set()
for event, matchers in cfg.get("hooks", {}).items():
    for m in matchers:
        for h in m.get("hooks", []):
            cmd = (h.get("command") or "").split()[0] if h.get("command") else ""
            if not cmd:
                continue
            registered.add(os.path.basename(cmd))
            # A registration pointing at a missing/non-exec file is a GHOST.
            if "conditions-kit" in cmd and not (os.path.isfile(cmd) and os.access(cmd, os.X_OK)):
                print(f"RED|GHOST — registered but file missing/non-exec: {os.path.basename(cmd)}")

if os.path.isdir(hooks_dir):
    on_disk = {os.path.basename(p) for p in glob.glob(os.path.join(hooks_dir, "*.sh"))}
    on_disk.discard("_kit-lib.sh")   # library, not an event hook
    for o in sorted(on_disk - registered):
        print(f"YELLOW|ORPHAN — on disk but never registered, it will never fire: {o}")
PY
)"
    while IFS='|' read -r level msg; do
        [[ -z "$level" ]] && continue
        [[ "$level" == "RED"    ]] && ALARMS+=("parity: $msg")
        [[ "$level" == "YELLOW" ]] && ISSUES+=("parity: $msg")
    done <<< "$PARITY"
fi

# --- 3. Routine parity: should-run vs did-run (Failure 1 — THE check) --------
# Honest about local-first limits: the kit can't read a cloud scheduler's
# registry, so "should exist" is what YOU declare in routines.conf (the same
# file routine-status reads). For each declared routine we confirm its output
# is fresh. "never" = output never appeared = almost always never registered —
# that is exactly the orphan that cost us five weeks. No conf → skip silently.
if [[ -n "${KIT_ROUTINES_CONF:-}" && -f "$KIT_ROUTINES_CONF" ]]; then
    newest_age_h() {  # hours since newest file matching glob; -1 if none
        local glob="$1" newest=0 m
        for f in $glob; do
            [[ -f "$f" ]] || continue
            m="$(kit_mtime "$f")"
            (( m > newest )) && newest="$m"
        done
        (( newest == 0 )) && { echo -1; return; }
        echo $(( (NOW - newest) / 3600 ))
    }
    while IFS='|' read -r name path max cadence; do
        name="$(echo "${name:-}" | xargs)"
        [[ -z "$name" || "$name" == \#* ]] && continue
        path="$(echo "${path:-}" | xargs)"; max="$(echo "${max:-}" | xargs)"
        [[ -z "$path" || -z "$max" ]] && continue
        path="$(eval echo "$path")"   # expand $HOME etc. from the conf
        age="$(newest_age_h "$path")"
        if (( age < 0 )); then
            ALARMS+=("routine: '$name' has NEVER produced output — almost always means it was never registered (the orphan)")
        elif (( age > max * 2 )); then
            ALARMS+=("routine: '$name' is ${age}h stale (>2x its ${max}h window) — it has likely stopped firing")
        elif (( age > max )); then
            ISSUES+=("routine: '$name' is ${age}h stale (window ${max}h) — a fire may have been missed")
        fi
    done < "$KIT_ROUTINES_CONF"
fi

# --- 4. Zombie scheduled-session runners (Failure 2) ------------------------
if command -v pgrep >/dev/null 2>&1; then
    ZOMBIES="$(pgrep -f "$KIT_ZOMBIE_PATTERN" 2>/dev/null | while read -r pid; do
        etime="$(ps -o etime= -p "$pid" 2>/dev/null | tr -d ' ')"
        case "$etime" in
            *-*) echo "$pid" ;;   # days old — definitely stale
            [0-9][0-9]:[0-9][0-9]:[0-9][0-9])  # HH:MM:SS — check the hour field
                h="${etime%%:*}"; [[ "${h#0}" -ge "$KIT_ZOMBIE_MAX_H" ]] 2>/dev/null && echo "$pid" ;;
        esac
    done | wc -l | tr -d ' ')"
    if [[ -n "$ZOMBIES" ]] && (( ZOMBIES > 0 )); then
        ISSUES+=("zombies: ${ZOMBIES} scheduled-runner process(es) older than ${KIT_ZOMBIE_MAX_H}h still resident (runner-reaper will sweep)")
    fi
fi

# --- 5. Session-letter staleness (Failure 6) --------------------------------
if [[ -n "${KIT_SESSION_FILE:-}" ]]; then
    if [[ ! -f "$KIT_SESSION_FILE" ]]; then
        ISSUES+=("session: no letter at $(basename "$KIT_SESSION_FILE") — the highest-leverage file in the kit is missing")
    else
        mt="$(kit_mtime "$KIT_SESSION_FILE")"
        if (( mt > 0 )); then
            age_h=$(( (NOW - mt) / 3600 ))
            (( age_h > KIT_SESSION_STALE_H )) && ISSUES+=("session: letter is ${age_h}h stale (>${KIT_SESSION_STALE_H}h) — a cold letter writes a flat next self")
        fi
    fi
fi

# --- Verdict ----------------------------------------------------------------
if   (( ${#ALARMS[@]} > 0 )); then VERDICT="RED"
elif (( ${#ISSUES[@]} > 0 )); then VERDICT="YELLOW"
else                               VERDICT="GREEN"; fi

REPORT="$TS | ${KIT_AGENT:-agent} | selftest: $VERDICT"
(( ${#ALARMS[@]} > 0 )) && REPORT+=" | ALARMS: $(IFS='; '; echo "${ALARMS[*]}")"
(( ${#ISSUES[@]} > 0 )) && REPORT+=" | issues: $(IFS='; '; echo "${ISSUES[*]}")"

# Human-readable to stdout...
echo "agent-selftest ${KIT_SIGIL:-●}  —  $VERDICT"
if (( ${#ALARMS[@]} > 0 )); then
    echo
    for a in "${ALARMS[@]}"; do echo "  ❌ $a"; done
fi
if (( ${#ISSUES[@]} > 0 )); then
    echo
    for i in "${ISSUES[@]}"; do echo "  ⚠️  $i"; done
fi
if [[ "$VERDICT" == "GREEN" ]]; then
    echo
    echo "  ✅ all checks clean. The light is on."
fi

# ...one line to the log, always.
mkdir -p "$(dirname "$SELFTEST_LOG")" 2>/dev/null || true
echo "$REPORT" >> "$SELFTEST_LOG" 2>/dev/null || true

(( STRICT == 1 )) && [[ "$VERDICT" == "RED" ]] && exit 1
exit 0
