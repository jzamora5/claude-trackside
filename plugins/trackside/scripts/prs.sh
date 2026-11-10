#!/usr/bin/env bash
# prs.sh <project root> <feature>/<track>: the state of each pull request the track's STATE.md names as
# <repo>#<number>, where <repo> is a folder on FEATURE.md's Repos line, skipping lines that already say it merged or
# closed. Each one that merged or closed is marked on the lines that name it, as "api#12 (merged 2026-10-24)", here
# rather than by the agent, which skipped that quiet edit in live runs. It only reads from gh, in that repo's folder,
# at most 10 per run, and prints nothing for a pull request gh can't read, or at all without gh.
set -uo pipefail
. "$(dirname "$0")/common.sh"
root=$(keep_root "${1:?project root}" "$PWD")
track="${2:?<feature>/<track>}"
keep=$(keep_dir "$root")
state="$keep/$track/STATE.md"
[ -f "$state" ] && command -v gh >/dev/null 2>&1 || exit 0

# mark <repo> <number> <mark>: adds " (<mark>)" after the first mention of <repo>#<number> on each line that doesn't
# already say merged or closed.
mark() {
  local tmp; tmp=$(mktemp "$state.XXXXXX") || return 0
  awk -v r="$1" -v n="$2" -v m="$3" '
    function marked(line,   s, out, i, k, f, at, len, pre, post) {
      s = line; out = ""
      while (1) {
        at = 0
        for (k = 1; k <= 2; k++) {
          f = (k == 1) ? r "#" n : r " #" n
          i = index(s, f)
          if (i && (!at || i < at)) { at = i; len = length(f) }
        }
        if (!at) return line
        pre = at > 1 ? substr(s, at - 1, 1) : substr(out, length(out), 1)
        post = substr(s, at + len, 1)
        if (pre !~ /[A-Za-z0-9._\/-]/ && post !~ /[0-9]/) return out substr(s, 1, at + len - 1) " (" m ")" substr(s, at + len)
        out = out substr(s, 1, at + len - 1); s = substr(s, at + len)
      }
    }
    tolower($0) !~ /merged|closed/ { $0 = marked($0) }
    { print }' "$state" > "$tmp" && mv "$tmp" "$state" || rm -f "$tmp"
}

n=0
while IFS= read -r r; do
  [ "$r" != "." ] || continue
  dir=$(repo_dir "$root" "$r" "")
  git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || continue
  for num in $(grep -viE 'merged|closed' "$state" | grep -oE "(^|[^A-Za-z0-9._/-])${r//./\\.} ?#[0-9]+" | grep -oE '[0-9]+$' | sort -un); do
    [ "$n" -lt 10 ] || break 2
    n=$((n + 1))
    s=$(cd "$dir" && gh pr view "$num" --json state,mergedAt --jq '.state + " " + ((.mergedAt // "")[0:10])' 2>/dev/null) || continue
    s=$(printf '%s' "$s" | tr 'A-Z' 'a-z' | sed 's/ *$//')
    [ -n "$s" ] || continue
    printf '%s#%s: %s\n' "$r" "$num" "$s"
    case "$s" in merged*|closed*) mark "$r" "$num" "$s" ;; esac
  done
done < <(repos_of "$keep/${track%%/*}/FEATURE.md")
exit 0
