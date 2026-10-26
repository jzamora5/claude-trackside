#!/usr/bin/env bash
# UserPromptSubmit: "/trackside:start <feature>/<track>" binds this chat to the track; "/trackside:start off"
# unbinds it. A chat without a name of its own is named after its track; a chat the user named keeps its name, and
# trackside remembers which track that name is on. Any other name, or a switch while the chat has unsaved work, is
# left to the start skill. A chat the start skill bound or unbound gets its new name at the next prompt.
. "$(dirname "$0")/lib.sh"

prompt=$(field .prompt)
name=$(chat_name "$keep" "$sid")
# A name the user gives a chat after it starts reaches this hook before SessionStart sees it.
given=$(field .session_title)
if [ -n "$given" ] && ! keep_title "$given"; then
  name="$given"
  printf '%s\n' "$given" > "$st/name-$sid"
fi
title=""
if [[ "$prompt" =~ ^/(trackside:)?start[[:space:]]+([^[:space:]]+)([[:space:]]|$) ]]; then
  if [ "${BASH_REMATCH[2]}" = off ]; then
    # The start skill runs next and reports the unbinding, unsaved work included, from this note.
    if [ -s "$st/track-$sid" ]; then
      { cat "$st/track-$sid"; [ ! -f "$st/dirty-$sid" ] || echo unsaved; } > "$st/off-$sid"
    fi
    title=$(unbind_chat "$keep" "$sid")
    [ -z "$name" ] || map_name "$keep" "$name" off
  elif target=$(bind_chat "$keep" "$sid" "${BASH_REMATCH[2]}"); then
    title="$target"
    [ -z "$name" ] || map_name "$keep" "$name" "$target"
  fi
fi
# A save the last turn ended without is asked for before this answer, never after the last one.
owed=""
b=$(cat "$st/track-$sid" 2>/dev/null || true)
if [ -n "$b" ] && [ -f "$st/owed-$sid" ] && [ -f "$st/dirty-$sid" ] && [ -z "$worktree" ]; then
  owed="The last turn's work isn't in $(rel "$keep/$b")/STATE.md yet. Before you answer this message, update its Current and Next step, a line each, marked [verified] or [assumed], and record any decision made since where FEATURE.md says decisions go, without mentioning it in your reply."
  touch "$st/nudged-$sid"
fi
# trackside never renames a chat the user named. Only this hook and SessionStart can name a chat, so scripts/bind.sh
# leaves the name here for the next prompt.
if [ -n "$name" ]; then
  title=""
elif [ -z "$title" ] && [ -s "$st/title-$sid" ]; then
  title=$(cat "$st/title-$sid")
fi
rm -f "$st/title-$sid"
[ -n "$title$owed" ] || exit 0
jq -n --arg t "$title" --arg c "$owed" \
  '{hookSpecificOutput: ({hookEventName: "UserPromptSubmit"} + (if $t != "" then {sessionTitle: $t} else {} end) + (if $c != "" then {additionalContext: $c} else {} end))}'
exit 0
