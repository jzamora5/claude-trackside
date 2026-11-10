#!/usr/bin/env bash
# Runs the journeys tests/hooks.test.sh can only simulate, in real headless Claude Code sessions: several messages in
# one chat, /compact, /clear, resume, a fork, two chats on one track, the permission prompts and the judge. Each chat is
# one claude process fed its messages through stream-json, so its hooks see what an interactive chat's hooks see, and
# each journey gets its own copy of the eval sandbox (plugins/trackside/evals/_fixture/sandbox.sh).
# Usage: bash tests/live.sh [journey ...]   (default: all; the journeys are the j_* functions below)
# A journey with a failed check runs once more in a fresh sandbox, since a model's answers vary from run to run, and the
# report says which journeys needed that. LIVE_MODEL picks the model (default haiku), LIVE_JOBS how many journeys run at
# once (default 4), and LIVE_KEEP=1 keeps the sandboxes and transcripts for a look afterwards.
set -uo pipefail
here=$(cd "$(dirname "$0")/.." && pwd)
P="$here/plugins/trackside"
CLAUDE=$(command -v claude) || { echo "claude isn't on PATH"; exit 1; }
model="${LIVE_MODEL:-haiku}"
TOOLS=(--allowedTools "Bash Edit Write Read Glob Grep Skill Agent")
# No dot in the folder name: Claude Code names a project's transcript folder after its path with dots turned into
# dashes, and cleanup finds that folder by this name.
R=$(mktemp -d "${TMPDIR:-/tmp}/trackside-live-XXXXXX")
cleanup() {
  pkill -f "tail -f $R/" 2>/dev/null
  [ -z "${LIVE_KEEP:-}" ] || { echo "kept in $R"; return; }
  local d
  for d in "$HOME"/.claude/projects/*"${R##*/}"*; do [ -d "$d" ] && rm -rf "${d:?}"; done
  rm -rf "${R:?}"
}
trap cleanup EXIT

# ---- chats ----
# open <chat> [claude args]: starts a chat in this journey's sandbox. Variables exported before it reach its hooks.
open() {
  local c=$1; shift
  : > "$J/$c.in"
  ( cd "$J" && tail -f "$J/$c.in" | "$CLAUDE" -p --plugin-dir "$P" --setting-sources "" --strict-mcp-config \
      --model "$model" --input-format stream-json --output-format stream-json --verbose "$@" \
      > "$J/$c.out" 2> "$J/$c.err" ) 2>/dev/null &
  echo $! > "$J/$c.pid"
}
results() { local n; n=$(grep -c '"type":"result"' "$J/$1.out" 2>/dev/null); echo "${n:-0}"; }
# send <chat> <message>: sends a message and waits for its reply; sets $reply and $sid.
send() {
  local c=$1 n i
  n=$(( $(results "$c") + 1 ))
  jq -nc --arg t "$2" '{type: "user", message: {role: "user", content: $t}}' >> "$J/$c.in"
  for (( i = 0; i < ${LIVE_TIMEOUT:-300}; i += 2 )); do
    [ "$(results "$c")" -ge "$n" ] && break
    kill -0 "$(cat "$J/$c.pid")" 2>/dev/null || { echo "  chat $c exited: $(tail -1 "$J/$c.err")"; break; }
    sleep 2
  done
  reply=$(jq -rs --argjson n "$n" '[.[] | select(.type == "result")][$n - 1].result // ""' "$J/$c.out")
  sid=$(jq -rs --argjson n "$n" '[.[] | select(.type == "result")][$n - 1].session_id // ""' "$J/$c.out")
  printf '    > %s\n    < %s\n' "$2" "$(printf '%s' "$reply" | head -c 200 | tr '\n' ' ')" >> "$J/talk"
}
# settle <chat> <seconds>: waits for a reply the chat sends on its own, as when a background check comes back; sets
# $reply and $sid like send.
settle() {
  local c=$1 n i
  n=$(( $(results "$c") + 1 ))
  for (( i = 0; i < $2; i += 3 )); do [ "$(results "$c")" -ge "$n" ] && break; sleep 3; done
  [ "$(results "$c")" -ge "$n" ] || return 1
  reply=$(jq -rs --argjson n "$n" '[.[] | select(.type == "result")][$n - 1].result // ""' "$J/$c.out")
  sid=$(jq -rs --argjson n "$n" '[.[] | select(.type == "result")][$n - 1].session_id // ""' "$J/$c.out")
  printf '    (on its own)\n    < %s\n' "$(printf '%s' "$reply" | head -c 200 | tr '\n' ' ')" >> "$J/talk"
}
# close <chat>: ends the chat the way closing it does, SessionEnd included, and waits for it to exit.
close() {
  local pid; pid=$(cat "$J/$1.pid")
  pkill -f "tail -f $J/$1.in" 2>/dev/null
  while kill -0 "$pid" 2>/dev/null; do sleep 0.5; done
}

# ---- what a chat saw ----
title_of() { jq -r 'select(.subtype == "session_title_changed") | .title' "$J/$1.out" | tail -1; }
track_of() { cat "$st/track-$1" 2>/dev/null; }
transcript() { find "$HOME/.claude/projects" -maxdepth 2 -name "$1.jsonl" | head -1; }
# Commands of trackside's own scripts that the permission check stopped.
script_denials() { jq -r 'select(.type == "result") | .permission_denials[]? | .tool_input.command // empty' "$J/$1.out" | grep -F "$P" || true; }
sum() { cksum < "$1" 2>/dev/null; }

# ---- checks ----
ok() {
  local what=$1; shift
  if "$@"; then echo "  ok    $what"; else echo "  FAIL  $what"; echo fail >> "$J/failed"; fi
}
eq() { [ -n "$2" ] && [ "$1" = "$2" ]; }
ne() { [ "$1" != "$2" ]; }
has() { local s=$1; shift; local w; for w in "$@"; do printf '%s' "$s" | grep -qiF -- "$w" || return 1; done; }
none() { [ -z "$1" ]; }
changed() { [ "$(sum "$1")" != "$2" ]; }

save_line() { send "$1" "Set the Current line of .trackside/demo/tickets/STATE.md to: - Ticket: T-1 in progress [verified]. Change nothing else."; }
plain_edit() { send "$1" "Add the comment $2 as the first line of api/app.js. Don't touch .trackside."; }

# ---- journeys ----
j_start() {  # rows 4, 15, 18, 25
  open a
  send a "/trackside:list"
  ok "row 18: /trackside:list shows each track with its start command" has "$reply" demo/tickets demo/research "/trackside:start"
  send a "/trackside:start demo/tickets"; local s=$sid
  ok "row 4: a typed start binds the chat" eq "$(track_of "$s")" demo/tickets
  ok "the first bind shows the offer of the track's name and renames nothing" bash -c "grep -q 'reply rename to name this chat' '$J/a.out' && [ -z '$(title_of a)' ]"
  send a "rename"
  ok "replying rename names the chat after its track" eq "$(title_of a)" demo/tickets
  ok "row 25: no permission prompt for trackside's scripts" none "$(script_denials a)"
  close a
  open b --resume "$s"
  send b "Which track is this chat on? Answer with the track's name only."
  ok "row 15: a resumed chat is still bound" eq "$(track_of "$s")" demo/tickets
  ok "row 15: and says so" has "$reply" demo/tickets
  close b
}

j_work() {  # rows 6, 7, 9, 11, 27
  local f="$T/demo/tickets/STATE.md" b s
  open w "${TOOLS[@]}"
  send w "/trackside:start demo/tickets"; s=$sid
  b=$(sum "$f")
  send w "Do T-1 now, without a plan: edit api/app.js so applyDiscount(100, \"TEN\") returns 90 and other codes leave the total unchanged."
  ok "row 6: the edit landed" grep -q TEN "$J/api/app.js"
  if ! changed "$f" "$b"; then
    ok "row 9: a turn that ended unsaved leaves the save owed" test -f "$st/owed-$s"
    send w "Thanks. What's next? One line."
  fi
  ok "row 6: STATE.md has the work, by the reply or at the next message" changed "$f" "$b"
  ok "row 6: the save stamped the repos" test -s "$st/stamp-demo@tickets"
  ok "row 27: the empty Next step got filled" awk '/^## Next step/{n=1; next} /^## /{n=0} n && /[^[:space:]]/{f=1} END{exit !f}' "$f"
  ok "row 11: .trackside got a save commit" bash -c "git -C '$T' log --format=%s | grep -q '^save: '"
  send w "Add a one-line comment above applyDiscount saying what it does."
  ok "row 7: no save request within 15 minutes of the last save" bash -c "[ ! -f '$st/nudged-$s' ] && [ ! -f '$st/owed-$s' ]"
  # 20 minutes pass.
  touch -t "$(date -v-20M +%Y%m%d%H%M.%S)" "$st/saved-$s"
  b=$(sum "$f")
  send w "Add the comment // end of discounts as the last line of api/app.js."
  changed "$f" "$b" || send w "Thanks. Anything else? One line."
  ok "row 9: once 15 minutes passed, the next work is saved again" changed "$f" "$b"
  close w
}

j_clear() {  # rows 8, 26, 36
  local s
  open c "${TOOLS[@]}" --name my-review
  send c "/trackside:start demo/tickets"; s=$sid
  ok "row 26: a named chat binds" eq "$(track_of "$s")" demo/tickets
  ok "row 26: and keeps its name" ne "$(title_of c)" demo/tickets
  save_line c
  ok "row 8: the save stamped the repos" test -s "$st/stamp-demo@tickets"
  ( cd "$J/api" && echo '// T-1' >> app.js && git commit -qam "T-1: percentage codes" )
  send c "/clear"; s=$sid
  ok "row 26, 36: after /clear the chat is on its track again" eq "$(track_of "$s")" demo/tickets
  ok "row 36: and the user is shown which track" grep -q "trackside: this chat is bound to demo/tickets." "$(transcript "$s")"
  ok "row 8: the reload reports the new commit" grep -q "1 new commit" "$J/c.out"
  send c "Which workspace is this?"
  ok "row 26: and says so" has "$reply" demo/tickets
  ok "row 26: the name stays through /clear" ne "$(title_of c)" demo/tickets
  send c "/trackside:fresh"
  # Its save may run the handoff check in the background and finish once it's back.
  has "$reply" "/clear" || settle c 180 || send c "Go on."
  ok "row 36: /trackside:fresh outside the app says to type /clear" has "$reply" "/clear"
  send c "/clear"
  ok "row 36: the chat after it is on the track" eq "$(track_of "$sid")" demo/tickets
  close c
}

j_compact() {  # row 10
  local f="$T/demo/tickets/STATE.md" b s
  open k "${TOOLS[@]}"
  send k "/trackside:start demo/tickets"; s=$sid
  save_line k
  plain_edit k "// discount codes"
  ok "row 10: an edit right after a save is unsaved work" test -f "$st/dirty-$s"
  send k "/compact"
  ok "row 10: the compaction's reload asks for a save" grep -q "This chat has work STATE.md" "$J/k.out"
  b=$(sum "$f")
  send k "What's the next step?"
  ok "row 10: the next message asks for the save too" grep -q "The last turn's work isn't in" "$(transcript "$s")"
  ok "row 10: the agent saves right after the compaction" changed "$f" "$b"
  plain_edit k "// end"
  send k "/compact"
  ok "row 10: the second compaction is counted" eq "$(cat "$st/compactions-$s" 2>/dev/null)" 2
  send k "What's the next step?"
  ok "row 10: the next message brings the offer to clear this chat" eq "$(cat "$st/offered-$s" 2>/dev/null)" 2
  ok "row 10: the offer says it clears this chat" bash -c "printf '%s' \"\$1\" | grep -qi clear" _ "$reply"
  close k
}

j_fork() {  # row 16
  local s
  open a
  send a "/trackside:start demo/tickets"; s=$sid
  # A fork's transcript doesn't exist yet when it starts, so only its name, here the track's, can link it to the track.
  send a "rename"
  close a
  open f --resume "$s" --fork-session
  send f "Reply with just: ok"
  ok "row 16: a fork is a new session" ne "$sid" "$s"
  ok "row 16: a fork stays on the track, as a second chat on it" eq "$(track_of "$sid")" demo/tickets
  close f
}

j_skillbind() {  # row 17
  open b "${TOOLS[@]}"
  send b "Let's continue the discount tickets."
  ok "row 17: work that fits one track binds the chat" eq "$(track_of "$sid")" demo/tickets
  send b "/clear"
  ok "row 17: a /clear straight after keeps the chat on the track" eq "$(track_of "$sid")" demo/tickets
  close b
}

j_review() {  # the deep review's items that need the user are settled in the chat
  local dup='- 2026-10-19 · T-0 · abc1234 · set up the discount module skeleton and its first test, all green'
  printf '\n## Done log (older)\n%s\n\n## Product notes\n- 2026-10-21: T-2 was dropped, since checkout already blocks totals below zero.\n' "$dup" >> "$T/demo/tickets/NOTES.md"
  printf '%s\n' '/^## Done log$/a' "$dup" . w q | ed -s "$T/demo/tickets/STATE.md"
  git -C "$T" commit -qam "A duplicated line and a contradiction"
  open r "${TOOLS[@]}"
  send r "/trackside:start demo/tickets"
  # As when the review is due at a chat's start: the agent starts the review and handles what comes back. Typed as
  # /trackside:audit in a headless session, the reviewer's own output would be the reply.
  send r "Run the trackside audit skill for demo/tickets now."
  # The review may come back in the background, and the chat carries on once it does.
  ls "$T/demo/tickets"/review-*.md >/dev/null 2>&1 || settle r 240 || true
  ok "the chat handled the review's result" bash -c "ls '$T/demo/tickets'/review-*.md >/dev/null 2>&1"
  ok "its reply brings the choice about T-2 into the chat" has "$reply" T-2
  ok "and asks which changes to apply, instead of pointing to the file" bash -c "printf '%s' \"\$1\" | grep -qiE 'apply|skip' && ! printf '%s' \"\$1\" | grep -q 'Next: apply the lossless'" _ "$reply"
  close r
}

j_names() {  # the name offered at a chat's first bind, numbered when another chat has it
  open a "${TOOLS[@]}"
  send a "/trackside:start demo/tickets"
  send a "rename"
  open b "${TOOLS[@]}"
  send b "/trackside:start demo/tickets"
  ok "a second chat on the track is offered the next number" bash -c "grep 'reply rename to name this chat' '$J/b.out' | grep -qF 'demo/tickets · 2'"
  send b "rename"
  ok "and takes it on rename" eq "$(title_of b)" "demo/tickets · 2"
  send b "/clear"
  send b "Which track is this chat on?"
  ok "after /clear it's still on the track" eq "$(track_of "$sid")" demo/tickets
  ok "and isn't offered a name again" bash -c "[ \$(grep -c 'reply rename to name this chat' '$J/b.out') = 1 ]"
  close a; close b
}

j_off() {  # row 24
  local s
  open o "${TOOLS[@]}"
  send o "/trackside:start demo/research"
  send o "/trackside:start off"; s=$sid
  ok "row 24: off unbinds the chat" bash -c "[ ! -s '$st/track-$s' ]"
  ok "row 24: and renames nothing" none "$(title_of o)"
  send o "/clear"; s=$sid
  ok "row 24: it stays unbound after /clear" bash -c "[ ! -s '$st/track-$s' ]"
  ok "row 24: and is told not to bind on its own" grep -q "The user unbound this chat" "$J/o.out"
  send o "Make applyDiscount in api/app.js return 90 for the code TEN."
  ok "row 24: even when work fits a track" bash -c "[ ! -s '$st/track-$s' ]"
  close o
}

j_two() {  # rows 39, 40
  local f="$T/demo/tickets/STATE.md" note="$st/stamp-demo@tickets.unsaved" b s1 s2
  open t1 "${TOOLS[@]}"
  send t1 "/trackside:start demo/tickets"; s1=$sid
  save_line t1
  plain_edit t1 "// discount codes"
  ok "row 39: the first chat's unsaved work is in the track's note" grep -q "$s1" "$note"
  open t2 "${TOOLS[@]}" --name demo/tickets
  send t2 "Which track is this chat on? Answer with the track's name only."; s2=$sid
  ok "row 39: the second chat is told another open chat has unsaved work" grep -q "Another chat on this track, still open" "$J/t2.out"
  send t2 "Set the Next step line of .trackside/demo/tickets/STATE.md to: - Propose T-2. Change nothing else."
  ok "row 39: the second chat's save leaves the first chat's line" grep -q "$s1" "$note"
  send t1 "Run cat .trackside/demo/tickets/STATE.md and tell me its Next step line."
  ok "row 40: reading STATE.md after another chat saved isn't a save" test -f "$st/dirty-$s1"
  close t1; close t2
  ok "row 39: closing the first chat marks its line ended" bash -c "grep '$s1' '$note' | grep -q ended"
  b=$(sum "$f")
  open t3 "${TOOLS[@]}" --name demo/tickets
  send t3 "Where does this track stand? One line."
  ok "row 39: the next chat is told the last one left off" grep -q "The last chat on this track left off" "$J/t3.out"
  ok "row 39: and fills the gap" bash -c "[ \"\$(cksum < '$f')\" != '$b' ] && ! grep -q '$s1' '$note' 2>/dev/null"
  close t3
}

j_whole() {  # row 37
  local s
  open h
  send h "/trackside:start demo/tickets"; s=$sid
  send h "/trackside:whole"
  ok "row 37: whole keeps this chat whole" test -f "$st/whole-$s"
  ok "row 37: and says where its transcript is" has "$reply" transcript
  send h "/trackside:whole off"
  ok "row 37: off brings the offers back" test ! -f "$st/whole-$s"
  ok "row 37: no permission prompt for either" none "$(script_denials h)"
  close h
}

j_judge() {  # row 38
  local s i f="$T/demo/tickets/STATE.md"
  # Without claude on PATH, as in the desktop app: the judge finds the command Claude Code runs from.
  ( export PATH="$(dirname "$(command -v jq)"):$(dirname "$(command -v git)"):/usr/bin:/bin" TRACKSIDE_JUDGE_TOKENS=1 TRACKSIDE_JUDGE_STEP=1
    open j "${TOOLS[@]}" )
  send j "/trackside:start demo/tickets"; s=$sid
  for (( i = 0; i < 150; i += 3 )); do [ -s "$st/judge-log" ] && break; sleep 3; done
  ok "row 38: the judge runs in the background after a turn" test -s "$st/judge-log"
  # The track moves on, as when another chat saves it, so this chat's reply about where it stands now disagrees with it.
  sed -i '' -e 's/^- Ticket: none \[verified\]$/- Ticket: T-2 (never return a negative total) is in progress on branch t-2 [verified]/' \
    -e 's/^- \[ \] T-1: apply a percentage code in applyDiscount/- [x] T-1, done and merged on 2026-11-08: apply a percentage code in applyDiscount/' "$f"
  send j "Reply with just: ok"
  for (( i = 0; i < 150; i += 3 )); do [ "$(wc -l < "$st/judge-log")" -ge 2 ] && break; sleep 3; done
  ok "row 38: it finds the reply that disagrees with STATE.md" test -s "$st/health-$s"
  send j "Is T-1 done? One line."
  ok "row 38: the next message brings the findings" test ! -f "$st/health-$s"
  ok "row 38: shown to the user as a warning too" grep -q "trackside's context check" "$J/j.out"
  ok "row 38: and the reply goes by STATE.md" bash -c "printf '%s' \"\$1\" | grep -qiE 'done|merged|finished|yes'" _ "$reply"
  close j
}

j_create() {  # row 19
  local before new
  before=$(find "$T" -name CONTEXT.md | sort)
  open n "${TOOLS[@]}"
  send n "I want to start on checkout emails."
  ok "row 19: nothing is created before the OK" eq "$(find "$T" -name CONTEXT.md | sort)" "$before"
  send n "Yes, create it. Its goal: email shoppers an order confirmation after checkout."
  # The agent offers a track first and the start skill then proposes its name and goal, so it can take a second OK.
  [ "$(find "$T" -name CONTEXT.md | sort)" != "$before" ] || send n "Yes, create it as proposed."
  new=$(comm -13 <(printf '%s\n' "$before") <(find "$T" -name CONTEXT.md | sort) | head -1)
  new=${new%/CONTEXT.md}; new=${new#"$T/"}
  ok "row 19: the track is created" test -n "$new"
  ok "row 19: the chat is bound to it" eq "$(track_of "$sid")" "$new"
  # The templates' guidance comments stay; a placeholder outside them doesn't.
  ok "row 19: no placeholder lines left" bash -c "[ -n '$new' ] && [ -z \"\$(grep -rhE '<[a-z][a-z ,/-]*>|TODO|TBD' '$T/$new' | grep -v '<!--')\" ]"
  ok "row 19: INDEX.md lists it" bash -c "[ -n '$new' ] && grep -qF '$new' '$T/INDEX.md'"
  close n
}

j_close() {  # row 20
  open x "${TOOLS[@]}"
  send x "We're done with the research track, close it."
  ok "row 20: nothing is archived before the OK" test ! -d "$T/_archive/demo/research"
  send x "Yes: move Q-1 to the Inbox of demo/tickets, then close it."
  ok "row 20: the track is archived" test -d "$T/_archive/demo/research"
  ok "row 20: Q-1 went to demo/tickets" grep -q Q-1 "$T/demo/tickets/STATE.md"
  ok "row 20: .trackside got a commit" bash -c "[ \$(git -C '$T' rev-list --count HEAD) -gt 1 ]"
  close x
}

j_switch() {  # row 23
  local f="$T/demo/tickets/STATE.md" b
  open sw "${TOOLS[@]}"
  send sw "/trackside:start demo/tickets"
  save_line sw
  plain_edit sw "// discount codes"
  b=$(sum "$f")
  send sw "Switch to the research track."
  # The save before a switch may run its handoff check in the background and switch once it's back.
  [ "$(track_of "$sid")" = demo/research ] || settle sw 180 || send sw "Go on."
  ok "row 23: the chat is on demo/research" eq "$(track_of "$sid")" demo/research
  ok "row 23: the edit was saved to demo/tickets first" changed "$f" "$b"
  close sw
}

j_docs() {  # rows 12, 14
  local n
  open d "${TOOLS[@]}"
  send d "/trackside:digest demo"
  ok "row 12: DIGEST.md is built from the design doc" bash -c "head -3 '$T/demo/DIGEST.md' 2>/dev/null | grep -q 'Built from docs/spec.md'"
  close d
  n=$(grep -c '^## D-' "$T/demo/DECISIONS.md")
  open e "${TOOLS[@]}"
  send e "/trackside:start demo/research settle Q-1: codes expire 30 days after they're issued; we rejected codes that never expire."
  ok "row 14: a start with a request binds the track" eq "$(track_of "$sid")" demo/research
  ok "row 14: the answer is a new decision" bash -c "[ \$(grep -c '^## D-' '$T/demo/DECISIONS.md') -gt $n ]"
  ok "row 14: with its rejected option" bash -c "awk '/^## D-/{n++} n>$n' '$T/demo/DECISIONS.md' | grep -qi 'rejected'"
  close e
}

j_merged() {  # row 34
  command -v gh >/dev/null || { echo "  skip  row 34: needs gh"; return; }
  git -C "$J/api" remote add origin https://github.com/cli/cli.git
  printf '%s\n' '/^## Done log/a' '- T-0 shipped in api#1' . w q | ed -s "$T/demo/tickets/STATE.md"
  open m "${TOOLS[@]}"
  send m "/trackside:start demo/tickets"
  send m "/trackside:next"
  ok "row 34: a merged pull request is marked" bash -c "grep 'api#1' '$T/demo/tickets/STATE.md' | grep -q 'merged 2019-10-04'"
  close m
}

j_unbound() {  # rows 21, 22
  open u "${TOOLS[@]}"
  send u "I'm done with this ticket."
  ok "row 22: an unbound chat runs no tests and makes no commit" bash -c "! jq -r 'select(.type==\"assistant\") | .message.content[]? | select(.type==\"tool_use\" and .name==\"Bash\") | .input.command' '$J/u.out' | grep -qE 'node|git commit'"
  ok "row 22: and marks no ticket done" bash -c "! grep -q '\[x\]' '$T/demo/tickets/STATE.md'"
  close u
  open v "${TOOLS[@]}"
  send v "For the discount tickets, we agreed codes are case-insensitive: TEN and ten both work."
  send v "Save this to trackside."
  ok "row 21: the chat is bound to the track that fits" eq "$(track_of "$sid")" demo/tickets
  ok "row 21: what it knows is saved" grep -qi 'case' "$T/demo/tickets/STATE.md" "$T/demo/DECISIONS.md"
  close v
}

# ---- run ----
all=$(declare -F | awk '$3 ~ /^j_/ { sub(/^j_/, "", $3); print $3 }')
want=${*:-$all}
# run <journey> <sandbox>
run() {
  J="$R/$2"; T="$J/.trackside"; st="$T/.state"
  mkdir -p "$J" && ( cd "$J" && bash "$P/evals/_fixture/sandbox.sh" ) >/dev/null || { echo "  FAIL  sandbox"; return 1; }
  "j_$1"
}
attempt() {
  run "$1" "$1" > "$R/$1.log" 2>&1 || echo "  FAIL  the journey stopped" >> "$R/$1.log"
  grep -q '^  FAIL ' "$R/$1.log" || return 0
  run "$1" "$1-2" > "$R/$1-2.log" 2>&1 || echo "  FAIL  the journey stopped" >> "$R/$1-2.log"
}
for j in $want; do
  declare -F "j_$j" >/dev/null || { echo "no journey $j (have: $(echo $all))"; exit 1; }
  while [ "$(jobs -r | wc -l)" -ge "${LIVE_JOBS:-4}" ]; do sleep 1; done
  ( attempt "$j" ) &
done
wait
fails=0; checks=0; cost=0; again=""
for j in $want; do
  last=$j
  if [ -f "$R/$j-2.log" ]; then
    last=$j-2
    echo "$j: a check failed, so it ran again"
    grep '^  FAIL ' "$R/$j.log"; echo "  conversation:"; cat "$R/$j/talk" 2>/dev/null
    echo "$j, second try"
    grep -q '^  FAIL ' "$R/$last.log" || again="$again $j"
  else
    echo "$j"
  fi
  cat "$R/$last.log"
  [ "$last" = "$j" ] || [ ! -s "$R/$last/failed" ] || { echo "  conversation:"; cat "$R/$last/talk" 2>/dev/null; }
  checks=$(( checks + $(grep -cE '^  (ok|FAIL) ' "$R/$last.log") ))
  fails=$(( fails + $(grep -c '^  FAIL ' "$R/$last.log") ))
  for o in "$R/$j"/*.out "$R/$j-2"/*.out; do
    [ -f "$o" ] || continue
    c=$(jq -rs '[.[] | select(.type == "result")] | group_by(.session_id) | map(max_by(.total_cost_usd).total_cost_usd) | add // 0' "$o")
    cost=$(awk -v a="$cost" -v b="$c" 'BEGIN { print a + b }')
  done
done
[ -z "$again" ] || echo "Passed only on a second try:$again"
printf 'passed %d, failed %d (%s, about $%.2f)\n' $(( checks - fails )) "$fails" "$model" "$cost"
[ "$fails" = 0 ]
