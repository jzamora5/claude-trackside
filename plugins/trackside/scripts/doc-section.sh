#!/usr/bin/env bash
# doc-section.sh <project root> <session id> <ID or heading words>: the exact text of the bound feature's source docs
# and DECISIONS.md for an ID such as AD-28 or for heading words, with each part's path and lines to cite. Read-only.
# The lookup skill runs it, so a chat reads the source itself rather than a summary of it.
set -uo pipefail
. "$(dirname "$0")/common.sh"
root=$(keep_root "${1:?project root}" "$PWD")
sid="${2:-}"
query="${3:-}"
keep=$(keep_dir "$root")
[[ "$sid" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "No valid session id: $sid" >&2; exit 1; }
[ -n "$query" ] || { echo "Say what to look up: an ID such as AD-28, or words from a heading." >&2; exit 1; }
b=$(cat "$keep/.state/track-$sid" 2>/dev/null || true)
[ -n "$b" ] || { echo "This chat isn't bound to a track, so there are no source docs to look in."; exit 0; }
docs=$(source_docs "$keep" "${b%%/*}")
[ -n "$docs" ] || { echo "${b%%/*}'s FEATURE.md names no source docs."; exit 0; }

# For an ID: the sections whose heading names it, the table rows it defines (with their table's header), then the
# other lines that mention it, where a later decision may override it. For words: the sections whose heading holds
# them all, in any order, or failing that, the lines that do. A section runs to the next heading of the same or a
# higher level.
out=$(printf '%s\n' "$docs" | while IFS= read -r d; do
  LC_ALL=C awk -v q="$query" -v doc="$d" '
    BEGIN { id = (q ~ /^[A-Z]+-[0-9]+$/); nw = split(tolower(q), w, /[ \t]+/); re = "(^|[^A-Za-z0-9-])" q "([^0-9]|$)" }
    /^(```|~~~)/ { fence = !fence }
    { line[NR] = $0; fenced[NR] = fence }
    !fence && match($0, /^#+[ \t]/) { n++; hl[n] = NR; lv[n] = RLENGTH - 1; ht[n] = substr($0, RLENGTH + 1) }
    function words(t,   i) { t = tolower(t); for (i = 1; i <= nw; i++) if (w[i] != "" && !index(t, w[i])) return 0; return 1 }
    function hit(t) { return id ? (t ~ re) : words(t) }
    END {
      for (i = 1; i <= n; i++) {
        if (!hit(ht[i])) continue
        e = NR
        for (j = i + 1; j <= n; j++) if (lv[j] <= lv[i]) { e = hl[j] - 1; break }
        printf "== %s:%d-%d · %s\n", doc, hl[i], e, ht[i]
        for (k = hl[i]; k <= e; k++) { print line[k]; shown[k] = 1 }
        found = 1
      }
      if (id) for (k = 1; k <= NR; k++) {
        if (shown[k] || fenced[k] || line[k] !~ ("^\\|[ \t]*\\**" q "([^0-9]|$)")) continue
        h = k; while (h > 1 && line[h - 1] ~ /^\|/) h--
        printf "== %s:%d · a row of the table at line %d\n", doc, k, h
        print line[h]; if (h + 1 < k) print line[h + 1]
        print line[k]; shown[k] = 1; found = 1
      }
      m = 0
      for (k = 1; k <= NR; k++) {
        if (shown[k]) continue
        if (id ? (line[k] ~ re) : (!found && words(line[k]))) {
          if (m++ == 0) printf "== %s: other lines that %s\n", doc, (id ? "mention " q : "contain it")
          if (m <= 15) printf "%d: %s\n", k, substr(line[k], 1, 240)
        }
      }
      if (m > 15) printf "… and %d more\n", m - 15
    }' "$root/$d"
done)
[ -n "$out" ] || { echo "Nothing in the source docs matches \"$query\". Try other words from the heading, or an ID."; exit 0; }
# With several matches, where each one is comes first, so a cut never hides where to read the rest.
index=""
n=$(printf '%s\n' "$out" | grep -c '^== ')
if [ "$n" -gt 1 ]; then
  index="Matches ($n):"$'\n'"$(printf '%s\n' "$out" | grep '^== ' | head -n 50 | sed 's/^== /- /')"$'\n'
  [ "$n" -le 50 ] || index+="… and $((n - 50)) more: use more words, or an ID, to narrow it"$'\n'
fi
room=$(( 8000 - $(bytes "$index") ))
if [ "$(bytes "$out")" -gt "$room" ]; then
  printf '%s%s\n%s\n' "$index" "$(printf '%s' "$out" | lines_within "$room")" "[Cut at 8,000 bytes: read the rest in the docs, at the matches listed first.]"
else
  printf '%s%s\n' "$index" "$out"
fi
