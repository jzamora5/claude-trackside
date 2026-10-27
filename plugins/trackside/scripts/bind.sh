#!/usr/bin/env bash
# Usage: bind.sh <project root> <session id> <name | off> [move]
# Binds a chat from the start skill, for when the agent starts a track the user agreed to, or unbinds it with
# "off". With "move", from the save skill, a chat with unsaved work switches anyway and takes that work along. Typing /trackside:start binds through the UserPromptSubmit hook instead, which also names the chat.
set -uo pipefail
. "$(dirname "$0")/common.sh"
root=$(keep_root "${1:?project root}" "$PWD")
sid="${2:-}"
name="${3:-}"
keep=$(keep_dir "$root")
st="$keep/.state"
[[ "$sid" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "No valid session id: $sid" >&2; exit 1; }
[ -d "$keep" ] || { echo "No trackside folder at $keep" >&2; exit 1; }
mkdir -p "$st"
[ -f "$st/.gitignore" ] || printf '*\n' > "$st/.gitignore"

# The hooks need jq and do nothing without it, so binding would look like it worked when nothing reloads or
# reminds.
note_jq() {
  command -v jq >/dev/null 2>&1 || echo "Note: jq isn't installed, so trackside's hooks are off: no reload after /clear or a compaction, and no save reminders. Install jq to turn them on."
}

own=$(chat_name "$keep" "$sid")
if [ "$name" = off ]; then
  unsaved=""
  [ -f "$st/dirty-$sid" ] && unsaved=" Its work since the last save wasn't saved there."
  title=$(unbind_chat "$keep" "$sid")
  if [ -z "$title" ] && [ -s "$st/off-$sid" ]; then
    # A typed /trackside:start off was already unbound by the prompt hook, which left this note.
    grep -qx unsaved "$st/off-$sid" && unsaved=" Its work since the last save wasn't saved there."
    echo "Unbound this chat from $(head -1 "$st/off-$sid").$unsaved"
  elif [ -z "$title" ]; then
    echo "This chat isn't bound to a track."
  else
    if [ -n "$own" ]; then map_name "$keep" "$own" off; else printf '%s' "$title" > "$st/title-$sid"; fi
    echo "Unbound this chat from ${title% (unbound)}.$unsaved"
  fi
  rm -f "$st/off-$sid"
  note_jq
  exit 0
fi

before=$(cat "$st/track-$sid" 2>/dev/null || true)
target=$(bind_chat "$keep" "$sid" "$name" "${4:-}")
case $? in
  1) echo "No track is named \"$name\". Use a track's full name, <feature>/<track>." >&2; exit 1 ;;
  2) echo "This chat has unsaved work on $target. Save it there first with /trackside:save, or unbind with /trackside:start off if it doesn't belong there, then bind again." >&2; exit 2 ;;
esac
if [ -n "$own" ]; then
  map_name "$keep" "$own" "$target"
elif [ "$before" != "$target" ]; then
  printf '%s' "$target" > "$st/title-$sid"
fi
echo "Bound this chat to $target."
note_jq
