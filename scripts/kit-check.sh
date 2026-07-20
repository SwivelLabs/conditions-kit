#!/bin/bash
# kit-check.sh — the kit proves it's healthy. Run anytime: bash scripts/kit-check.sh [project-dir]
#
# Checks, in order:
#   1. Hook files present + executable + valid bash syntax
#   2. Registration parity — every kit hook on disk is registered in
#      settings.json, and every kit registration points at a real file.
#      ORPHAN = file exists, never registered (it will never fire, and
#      nothing will ever tell you). GHOST = registered, file missing.
#      Both of the worst silent failures we've shipped were orphans —
#      hooks everyone believed were running that were never wired up.
#   3. Session letter exists + freshness
#   4. Reload integrity (v0.2) — the last compact-reload's logged byte
#      receipt matches the persisted payload copy. Catches the nastiest
#      class we've been burned by: a reload that LOOKED like success but
#      was silently truncated or half-written.
#   5. jq present (several hooks need it)
#
# Exit code = number of failures. 0 = healthy.

set -uo pipefail

TARGET="${1:-$PWD}"
TARGET="$(cd "$TARGET" && pwd)"
CLAUDE_DIR="$TARGET/.claude"
HOOKS_DIR="$CLAUDE_DIR/hooks/conditions-kit"
SETTINGS="$CLAUDE_DIR/settings.json"

FAILS=0
pass() { echo "  ✅ $1"; }
warn() { echo "  ⚠️  $1"; }
fail() { echo "  ❌ $1"; FAILS=$((FAILS+1)); }

echo "Conditions Kit health check — $TARGET"
echo

# --- 1. Hook files -------------------------------------------------------------
echo "[1/5] Hook files"
if [[ ! -d "$HOOKS_DIR" ]]; then
    fail "hooks dir missing: $HOOKS_DIR (run ./install)"
else
    for f in "$HOOKS_DIR"/*.sh; do
        [[ -e "$f" ]] || { fail "no hooks found in $HOOKS_DIR"; break; }
        name=$(basename "$f")
        if [[ ! -x "$f" ]]; then
            fail "$name not executable (chmod +x)"
        elif ! bash -n "$f" 2>/dev/null; then
            fail "$name has a bash syntax error"
        else
            pass "$name"
        fi
    done
fi

# --- 2. Registration parity ------------------------------------------------------
echo "[2/5] Registration parity (orphans + ghosts)"
if [[ ! -f "$SETTINGS" ]]; then
    fail "settings.json missing — nothing is registered"
elif ! command -v python3 >/dev/null 2>&1; then
    warn "python3 missing — skipping parity check"
else
    python3 - "$SETTINGS" "$HOOKS_DIR" <<'PYEOF'
import json, sys, os, glob

settings_path, hooks_dir = sys.argv[1], sys.argv[2]
try:
    with open(settings_path) as f:
        settings = json.load(f)
except Exception as e:
    print(f"  ❌ settings.json unreadable: {e}"); sys.exit(1)

registered = set()
for event, entries in settings.get("hooks", {}).items():
    for entry in entries:
        for h in entry.get("hooks", []):
            c = h.get("command", "")
            if "conditions-kit" in c:
                registered.add(os.path.basename(c))  # full string; kit commands carry no args, space-safe

on_disk = {os.path.basename(p) for p in glob.glob(os.path.join(hooks_dir, "*.sh"))}
on_disk.discard("_kit-lib.sh")  # library, not a hook

fails = 0
orphans = on_disk - registered
ghosts = registered - on_disk
for o in sorted(orphans):
    print(f"  ❌ ORPHAN: {o} exists on disk but is not registered — it will never fire")
    fails += 1
for g in sorted(ghosts):
    print(f"  ❌ GHOST: {g} is registered but the file is missing")
    fails += 1
if not orphans and not ghosts and on_disk:
    print(f"  ✅ parity clean — {len(on_disk)} hooks on disk, all registered")
sys.exit(fails)
PYEOF
    PARITY_FAILS=$?
    FAILS=$((FAILS + PARITY_FAILS))
fi

# --- 3. Session letter ------------------------------------------------------------
echo "[3/5] Session letter"
CONF="$CLAUDE_DIR/conditions-kit.conf"
SESSION_FILE="$TARGET/SESSION.md"
# shellcheck disable=SC1090
[[ -f "$CONF" ]] && source "$CONF" 2>/dev/null && SESSION_FILE="${KIT_SESSION_FILE:-$SESSION_FILE}"
if [[ ! -f "$SESSION_FILE" ]]; then
    warn "no session letter at $SESSION_FILE — the highest-leverage file in this kit is missing"
else
    NOW=$(date +%s)
    MTIME=$(stat -c %Y "$SESSION_FILE" 2>/dev/null || stat -f %m "$SESSION_FILE" 2>/dev/null || echo 0)
    AGE_H=$(( (NOW - MTIME) / 3600 ))
    if (( AGE_H > 72 )); then
        warn "session letter is ${AGE_H}h stale — the letter only works if it's warm"
    else
        pass "session letter present (${AGE_H}h old)"
    fi
fi

# --- 4. Reload integrity (v0.2) ---------------------------------------------------
# The compact-reload hook persists its full payload and logs a byte-count
# receipt. If the copy on disk doesn't match the last logged receipt, the
# reload the agent SAW and the reload that RAN were different things.
# Report the looking even when there's nothing to check — a silent check
# is indistinguishable from a check that never ran.
echo "[4/5] Reload integrity (guard receipts)"
KIT_EVENTS="$TARGET/.kit-events.log"
RELOAD_COPY="$TARGET/.claude/conditions-kit-last-reload.md"
# shellcheck disable=SC1090
[[ -f "$CONF" ]] && source "$CONF" 2>/dev/null && RELOAD_COPY="${KIT_RELOAD_COPY:-$RELOAD_COPY}" && KIT_EVENTS="${KIT_LOG:-$KIT_EVENTS}"
LAST_RELOAD=$(grep 'kind: compact_reload' "$KIT_EVENTS" 2>/dev/null | tail -1 || true)
if [[ -z "$LAST_RELOAD" ]]; then
    pass "no compact reload has fired yet — nothing to verify (checked $KIT_EVENTS)"
elif [[ "$LAST_RELOAD" != *"bytes: "* ]]; then
    warn "last reload predates the v0.2 guard (no byte receipt in log) — next compaction will stamp one"
else
    LOGGED_BYTES=$(echo "$LAST_RELOAD" | sed -n 's/.*bytes: \([0-9][0-9]*\).*/\1/p')
    if [[ ! -f "$RELOAD_COPY" ]]; then
        fail "reload log claims $LOGGED_BYTES bytes but the persisted copy is missing: $RELOAD_COPY"
    else
        COPY_BYTES=$(wc -c < "$RELOAD_COPY" | tr -d ' ')
        if [[ "$COPY_BYTES" == "$LOGGED_BYTES" ]]; then
            pass "last reload receipt matches the persisted copy ($COPY_BYTES bytes)"
        else
            fail "reload receipt mismatch — log says $LOGGED_BYTES bytes, copy on disk is $COPY_BYTES ($RELOAD_COPY)"
        fi
    fi
fi

# --- 5. Dependencies ----------------------------------------------------------------
echo "[5/5] Dependencies"
command -v jq >/dev/null 2>&1 && pass "jq present" || fail "jq missing — several hooks parse hook JSON with it (brew install jq / apt install jq)"

echo
if (( FAILS == 0 )); then
    echo "Healthy. $((0)) failures. The light is on."
else
    echo "$FAILS issue(s) found — details above."
fi
exit "$FAILS"
