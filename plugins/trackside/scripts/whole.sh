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

# setting <key> <files...>: the key's value in the last of the files that sets it, as Claude Code reads them in order.
setting() {
  local k="$1" v="" f x
  shift
  for f in "$@"; do
    x=$(jq -r --arg k "$k" '.[$k] // empty' "$f" 2>/dev/null) && [ -n "$x" ] && v=$x
  done
  printf '%s' "$v"
}
keep_days=$(setting cleanupPeriodDays "$HOME/.claude/settings.json" "$root/.claude/settings.json" "$root/.claude/settings.local.json")
from="cleanupPeriodDays in your settings"
[[ "$keep_days" =~ ^[0-9]+$ ]] || { keep_days=30; from="cleanupPeriodDays, the default"; }
if [ "${CLAUDE_CODE_ENTRYPOINT:-}" = claude-desktop ]; then
  # Claude Code reads this key only from user or managed settings, and 0 means no age limit. A desktop transcript is
  # deleted once it's older than both this and cleanupPeriodDays.
  days=$(setting desktopSessionCleanupPeriodDays "$HOME/.claude/settings.json")
  if ! [[ "$days" =~ ^[0-9]+$ ]] || [ "$days" = 0 ]; then
    echo "Claude Code keeps the transcripts of desktop app chats at any age: desktopSessionCleanupPeriodDays isn't above 0 in your user settings (managed settings could still set it)."
  else
    [ "$days" -ge "$keep_days" ] || days=$keep_days
    echo "Claude Code deletes a desktop app transcript once it goes $days days unused (the larger of desktopSessionCleanupPeriodDays and $from); raise them, or copy the transcript, to keep this one longer."
  fi
else
  echo "Claude Code deletes a transcript once it goes $keep_days days unused ($from); raise it, or copy the transcript, to keep this one longer."
fi
