#!/usr/bin/env bash
# Stop: when a turn ends with work STATE.md doesn't have yet and a save is due (TRACKSIDE_SAVE_MINUTES, default 15;
# 0 means every working turn), this only notes it. Sending the chat back would put the edits after its reply and push
# the reply out of view; instead the prompt hook asks for the save before the next answer. The note it leaves on the
# track names this chat, so another chat opened meanwhile leaves the work to it (end.sh marks it once this one ends).
. "$(dirname "$0")/lib.sh"
[ "$(field .stop_hook_active)" = "true" ] && exit 0
[ -n "$binding" ] && [ -f "$st/dirty-$sid" ] || exit 0
# Claude Code blocks edits to the main checkout from a worktree session, and .trackside/ is there: asking for an
# update the chat can't make would only repeat every turn.
[ -z "$worktree" ] || exit 0
save_due "$st" "$sid" || exit 0
touch "$st/owed-$sid"
printf '%s\t%s\t-\n' "$(date +%Y-%m-%d\ %H:%M)" "$sid" > "$(stamp_file "$keep" "$binding").unsaved"
exit 0
