#!/usr/bin/env bash
# UserPromptSubmit: "/trackside:start <feature>/<track>" binds this chat to the track; "/trackside:start off"
# unbinds it. Any other name, or a switch while the chat has unsaved work, is left to the start skill. trackside never
# renames a chat on its own: the first time a chat is bound, the user is offered the track's name for it, and this hook
# renames the chat only when they reply "rename". It remembers which track each chat's name is on. A bound chat whose
# context has grown is offered a fresh one.
. "$(dirname "$0")/lib.sh"

prompt=$(field .prompt)
name=$(chat_name "$keep" "$sid")
# A name the user gives a chat after it starts reaches this hook before SessionStart sees it.
given=$(field .session_title)
if [ -n "$given" ] && ! keep_title "$given"; then
  # After /clear a named chat finds its track only by its name.
  [ "$given" = "$name" ] || [ -z "$binding" ] || map_name "$keep" "$given" "$binding"
  name="$given"
  printf '%s\n' "$given" > "$st/name-$sid"
fi
[ -z "$given" ] || printf '%s\n' "$given" > "$st/seen-$sid"
# The answer to the offer of a name for this chat (offer_name), once the user has seen it. A message that is only
# "rename", in a few forms, takes it; any other message keeps the chat's name, and the offer stays open until the chat
# is bound elsewhere, unbound or cleared, so a "yes" first doesn't use it up.
renamed=""
if [ -f "$st/rename-$sid" ] && [ -f "$st/rename-shown-$sid" ]; then
  answer=$(printf '%s' "$prompt" | tr 'A-Z' 'a-z' | tr -d '`*"' | sed -E 's/^[[:space:]]*((yes|ok|okay|sure)[,.!]*[[:space:]]+)?//; s/[[:space:].!,]*$//')
  case "$answer" in
    rename|"rename it"|"rename this chat"|"rename please"|"please rename"|"please rename it")
      renamed=$(cat "$st/rename-$sid")
      printf '%s\n' "$renamed" > "$st/seen-$sid"
      if ! keep_title "$renamed"; then printf '%s\n' "$renamed" > "$st/name-$sid"; fi
      [ -z "$binding" ] || map_name "$keep" "$renamed" "$binding"
      rm -f "$st/rename-$sid" "$st/rename-shown-$sid" ;;
  esac
fi
title=""
if [[ "$prompt" =~ ^/trackside:start[[:space:]]+([^[:space:]]+)([[:space:]]|$) ]]; then
  if [ "${BASH_REMATCH[1]}" = off ]; then
    # The start skill runs next and reports the unbinding, unsaved work included, from this note.
    if [ -s "$st/track-$sid" ]; then
      { cat "$st/track-$sid"; [ ! -f "$st/dirty-$sid" ] || echo unsaved; } > "$st/off-$sid"
    fi
    unbind_chat "$keep" "$sid" >/dev/null
    [ -z "$name" ] || map_name "$keep" "$name" off
  elif target=$(bind_chat "$keep" "$sid" "${BASH_REMATCH[1]}"); then
    offer_name "$keep" "$sid" "$binding" "$target"
  fi
fi
# The app can start a cleared chat without its title, so SessionStart found no track for it. The title arrives with
# the first message: rebind from it, and give the agent the reload it would have had (gaps to fill, other open chats,
# worktree, doc changes), with STATE.md to read. Only at that first message, and not when the message is itself a
# /trackside:start, which binds or unbinds on its own.
rebound=""
notice=""
called="${given:-$name}"
if [ -f "$st/pending-$sid" ] && [ ! -s "$st/track-$sid" ] && [ -n "$called" ] \
  && [[ "$prompt" != /trackside:start* ]]; then
  rb=$(chat_binding "$keep" "$sid" "$called")
  if [ -n "$rb" ]; then
    reload=$(jq -n -c --arg s "$sid" --arg t "$called" --arg c "$(field .cwd)" '{session_id: $s, source: "clear", session_title: $t, cwd: $c}' \
      | "$(dirname "$0")/load.sh" 2>/dev/null)
    files="$(rel "$keep/$rb")/STATE.md"
    starts_clean "$keep" "$rb" && files="$files and LESSONS.md"
    notice="trackside: this chat is bound to $rb."
    rebound="This chat is back on its track, $rb, by its name \"$called\": the app started it without its name, so this is the reload it would have had. Before you answer, read $files, and if this message asks to go on, propose STATE.md's Next step and wait for the user's OK before starting it. Don't mention this unless the user asks."$'\n'"$reload"
    if [ "$(bytes "$rebound")" -gt "$cut_over" ]; then
      rebound="$(printf '%s' "$rebound" | lines_within "$cut_to")"$'\n'"[Cut to stay under the hook output limit: read $(rel "$keep/$rb")/CONTEXT.md in full.]"
    fi
  fi
fi
rm -f "$st/pending-$sid"
# An offer of a name from this prompt's /trackside:start, or from a fork's start (load.sh), is shown to the user once.
# The start skill's bind has the agent make its offer instead, in the line that says the chat is bound, since the turn
# that binds has no prompt left to show it at.
asked=""
if [ -s "$st/rename-$sid" ] && [ ! -f "$st/rename-shown-$sid" ]; then
  asked="trackside: $(offer_line "$keep" "$sid")"
  touch "$st/rename-shown-$sid"
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
[ -z "$renamed" ] || context="${context:+$context$'\n'}The user's message \"rename\" answered trackside's offer, so this chat is now named \"$renamed\". Confirm it in a few words."
[ -z "$owed" ] || context="${context:+$context$'\n'}$owed"
[ -z "$offer" ] || context="${context:+$context$'\n'}$offer"
# A name the chat took from trackside follows its track's rename (scripts/rename.sh). Only a hook can rename a chat, so
# the script leaves the new name here for the next prompt.
if [ -s "$st/title-$sid" ]; then
  title=$(cat "$st/title-$sid")
  printf '%s\n' "$title" > "$st/seen-$sid"
  notice="${notice:+$notice$'\n'}trackside: this chat's name follows its track's new name: \"$title\"."
fi
[ -z "$renamed" ] || title="$renamed"
rm -f "$st/title-$sid"
[ -z "$asked" ] || notice="${notice:+$notice$'\n'}$asked"
[ -n "$title$context$notice" ] || exit 0
[ -z "$notice" ] || warn="$notice${warn:+$'\n'$warn}"
jq -n --arg t "$title" --arg c "$context" --arg w "$warn" \
  '(if $w != "" then {systemMessage: $w} else {} end) + {hookSpecificOutput: ({hookEventName: "UserPromptSubmit"} + (if $t != "" then {sessionTitle: $t} else {} end) + (if $c != "" then {additionalContext: $c} else {} end))}'
exit 0
