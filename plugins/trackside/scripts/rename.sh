#!/usr/bin/env bash
# rename.sh <project root> <feature>[/<track>] <new name>: rename a track within its feature, or a whole
# feature. Every reference to it inside the trackside folder is updated, chats bound to it stay bound (those named
# after it get the new name at their next message), its git stamps and review record follow it, and the index
# is refreshed.
set -uo pipefail
. "$(dirname "$0")/common.sh"
root=$(keep_root "${1:?project root}" "$PWD")
target="${2:?<feature> or <feature>/<track>}"
new="${3:?new name}"
keep=$(keep_dir "$root")
st="$keep/.state"

feature="${target%%/*}"
track=""
[[ "$target" == */* ]] && track="${target#*/}"
valid_name "$feature" || { echo "Not a feature name: $feature" >&2; exit 1; }
if [ -n "$track" ] && ! valid_name "$track"; then echo "Not a track name: $track" >&2; exit 1; fi
valid_name "$new" || { echo "Not a valid name: $new. Use letters, digits, '.', '_' and '-', starting with a letter or digit." >&2; exit 1; }
if [ -n "$track" ]; then
  [ "$new" != off ] || { echo "A track can't be named off: /trackside:start off unbinds a chat." >&2; exit 1; }
  old="$feature/$track"
  to="$feature/$new"
  [ -f "$keep/$old/STATE.md" ] || { echo "No track $old." >&2; exit 1; }
else
  old="$feature"
  to="$new"
  [ -d "$keep/$old" ] || { echo "No feature $old." >&2; exit 1; }
fi
[ ! -e "$keep/$to" ] || { echo "$(rel "$keep/$to") already exists." >&2; exit 1; }

mv "$keep/$old" "$keep/$to" || exit 1
echo "Renamed $(rel "$keep/$old") to $(rel "$keep/$to")"

# References are full names (<feature>/<track>) and .trackside/ paths; a feature's bare name is too often a plain
# word to replace, except in the headers trackside's templates write.
re_() { printf '%s' "${1//./\\.}"; }
args=(-e "s,\\.trackside/$(re_ "$old")(/|[^A-Za-z0-9._-]|$),.trackside/$to\\1,g")
if [ -n "$track" ]; then
  args+=(-e "s,(^|[^A-Za-z0-9._/-])$(re_ "$old")(/|[^A-Za-z0-9._-]|$),\\1$to\\2,g")
else
  args+=(-e "s,^(# (Feature|Decisions): )$(re_ "$old")([^A-Za-z0-9._-]|$),\\1$to\\3,")
  for t in $(list_tracks "$keep" "$to"); do
    args+=(-e "s,(^|[^A-Za-z0-9._/-])$(re_ "$old/$t")(/|[^A-Za-z0-9._-]|$),\\1$to/$t\\2,g")
  done
fi
updated=0
while IFS= read -r f; do
  # Twice: a match takes the character after it, so a name one character after another is seen only on a second
  # pass.
  sed -E "${args[@]}" "${args[@]}" "$f" > "$f.tmp" || { rm -f "$f.tmp"; continue; }
  if cmp -s "$f" "$f.tmp"; then rm -f "$f.tmp"; else mv "$f.tmp" "$f"; updated=$((updated + 1)); fi
done < <(find "$keep" -name '*.md' -not -path "$keep/.git/*" -not -path "$keep/.state/*" -not -path "$keep/_archive/*" -not -name INDEX.md)
echo "Files updated to the new name: $updated"

kept=0
renamed=0
for b in "$st"/track-*; do
  [ -f "$b" ] || continue
  v=$(cat "$b")
  nv=""
  if [ -n "$track" ]; then
    [ "$v" = "$old" ] && nv="$to"
  else
    [[ "$v" == "$old"/* ]] && nv="$to/${v#*/}"
  fi
  [ -n "$nv" ] || continue
  sid="${b##*/track-}"
  printf '%s\n' "$nv" > "$b"
  kept=$((kept + 1))
  # A chat the user named keeps its name. Only a hook can name a chat, so the bind hook applies this at the
  # chat's next message.
  [ -n "$(chat_name "$keep" "$sid")" ] && continue
  printf '%s' "$nv" > "$st/title-$sid"
  renamed=$((renamed + 1))
done
echo "Chats kept bound: $kept, renamed at their next message: $renamed"
for m in "$st"/named-*; do
  [ -f "$m" ] || continue
  v=$(cat "$m")
  if [ -n "$track" ]; then
    [ "$v" = "$old" ] && printf '%s\n' "$to" > "$m"
  else
    [[ "$v" == "$old"/* ]] && printf '%s\n' "$to/${v#*/}" > "$m"
  fi
done

# The deep-review record moves too, so a renamed track isn't reviewed again just for its new name.
if [ -n "$track" ]; then
  s=$(stamp_file "$keep" "$old")
  [ -f "$s" ] && mv "$s" "$(stamp_file "$keep" "$to")"
  [ -f "$s.docs" ] && mv "$s.docs" "$(stamp_file "$keep" "$to").docs"
  [ -f "$s.unsaved" ] && mv "$s.unsaved" "$(stamp_file "$keep" "$to").unsaved"
  [ -f "$st/deep-$feature@$track" ] && mv "$st/deep-$feature@$track" "$st/deep-$feature@$new"
else
  for s in "$st/stamp-$old@"* "$st/deep-$old@"*; do
    [ -f "$s" ] || continue
    case "$s" in */stamp-*) mv "$s" "$st/stamp-$new@${s##*@}" ;; *) mv "$s" "$st/deep-$new@${s##*@}" ;; esac
  done
fi

bash "$(dirname "$0")/index.sh" "$root"
exit 0
