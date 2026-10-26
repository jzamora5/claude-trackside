#!/usr/bin/env bash
# Usage: allow-edits.sh <project root>
# Lets Claude Code edit .trackside/ without a permission prompt, through an Edit allow rule in the project's
# .claude/settings.local.json, which only this user reads, and keeps that file out of the project's git. Safe to run
# again.
set -uo pipefail
. "$(dirname "$0")/common.sh"
root=$(keep_root "${1:?project root}" "$PWD")
f="$root/.claude/settings.local.json"
rule="Edit(/.trackside/**)"
mkdir -p "$root/.claude"
[ -s "$f" ] || printf '{}\n' > "$f"
jq -e . "$f" >/dev/null 2>&1 || { echo "$f isn't valid JSON, so nothing was changed." >&2; exit 1; }
if jq -e --arg r "$rule" 'any(.permissions.allow[]?; . == $r)' "$f" >/dev/null 2>&1; then
  echo "Edits to .trackside/ were already allowed in .claude/settings.local.json."
else
  tmp=$(mktemp "$f.XXXXXX") || exit 1
  jq --arg r "$rule" '.permissions.allow = ((.permissions.allow // []) + [$r])' "$f" > "$tmp" && mv "$tmp" "$f"
  echo "Allowed edits to .trackside/ in .claude/settings.local.json, so trackside's saves won't ask for permission."
fi
# Claude Code keeps settings.local.json out of git only when it creates the file itself.
if git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 && ! git -C "$root" check-ignore -q .claude/settings.local.json; then
  ex=$(git -C "$root" rev-parse --git-path info/exclude)
  case "$ex" in /*) ;; *) ex="$root/$ex" ;; esac
  mkdir -p "$(dirname "$ex")"
  printf '.claude/settings.local.json\n' >> "$ex"
fi
