#!/usr/bin/env bash
# SessionStart (startup|resume|clear|compact|fork): reload the bound track's FEATURE.md and CONTEXT.md, with
# trackside's instructions, and report what changed in the feature's repos since STATE.md was written; load-state.sh
# reloads STATE.md beside it. An unbound chat gets the list of tracks instead. Compactions are counted for the prompt
# hook, which offers a fresh chat when one is due.
. "$(dirname "$0")/lib.sh"
here="$(dirname "$0")"
src=$(field .source)
title=$(field .session_title)

budget=$reload_budget
out=""
add() { out+="$1"$'\n'; }

# A session that starts without a binding is rebound: after /clear from the chat it ended (cleared_note), else by the
# track trackside remembers for its title, else by the track its title names.
cleared=""
[ "$src" != clear ] || cleared=$(cleared_note "$keep" "$PPID")
binding=$(chat_binding "$keep" "$sid" "$title" "$([ "$src" != clear ] || printf '%s' "$PPID")")
# The chat a /clear ended carries on here, unbound if the user unbound it.
[ "$cleared" != off ] || touch "$st/unbound-$sid"
[ -z "$title" ] || printf '%s\n' "$title" > "$st/seen-$sid"
if [ -n "$title" ] && ! keep_title "$title"; then
  printf '%s\n' "$title" > "$st/name-$sid"
else
  rm -f "$st/name-$sid"
fi
# A chat that starts on its track continues a chat that was on it, so its title stays on the track and it isn't offered
# the track's name, except a fork, which is a second chat with the same name and is offered the next number once.
if [ -n "$binding" ] && [ -f "$keep/$binding/STATE.md" ]; then
  title_map "$keep" "$sid" "$binding"
  [ -f "$st/name-asked-$sid" ] || printf '%s\n' "$binding" > "$st/name-asked-$sid"
  if [ "$src" = fork ] && [ -n "$title" ] && [ ! -f "$st/rename-$sid" ] && names_chats "$keep" "$binding"; then
    want=$(name_offer "$keep" "fork-of-$sid" "${title% · [0-9]*}")
    if [ -n "$want" ] && [ "$want" != "$title" ]; then
      printf '%s\n' "$want" > "$st/rename-$sid"
      rm -f "$st/rename-shown-$sid"
    fi
  fi
fi
[ "$src" = "clear" ] && rm -f "$st/compactions-$sid" "$st/offered-$sid" "$st/judged-$sid" "$st/health-$sid"

# Housekeeping: runtime files of old sessions only pile up, and a resumed chat rebinds from its title. Stamps, the
# deep-review records, the tracks remembered for chats the user named, chats kept whole and where each model compacts
# are kept: they matter most after a long pause, and closing a track removes its own.
find "$st" -type f ! -name .gitignore ! -name 'stamp-*' ! -name 'deep-*' ! -name 'named-*' ! -name 'whole-*' ! -name 'limit-*' -mtime +"${TRACKSIDE_STATE_DAYS:-30}" -exec rm -f {} + 2>/dev/null
[ -n "$binding" ] && printf '%s\n' "$binding" > "$st/track-$sid"
# A chat the app started without its title may only lack it: the prompt hook may rebind it at its first message. A
# compaction or resume keeps the chat, so an unbound one there was unbound on purpose.
case "$binding:$src" in
  :startup|:clear|:fork) touch "$st/pending-$sid" ;;
  *) rm -f "$st/pending-$sid" ;;
esac
bash "$here/../scripts/index.sh" "$root" 2>/dev/null

if [ -z "$binding" ] || [ ! -f "$keep/$binding/STATE.md" ]; then
  add "No track is bound to this chat. The user may call a track a workspace."
  list=$(bash "$here/../scripts/status.sh" "$root" 2>/dev/null)
  if [[ "$list" == "- "* ]]; then
    add "Tracks, their current work or goal, and how to start each:"
    add "$list"
  fi
  # A chat the user unbound stays unbound after /clear: the chat it cleared handed over "off", trackside remembered
  # "off" for its name, or its title says so, as trackside named unbound chats before 0.26.0.
  if [[ "$title" == *" (unbound)" ]] || [ "$(named_track "$keep" "$title")" = off ] || [ -f "$st/unbound-$sid" ]; then
    add "The user unbound this chat from its track, so don't bind it on your own. If they ask to use a track, run the trackside start skill (/trackside:start) with its full name, <feature>/<track>."
  else
    add "When a message of the user starts work (a change, a review, research or a ticket, not a quick question): if one track clearly fits it, because its name, goal or current work is about that work and no other track's is, bind the chat to it right away by running the trackside start skill (/trackside:start) with the track's full name, <feature>/<track>, and carry on with what they asked. If more than one track could fit, ask once which, listing them. If none fits, offer once to create a track, and create it only after the user agrees, by running the trackside start skill with no name. Don't bind again in this chat once the user unbinds it or turns a track down. Otherwise just answer."
  fi
  printf '%s' "$out" | lines_within "$budget"
  exit 0
fi

fdir="$keep/${binding%%/*}"
tdir="$keep/$binding"
add "Active track: $binding (a new chat starts it with /trackside:start $binding). Its files: $(rel "$fdir")/FEATURE.md, plus CONTEXT.md, STATE.md and NOTES.md in $(rel "$tdir")/."
add "The user may call a track a workspace; /trackside:current shows this one."
add "STATE.md is the handoff for the next chat and must stay current. Record each decision as soon as it's made, with the options rejected and why, where FEATURE.md says decisions go. Write down only what a new chat couldn't get from the code, git, the docs or a command: no copied file contents, diffs or test output; point to them instead."
add "Keep trackside's bookkeeping out of your replies: update STATE.md before you write a reply, not after it, in one edit (one Edit call or one script), never a series of small ones, since every call re-reads the whole chat; and don't tell the user about saves, fixes the automatic check asked for, or commits of the trackside folder. Mention trackside only when the user has to decide something, in a line before the rest of your reply, never after a question you ask."
[ -z "$(source_docs "$keep" "${binding%%/*}")" ] || add "The source docs FEATURE.md lists are the source of truth: before you state, decide or change anything they cover, read it with the trackside lookup skill (/trackside:lookup <ID or heading words>), which prints the exact text, instead of trusting what STATE.md says, and cite what you use by ID (such as AD-28) or heading."
# The note has a line for each chat with unsaved work. This chat's own line, at a resume, makes its save owed again.
# This chat fills the gap of chats that ended or left their work for a day, and leaves an open chat's work to it.
note=$(note_file "$keep" "$binding")
if [ -s "$note" ] && [ -z "$worktree" ]; then
  if [ -f "$st/dirty-$sid" ] && awk -F'\t' -v s="$sid" '$2 == s { f = 1 } END { exit !f }' "$note"; then
    note_set "$note" "$sid" -
    touch "$st/owed-$sid"
  fi
  left=$(note_lines "$note" left | awk -F'\t' -v s="$sid" '$2 != s')
  open=$(note_lines "$note" open | awk -F'\t' -v s="$sid" '$2 != s')
  if [ -n "$left" ]; then
    add "The last chat on this track left off on $(printf '%s\n' "$left" | cut -f1 | sort | tail -1) with work STATE.md doesn't have yet. Before your first reply, update its Current and Next step from what changed (below) and the code, marking those lines [assumed], and tell the user in one line that you filled in work the last chat left unsaved."
    touch "$st/gap-$sid"
  fi
  if [ -n "$open" ]; then
    add "Another chat on this track, still open, has work STATE.md doesn't have yet (its last turn ended $(printf '%s\n' "$open" | cut -f1 | sort | tail -1)). It saves that work itself, so don't fill it in from here."
  fi
fi
if starts_clean "$keep" "$binding"; then
  add "Each item on this track starts clean: only CONTEXT.md and LESSONS.md carry over from one item to the next. LESSONS.md says how to finish an item."
fi
if [ -n "$worktree" ]; then
  add "This chat runs in a Claude Code worktree, and Claude Code blocks edits to the main checkout, where $(rel "$keep")/ is. So this chat can read the track but can't update STATE.md, and isn't asked to. Say so in your first reply, so the user knows this chat's work won't reach the track."
fi

if [ "$src" = "compact" ]; then
  c=$(cat "$st/compactions-$sid" 2>/dev/null || true)
  [[ "$c" =~ ^[0-9]+$ ]] || c=0
  n=$(( c + 1 ))
  echo "$n" > "$st/compactions-$sid"
  add "This chat has been compacted $n time(s); the track's files reloaded with this are authoritative over the summary."
  add "Re-read the files FEATURE.md and CONTEXT.md list under \"Read on start\"; the summary may have dropped them."
  # Right after a compaction the context is at its smallest, so a save costs the least it ever will in this chat, and
  # the summary is the last place this session's recent decisions still exist. The request also comes with the next
  # message (owed): in live runs, agents answered that message without acting on the reload's request alone.
  if [ -f "$st/dirty-$sid" ] && [ -z "$worktree" ]; then
    touch "$st/owed-$sid"
    add "This chat has work STATE.md doesn't have yet. Before your first reply, update its Current and Next step in one edit, from the summary and the code, and record any decision or ruled-out option the summary holds that the track doesn't, without mentioning it."
  fi
fi

add ""
add "$(bash "$here/../scripts/freshness.sh" "$root" "$binding" "$(field .cwd)" 2>/dev/null | head -n 25)"
if [ -z "$worktree" ]; then
  issues=$(bash "$here/../scripts/audit.sh" "$root" "$binding" start 2>/dev/null)
  if [ -n "$issues" ]; then
    add ""
    add "trackside's check of this track:"
    add "$issues"
    add "Fix the ones that only move or de-duplicate text, or fill in what's missing, in your first save. Mention the ones that need the user once in this chat, at a natural pause, never before answering what they asked."
  fi
  if [ "$(bash "$here/../scripts/audit.sh" "$root" "$binding" due 2>/dev/null)" = due ]; then
    add ""
    add "trackside's periodic review of this track is due. Start the trackside audit skill for $binding now, without waiting for the user; it runs in the background on a cheaper model and reads only. When its list comes back, apply the items it marks lossless, only in files inside .trackside/, write the other items to the track's review-<date>.md (or \"Nothing needs the user.\"; writing the file marks the review as handled) with an Inbox line pointing to it when it has items, and at a natural pause, settle the other items with the user in the chat, never by pointing to the file: first confirm what the files, git or gh can, so each line states facts; list the changes in plain words, one line each saying what you'd change and why, and ask once whether to apply them all or which to skip; ask a choice only the user can make, such as moving notes to another track, as its own question with your recommendation. Apply what they approve, and keep in the file, with its Inbox line, only what they postpone."
  fi
fi
out+="$(reload_files "$keep" "$binding" $(( budget - $(bytes "$out") - 200 )))"$'\n'
if [ "$(bytes "$out")" -gt "$cut_over" ]; then
  out="$(printf '%s' "$out" | lines_within "$cut_to")"$'\n'"[Cut to stay under the hook output limit: read $(rel "$tdir")/CONTEXT.md in full.]"
fi
printf '%s' "$out"
exit 0
