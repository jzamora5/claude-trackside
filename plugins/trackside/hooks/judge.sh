#!/usr/bin/env bash
# Stop, in the background: once a bound chat's context passes TRACKSIDE_JUDGE_TOKENS (default 300000; 0 turns it off),
# a cheaper model (TRACKSIDE_JUDGE_MODEL, default haiku) compares the chat's last messages with the track's files and
# the feature's DECISIONS.md, each cut at 40 KB, at most once each time the chat compacts and never once a fresh chat
# is due anyway. It runs as its own Claude Code process, so the chat spends nothing on it. Only findings whose quotes
# appear word for word, the chat's in its own replies and the track's in the file named, are kept for the prompt hook
# to show. Each run logs its counts, never the chat's text, to .state/judge-log.
. "$(dirname "$0")/lib.sh"
here="$(cd "$(dirname "$0")" && pwd)"
line="${TRACKSIDE_JUDGE_TOKENS:-300000}"
[[ "$line" =~ ^[0-9]+$ ]] && [ "$line" -gt 0 ] || exit 0
[ -n "$binding" ] && [ -f "$keep/$binding/STATE.md" ] && [ -z "$worktree" ] && [ ! -f "$st/whole-$sid" ] || exit 0
transcript=$(field .transcript_path)
read -r tokens model point <<<"$(context_usage "$transcript")"
[[ "${tokens:-}" =~ ^[0-9]+$ ]] && [ "$tokens" -ge "$line" ] || exit 0
c=$(compactions "$st" "$sid")
[ "$(cat "$st/judged-$sid" 2>/dev/null)" != "$c" ] && [ "$(cat "$st/offered-$sid" 2>/dev/null)" != "$c" ] || exit 0
size_due "$st" "$sid" "$tokens" "$model" && exit 0
cli=$(command -v claude 2>/dev/null || printf '%s' "${CLAUDE_CODE_EXECPATH:-}")
[ -n "$cli" ] && [ -x "$cli" ] || exit 0
echo "$c" > "$st/judged-$sid"

w=$(mktemp -d "${TMPDIR:-/tmp}/trackside-judge.XXXXXX") || exit 0
trap 'rm -rf "$w"' EXIT
chat_messages "$transcript" > "$w/messages"
last=$(field .last_assistant_message)
# The transcript is written after the hook can run, so the reply that just ended may not be in it yet.
[ -z "$last" ] || jq -n -c --arg x "${last:0:1500}" '{r: "ASSISTANT", x: $x}' >> "$w/messages"
norm() { tr -s ' \t\r\n' ' ' | tr -d '*`'; }
jq -r 'select(.r == "ASSISTANT") | .x' "$w/messages" | norm > "$w/said"
{
  for f in "$keep/${binding%%/*}/FEATURE.md" "$keep/${binding%%/*}/DECISIONS.md" "$keep/$binding/CONTEXT.md" \
    "$keep/$binding/LESSONS.md" "$keep/$binding/STATE.md"; do
    [ -f "$f" ] || continue
    printf '=== FILE %s ===\n' "${f##*/}"; lines_within 40000 < "$f"; printf '\n'
    norm < "$f" > "$w/file-${f##*/}"
  done
  printf '=== CHAT ===\n'
  jq -r '"\(.r): \(.x)\n"' "$w/messages"
} > "$w/prompt"
out=$(cd "$w" && TRACKSIDE_CHILD=1 "$cli" -p --model "${TRACKSIDE_JUDGE_MODEL:-haiku}" --tools "" --strict-mcp-config \
  --no-session-persistence --disable-slash-commands --setting-sources "" --system-prompt-file "$here/judge.md" \
  < "$w/prompt" 2>/dev/null)

clean() { printf '%s' "$1" | norm | sed -e 's/^ *//' -e 's/ *$//' -e 's/^"//' -e 's/"$//'; }
raw=0; kept=0; found=""
while IFS= read -r l; do
  [[ "$l" == *" ||| "*" ||| "*" ||| "* ]] || continue
  raw=$((raw + 1))
  l=$(printf '%s' "$l" | sed -E 's/^[[:space:]]*([-*]|[0-9]+[.)])[[:space:]]+//')
  said=$(clean "${l%% ||| *}"); r=${l#* ||| }
  f=$(printf '%s' "${r%% ||| *}" | tr -d ' `*"'); r=${r#* ||| }
  says=$(clean "${r%% ||| *}"); why=$(clean "${r#* ||| }")
  [ -f "$w/file-$f" ] && [ "${#said}" -ge 15 ] && [ "${#says}" -ge 15 ] || continue
  grep -qF -- "$said" "$w/said" && grep -qF -- "$says" "$w/file-$f" || continue
  found+="- The chat said \"$said\"; $f says \"$says\" (${why:0:200})"$'\n'
  kept=$((kept + 1))
  [ "$kept" -lt 3 ] || break
done <<<"$out"
[ -z "$found" ] || printf '%s' "$found" > "$st/health-$sid"
printf '%s\t%s\t%s\t%s\tfound %s\tkept %s\n' "$(date +%Y-%m-%d\ %H:%M)" "$binding" "$model" "$tokens" "$raw" "$kept" >> "$st/judge-log"
exit 0
