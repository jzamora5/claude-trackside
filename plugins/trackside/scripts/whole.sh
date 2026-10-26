#!/usr/bin/env bash
# Usage: whole.sh <project root> <session id> on|off
# Keeps a chat whole, so trackside never offers to continue it in a fresh chat or runs its judge on it, or undoes that.
# Says where the chat's transcript is and how long Claude Code keeps it, since a chat kept for an audit needs it.
set -uo pipefail
. "$(dirname "$0")/common.sh"
root=$(keep_root "${1:?project root}" "$PWD")
sid="${2:-}"
keep=$(keep_dir "$root")
[[ "$sid" =~ ^[A-Za-z0-9._-]+$ ]] || { echo "No valid session id: $sid" >&2; exit 1; }
[ -d "$keep" ] || { echo "No trackside folder at $keep." >&2; exit 1; }
mkdir -p "$keep/.state"

case "${3:-}" in
  off)
    rm -f "$keep/.state/whole-$sid"
    echo "trackside will offer to continue this chat in a fresh one again once it gets long."
    exit 0 ;;
  on) date +%Y-%m-%d > "$keep/.state/whole-$sid" ;;
  *) echo "Say on or off." >&2; exit 1 ;;
esac
echo "This chat stays whole: trackside won't offer to continue it in a fresh chat or check it against the track."
t=$(find "$HOME/.claude/projects" -maxdepth 2 -name "$sid.jsonl" 2>/dev/null | head -n 1)
[ -z "$t" ] || echo "Its transcript: ${t/#$HOME/~}"

# The later file wins, as in Claude Code's own order: user, then project, then local settings.
setting() {
  local v="" f x
  for f in "$HOME/.claude/settings.json" "$root/.claude/settings.json" "$root/.claude/settings.local.json"; do
    x=$(jq -r --arg k "$1" '.[$k] // empty' "$f" 2>/dev/null) && [ -n "$x" ] && v=$x
  done
  printf '%s' "$v"
}
if [ "${CLAUDE_CODE_ENTRYPOINT:-}" = claude-desktop ]; then
  days=$(setting desktopSessionCleanupPeriodDays)
  if [ -z "$days" ]; then
    echo "Claude Code keeps the transcripts of desktop app chats at any age, since desktopSessionCleanupPeriodDays isn't set."
  else
    echo "Claude Code deletes desktop app transcripts after $days days (desktopSessionCleanupPeriodDays); raise it, or copy the transcript, to keep this one longer."
  fi
else
  days=$(setting cleanupPeriodDays)
  from="cleanupPeriodDays in your settings"
  [ -n "$days" ] || { days=30; from="cleanupPeriodDays, the default"; }
  echo "Claude Code deletes a transcript once it goes $days days unused ($from); raise it, or copy the transcript, to keep this one longer."
fi
