#!/bin/bash
# _kit-lib.sh — shared plumbing for Conditions Kit hooks.
#
# Every kit hook sources this file. It loads your kit config, provides
# portable helpers (macOS + Linux), and parses the hook JSON Claude Code
# pipes to stdin. Hooks stay readable; the boring parts live here.
#
# CONFIG RESOLUTION (first match wins):
#   1. $CONDITIONS_KIT_CONF (env var, explicit override)
#   2. <project>/.claude/conditions-kit.conf
#   3. ~/.claude/conditions-kit.conf
#   4. Built-in defaults (kit works out of the box, anonymous)
#
# This file defines, after kit_load_config:
#   KIT_AGENT        — short name for your agent (default: "agent")
#   KIT_DISPLAY      — display name (default: capitalize of KIT_AGENT)
#   KIT_SIGIL        — emoji/sigil for banners (default: "●")
#   KIT_WORKSPACE    — the agent's home dir (default: project root or $PWD)
#   KIT_SESSION_FILE — the session letter (default: $KIT_WORKSPACE/SESSION.md)
#   KIT_IDENTITY_FILES — basenames to audit-watch (default: "IDENTITY.md SHAPE.md")
#   KIT_NOTES_DIR    — where your agent's notes/journal live (for past-self)
#   KIT_LOG          — lifecycle log (default: $KIT_WORKSPACE/.kit-events.log)

set -uo pipefail

# --- portable helpers -------------------------------------------------------

# kit_mtime FILE — epoch mtime, 0 if missing. Works on macOS and Linux.
# GNU (-c) first: on Linux, BSD `stat -f` exits 0 with garbage (filesystem
# info), so BSD-first would never reach the GNU branch. macOS `stat -c` fails
# cleanly and falls through to `-f`. This order is correct on both.
kit_mtime() {
    stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0
}

kit_ts_utc()   { date -u +%Y-%m-%dT%H:%M:%SZ; }
kit_ts_local() { date '+%A, %B %-d, %Y — %-I:%M %p %Z' 2>/dev/null || date; }

# kit_log_event "message" — one-line lifecycle receipt
kit_log_event() {
    mkdir -p "$(dirname "$KIT_LOG")" 2>/dev/null || true
    echo "$(kit_ts_utc) | $KIT_AGENT | ${KIT_SESSION_ID:-none} | $1" >> "$KIT_LOG" 2>/dev/null || true
}

# --- hook stdin parsing -----------------------------------------------------
# Claude Code pipes JSON to hooks. Call kit_read_input once; it sets:
#   KIT_INPUT, KIT_SESSION_ID, KIT_HOOK_SOURCE, KIT_TOOL_NAME, KIT_TRANSCRIPT
kit_read_input() {
    KIT_INPUT=""
    if ! [[ -t 0 ]]; then
        KIT_INPUT=$(cat || true)
    fi
    KIT_SESSION_ID="none"; KIT_HOOK_SOURCE="unknown"; KIT_TOOL_NAME="?"; KIT_TRANSCRIPT=""
    if [[ -n "$KIT_INPUT" ]] && command -v jq >/dev/null 2>&1; then
        KIT_SESSION_ID=$(echo "$KIT_INPUT"  | jq -r '.session_id // "none"'      2>/dev/null || echo "none")
        KIT_HOOK_SOURCE=$(echo "$KIT_INPUT" | jq -r '.source // "unknown"'       2>/dev/null || echo "unknown")
        KIT_TOOL_NAME=$(echo "$KIT_INPUT"   | jq -r '.tool_name // "?"'          2>/dev/null || echo "?")
        KIT_TRANSCRIPT=$(echo "$KIT_INPUT"  | jq -r '.transcript_path // ""'     2>/dev/null || echo "")
    fi
}

# --- config loading ---------------------------------------------------------
kit_load_config() {
    # Defaults first — the kit must work with zero configuration.
    KIT_WORKSPACE="${KIT_WORKSPACE:-${CLAUDE_PROJECT_DIR:-$PWD}}"
    KIT_AGENT="${KIT_AGENT:-agent}"
    KIT_DISPLAY="${KIT_DISPLAY:-}"
    KIT_SIGIL="${KIT_SIGIL:-●}"
    KIT_SESSION_FILE="${KIT_SESSION_FILE:-}"
    KIT_IDENTITY_FILES="${KIT_IDENTITY_FILES:-IDENTITY.md SHAPE.md SOUL.md}"
    KIT_NOTES_DIR="${KIT_NOTES_DIR:-}"
    KIT_LOG="${KIT_LOG:-}"

    local conf=""
    if [[ -n "${CONDITIONS_KIT_CONF:-}" && -f "${CONDITIONS_KIT_CONF}" ]]; then
        conf="$CONDITIONS_KIT_CONF"
    elif [[ -f "$KIT_WORKSPACE/.claude/conditions-kit.conf" ]]; then
        conf="$KIT_WORKSPACE/.claude/conditions-kit.conf"
    elif [[ -f "$HOME/.claude/conditions-kit.conf" ]]; then
        conf="$HOME/.claude/conditions-kit.conf"
    fi
    # shellcheck disable=SC1090
    [[ -n "$conf" ]] && source "$conf"

    # Derived defaults after conf load
    [[ -z "$KIT_DISPLAY" ]] && KIT_DISPLAY="$(echo "${KIT_AGENT:0:1}" | tr '[:lower:]' '[:upper:]')${KIT_AGENT:1}"
    [[ -z "$KIT_SESSION_FILE" ]] && KIT_SESSION_FILE="$KIT_WORKSPACE/SESSION.md"
    [[ -z "$KIT_LOG" ]] && KIT_LOG="$KIT_WORKSPACE/.kit-events.log"
    [[ -z "$KIT_NOTES_DIR" ]] && KIT_NOTES_DIR="$KIT_WORKSPACE/notes"
    return 0
}

kit_load_config
