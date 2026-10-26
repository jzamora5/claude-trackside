# Shared setup for the trackside hooks. Sourced, not run.
# Every hook fails open: without jq, a trackside folder or a session id, it exits 0 and changes nothing,
# so trackside never breaks a session. The Claude Code process the judge starts (hooks/judge.sh) runs none of them.
set -uo pipefail
[ -z "${TRACKSIDE_CHILD:-}" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0
. "$(dirname "${BASH_SOURCE[0]}")/../scripts/common.sh"

input=$(cat)
field() { jq -r "$1 // \"\"" <<<"$input" 2>/dev/null; }
root=$(keep_root "${CLAUDE_PROJECT_DIR:-$PWD}" "$(field .cwd)")
keep=$(keep_dir "$root")
[ -d "$keep" ] || exit 0
st="$keep/.state"
if [ ! -d "$st" ]; then
  mkdir -p "$st" || exit 0
  printf '*\n' > "$st/.gitignore"
fi

sid=$(field .session_id)
[[ "$sid" =~ ^[A-Za-z0-9._-]+$ ]] || exit 0
binding=$(cat "$st/track-$sid" 2>/dev/null || true)
# In a Claude Code worktree session, CLAUDE_PROJECT_DIR stays at the main checkout and cwd is the worktree.
worktree=$(worktree_root "$root" "$(field .cwd)")
