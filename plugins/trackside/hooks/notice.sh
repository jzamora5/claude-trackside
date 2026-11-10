#!/usr/bin/env bash
# SessionStart (startup|clear|fork), beside load.sh: shows the user which track a chat that just started is on, so
# after /clear they can see it was put back on its track. Only the agent sees load.sh's reload. It works out the
# binding the way load-state.sh does, since the hooks run in parallel.
. "$(dirname "$0")/lib.sh"
binding=$(chat_binding "$keep" "$sid" "$(field .session_title)" "$([ "$(field .source)" != clear ] || printf '%s' "$PPID")")
[ -n "$binding" ] && [ -f "$keep/$binding/STATE.md" ] || exit 0
jq -n --arg m "trackside: this chat is bound to $binding." '{systemMessage: $m}'
exit 0
