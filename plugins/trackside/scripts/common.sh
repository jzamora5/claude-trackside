# Shared by the hooks and the helper scripts. Sourced, not run. Functions that print paths use $root.

keep_dir() { printf '%s/.trackside' "$1"; }

# keep_root <project dir> <working dir>: the folder whose .trackside/ to use: the project dir when it has one, or
# else the nearest .trackside/ at or above the working dir, so a chat that works in another folder than the one it
# started in still finds its trackside folder.
keep_root() {
  local d="$2"
  if [ ! -d "$1/.trackside" ]; then
    while [ -n "$d" ] && [ "$d" != / ]; do
      [ -d "$d/.trackside" ] && { printf '%s' "$d"; return; }
      d=$(dirname "$d")
    done
  fi
  printf '%s' "$1"
}

rel() { printf '%s' "${1#"$root"/}"; }

# Names are single path segments starting with a letter or digit, so "../x" can't escape the trackside folder
# and trackside's own folders (".state", "_archive") never count as features or tracks.
valid_name() { [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]]; }

list_features() {
  local d
  for d in "$1"/*/; do
    [ -d "$d" ] || continue
    valid_name "$(basename "$d")" && basename "$d"
  done
}

# list_tracks <keep> <feature>: a folder counts as a track only once it holds a STATE.md.
list_tracks() {
  local d
  for d in "$1/$2"/*/; do
    [ -f "$d/STATE.md" ] || continue
    valid_name "$(basename "$d")" && basename "$d"
  done
}

# resolve_name <keep> <name>: the track a /trackside:start name means, as <feature>/<track>. Only the full name
# counts: a bare track name doesn't say which feature it belongs to, and could mean another track once one is added.
resolve_name() {
  [[ "$2" == */* ]] || return 0
  local f="${2%%/*}" t="${2#*/}"
  valid_name "$f" && valid_name "$t" && [ -f "$1/$f/$t/STATE.md" ] && printf '%s/%s' "$f" "$t"
  return 0
}

# bind_chat <keep> <session id> <name> [move]: binds the chat to the track and prints it. Returns 1 when the name
# matches no track or several. Returns 2, printing the current track, when the chat has unsaved work on another
# track: switching would leave that work to be saved into the wrong one. "move" says that work belongs to the new
# track, so it moves with the chat and the old track's note about it goes.
bind_chat() {
  local target before
  target=$(resolve_name "$1" "$3")
  [ -n "$target" ] || return 1
  before=$(cat "$1/.state/track-$2" 2>/dev/null || true)
  if [ -n "$before" ] && [ "$before" != "$target" ] && [ -f "$1/.state/dirty-$2" ] && [ "${4:-}" != move ]; then
    printf '%s' "$before"
    return 2
  fi
  # A reminder, an unbinding note or an offer of a name left from before no longer applies once the chat is on another
  # track.
  if [ "$before" != "$target" ]; then
    rm -f "$1/.state/nudged-$2" "$1/.state/off-$2" "$1/.state/owed-$2" "$1/.state/rename-$2" "$1/.state/rename-shown-$2"
    [ -z "$before" ] || note_drop "$(note_file "$1" "$before")" "$2"
  fi
  rm -f "$1/.state/unbound-$2"
  printf '%s\n' "$target" > "$1/.state/track-$2"
  title_map "$1" "$2" "$target"
  printf '%s' "$target"
}

# title_map <keep> <session id> <track|off>: remembers the track the chat's title is on, whatever the title, so a fork or
# a cleared chat with that title follows where the user left it, a track's name included.
title_map() {
  local t
  t=$(cat "$1/.state/seen-$2" 2>/dev/null)
  [ -n "$t" ] && [[ "$t" != *" (unbound)" ]] && map_name "$1" "$t" "$3"
  return 0
}

# unbind_chat <keep> <session id>: unbinds the chat, dropping its unsaved-work marker and its line in the track's
# note, and prints the track it was on. unbound-<session> keeps a compaction or resume from rebinding it by its name,
# and end.sh hands "off" to the chat a /clear starts.
unbind_chat() {
  local before
  before=$(cat "$1/.state/track-$2" 2>/dev/null || true)
  [ -n "$before" ] || return 0
  note_drop "$(note_file "$1" "$before")" "$2"
  rm -f "$1/.state/track-$2" "$1/.state/dirty-$2" "$1/.state/saved-$2" "$1/.state/nudged-$2" "$1/.state/owed-$2" \
    "$1/.state/rename-$2" "$1/.state/rename-shown-$2"
  touch "$1/.state/unbound-$2"
  title_map "$1" "$2" off
  printf '%s' "$before"
}

# A /clear starts a new session with no link to the one it ends, except that both run in the same Claude Code process,
# whose id a hook sees as $PPID. end.sh leaves cleared-<process id>: the track, or "off" when the user unbound the chat.
# cleared_note <keep> <process id> prints it while it's under a minute old, so the note of an earlier clear in the same
# process can't apply.
cleared_note() {
  local f="$1/.state/cleared-$2"
  [ -n "$2" ] && [ -n "$(find "$f" -mmin -1 2>/dev/null)" ] && cat "$f"
}

# name_offer <keep> <session id> <name>: <name>, or, when another chat has it, "<name> · 2" or the next number no chat
# has. A chat's name is the title trackside last saw for it (seen-<session>); a chat bound before trackside offered names
# and recorded titles counts as named after its track, as trackside named chats then. Prints nothing when this chat
# already has <name>.
name_offer() {
  local st="$1/.state" want="$3" n=1 s
  [ "$(cat "$st/seen-$2" 2>/dev/null)" != "$want" ] || return 0
  while :; do
    s=$( { grep -lxF -- "$want" "$st"/seen-* 2>/dev/null
           [ "$n" != 1 ] || ! keep_title "$3" || grep -lxF -- "$want" "$st"/track-* 2>/dev/null | while IFS= read -r f; do
             f=${f##*/track-}; [ -f "$st/seen-$f" ] || [ -f "$st/name-$f" ] || [ -f "$st/name-asked-$f" ] || printf 'track-%s\n' "$f"; done
         } | sed 's#.*/##' | grep -vx -e "seen-$2" -e "track-$2" | head -1)
    [ -n "$s" ] || { printf '%s' "$want"; return 0; }
    n=$((n + 1)); want="$3 · $n"
  done
}

# offer_name <keep> <session id> <track before> <track>: when a chat moves to a track it wasn't offered before, the first
# time it's bound or while its name is still the one offered for another track, leaves the name to offer in
# rename-<session> and records the track in name-asked-<session>, so a declined offer isn't made again. The prompt hook
# takes the offer on the user's "rename". It carries over /clear (cleared_note).
offer_name() {
  local st="$1/.state" cur want
  [ "$3" != "$4" ] && names_chats "$1" "$4" || return 1
  if [ -f "$st/name-asked-$2" ]; then
    [ "$(cat "$st/name-asked-$2")" != "$4" ] || return 1
    cur=$(cat "$st/seen-$2" 2>/dev/null); cur=${cur% · [0-9]*}
    [ "$cur" != "$4" ] && keep_title "$cur" && [[ "$cur" != *" (unbound)" ]] || return 1
  fi
  printf '%s\n' "$4" > "$st/name-asked-$2"
  want=$(name_offer "$1" "$2" "$4")
  [ -n "$want" ] || return 1
  printf '%s\n' "$want" > "$st/rename-$2"
  rm -f "$st/rename-shown-$2"
}

# offer_line <keep> <session id>: the line that offers the chat the name in rename-<session>, saying, when it's
# numbered, which name another chat has: this chat's own when they share it, as a fork does, else the unnumbered one.
offer_line() {
  local st="$1/.state" want base cur
  want=$(cat "$st/rename-$2" 2>/dev/null)
  [ -n "$want" ] || return 0
  base=${want% · [0-9]*}
  cur=$(cat "$st/seen-$2" 2>/dev/null)
  [ -n "$cur" ] && grep -lxF -- "$cur" "$st"/seen-* 2>/dev/null | grep -qvx "$st/seen-$2" && base=$cur
  if [ "$base" != "$want" ]; then
    printf 'reply rename to name this chat "%s" (another chat has "%s"). Otherwise it keeps its name.' "$want" "$base"
  else
    printf 'reply rename to name this chat "%s" after its track. Otherwise it keeps its name.' "$want"
  fi
}

# A name the user gave a chat survives /clear, so it can stand in for the track name in the title: trackside records
# each chat's own name as SessionStart reports it, remembers which track that name is on, and leaves the name be.

# keep_title <title>: true for a title trackside set itself, a track name or one marked unbound.
keep_title() {
  [[ "$1" == *" (unbound)" ]] && return 0
  [[ "$1" == */* ]] && valid_name "${1%%/*}" && valid_name "${1#*/}"
}

# name_file <keep> <name>: where trackside remembers the track a chat with this name is on.
name_file() { printf '%s/.state/named-%s' "$1" "$(printf '%s' "$2" | cksum | tr ' ' '-')"; }

# chat_name <keep> <session id>: the chat's own name, if the user gave it one.
chat_name() { cat "$1/.state/name-$2" 2>/dev/null || true; }

# map_name <keep> <name> <track>, named_track <keep> <name>. A chat the user unbound is mapped to "off", which
# no track can be named, so it isn't bound on its own again after /clear.
map_name() { [ -z "$2" ] || printf '%s\n' "$3" > "$(name_file "$1" "$2")"; }
named_track() { [ -z "$2" ] || cat "$(name_file "$1" "$2")" 2>/dev/null || true; }

# starts_clean <keep> <feature>/<track>: true for a track whose CONTEXT.md says each item starts clean, so only
# CONTEXT.md and LESSONS.md carry over from one item to the next.
starts_clean() { grep -qiE '^\*\*Each item starts clean:\*\*[[:space:]]*yes' "$1/$2/CONTEXT.md" 2>/dev/null; }

# names_chats <keep> <feature>/<track>: false for a track whose CONTEXT.md says "**Name chats after the track:** no",
# such as one whose own rules name its chats, so trackside offers its chats no name.
names_chats() { ! grep -qiE '^\*\*Name chats after the track:\*\*[[:space:]]*no' "$1/$2/CONTEXT.md" 2>/dev/null; }

# save_due <state dir> <session id>: true once TRACKSIDE_SAVE_MINUTES (default 15; 0 means always) have passed since
# this chat last saved its track, or when it hasn't saved yet. The clock is this chat's own last save: another
# chat editing the same STATE.md, for example to add an Inbox line, says nothing about this chat's work.
save_due() {
  local mins="${TRACKSIDE_SAVE_MINUTES:-15}"
  [[ "$mins" =~ ^[0-9]+$ ]] || mins=15
  [ "$mins" = 0 ] || [ ! -f "$1/saved-$2" ] || [ -n "$(find "$1/saved-$2" -mmin +"$mins" 2>/dev/null)" ]
}

# A track's unsaved-work note (<stamp>.unsaved) has one line per chat with work STATE.md doesn't have yet:
# date, session id, "-" while the chat is open or "ended", and the time in seconds. Notes from older versions have only
# the date, or no seconds.
note_file() { printf '%s.unsaved' "$(stamp_file "$1" "$2")"; }

# note_set <note> <session id> <-|ended>: writes or replaces this chat's line.
note_set() {
  local tmp
  tmp=$(mktemp "$1.XXXXXX") || return 0
  { [ ! -f "$1" ] || awk -F'\t' -v s="$2" '$2 != s' "$1"
    printf '%s\t%s\t%s\t%s\n' "$(date +%Y-%m-%d\ %H:%M)" "$2" "$3" "$(date +%s)"; } > "$tmp" && mv "$tmp" "$1"
}

# note_drop <note> <session id|left>: removes this chat's line, or with "left" the lines of chats that left work
# behind; the file goes when no line is left.
note_drop() {
  local tmp
  [ -f "$1" ] || return 0
  tmp=$(mktemp "$1.XXXXXX") || return 0
  if [ "$2" = left ]; then note_lines "$1" open > "$tmp"; else awk -F'\t' -v s="$2" '$2 != s' "$1" > "$tmp"; fi
  if [ -s "$tmp" ]; then mv "$tmp" "$1"; else rm -f "$tmp" "$1"; fi
}

# note_lines <note> <left|open>: the lines of chats that left work behind (ended, older than a day, or from an older
# version that named no chat), or the others. A line without seconds is aged by the file.
note_lines() {
  local old=0
  [ -z "$(find "$1" -mmin +1440 2>/dev/null)" ] || old=1
  awk -F'\t' -v now="$(date +%s)" -v old="$old" -v want="$2" \
    '{ left = ($2 == "" || $3 == "ended" || ($4 == "" && old) || ($4 != "" && now - $4 > 86400)) }
     (want == "left") == left' "$1" 2>/dev/null
}

compactions() { local c; c=$(cat "$1/compactions-$2" 2>/dev/null); [[ "$c" =~ ^[0-9]+$ ]] && echo "$c" || echo 0; }

# context_usage <transcript>: "<tokens> <model> <compaction size>" for the main chat, read from the end of its
# transcript: the context its last reply was sent with, its model, and the size at which it last compacted on its own
# (0 when that isn't in the last 3 MB). Prints nothing when no reply is.
context_usage() {
  [ -f "$1" ] || return 0
  tail -c 3000000 "$1" 2>/dev/null | grep -E '"type":"assistant"|"subtype":"compact_boundary"' |
    jq -R -s -r '[split("\n")[] | fromjson? | select(.isSidechain != true)] as $l
      | ([$l[] | select(.type == "assistant" and .message.usage != null and .message.model != "<synthetic>")] | last) as $a
      | ([$l[] | select(.subtype == "compact_boundary" and .compactMetadata.trigger == "auto")] | last) as $b
      | if $a == null then empty else
          "\([$a.message.usage | .input_tokens, .cache_read_input_tokens, .cache_creation_input_tokens | numbers] | add // 0) \($a.message.model | gsub("[^A-Za-z0-9._-]"; "_")) \($b.compactMetadata.preTokens // 0)"
        end' 2>/dev/null
}

# compact_point <state dir> <model>: the context size at which this model's chats compact on their own:
# CLAUDE_CODE_AUTO_COMPACT_WINDOW when it holds a value Claude Code accepts, else the largest size trackside has seen
# one compact at, since an idle compaction can run well below it. Prints nothing until then.
compact_point() {
  local w="${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-}"
  if [[ "$w" =~ ^[0-9]+$ ]] && [ "$w" -ge 100000 ]; then echo "$w"; return; fi
  cat "$1/limit-$2" 2>/dev/null || true
}

# size_due <state dir> <session id> <tokens> <model>: true once the chat has compacted COMPACT_LIMIT times (default 2),
# or its context has reached TRACKSIDE_OFFER_PERCENT (default 90) of where its model compacts.
size_due() {
  local lim="${COMPACT_LIMIT:-2}" pct="${TRACKSIDE_OFFER_PERCENT:-90}" cp
  [[ "$lim" =~ ^[0-9]+$ ]] || lim=2
  [[ "$pct" =~ ^[0-9]+$ ]] || pct=90
  [ "$(compactions "$1" "$2")" -ge "$lim" ] && return 0
  cp=$(compact_point "$1" "$4")
  [[ "$cp" =~ ^[0-9]+$ ]] && [[ "$3" =~ ^[0-9]+$ ]] && [ $(( $3 * 100 )) -ge $(( cp * pct )) ]
}

# chat_messages <transcript>: the main chat's last 20 messages, one JSON object each, {r: USER or ASSISTANT, x: its
# text, cut at 1500 characters}, without tool calls, tool output, summaries, background-task notices or context hooks
# added.
chat_messages() {
  tail -c 3000000 "$1" 2>/dev/null | jq -R -c 'fromjson?
    | select((.type == "user" or .type == "assistant") and .isSidechain != true and .isMeta != true and .isCompactSummary != true)
    | {r: (if .type == "user" then "USER" else "ASSISTANT" end),
       x: (.message.content | if type == "string" then . else ([.[]? | select(.type == "text") | .text] | join("\n")) end)}
    | select(.x != "" and (.x | test("^<(task-notification|local-command-)") | not)) | .x |= .[0:1500]' 2>/dev/null |
    tail -n 20
}

# sections <file>: one line per "## " heading outside code fences: its name, its line and the last line of its
# section, tab-separated; a heading with no name is named "-", so no field is ever empty.
sections() {
  awk '/^(```|~~~)/ { fence = !fence }
       !fence && /^## / { if (n) print name "\t" s "\t" NR - 1; name = substr($0, 4); sub(/[[:space:]]+$/, "", name)
                          if (name == "") name = "-"; s = NR; n = 1 }
       END { if (n) print name "\t" s "\t" NR }' "$1" 2>/dev/null
}

# section <file> <heading>: the lines under the heading named exactly "## <heading>".
section() {
  local name s e
  while IFS=$'\t' read -r name s e; do
    if [ "$name" = "$2" ]; then sed -n "$((s + 1)),${e}p" "$1"; return 0; fi
  done < <(sections "$1")
  return 0
}

# section_line <STATE.md> <heading>: the first entry under "## <heading>", skipping comments and blank lines.
section_line() {
  section "$1" "$2" | awk '$0 !~ /^[[:space:]]*(<!--.*-->)?[[:space:]]*$/ { sub(/^[[:space:]]*[-*][[:space:]]*/, ""); print; exit }' | cut -c1-140
}

current_line() { section_line "$1" Current; }

# age_days <file>: whole days since the file last changed.
age_days() {
  local m
  m=$(date -r "$1" +%s 2>/dev/null) || { echo 0; return; }
  echo $(( ($(date +%s) - m) / 86400 ))
}

# goal_line <CONTEXT.md>: the text of its **Goal:** line, unless that's still the template's placeholder.
goal_line() {
  sed -n 's/^\*\*Goal:\*\*[[:space:]]*//p' "$1" 2>/dev/null | head -1 | grep -v '^<' | cut -c1-140
}

# track_rows <keep>: one line per track: feature, track, current work (or its goal when nothing is in flight,
# so a new chat can still tell what the track is for), last update, days since.
track_rows() {
  local f t s work goal
  for f in $(list_features "$1"); do
    for t in $(list_tracks "$1" "$f"); do
      s="$1/$f/$t/STATE.md"
      work=$(current_line "$s" | tr '\t' ' ')
      if [[ "$(printf '%s' "$work" | tr 'A-Z' 'a-z')" =~ ^((ticket:[[:space:]]*)?none([^a-z]|$)|$) ]]; then
        goal=$(goal_line "$1/$f/$t/CONTEXT.md" | tr '\t' ' ')
        [ -n "$goal" ] && work="Goal: $goal"
      fi
      # Empty fields are written as "-": two tabs in a row would read as one, shifting the fields after them.
      printf '%s\t%s\t%s\t%s\t%s\n' "$f" "$t" "${work:--}" "$(date -r "$s" +%Y-%m-%d 2>/dev/null || echo -)" "$(age_days "$s")"
    done
  done
}

# listed <file> <label>: the backticked entries after "**<label>:**", on its line and the list under it.
listed() {
  awk -v l="**$2:**" 'index($0, l) { c = 1; print; next } c && /^[[:space:]]*-/ { print; next } { c = 0 }' "$1" 2>/dev/null \
    | grep -oE '`[^`]+`' | tr -d '`'
}

# source_docs <keep> <feature>: the feature's source docs that exist, and its DECISIONS.md, relative to $root.
source_docs() {
  local p
  {
    listed "$1/$2/FEATURE.md" "Source docs" | while IFS= read -r p; do
      case "$p" in *'<'*|*'*'*|*' '*) continue ;; esac
      [ -f "$root/$p" ] && printf '%s\n' "$p"
    done
    [ -f "$1/$2/DECISIONS.md" ] && rel "$1/$2/DECISIONS.md" && echo
  } | awk 'NF && !seen[$0]++'
}

# ids_in <file>...: the IDs, such as AD-28 or CP-041, that the files mention.
ids_in() { cat "$@" 2>/dev/null | grep -oE '[A-Z]+-[0-9]+' | sort -u; }

# doc_index <file> <scratch dir>: "f<TAB>-<TAB><checksum>" for the whole file and, for Markdown, one line per
# heading section ("s<TAB><heading><TAB><checksum>") and per ID it defines ("a<TAB><ID><TAB><checksum>"). A
# section runs to the next heading of any level, so an edit shows up only in the section it's in.
doc_index() {
  local d
  printf 'f\t-\t%s\n' "$(cksum < "$1" | tr ' ' '-')"
  case "$1" in *.md|*.markdown) ;; *) return 0 ;; esac
  d=$(mktemp -d "$2/idx.XXXXXX") || return 0
  LC_ALL=C awk -v d="$d" '
    function section(k) { if (out) close(out); n++; out = sprintf("%s/%06d", d, n); printf "%06d\ts\t%s\n", n, k > (d "/keys") }
    BEGIN { section("(before the first heading)") }
    /^(```|~~~)/ { fence = !fence }
    !fence && /^#+[ \t]/ {
      k = $0; sub(/^#+[ \t]+/, "", k); sub(/[ \t]+#*[ \t]*$/, "", k); gsub(/\t/, " ", k)
      if (++seen[k] > 1) k = k " (" seen[k] ")"
      section(k)
      if (match(k, /[A-Z]+-[0-9]+/)) printf "%06d\ta\t%s\n", n, substr(k, RSTART, RLENGTH) > (d "/keys")
    }
    { print > out }
    !fence && /^\|[ \t]*\**[A-Z]+-[0-9]+/ && match($0, /[A-Z]+-[0-9]+/) {
      id = substr($0, RSTART, RLENGTH); f = d "/a_" id
      print >> f; close(f)
      if (!(id in ids)) { ids[id]; printf "a_%s\ta\t%s\n", id, id > (d "/keys") }
    }' "$1"
  awk 'NR == FNR { sum[$3] = $1 "-" $2; next } { split($0, p, "\t"); print p[2] "\t" p[3] "\t" sum[p[1]] }' \
    <(cd "$d" && cksum [0-9]* a_* 2>/dev/null) "$d/keys"
  rm -r "${d:?}"
}

# repos_of <FEATURE.md>: the folders on its "Repos:" line, or "." for the project root.
repos_of() {
  local line
  line=$(grep -m1 -iE '^[-*[:space:]]*(\*\*)?repos:' "$1" 2>/dev/null \
    | sed -E 's/^[^:]*:[[:space:]]*(\*\*)?[[:space:]]*//; s/`//g')
  [ -n "$line" ] || line="."
  printf '%s\n' "$line" | tr ',' '\n' | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s#/$##' | grep -v '^$'
}

# The reload. Claude Code caps each hook's output at 10,000 characters, measured hook by hook, so the
# reload is two outputs: load.sh's messages with FEATURE.md and CONTEXT.md, and load-state.sh's STATE.md, with
# LESSONS.md after it on a track whose items start clean. Each part stays under reload_budget, counted in bytes (never
# fewer than characters); cuts fall at line ends, and a file that doesn't fit loses whole sections, which are named.
hook_limit=10000
reload_budget=$(( hook_limit - 700 ))
# An output still over cut_over is cut to cut_to, which leaves room for the line that says so.
cut_over=$(( hook_limit - 200 ))
cut_to=$(( hook_limit - 400 ))

# chat_binding <keep> <session id> <title> [process id after /clear]: the track a starting chat is on: its binding,
# else the track of the chat a /clear just ended, else the track remembered for its title, else the track its title
# names. Reads only, so the reload hooks, which run in parallel, agree on it.
chat_binding() {
  local b named c
  b=$(cat "$1/.state/track-$2" 2>/dev/null || true)
  [ -n "$b" ] || [ ! -f "$1/.state/unbound-$2" ] || return 0
  # The chat this one cleared, when the hook passes the process id after a /clear.
  if [ -z "$b" ] && [ -n "${4:-}" ]; then
    c=$(cleared_note "$1" "$4")
    [ "$c" != off ] || return 0
    [ -n "$c" ] && [ -f "$1/$c/STATE.md" ] && b="$c"
  fi
  # Where the user last left a chat with this title (title_map) comes before the track a title names, so a chat that
  # took a track's name and then left the track doesn't go back to it.
  if [ -z "$b" ] && [ -n "$3" ] && [[ "$3" != *" (unbound)" ]]; then
    named=$(named_track "$1" "$3")
    [ "$named" != off ] || return 0
    [ -n "$named" ] && [ -f "$1/$named/STATE.md" ] && b="$named"
  fi
  if [ -z "$b" ] && [[ "$3" == */* ]] && valid_name "${3%%/*}" && valid_name "${3#*/}" && [ -f "$1/$3/STATE.md" ]; then
    b="$3"
  fi
  printf '%s' "$b"
}

_emit_add() { o+="$1"$'\n'; }

# emit_file <title> <file> <budget> [sections that always load...]: the file under a "=== <title> ===" line, whole when
# it fits the budget, else its sections in order while they fit, the listed ones always, and a line naming the rest.
emit_file() {
  local title="$1" f="$2" b="$3" o="" i n used size pre left want name s e
  local -a names starts ends inc
  shift 3
  _emit_add ""
  if [ ! -f "$f" ]; then _emit_add "=== $title: missing ($(rel "$f")) ==="; printf '%s' "$o"; return; fi
  _emit_add "=== $title ($(rel "$f")) ==="
  if [ "$(wc -c < "$f" | tr -d ' ')" -le "$b" ]; then _emit_add "$(cat "$f")"; printf '%s' "$o"; return; fi
  names=(); starts=(); ends=(); inc=()
  while IFS=$'\t' read -r name s e; do
    [ -n "$name" ] || continue
    names+=("$name"); starts+=("$s"); ends+=("$e"); inc+=(0)
  done < <(sections "$f")
  n=${#names[@]}
  if [ "$n" -eq 0 ]; then
    _emit_add "$(lines_within "$(( b > 0 ? b : 0 ))" < "$f")"
    _emit_add "[Cut to stay under the hook output limit: read $(rel "$f") for the rest.]"
    printf '%s' "$o"; return
  fi
  pre=""
  [ "${starts[0]}" -gt 1 ] && pre=$(sed -n "1,$(( starts[0] - 1 ))p" "$f")
  used=$(bytes "$pre")
  for want in "$@"; do
    for ((i = 0; i < n; i++)); do
      [ "${names[$i]}" = "$want" ] || continue
      size=$(sed -n "${starts[$i]},${ends[$i]}p" "$f" | wc -c)
      inc[$i]=1
      used=$(( used + size ))
    done
  done
  for ((i = 0; i < n; i++)); do
    [ "${inc[$i]}" = 1 ] && continue
    size=$(sed -n "${starts[$i]},${ends[$i]}p" "$f" | wc -c)
    if [ $(( used + size )) -le "$b" ]; then
      inc[$i]=1
      used=$(( used + size ))
    fi
  done
  [ -n "$pre" ] && _emit_add "$pre"
  left=""
  for ((i = 0; i < n; i++)); do
    if [ "${inc[$i]}" = 1 ]; then
      _emit_add "$(sed -n "${starts[$i]},${ends[$i]}p" "$f")"
    else
      left="${left:+$left, }${names[$i]}"
    fi
  done
  [ -n "$left" ] && _emit_add "[Not loaded, to stay under the hook output limit: $left. Read $(rel "$f") for them.]"
  printf '%s' "$o"
}

# fsize <file>: its size in bytes, 0 when it's missing.
fsize() { if [ -f "$1" ]; then wc -c < "$1" | tr -d ' '; else echo 0; fi; }

# reload_files <keep> <track> <room>: FEATURE.md and CONTEXT.md for the first reload output, in <room> bytes. When
# both don't fit, FEATURE.md gets what CONTEXT.md leaves, but never less than half.
reload_files() {
  local fdir="$1/${2%%/*}" tdir="$1/$2" room="$3" fb a
  fb=$room
  if [ $(( $(fsize "$fdir/FEATURE.md") + $(fsize "$tdir/CONTEXT.md") )) -gt "$room" ]; then
    fb=$(( room - $(fsize "$tdir/CONTEXT.md") ))
    [ "$fb" -ge $(( room / 2 )) ] || fb=$(( room / 2 ))
  fi
  a=$(emit_file "FEATURE.md" "$fdir/FEATURE.md" "$fb")
  printf '%s\n' "$a"
  emit_file "CONTEXT.md" "$tdir/CONTEXT.md" $(( room - $(bytes "$a") - 100 ))
}

# reload_state <keep> <track>: the second reload output. STATE.md comes first, so a last-resort cut can't take its
# Current and Next step; the room LESSONS.md needs, up to half, is held back from STATE.md's budget instead.
reload_state() {
  local tdir="$1/$2" last held=0 o
  last="$tdir/STATE.md"
  if starts_clean "$1" "$2" && [ -f "$tdir/LESSONS.md" ]; then
    last="$tdir/LESSONS.md"
    held=$(fsize "$last")
    [ "$held" -le $(( reload_budget / 2 )) ] || held=$(( reload_budget / 2 ))
  fi
  o="The state of $2, the track this chat is on:"$'\n'
  o+="$(emit_file "STATE.md" "$tdir/STATE.md" $(( reload_budget - 200 - held )) "Inbox" "Current" "Next step")"$'\n'
  [ "$last" = "$tdir/STATE.md" ] || o+="$(emit_file "LESSONS.md" "$last" $(( reload_budget - $(bytes "$o") - 100 )))"$'\n'
  if [ "$(bytes "$o")" -gt "$cut_over" ]; then
    o="$(printf '%s' "$o" | lines_within "$cut_to")"$'\n'"[Cut to stay under the hook output limit: read $(rel "$last") in full.]"
  fi
  printf '%s' "$o"
}

# The stamp is local runtime state: it describes this machine's checkouts, so it stays out of git.
stamp_file() { printf '%s/.state/stamp-%s@%s' "$1" "${2%%/*}" "${2#*/}"; }

# worktree_root <root> <cwd>: the Claude Code worktree (under .claude/worktrees/) a session works in, if any.
worktree_root() {
  local rest
  case "$2" in
    "$1"/.claude/worktrees/?*)
      rest="${2#"$1"/.claude/worktrees/}"
      printf '%s/.claude/worktrees/%s' "$1" "${rest%%/*}" ;;
  esac
}

# repo_dir <root> <repo> <worktree>: where to read a repo listed in FEATURE.md. In a worktree session the
# project's own repo (".") is read in the worktree, since that's the checkout being edited.
repo_dir() {
  if [ "$2" = "." ]; then printf '%s' "${3:-$1}"; else printf '%s/%s' "$1" "$2"; fi
}

# repo_status <dir>: git status of a repo, leaving out trackside's own folder, which isn't project work even when
# it sits inside the project's repo.
repo_status() { git -C "$1" status --porcelain -- ':(exclude).trackside' 2>/dev/null; }

# changes_fingerprint <dir>: changes when tracked changes or the list of untracked files changes, not only
# the number of files. Untracked contents aren't hashed, so a large untracked file can't slow the hooks;
# untracked_newer covers rewrites of those.
changes_fingerprint() {
  { repo_status "$1"; git -C "$1" diff HEAD -- ':(exclude).trackside' 2>/dev/null; } | git hash-object --stdin 2>/dev/null
}

# untracked_newer <dir> <file>: the first untracked file modified after <file>, if any.
untracked_newer() {
  git -C "$1" ls-files --others --exclude-standard -z -- ':(exclude).trackside' 2>/dev/null \
    | (cd "$1" && xargs -0 sh -c '[ "$#" -gt 0 ] || exit 0; find "$@" -prune -newer "$0" -print' "$2" 2>/dev/null) | head -1
}

# lines_within <bytes>: copy whole lines from stdin while they fit, so a cut never splits a character.
lines_within() { LC_ALL=C awk -v b="$1" '{ n += length($0) + 1; if (n > b) exit; print }'; }

bytes() { printf '%s' "$1" | wc -c | tr -d ' '; }
