#!/usr/bin/env bash
# PostToolUse (Edit|Write|NotebookEdit|WebFetch|WebSearch|Agent|Bash): edits to project files and research mark
# the chat "dirty". Editing the bound track's STATE.md clears that and stamps each of the feature's repos
# with its current commit, and its source docs with their sections and IDs, so the next chat can see what
# changed since. PreToolUse (Bash) only notes STATE.md's checksum, so a shell command that changes it counts as a
# save and one that only reads it doesn't.
. "$(dirname "$0")/lib.sh"
[ -n "$binding" ] || exit 0
tdir="$keep/$binding"

# mark_dirty: records unsaved work. Once a save is due, it asks for one while the agent is still working, once
# per save, so the state is updated before the reply and the reply stays the last thing the user reads.
mark_dirty() {
  touch "$st/dirty-$sid"
  [ -z "$worktree" ] && save_due "$st" "$sid" || return 0
  [ -f "$st/nudged-$sid" ] && return 0
  touch "$st/nudged-$sid"
  jq -n --arg p "$(rel "$tdir")/STATE.md" '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: ("Before you write your reply to the user, update " + $p + ": its Current and Next step, a line each, marked [verified] or [assumed], and any decision made since, where FEATURE.md says decisions go. Do it quietly, without mentioning it in your reply.")}}'
}

fp=""
case "$(field .tool_name)" in
  WebFetch|WebSearch) mark_dirty; exit 0 ;;
  Bash)
    # A save through the shell, such as sed on STATE.md, counts like an Edit: the command names the bound track's
    # STATE.md, by its track path or from the track's folder, and the file's checksum changed while it ran, so
    # another chat's edit doesn't count. Other shell commands still don't count as work.
    cmd=$(field .tool_input.command)
    case "$cmd" in *STATE.md*) ;; *) exit 0 ;; esac
    [[ "$cmd" == *"$binding"* ]] || [ "$(field .cwd)" = "$tdir" ] || exit 0
    sum=$(cksum < "$tdir/STATE.md" 2>/dev/null)
    if [ "$(field .hook_event_name)" = PreToolUse ]; then printf '%s\n' "$sum" > "$st/before-$sid"; exit 0; fi
    before=$(cat "$st/before-$sid" 2>/dev/null); rm -f "$st/before-$sid"
    [ -n "$before" ] && [ "$sum" != "$before" ] || exit 0
    fp="$tdir/STATE.md" ;;
  Agent)
    # trackside's auditor and handoff check only read the track's own files, so asking them isn't new research.
    case "$(field .tool_input.subagent_type)" in
      trackside:auditor|auditor|trackside:handoff-check|handoff-check) ;;
      *) mark_dirty ;;
    esac
    exit 0 ;;
esac

# Empty fields are written as "-": freshness reads the stamp with tab as the separator, and two tabs in a row would
# read as one.
write_stamp() {
  local stamp tmp r dir
  stamp=$(stamp_file "$keep" "$binding")
  tmp=$(mktemp "$st/stamp.XXXXXX") || return 0
  while IFS= read -r r; do
    dir=$(repo_dir "$root" "$r" "$worktree")
    git -C "$dir" rev-parse --git-dir >/dev/null 2>&1 || continue
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$r" \
      "$(git -C "$dir" rev-parse HEAD 2>/dev/null)" \
      "$(git -C "$dir" branch --show-current 2>/dev/null | grep . || echo -)" \
      "$(repo_status "$dir" | wc -l | tr -d ' ')" \
      "$(changes_fingerprint "$dir" | grep . || echo -)" \
      "$(date -u +%Y-%m-%dT%H:%MZ)" >> "$tmp"
  done < <(repos_of "$keep/${binding%%/*}/FEATURE.md")
  mv "$tmp" "$stamp"
}

write_doc_stamp() {
  local out tmp doc sum
  out="$(stamp_file "$keep" "$binding").docs"
  tmp=$(mktemp "$st/docs.XXXXXX") || return 0
  while IFS= read -r doc; do
    sum=$(cksum < "$root/$doc" | tr ' ' '-')
    # A doc that hasn't changed keeps its lines, so a save doesn't index a large doc again for nothing.
    if awk -F'\t' -v d="$doc" -v s="$sum" '$1 == d && $2 == "f" && $4 == s { found = 1 } END { exit !found }' "$out" 2>/dev/null; then
      awk -F'\t' -v d="$doc" '$1 == d' "$out" >> "$tmp"
    else
      doc_index "$root/$doc" "$st" | awk -v d="$doc" '{ print d "\t" $0 }' >> "$tmp"
    fi
  done < <(source_docs "$keep" "${binding%%/*}")
  if [ -s "$tmp" ]; then mv "$tmp" "$out"; else rm -f "$tmp" "$out"; fi
}

[ -n "$fp" ] || fp=$(field '.tool_input.file_path // .tool_input.notebook_path')
case "$fp" in
  "$tdir/STATE.md")
    # The save fills this chat's own unsaved work, or the gap the reload asked it to fill; a note another chat that's
    # still open left stays for that chat.
    note="$(stamp_file "$keep" "$binding").unsaved"
    if [ "$(cut -s -f2 "$note" 2>/dev/null)" = "$sid" ] || [ -f "$st/gap-$sid" ]; then rm -f "$note"; fi
    rm -f "$st/dirty-$sid" "$st/nudged-$sid" "$st/owed-$sid" "$st/gap-$sid"
    touch "$st/saved-$sid"
    write_stamp
    write_doc_stamp
    bash "$(dirname "$0")/../scripts/index.sh" "$root" 2>/dev/null
    issues=$(bash "$(dirname "$0")/../scripts/audit.sh" "$root" "$binding" save 2>/dev/null)
    [ -z "$issues" ] || jq -n --arg c "trackside's check of $binding after this save:
$issues
Fix the ones that only move or de-duplicate text, or fill in what's missing, in this turn, in one edit that gets well under any limit, before your reply and without mentioning it. Anything that drops or rewords content, ask the user about at the next natural pause." \
      '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $c}}' ;;
  # Writing a review file means the deep review's result was handled, so the next one waits until it's due again.
  "$tdir"/review-*.md) bash "$(dirname "$0")/../scripts/audit.sh" "$root" "$binding" reviewed 2>/dev/null ;;
  # Claude Code puts worktrees under .claude/worktrees/, so edits there are project edits.
  "$root"/.claude/worktrees/*) mark_dirty ;;
  # Claude's own files (settings, memory, plans, CLAUDE.md instructions) aren't project work.
  "$keep"/*|"$root"/.claude/*|"${HOME:-/nonexistent}"/.claude/*|*/CLAUDE.md|"") ;;
  "$root"/*) mark_dirty ;;
esac
exit 0
