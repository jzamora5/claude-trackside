#!/usr/bin/env bash
# UserPromptSubmit: "/trackside:start <feature>/<track>" binds this chat to the track; "/trackside:start off"
# unbinds it. A chat without a name of its own is named after its track; a chat the user named keeps its name, and
# trackside remembers which track that name is on. Any other name, or a switch while the chat has unsaved work, is
# left to the start skill. A chat the start skill bound or unbound gets its new name at the next prompt. A bound chat
# whose context has grown is offered a fresh one.
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
  owed="The last turn's work isn't in $(rel "$keep/$b")/STATE.md yet. Before you answer this message, update its Current and Next step, a line each, marked [verified] or [assumed], and record any decision made since where FEATURE.md says decisions go, in one edit each, without mentioning it in your reply."
  touch "$st/nudged-$sid"
fi
# A chat is offered a fresh one at most once each time it compacts: when its context nears the size at which it
# compacts (size_due), or when the judge (judge.sh) found its replies disagree with the track. A chat kept whole, or
# one in a worktree, which can't save, is never offered.
offer=""
warn=""
if [ -n "$b" ] && [ -z "$worktree" ] && [ ! -f "$st/whole-$sid" ]; then
  read -r tokens model point <<<"$(context_usage "$(field .transcript_path)")"
  if [[ "${point:-}" =~ ^[0-9]+$ ]] && [ "$point" -ge 100000 ] && [ -n "$model" ]; then
    old=$(cat "$st/limit-$model" 2>/dev/null); [[ "$old" =~ ^[0-9]+$ ]] || old=0
    [ "$point" -le "$old" ] || echo "$point" > "$st/limit-$model"
  fi
  c=$(compactions "$st" "$sid")
  due=""; [ "$(cat "$st/offered-$sid" 2>/dev/null)" = "$c" ] || due=1
  found=$(cat "$st/health-$sid" 2>/dev/null || true); rm -f "$st/health-$sid"
  fresh="once, in one line before the rest of your reply to this message, to continue in a fresh chat: /trackside:fresh saves the track and clears this chat, which then reloads the track; /trackside:whole keeps this chat as it is with no more offers, for a chat to keep complete, such as for an audit; otherwise trackside asks again after the next compaction. Run neither unless the user asks."
  if [ -n "$found" ]; then
    # The agent doesn't always say so, so the user sees the findings too.
    warn="trackside's context check: this chat's recent replies disagree with $b's files:"$'\n'"$found"$'\n'"If the chat got it wrong, /trackside:fresh continues the track in a fresh chat."
    offer="trackside's context check compared this chat's recent replies with the track's files and found these disagreements:"$'\n'"$found"$'\n'"Before you answer, settle each: if the track is out of date, update it; if a reply of yours was wrong, say so in a line before the rest of your reply."
    [ -z "$due" ] || offer+=" If one was, also offer $fresh"
  elif [ -n "$due" ] && size_due "$st" "$sid" "${tokens:-}" "${model:-}"; then
    if [[ "${tokens:-}" =~ ^[0-9]+$ ]] && [ "$tokens" -gt 0 ]; then
      offer="This chat's context is about $((tokens / 1000))K tokens"
      cp=$(compact_point "$st" "$model")
      [[ "$cp" =~ ^[1-9][0-9]*$ ]] && offer+=", $((tokens * 100 / cp))% of the $((cp / 1000))K at which it compacts"
      [ "$c" = 0 ] || offer+=", and it has compacted $c time(s)"
    else
      offer="This chat has compacted $c time(s)"
    fi
    offer+=". Offer $fresh"
  fi
  [ -z "$offer" ] || [ -z "$due" ] || echo "$c" > "$st/offered-$sid"
fi
context="$owed"
[ -z "$offer" ] || context="${context:+$context$'\n'}$offer"
# trackside never renames a chat the user named. Only this hook and SessionStart can name a chat, so scripts/bind.sh
# leaves the name here for the next prompt.
if [ -n "$name" ]; then
  title=""
elif [ -z "$title" ] && [ -s "$st/title-$sid" ]; then
  title=$(cat "$st/title-$sid")
fi
rm -f "$st/title-$sid"
[ -n "$title$context" ] || exit 0
jq -n --arg t "$title" --arg c "$context" --arg w "$warn" \
  '(if $w != "" then {systemMessage: $w} else {} end) + {hookSpecificOutput: ({hookEventName: "UserPromptSubmit"} + (if $t != "" then {sessionTitle: $t} else {} end) + (if $c != "" then {additionalContext: $c} else {} end))}'
exit 0
