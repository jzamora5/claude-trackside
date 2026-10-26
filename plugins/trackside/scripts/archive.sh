#!/usr/bin/env bash
# archive.sh <project root> <feature>[/<track>]: move a finished track, or a whole feature, into _archive/,
# remove the chat bindings and git stamps that point at it, and refresh the index. The track's own files
# are never deleted.
set -uo pipefail
. "$(dirname "$0")/common.sh"
root=$(keep_root "${1:?project root}" "$PWD")
target="${2:?<feature> or <feature>/<track>}"
keep=$(keep_dir "$root")
st="$keep/.state"

feature="${target%%/*}"
track=""
[[ "$target" == */* ]] && track="${target#*/}"
valid_name "$feature" || { echo "Not a feature name: $feature" >&2; exit 1; }
if [ -n "$track" ] && ! valid_name "$track"; then echo "Not a track name: $track" >&2; exit 1; fi
src="$keep/$feature${track:+/$track}"
kind=feature
[ -n "$track" ] && kind=track
if [ ! -d "$src" ] || { [ -n "$track" ] && [ ! -f "$src/STATE.md" ]; }; then
  echo "Nothing to close: $(rel "$src") isn't a $kind." >&2
  exit 1
fi

# move <from> <to>: a name already in the archive gets a timestamp suffix instead of being overwritten.
move() {
  local to="$2"
  [ -e "$to" ] && to="$to-$(date +%Y%m%d-%H%M%S)"
  mv "$1" "$to" && echo "Moved $(rel "$1") to $(rel "$to")"
}

mkdir -p "$keep/_archive/$feature" || exit 1
if [ -n "$track" ]; then
  move "$src" "$keep/_archive/$feature/$track" || exit 1
else
  for item in "$src"/* "$src"/.[!.]*; do
    [ -e "$item" ] || continue
    move "$item" "$keep/_archive/$feature/$(basename "$item")" || exit 1
  done
  rmdir "$src" || exit 1
fi

unbound=0
for b in "$st"/track-*; do
  [ -f "$b" ] || continue
  v=$(cat "$b")
  match=0
  if [ -n "$track" ]; then [ "$v" = "$feature/$track" ] && match=1; else [[ "$v" == "$feature"/* ]] && match=1; fi
  if [ "$match" = 1 ]; then
    sid="${b##*/track-}"
    rm -f "$b" "$st/dirty-$sid" "$st/compactions-$sid" "$st/nudged-$sid" "$st/owed-$sid"
    unbound=$((unbound + 1))
  fi
done
echo "Chats unbound: $unbound"
for m in "$st"/named-*; do
  [ -f "$m" ] || continue
  v=$(cat "$m")
  if [ -n "$track" ]; then [ "$v" = "$feature/$track" ] && rm -f "$m"; else [[ "$v" == "$feature"/* ]] && rm -f "$m"; fi
done
if [ -n "$track" ]; then s=$(stamp_file "$keep" "$feature/$track"); rm -f "$s" "$s.docs" "$s.unsaved"; else rm -f "$st/stamp-$feature@"*; fi

bash "$(dirname "$0")/index.sh" "$root"
echo "To restore it, move it back out of $(rel "$keep/_archive")/."
