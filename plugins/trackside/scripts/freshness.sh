#!/usr/bin/env bash
# freshness.sh <project root> <feature>/<track> [cwd]: what changed in the feature's source docs and repos since
# the track's STATE.md was last written, compared with the stamps the edit hook records. Pass the session's
# working directory as cwd so a Claude Code worktree session is checked in its worktree.
set -uo pipefail
. "$(dirname "$0")/common.sh"
root=$(keep_root "${1:?project root}" "$PWD")
track="${2:?<feature>/<track>}"
keep=$(keep_dir "$root")
stamp=$(stamp_file "$keep" "$track")
worktree=$(worktree_root "$root" "${3:-}")

# doc_changes <doc> <old index> <new index> <cited IDs>: one line on what changed in the doc, then "cited<TAB>ID"
# for each ID the track cites that changed or was removed.
doc_changes() {
  awk -F'\t' -v doc="$1" -v cited=" $4 " '
    function add(name, item) { if (++cnt[name] <= lim[name]) list[name] = list[name] (cnt[name] > 1 ? ", " : "") item }
    function part(name, label) { if (!cnt[name]) return; out = out (out == "" ? "" : "; ") label list[name] (cnt[name] > lim[name] ? " and " (cnt[name] - lim[name]) " more" : "") }
    function seen(kind, key, how) {
      if (kind == "s") { add("s" how, "\"" key "\""); return }
      add("a" how, key)
      if (how != "n" && index(cited, " " key " ")) add("c", key (how == "r" ? " (removed)" : ""))
    }
    BEGIN { lim["sc"] = lim["sn"] = lim["sr"] = 5; lim["ac"] = lim["an"] = lim["ar"] = 12; lim["c"] = 30 }
    NR == FNR { if ($1 != "f") { old[$1 SUBSEP $2] = $3; order[++n] = $1 SUBSEP $2 } next }
    $1 == "f" { next }
    { k = $1 SUBSEP $2; now[k] = 1; if (!(k in old)) seen($1, $2, "n"); else if (old[k] != $3) seen($1, $2, "c") }
    END {
      for (i = 1; i <= n; i++) if (!(order[i] in now)) { split(order[i], p, SUBSEP); seen(p[1], p[2], "r") }
      part("sc", "sections changed: "); part("sn", "new sections: "); part("sr", "removed sections: ")
      part("ac", "IDs changed: "); part("an", "new IDs: "); part("ar", "removed IDs: ")
      print "- " doc ": " (out == "" ? "changed" : out)
      if (cnt["c"]) print "cited\t" list["c"]
    }' "$2" "$3"
}

# Source docs first: the reload keeps only the first lines of this report, and they're what a track's state
# most often rests on.
docs="$stamp.docs"
if [ -s "$docs" ]; then
  tmp=$(mktemp -d "$keep/.state/fresh.XXXXXX")
  cited=$(ids_in "$keep/$track/STATE.md" "$keep/$track/CONTEXT.md" | tr '\n' ' ')
  report=""
  while IFS= read -r doc; do
    awk -F'\t' -v d="$doc" '$1 == d { print $2 "\t" $3 "\t" $4 }' "$docs" > "$tmp/old"
    if [ ! -f "$root/$doc" ]; then
      report="$report- $doc: no longer there"$'\n'
    elif [ "$(awk -F'\t' '$1 == "f" { print $3 }' "$tmp/old")" != "$(cksum < "$root/$doc" | tr ' ' '-')" ]; then
      doc_index "$root/$doc" "$tmp" > "$tmp/new"
      report="$report$(doc_changes "$doc" "$tmp/old" "$tmp/new" "$cited")"$'\n'
    fi
  done < <(cut -f1 "$docs" | awk '!seen[$0]++')
  rm -r "${tmp:?}"
  if [ -z "$report" ]; then
    echo "Source docs: no changes since STATE.md was last written."
  else
    echo "Source docs changed since STATE.md was last written. Before relying on what STATE.md says about these parts, read them with the trackside lookup skill:"
    printf '%s' "$report" | grep -v $'^cited\t'
    c=$(printf '%s' "$report" | sed -n $'s/^cited\t//p' | awk 'NR > 1 { printf ", " } { printf "%s", $0 }')
    [ -n "$c" ] && echo "This track's STATE.md or CONTEXT.md cites IDs that changed: $c. Check those lines against the docs."
  fi
fi

if [ ! -s "$stamp" ]; then
  echo "No git stamp yet: STATE.md hasn't been saved through trackside in a git repo here, so its claims aren't checked against git."
  exit 0
fi

echo "Since STATE.md was last written ($(head -1 "$stamp" | cut -f6)):"
while IFS=$'\t' read -r repo hash branch dirty fingerprint _; do
  [ -n "$repo" ] || continue
  [ "$branch" != - ] || branch=""
  [ "$fingerprint" != - ] || fingerprint=""
  dir=$(repo_dir "$root" "$repo" "$worktree")
  label="$repo"
  [ "$repo" = "." ] && [ -n "$worktree" ] && label=". in worktree ${worktree##*/}"
  if ! git -C "$dir" rev-parse --git-dir >/dev/null 2>&1; then
    echo "- $label: not a git repo here, not checked"
    continue
  fi
  if ! git -C "$dir" cat-file -e "$hash^{commit}" 2>/dev/null; then
    echo "- $label: the stamped commit ${hash:0:7} isn't in this checkout (rebased, or another clone)"
    continue
  fi
  now_branch=$(git -C "$dir" branch --show-current 2>/dev/null)
  changes=()
  if [ "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" != "$hash" ]; then
    ahead=$(git -C "$dir" rev-list --count "$hash..HEAD" 2>/dev/null || echo 0)
    behind=$(git -C "$dir" rev-list --count "HEAD..$hash" 2>/dev/null || echo 0)
    [ "$ahead" -gt 0 ] && changes+=("$ahead new commit(s)")
    [ "$behind" -gt 0 ] && changes+=("moved back $behind commit(s)")
  fi
  [ "$now_branch" != "$branch" ] && changes+=("branch changed from ${branch:-detached} to ${now_branch:-detached}")
  if [ "$(changes_fingerprint "$dir")" != "$fingerprint" ] || [ -n "$(untracked_newer "$dir" "$stamp")" ]; then
    changes+=("uncommitted changes differ: $(repo_status "$dir" | wc -l | tr -d ' ') file(s) now, $dirty then")
  fi
  if [ "${#changes[@]}" -eq 0 ]; then
    echo "- $label (${now_branch:-detached}): no changes"
  else
    summary=$(printf '%s; ' "${changes[@]}")
    echo "- $label (${now_branch:-detached}): ${summary%; }"
    git -C "$dir" log --oneline -5 "$hash..HEAD" 2>/dev/null | sed 's/^/    /'
    [ "${ahead:-0}" -gt 5 ] && echo "    … and $((ahead - 5)) more"
  fi
  ahead=0
done < "$stamp"
echo "Recheck files before acting on what STATE.md says about them."
