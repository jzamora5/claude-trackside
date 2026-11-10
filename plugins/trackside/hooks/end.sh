#!/usr/bin/env bash
# SessionEnd (exit, /clear, a switch with /resume): a chat that ends with work STATE.md doesn't have yet marks its note
# on the track as left behind, so the next chat there, the one after /clear included, fills the gap.
. "$(dirname "$0")/lib.sh"
# A /clear starts the next session in this same process (cleared_note): hand it this chat's track, or "off" when the
# user unbound it.
if [ "$(field .reason)" = clear ]; then
  t="$binding"
  [ -n "$t" ] || [ ! -f "$st/unbound-$sid" ] || t=off
  if [ -n "$t" ]; then
    printf '%s\n' "$t" > "$st/cleared-$PPID"
  else
    rm -f "$st/cleared-$PPID"
  fi
fi
[ -n "$binding" ] && [ -f "$st/dirty-$sid" ] && [ -z "$worktree" ] || exit 0
note_set "$(note_file "$keep" "$binding")" "$sid" ended
exit 0
