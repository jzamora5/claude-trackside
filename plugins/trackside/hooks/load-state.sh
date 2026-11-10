#!/usr/bin/env bash
# SessionStart, beside load.sh: the bound track's STATE.md, and its LESSONS.md on a track whose items start clean, in a
# hook output of their own, so the state doesn't share load.sh's budget. The two hooks run in parallel, so this works
# out the binding the way load.sh does instead of waiting for load.sh to write it.
. "$(dirname "$0")/lib.sh"
binding=$(chat_binding "$keep" "$sid" "$(field .session_title)" "$([ "$(field .source)" != clear ] || printf '%s' "$PPID")")
[ -n "$binding" ] && [ -f "$keep/$binding/STATE.md" ] || exit 0
reload_state "$keep" "$binding"
exit 0
