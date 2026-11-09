#!/usr/bin/env bash
# SessionEnd (exit, /clear, a switch with /resume): a chat that ends with work STATE.md doesn't have yet marks its note
# on the track as left behind, so the next chat there, the one after /clear included, fills the gap.
. "$(dirname "$0")/lib.sh"
[ -n "$binding" ] && [ -f "$st/dirty-$sid" ] && [ -z "$worktree" ] || exit 0
note_set "$(note_file "$keep" "$binding")" "$sid" ended
exit 0
