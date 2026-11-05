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
if [[ "$prompt" =~ ^/trackside:start[[:space:]]+([^[:space:]]+)([[:space:]]|$) ]]; then
  if [ "${BASH_REMATCH[1]}" = off ]; then
    # The start skill runs next and reports the unbinding, unsaved work included, from this note.
    if [ -s "$st/track-$sid" ]; then
      { cat "$st/track-$sid"; [ ! -f "$st/dirty-$sid" ] || echo unsaved; } > "$st/off-$sid"
    fi
    title=$(unbind_chat "$keep" "$sid")
    [ -z "$name" ] || map_name "$keep" "$name" off
  elif target=$(bind_chat "$keep" "$sid" "${BASH_REMATCH[1]}"); then
    title="$target"
    [ -z "$name" ] || map_name "$keep" "$name" "$target"
  fi
fi
# The app can start a cleared chat without its title, so SessionStart found no track for it. The title arrives with
# the first message: rebind from it the way the reload would, and have the agent read what the reload would have loaded.
# Only at that first message: later, an unbound chat is one the user or the agent unbound, and stays so.
rebound=""
called="${given:-$name}"
if [ -f "$st/pending-$sid" ] && [ -z "$title" ] && [ ! -s "$st/track-$sid" ] && [ -n "$called" ]; then
  rb=$(chat_binding "$keep" "$sid" "$called")
  if [ -n "$rb" ]; then
    printf '%s\n' "$rb" > "$st/track-$sid"
    rebound="This chat is back on its track, $rb, by its name \"$called\": the reload when it started didn't have the name yet. Before you answer, read $(rel "$keep/${rb%%/*}")/FEATURE.md, then $(rel "$keep/$rb")/CONTEXT.md and STATE.md, and if this message asks to go on, propose STATE.md's Next step and wait for the user's OK before starting it. Don't mention this unless the user asks."
  fi
fi
rm -f "$st/pending-$sid"
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
  fresh="once, in one line before the rest of your reply to this message, to clear this chat and continue the track: /trackside:fresh saves the track, then clears this chat, which reloads the track; /trackside:whole keeps this chat as it is with no more offers, for a chat to keep complete, such as for an audit; otherwise trackside asks again after the next compaction. Run neither unless the user asks."
  if [ -n "$found" ]; then
    # The agent doesn't always say so, so the user sees the findings too.
    warn="trackside's context check: this chat's recent replies disagree with $b's files:"$'\n'"$found"$'\n'"If the chat got it wrong, /trackside:fresh saves the track, then clears this chat."
    offer="trackside's context check compared this chat's recent replies with the track's files and found these disagreements:"$'\n'"$found"$'\n'"Before you answer, settle each in a line before the rest of your reply: if a reply of yours was wrong, say so; if the track looks out of date, say what you'd change in it and ask before editing it, since it holds decisions the user made."
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
context="$rebound"
[ -z "$owed" ] || context="${context:+$context$'\n'}$owed"
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
