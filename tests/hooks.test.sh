#!/usr/bin/env bash
# Runs the trackside hooks against simulated hook inputs in a scratch project. Usage: bash tests/hooks.test.sh
set -uo pipefail
H="$(cd "$(dirname "$0")/../plugins/trackside" && pwd)"
R=$(mktemp -d "${TMPDIR:-/tmp}/trackside-test.XXXXXX")
trap 'rm -rf "$R"' EXIT
export CLAUDE_PROJECT_DIR="$R"
unset COMPACT_LIMIT TRACKSIDE_IDLE_DAYS TRACKSIDE_STATE_DAYS TRACKSIDE_SAVE_MINUTES
K="$R/.trackside"
st="$K/.state"
pass=0; fail=0
ok() { if eval "$2"; then pass=$((pass + 1)); echo "PASS $1"; else fail=$((fail + 1)); echo "FAIL $1"; fi; }
hook() { printf '%s' "$2" | "$H/hooks/$1.sh"; [ "$1" != load ] || printf '%s' "$2" | "$H/hooks/load-state.sh"; }
q() { git -C "$1" "${@:2}" >/dev/null 2>&1; }

# A project with two repos and two features: "shop" (two tracks) and "solo" (one track).
for r in api web; do
  mkdir -p "$R/$r"; q "$R/$r" init -b main; q "$R/$r" -c user.name=t -c user.email=t@example.com commit --allow-empty -m "start $r"
done
mkdir -p "$K/shop/tickets" "$K/shop/research" "$K/solo/main"
printf '# Feature: shop\n\n**Repos:** api, web\n\n**Read on start:**\n- DIGEST.md\n' > "$K/shop/FEATURE.md"
printf '# Feature: solo\n' > "$K/solo/FEATURE.md"
printf '# Track: shop/tickets\n**Goal:** ship tickets\n' > "$K/shop/tickets/CONTEXT.md"
state() { printf '# State: %s\n\n## Inbox\n\n## Current\n<!-- comment -->\n- Ticket: %s\n\n## Next step\n- %s\n\n## Done log\n' "$1" "$2" "$3"; }
state shop/tickets "T-7 checkout fix" "edit api/cart.js applyDiscount" > "$K/shop/tickets/STATE.md"
state shop/research "pricing question" "read the vendor docs" > "$K/shop/research/STATE.md"
state solo/main "none" "none" > "$K/solo/main/STATE.md"

echo "--- no trackside folder"
E=$(mktemp -d "${TMPDIR:-/tmp}/trackside-empty.XXXXXX")
for h in bind load track stop; do
  out=$(printf '{"session_id":"s1","prompt":"/trackside:start shop/tickets","source":"startup"}' | CLAUDE_PROJECT_DIR="$E" "$H/hooks/$h.sh"; echo "exit=$?")
  ok "$h is silent without a trackside folder" '[ "$out" = "exit=0" ] && [ ! -e "$E/.trackside" ]'
done
rm -rf "$E"

echo "--- binding"
out=$(hook load '{"session_id":"s1","source":"startup"}')
ok "unbound chat lists tracks with their current work" '[[ "$out" == *"No track is bound"* && "$out" == *"shop/tickets: Ticket: T-7 checkout fix"* && "$out" == *"solo/main"* ]]'
ok "and tells the agent to bind on its own when one track clearly fits, for real work only" '[[ "$out" == *"starts work"* && "$out" == *"not a quick question"* && "$out" == *"if one track clearly fits it"* && "$out" == *"bind the chat to it right away"* ]]'
ok "to ask only when more than one could fit, and to create a track only once the user agrees" '[[ "$out" == *"If more than one track could fit, ask once which"* && "$out" == *"offer once to create a track, and create it only after the user agrees"* && "$out" == *"once the user unbinds it or turns a track down"* ]]'
X=$(mktemp -d "${TMPDIR:-/tmp}/trackside-none.XXXXXX"); mkdir -p "$X/.trackside"
out=$(printf '{"session_id":"x1","source":"startup"}' | CLAUDE_PROJECT_DIR="$X" "$H/hooks/load.sh")
ok "a trackside folder with no tracks yet still offers to create one" '[[ "$out" == *"offer once to create a track"* && "$out" != *"Tracks, their"* ]]'
rm -rf "$X"
ok "the state folder ignores itself in git" '[ "$(cat "$st/.gitignore")" = "*" ]'
out=$(hook bind '{"session_id":"s1","prompt":"/trackside:start shop/tickets"}')
ok "bind names the chat after the track" '[ "$(jq -r .hookSpecificOutput.sessionTitle <<<"$out")" = shop/tickets ]'
ok "bind records the binding" '[ "$(cat "$st/track-s1")" = shop/tickets ]'
out=$(hook bind '{"session_id":"s2","prompt":"/start shop/research"}')
ok "the unprefixed form binds too" '[ "$(cat "$st/track-s2" 2>/dev/null)" = shop/research ]'
for p in "/trackside:start solo" "/trackside:start research" "/trackside:start main" "/trackside:start research fix the totals"; do
  hook bind "{\"session_id\":\"r1\",\"prompt\":\"$p\"}" >/dev/null
  ok "a bare name doesn't bind, even when one track has it: ${p#/trackside:start }" '[ ! -f "$st/track-r1" ]'
done
hook bind '{"session_id":"s3","prompt":"/trackside:start solo/main"}' >/dev/null
out=$(bash "$H/scripts/status.sh" "$R")
ok "the listing gives each track's full start command" '[[ "$out" == *"shop/tickets: Ticket: T-7 checkout fix (start: /trackside:start shop/tickets)"* && "$out" == *"(start: /trackside:start solo/main)"* ]]'
out=$(hook bind '{"session_id":"s8","prompt":"/trackside:start shop/tickets and continue"}')
ok "words after the track are fine" '[ "$(cat "$st/track-s8" 2>/dev/null)" = shop/tickets ]'; rm -f "$st/track-s8"

echo "--- binding from the start skill"
out=$(bash "$H/scripts/bind.sh" "$R" b1 shop/research)
ok "the bind script binds a full name" '[ "$out" = "Bound this chat to shop/research." ] && [ "$(cat "$st/track-b1")" = shop/research ]'
out=$(hook bind '{"session_id":"b1","prompt":"yes, go ahead"}')
ok "the next prompt names the chat after the track" '[ "$(jq -r .hookSpecificOutput.sessionTitle <<<"$out")" = shop/research ] && [ ! -f "$st/title-b1" ]'
out=$(hook bind '{"session_id":"b1","prompt":"and then this"}')
ok "only once" '[ -z "$out" ]'
bash "$H/scripts/bind.sh" "$R" b1 shop/research >/dev/null
ok "binding the same track again doesn't rename the chat" '[ ! -f "$st/title-b1" ]'
out=$(hook bind '{"session_id":"b2","prompt":"/trackside:start shop/tickets"}'); bash "$H/scripts/bind.sh" "$R" b2 shop/tickets >/dev/null
ok "after a typed /trackside:start, the skill's bind is a no-op" '[ "$(cat "$st/track-b2")" = shop/tickets ] && [ ! -f "$st/title-b2" ]'
for a in "b1 shop" "b1 research" "b1 nope" "b1 ../shop/tickets" "b1 shop/tickets/extra" '${CLAUDE_SESSION_ID} shop/research' "b3"; do
  out=$(bash "$H/scripts/bind.sh" "$R" $a 2>&1; echo "exit=$?")
  ok "the bind script refuses: $a" '[[ "$out" == *"exit=1"* ]] && [ "$(cat "$st/track-b1")" = shop/research ] && [ ! -f "$st/track-b3" ]'
done
touch "$st/dirty-b2"
out=$(hook bind '{"session_id":"b2","prompt":"/trackside:start shop/research"}')
ok "a typed switch with unsaved work doesn't rebind" '[ -z "$out" ] && [ "$(cat "$st/track-b2")" = shop/tickets ]'
out=$(bash "$H/scripts/bind.sh" "$R" b2 shop/research 2>&1; echo "exit=$?")
ok "and the bind script says to save it there first" '[[ "$out" == *"unsaved work on shop/tickets. Save it there first"* && "$out" == *"exit=2"* ]] && [ "$(cat "$st/track-b2")" = shop/tickets ]'
rm -f "$st/dirty-b2"
out=$(bash "$H/scripts/bind.sh" "$R" b2 shop/research)
ok "once it's saved, the chat switches" '[ "$out" = "Bound this chat to shop/research." ] && [ "$(cat "$st/title-b2")" = shop/research ]'
touch "$st/dirty-b2"
out=$(bash "$H/scripts/bind.sh" "$R" b2 off)
ok "off unbinds the chat and says its unsaved work wasn't saved" '[ ! -f "$st/track-b2" ] && [ ! -f "$st/dirty-b2" ] && [ "$out" = "Unbound this chat from shop/research. Its work since the last save wasn'"'"'t saved there." ]'
out=$(hook bind '{"session_id":"b2","prompt":"ok"}')
ok "the chat is renamed so its title can't rebind it" '[ "$(jq -r .hookSpecificOutput.sessionTitle <<<"$out")" = "shop/research (unbound)" ]'
out=$(hook load '{"session_id":"b9","source":"clear","session_title":"shop/research (unbound)"}')
ok "a cleared chat with that title stays unbound, and isn't bound on its own" '[ ! -f "$st/track-b9" ] && [[ "$out" == *"No track is bound"* && "$out" == *"The user unbound this chat from its track, so don'"'"'t bind it on your own"* && "$out" != *"bind the chat to it right away"* ]]'
out=$(bash "$H/scripts/bind.sh" "$R" b2 off)
ok "off on an unbound chat says so" '[ "$out" = "This chat isn'"'"'t bound to a track." ]'
hook bind '{"session_id":"b4","prompt":"/trackside:start shop/tickets"}' >/dev/null
out=$(hook bind '{"session_id":"b4","prompt":"/trackside:start off"}')
ok "a typed /trackside:start off unbinds and renames at once" '[ ! -f "$st/track-b4" ] && [ "$(jq -r .hookSpecificOutput.sessionTitle <<<"$out")" = "shop/tickets (unbound)" ]'
B=$(mktemp -d "${TMPDIR:-/tmp}/trackside-nojq.XXXXXX")
for c in dirname mkdir cat basename wc tr rm; do ln -s "$(command -v "$c")" "$B/$c"; done
out=$(PATH="$B" /bin/bash "$H/scripts/bind.sh" "$R" j1 shop/research)
ok "without jq, binding says trackside's hooks are off" '[[ "$out" == *"Bound this chat to shop/research."* && "$out" == *"jq isn'"'"'t installed"* ]]'
out=$(bash "$H/scripts/bind.sh" "$R" j2 shop/research)
ok "with jq it doesn't" '[[ "$out" != *jq* ]]'
rm -rf "$B"; rm -f "$st/track-b1" "$st/track-b2" "$st/track-j1" "$st/track-j2" "$st"/title-*
ok "the agent can run every skill, close included, when the user asks" '! grep -q "disable-model-invocation" "$H"/skills/*/SKILL.md && grep -q "asks in words to close one; never on your own" "$H/skills/close/SKILL.md"'
for p in "/trackside:start shop" "/trackside:start shop/nope" "/trackside:start ../shop/tickets" "/trackside:start .state/x" "hello /trackside:start shop/tickets" "/trackside:startshop/tickets" "/trackside:start shop/tickets/extra"; do
  out=$(hook bind "{\"session_id\":\"s4\",\"prompt\":\"$p\"}")
  ok "no binding for: $p" '[ -z "$out" ] && [ ! -f "$st/track-s4" ]'
done

echo "--- loading"
out=$(hook load '{"session_id":"s1","source":"resume"}')
ok "bound chat loads feature, context and state" '[[ "$out" == *"Active track: shop/tickets"* && "$out" == *"**Repos:** api, web"* && "$out" == *"ship tickets"* && "$out" == *"T-7 checkout fix"* ]]'
ok "it gives the full command that starts the track in a new chat" '[[ "$out" == *"Active track: shop/tickets (a new chat starts it with /trackside:start shop/tickets)"* ]]'
ok "it asks for decisions to be recorded when they're made" '[[ "$out" == *"Record each decision as soon as it'"'"'s made"* ]]'
ok "without a stamp it says nothing was checked against git" '[[ "$out" == *"No git stamp yet"* ]]'
ok "no compaction notes on resume" '[[ "$out" != *compacted* ]]'

echo "--- the current track"
out=$(bash "$H/scripts/current.sh" "$R" s1)
ok "current shows this chat's track, its current work, next step and start command" '[[ "$out" == *"This chat is on shop/tickets. A new chat starts it with /trackside:start shop/tickets."* && "$out" == *"Current: Ticket: T-7 checkout fix"* && "$out" == *"Next step: edit api/cart.js applyDiscount"* ]]'
out=$(bash "$H/scripts/current.sh" "$R" nobody)
ok "an unbound chat is told so, with the tracks to pick from" '[[ "$out" == *"This chat isn'"'"'t bound to a track."* && "$out" == *"- shop/research:"* ]]'
out=$(bash "$H/scripts/current.sh" "$R" "../x" 2>&1; echo "exit=$?")
ok "current refuses a bad session id" '[[ "$out" == *"exit=1"* ]]'
out=$(hook load '{"session_id":"s1","source":"resume"}')
ok "a bound chat is told a track may be called a workspace" '[[ "$out" == *"The user may call a track a workspace; /trackside:current shows this one."* ]]'
out=$(hook load '{"session_id":"nobody","source":"startup"}')
ok "so is an unbound one" '[[ "$out" == *"The user may call a track a workspace."* ]]'
ok "every skill about tracks mentions the word workspace" '[ -z "$(grep -L "workspace" "$H"/skills/{start,current,list,rename,close,save,next,done}/SKILL.md)" ]'

echo "--- chats the user named"
nf() { (. "$H/scripts/common.sh"; name_file "$K" "$1"); }
hook load '{"session_id":"u1","source":"startup","session_title":"CASH-508 withdrawal"}' >/dev/null
ok "trackside records the name a user gave a chat" '[ "$(cat "$st/name-u1")" = "CASH-508 withdrawal" ]'
out=$(hook bind '{"session_id":"u1","prompt":"/trackside:start shop/tickets"}')
ok "binding it keeps that name and remembers its track" '[ -z "$out" ] && [ "$(cat "$st/track-u1")" = shop/tickets ] && [ "$(cat "$(nf "CASH-508 withdrawal")")" = shop/tickets ]'
out=$(hook load '{"session_id":"u2","source":"clear","session_title":"CASH-508 withdrawal"}')
ok "after /clear the same name finds the track again" '[[ "$out" == *"Active track: shop/tickets"* ]] && [ "$(cat "$st/track-u2")" = shop/tickets ]'
hook load '{"session_id":"u3","source":"resume","session_title":"shop/research"}' >/dev/null
ok "a title trackside set isn't taken for the user's name" '[ ! -f "$st/name-u3" ] && [ "$(cat "$st/track-u3")" = shop/research ]'
hook load '{"session_id":"u4","source":"startup","session_title":"My review"}' >/dev/null
bash "$H/scripts/bind.sh" "$R" u4 shop/research >/dev/null
ok "the start skill's bind keeps a named chat's name too" '[ ! -f "$st/title-u4" ] && [ "$(cat "$(nf "My review")")" = shop/research ]'
out=$(hook bind '{"session_id":"u1","prompt":"/trackside:start off"}')
ok "unbinding a named chat keeps its name and remembers it was unbound" '[ -z "$out" ] && [ ! -f "$st/track-u1" ] && [ "$(cat "$(nf "CASH-508 withdrawal")")" = off ]'
out=$(hook load '{"session_id":"u5","source":"clear","session_title":"CASH-508 withdrawal"}')
ok "so after /clear it stays unbound and isn't bound on its own" '[ ! -f "$st/track-u5" ] && [[ "$out" == *"The user unbound this chat from its track"* && "$out" != *"bind the chat to it right away"* ]]'
bash "$H/scripts/bind.sh" "$R" u4 off >/dev/null
ok "the start skill's off on a named chat remembers it too" '[ ! -f "$st/track-u4" ] && [ ! -f "$st/title-u4" ] && [ "$(cat "$(nf "My review")")" = off ]'
bash "$H/scripts/bind.sh" "$R" u4 shop/research >/dev/null
ok "binding it again replaces that" '[ "$(cat "$(nf "My review")")" = shop/research ]'
rm -f "$st"/track-u2 "$st"/track-u3 "$st"/track-u4

echo "--- a chat that moved to another folder"
M=$(mktemp -d "${TMPDIR:-/tmp}/trackside-moved.XXXXXX")
out=$(printf '{"session_id":"mv1","prompt":"/trackside:start shop/tickets","cwd":"%s"}' "$R/api" | CLAUDE_PROJECT_DIR="$M" "$H/hooks/bind.sh")
ok "a chat that started elsewhere finds the trackside folder from where it works now" '[ "$(cat "$st/track-mv1" 2>/dev/null)" = shop/tickets ] && [ "$(jq -r .hookSpecificOutput.sessionTitle <<<"$out")" = shop/tickets ]'
out=$(printf '{"session_id":"mv1","source":"resume","cwd":"%s"}' "$R/api" | CLAUDE_PROJECT_DIR="$M" "$H/hooks/load.sh")
ok "and loads its track" '[[ "$out" == *"Active track: shop/tickets"* ]]'
printf '{"session_id":"mv1","tool_name":"Edit","tool_input":{"file_path":"%s"},"cwd":"%s"}' "$R/api/cart.js" "$R/api" | CLAUDE_PROJECT_DIR="$M" "$H/hooks/track.sh"
ok "and counts its edits" '[ -f "$st/dirty-mv1" ]'
out=$(cd "$R/api" && bash "$H/scripts/status.sh" "$M")
ok "the scripts find it the same way" '[[ "$out" == *"shop/tickets"* ]]'
out=$(printf '{"session_id":"mv2","prompt":"/trackside:start shop/tickets","cwd":"%s"}' "$M" | CLAUDE_PROJECT_DIR="$M" "$H/hooks/bind.sh"; echo "exit=$?")
ok "with no trackside folder at or above it, trackside stays silent" '[ "$out" = "exit=0" ] && [ ! -e "$M/.trackside" ]'
missing=""
for f in "$H"/skills/*/SKILL.md; do
  grep -q "CLAUDE_PROJECT_DIR" "$f" && ! grep -q "has no \`.trackside/\` folder, which happens when a chat moves" "$f" && missing="$missing ${f#$H/}"
done
ok "every skill that uses the project folder says what to do when it has no .trackside/${missing:+ (missing:$missing)}" '[ -z "$missing" ]'
rm -f "$st/track-mv1" "$st/dirty-mv1"; rm -rf "$M"

echo "--- tracking and the Stop gate"
edit() { hook track "{\"session_id\":\"$1\",\"tool_name\":\"$2\",\"tool_input\":{\"file_path\":\"$3\"}}" >/dev/null; }
edit_out() { hook track "{\"session_id\":\"$1\",\"tool_name\":\"$2\",\"tool_input\":{\"file_path\":\"$3\"}}"; }
stop() { hook stop "{\"session_id\":\"$1\",\"stop_hook_active\":$2}"; }
# owed <session>: whether the Stop hook, which prints nothing, noted that the turn ended owing a save.
owed() { rm -f "$st/owed-$1"; [ -z "$(stop "$1" "${2:-false}")" ] && [ -f "$st/owed-$1" ]; }
ok "stop passes while clean" '! owed s1'
edit s1 Edit "$K/shop/FEATURE.md";                     ok "editing trackside files stays clean" '[ ! -f "$st/dirty-s1" ]'
edit s1 Edit "$K/shop/research/STATE.md";              ok "editing another track's state stays clean" '[ ! -f "$st/dirty-s1" ]'
edit s1 Edit "$R/.claude/settings.json";               ok "editing the project's .claude stays clean" '[ ! -f "$st/dirty-s1" ]'
edit s1 Write "$HOME/.claude/projects/p/memory/MEMORY.md"; ok "writing Claude's own memory or plans stays clean" '[ ! -f "$st/dirty-s1" ]'
edit s1 Edit "$R/CLAUDE.md";                           ok "editing a CLAUDE.md stays clean" '[ ! -f "$st/dirty-s1" ]'
edit s1 Write "/tmp/trackside-elsewhere/scratch-note.md";   ok "an edit outside the project folder stays clean" '[ ! -f "$st/dirty-s1" ]'
edit s1 Edit "$R/.claude/worktrees/w1/api/cart.js";    ok "an edit in a Claude Code worktree marks the chat dirty" '[ -f "$st/dirty-s1" ]'; rm -f "$st/dirty-s1"
edit s1 Edit "$R/api/.claude/notes.md";                ok "a repo's own .claude folder counts as project files" '[ -f "$st/dirty-s1" ]'; rm -f "$st/dirty-s1"
edit s1 Edit "$R/api/cart.js";                         ok "a project edit marks the chat dirty" '[ -f "$st/dirty-s1" ]'
ok "a chat that hasn't saved yet owes a save after its first working turn" 'owed s1'
edit s1 Edit "$K/shop/tickets/STATE.md"; edit s1 Edit "$R/api/cart.js"
ok "(setup) saving starts this chat's own clock" '[ -f "$st/saved-s1" ] && [ -f "$st/dirty-s1" ]'
ok "it waits while this chat saved in the last 15 minutes" '! owed s1 && [ -f "$st/dirty-s1" ]'
ok "TRACKSIDE_SAVE_MINUTES=0 asks after every working turn" 'TRACKSIDE_SAVE_MINUTES=0 owed s1'
mins_ago() { date -v-"$1"M +%Y%m%d%H%M 2>/dev/null || date -d "$1 minutes ago" +%Y%m%d%H%M; }
touch -t "$(mins_ago 20)" "$st/saved-s1"
ok "TRACKSIDE_SAVE_MINUTES moves the wait" '! TRACKSIDE_SAVE_MINUTES=30 owed s1'
hook bind '{"session_id":"s10","prompt":"/trackside:start shop/tickets"}' >/dev/null; edit s10 Edit "$K/shop/tickets/STATE.md"
ok "another chat saving the same track doesn't silence this one" 'owed s1'; rm -f "$st/track-s10" "$st/saved-s10"
ok "the Stop hook adds nothing after the reply, and leaves a note on the track naming the chat" '[ -z "$(stop s1 false)" ] && [ "$(cut -f2- "$st/stamp-shop@tickets.unsaved")" = "s1	-" ]'
note="$st/stamp-shop@tickets.unsaved"
printf 'shop/tickets\n' > "$st/track-n6"; out=$(hook load '{"session_id":"n6","source":"startup"}')
ok "a chat opened on the track while that one is open leaves its work to it" '[[ "$out" == *"Another chat on this track, still open, has work STATE.md doesn'"'"'t have yet"* && "$out" != *"Before your first reply"* ]] && [ ! -f "$st/gap-n6" ]'
edit n6 Edit "$K/shop/tickets/STATE.md"
ok "and its save leaves the note for that chat" '[ -s "$note" ]'
out=$(hook load '{"session_id":"s1","source":"resume"}')
ok "the chat that left the note isn't told about it at a resume; its next message asks for the save" '[[ "$out" != *"left off"* && "$out" != *"Another chat"* ]]'
hook end '{"session_id":"s1","reason":"clear"}'
ok "once that chat ends or is cleared, the note says so" '[ "$(cut -f2- "$note")" = "s1	ended" ]'
out=$(hook load '{"session_id":"n7","source":"clear","session_title":"shop/tickets"}')
ok "and the next chat on the track fills the gap" '[[ "$out" == *"The last chat on this track left off on "*" with work STATE.md doesn'"'"'t have yet. Before your first reply, update its Current and Next step"* ]] && [ -f "$st/gap-n7" ]'
cp "$note" "$R/note.tmp"; edit n7 Edit "$K/shop/tickets/STATE.md"
ok "its save clears the note" '[ ! -f "$note" ] && [ ! -f "$st/gap-n7" ]'
mv "$R/note.tmp" "$note"; sed -i '' 's/ended$/-/' "$note"; touch -t "$(mins_ago 1500)" "$note"; printf 'shop/tickets\n' > "$st/track-n8"
out=$(hook load '{"session_id":"n8","source":"startup"}')
ok "a note an open chat left a day ago counts as left behind too" '[[ "$out" == *"The last chat on this track left off on"* ]]'
printf '2026-10-01 10:00\n' > "$note"
out=$(hook load '{"session_id":"n8","source":"startup"}')
ok "so does a note from before notes named the chat" '[[ "$out" == *"left off on 2026-10-01 10:00 with work"* ]]'
printf '%s\t%s\t-\n' "2026-10-26 10:00" s1 > "$note"; rm -f "$st"/*-n[678]
rm -f "$st/dirty-n9"; printf 'shop/tickets\n' > "$st/track-n9"; cp "$note" "$R/note.tmp"
hook end '{"session_id":"n9","reason":"other"}'
ok "a chat that ends with nothing unsaved leaves no note" 'cmp -s "$note" "$R/note.tmp"'; rm -f "$R/note.tmp" "$st/track-n9"
printf 'shop/tickets' > "$st/title-s1"
both=$(hook bind '{"session_id":"s1","prompt":"what about the totals?"}')
ok "one prompt can carry the chat's new name and the reminder" '[ "$(jq -r .hookSpecificOutput.sessionTitle <<<"$both")" = shop/tickets ] && [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$both")" == *"Before you answer this message"* ]]'
out=$(hook bind '{"session_id":"s1","prompt":"what about the totals?"}')
ok "the next message asks for the save before its answer, naming the state file" '[ "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")" = UserPromptSubmit ] && [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$out")" == *".trackside/shop/tickets/STATE.md"* ]] && [ "$(jq -r ".decision // empty" <<<"$out")" = "" ]'
ok "and asks for Current, Next step and new decisions, nothing more" '[[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$out")" == *"Before you answer this message, update its Current and Next step"* && "$(jq -r .hookSpecificOutput.additionalContext <<<"$out")" == *"record any decision made since"* && "$(jq -r .hookSpecificOutput.additionalContext <<<"$out")" != *"Done log"* ]]'
ok "a bad TRACKSIDE_SAVE_MINUTES falls back to 15" 'TRACKSIDE_SAVE_MINUTES=soon owed s1'
ok "stop_hook_active lets it stop" '! owed s1 true'
touch "$st/owed-s1"
edit s1 Edit "$K/shop/tickets/STATE.md";               ok "updating the track's state clears it, and the save it owed" '[ ! -f "$st/dirty-s1" ] && [ ! -f "$st/owed-s1" ] && [ ! -f "$st/stamp-shop@tickets.unsaved" ]'
ok "stop passes after the update" '! owed s1'
stamp="$st/stamp-shop@tickets"
ok "the update stamps both repos, in .state" '[ "$(cut -f1 "$stamp" | tr "\n" " ")" = "api web " ] && [ "$(cut -f2 "$stamp" | head -1)" = "$(git -C "$R/api" rev-parse HEAD)" ] && [ ! -e "$K/shop/tickets/.stamp" ]'
for t in WebFetch WebSearch; do
  hook track "{\"session_id\":\"s1\",\"tool_name\":\"$t\",\"tool_input\":{}}"
  ok "$t marks the chat dirty" '[ -f "$st/dirty-s1" ]'; rm -f "$st/dirty-s1"
done
hook track '{"session_id":"s1","tool_name":"Agent","tool_input":{"subagent_type":"Explore"}}'
ok "another subagent marks the chat dirty" '[ -f "$st/dirty-s1" ]'; rm -f "$st/dirty-s1"
hook track '{"session_id":"s1","tool_name":"Agent","tool_input":{"subagent_type":"trackside:auditor"}}'
ok "asking trackside's auditor doesn't" '[ ! -f "$st/dirty-s1" ]'
hook track '{"session_id":"s1","tool_name":"Agent","tool_input":{"subagent_type":"auditor"}}'
ok "nor does the unprefixed name" '[ ! -f "$st/dirty-s1" ]'
hook track '{"session_id":"s1","tool_name":"Agent","tool_input":{"subagent_type":"my-team:auditor"}}'
ok "another plugin's auditor still counts" '[ -f "$st/dirty-s1" ]'; rm -f "$st/dirty-s1"
m=$(jq -r '.hooks.PostToolUse[0].matcher' "$H/hooks/hooks.json")
ok "the matcher passes edits, research and Bash, not Read" '[[ "Edit" =~ ^($m)$ && "Agent" =~ ^($m)$ && "Bash" =~ ^($m)$ && ! "Read" =~ ^($m)$ ]]'
printf 'shop/tickets\n' > "$st/track-sb"
hook track "{\"session_id\":\"sb\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sed -i '' s/a/b/ api/cart.js\"}}"
ok "a shell command that doesn't touch STATE.md still doesn't count as work" '[ ! -f "$st/dirty-sb" ] && [ ! -f "$st/saved-sb" ]'
# sh <session> <command> [cwd] [change]: a Bash call as Claude Code reports it, before and after; with "change", the
# command changes STATE.md while it runs.
sh() {
  local j="{\"session_id\":\"$1\",\"tool_name\":\"Bash\",\"cwd\":\"${3:-$R}\",\"tool_input\":{\"command\":\"$2\"}"
  hook track "$j,\"hook_event_name\":\"PreToolUse\"}" >/dev/null
  [ -z "${4:-}" ] || printf '\n' >> "$K/shop/tickets/STATE.md"
  hook track "$j,\"hook_event_name\":\"PostToolUse\"}" >/dev/null
}
touch "$st/dirty-sb" "$st/owed-sb" "$st/nudged-sb" "$K/shop/tickets/STATE.md"
sh sb "wc -c $K/shop/tickets/STATE.md"
ok "a command that only reads STATE.md isn't a save, even right after the file changed" '[ -f "$st/dirty-sb" ] && [ ! -f "$st/saved-sb" ] && [ ! -f "$st/before-sb" ]'
hook track "{\"session_id\":\"sb\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"sed -i '' s/x/y/ $K/shop/tickets/STATE.md\"}}" >/dev/null
ok "nor is a change Claude Code didn't report a start for" '[ ! -f "$st/saved-sb" ]'
sh sb "cd $K/shop/tickets && sed -i '' s/x/y/ STATE.md" "" change
ok "a save through the shell counts like an Edit, owed save and reminder included" '[ -f "$st/saved-sb" ] && [ ! -f "$st/dirty-sb" ] && [ ! -f "$st/owed-sb" ] && [ ! -f "$st/nudged-sb" ]'
touch "$st/dirty-sb"; rm -f "$st/saved-sb"
sh sb "sed -i '' s/x/y/ STATE.md" "$K/shop/tickets" change
ok "so does one run from the track's folder by name only" '[ -f "$st/saved-sb" ] && [ ! -f "$st/dirty-sb" ]'
touch "$st/dirty-sb"; rm -f "$st/saved-sb"
hook track "{\"session_id\":\"sb\",\"tool_name\":\"Bash\",\"cwd\":\"$R\",\"tool_input\":{\"command\":\"sed -i '' s/x/y/ other/STATE.md\"}}" >/dev/null
ok "but not another track's STATE.md from elsewhere" '[ ! -f "$st/saved-sb" ] && [ -f "$st/dirty-sb" ]'
rm -f "$st"/*-sb
edit s9 Edit "$R/api/cart.js";                         ok "an unbound chat is never tracked" '[ ! -f "$st/dirty-s9" ]'
out=$(stop s9 false);                                  ok "an unbound chat is never blocked" '[ -z "$out" ]'

echo "--- freshness"
q "$R/api" -c user.name=t -c user.email=t@example.com commit --allow-empty -m "fix cart totals"
q "$R/web" checkout -b redesign
touch "$R/web/new.txt"
out=$(hook load '{"session_id":"s1","source":"resume"}')
ok "a new commit is reported with its subject" '[[ "$out" == *"api (main): 1 new commit(s)"* && "$out" == *"fix cart totals"* ]]'
ok "a branch change and new files are reported" '[[ "$out" == *"branch changed from main to redesign"* && "$out" == *"uncommitted changes differ: 1 file(s) now, 0 then"* ]]'
ok "it asks to recheck before acting" '[[ "$out" == *"Recheck files before acting"* ]]'
q "$R/web" checkout main
rm -f "$R/web/new.txt"
printf 'one\n' > "$R/api/notes.txt"
edit s1 Edit "$K/shop/tickets/STATE.md"
printf 'two\n' > "$R/api/notes.txt"
touch -t "$(date -v+2M +%Y%m%d%H%M 2>/dev/null || date -d '2 minutes' +%Y%m%d%H%M)" "$R/api/notes.txt"
q "$R/api" reset --hard HEAD~1
out=$(bash "$H/scripts/freshness.sh" "$R" shop/tickets)
ok "a reset to an older commit is reported" '[[ "$out" == *"api (main): moved back 1 commit(s)"* ]]'
ok "rewriting a file that was already uncommitted is reported" '[[ "$out" == *"api (main): moved back 1 commit(s); uncommitted changes differ: 1 file(s) now, 1 then"* ]]'
ok "an unchanged repo still says so" '[[ "$out" == *"web (main): no changes"* ]]'

echo "--- asking for the save before the reply"
printf 'shop/tickets\n' > "$st/track-v1"
out=$(edit_out v1 Edit "$R/api/cart.js")
ok "the first edit in a chat that hasn't saved asks for the save before the reply, quietly" '[[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$out")" == "Before you write your reply to the user, update .trackside/shop/tickets/STATE.md"*"without mentioning it in your reply." ]]'
out=$(edit_out v1 Edit "$R/web/index.html")
ok "only once until the next save" '[ -z "$out" ]'
edit v1 Edit "$K/shop/tickets/STATE.md"
out=$(edit_out v1 Edit "$R/api/cart.js")
ok "after a save, not again until a save is due" '[ -z "$out" ] && [ -f "$st/dirty-v1" ]'
out=$(TRACKSIDE_SAVE_MINUTES=0 hook track '{"session_id":"v1","tool_name":"WebFetch","tool_input":{}}')
ok "once a save is due it asks again, after research too" '[[ "$out" == *"Before you write your reply to the user"* ]]'
out=$(TRACKSIDE_SAVE_MINUTES=0 hook stop '{"session_id":"v1","stop_hook_active":false}'); out=$(hook bind '{"session_id":"v1","prompt":"and the next thing?"}')
ok "a chat that didn't save before replying is asked at its next message, before that answer, quietly" '[[ "$out" == *"Before you answer this message"* && "$out" == *"without mentioning it in your reply"* ]]'
out=$(hook load '{"session_id":"s1","source":"resume"}')
ok "a bound chat is told to keep the bookkeeping out of its replies" '[[ "$out" == *"update STATE.md before you write a reply, not after it, in one edit (one Edit call or one script), never a series of small ones"* && "$out" == *"don'"'"'t tell the user about saves"* ]]'
rm -f "$st"/*-v1

echo "--- compaction and /clear"
out=$(hook load '{"session_id":"s1","source":"compact"}')
ok "the first compaction is counted" '[[ "$out" == *"compacted 1 time"* && "$out" == *"Read on start"* && "$out" != *"/trackside:save"* ]]'
out=$(hook load '{"session_id":"s1","source":"compact"}')
ok "the second is counted too, and the reload leaves the offer of a fresh chat to the next prompt" '[[ "$out" == *"compacted 2 time"* && "$out" != *"/trackside:save"* && "$out" != *"/trackside:fresh"* ]]'
out=$(hook bind '{"session_id":"s1","prompt":"go on"}')
ok "which offers it" '[[ "$out" == *"This chat has compacted 2 time(s). Offer once"* ]]'
echo bogus > "$st/compactions-s1"
out=$(hook load '{"session_id":"s1","source":"compact"}')
ok "a corrupt counter restarts at 1" '[[ "$out" == *"compacted 1 time"* ]]'
out=$(hook load '{"session_id":"s1","source":"clear"}')
ok "clear resets the count and keeps the binding" '[ ! -f "$st/compactions-s1" ] && [[ "$out" == *"Active track: shop/tickets"* ]]'
out=$(hook load '{"session_id":"s5","source":"clear","session_title":"shop/research"}')
ok "a new session id rebinds from the chat title" '[ "$(cat "$st/track-s5" 2>/dev/null)" = shop/research ] && [[ "$out" == *"Active track: shop/research"* ]]'
for t in "Fix the bug" "../shop/tickets" "shop/tickets/x" ".state/x"; do
  out=$(hook load "{\"session_id\":\"s6\",\"source\":\"resume\",\"session_title\":\"$t\"}")
  ok "no rebinding from the title: $t" '[ ! -f "$st/track-s6" ] && [[ "$out" == *"No track is bound"* ]]'
done

echo "--- size limits"
{ state shop/tickets "T-8 big" "edit web/app.js render"; for i in $(seq 1 120); do echo "- 2026-10-$((i % 28 + 1)) · T-$i · abc$i · tests passed, with a long note to fill space"; done; printf '\n## Gotchas\n- small gotcha\n'; } > "$K/shop/tickets/STATE.md"
out=$(hook load '{"session_id":"s1","source":"resume"}')
n=$(hook load-state '{"session_id":"s1","source":"resume"}' | wc -c | tr -d ' ')
ok "a big state keeps Inbox, Current and Next step" '[[ "$out" == *"## Inbox"* && "$out" == *"T-8 big"* && "$out" == *"edit web/app.js render"* ]]'
ok "the sections left out are named" '[[ "$out" == *"Not loaded, to stay under the hook output limit: Done log"* ]]'
ok "sections that fit still load" '[[ "$out" == *"small gotcha"* ]]'
ok "STATE.md's own output stays under 10,000 bytes ($n)" '[ "$n" -lt 10000 ]'
n=$(printf '{"session_id":"s1","source":"resume"}' | "$H/hooks/load.sh" | wc -c | tr -d ' ')
ok "and so does the other one ($n)" '[ "$n" -lt 10000 ]'
ok "the output is valid UTF-8" 'printf "%s" "$out" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1'
{ printf '# State: shop/tickets\n\n## Current\n'; for i in $(seq 1 400); do echo "- [assumed] a very long current line number $i that keeps going — with · marks"; done; } > "$K/shop/tickets/STATE.md"
out=$(hook load-state '{"session_id":"s1","source":"resume"}')
n=$(printf '%s' "$out" | wc -c | tr -d ' ')
ok "even an oversized Current is cut under 10,000 bytes ($n)" '[ "$n" -lt 10000 ] && [[ "$out" == *"[Cut to stay under the hook output limit"* ]]'
ok "the cut falls at a line end, so no character is split" 'printf "%s" "$out" | iconv -f UTF-8 -t UTF-8 >/dev/null 2>&1'
printf '# Track: shop/tickets\n**Goal:** ship tickets\n%s\n**Rules for this track:**\n- the last rule\n' "$(head -c 4800 < /dev/zero | tr '\0' 'x')" > "$K/shop/tickets/CONTEXT.md"
out=$(hook load '{"session_id":"s1","source":"resume"}')
ok "with no fixed size limit, a 5,000-byte CONTEXT.md loads whole, rules included" '[[ "$out" == *"- the last rule"* ]]'
printf '# Track: shop/tickets\n**Goal:** ship tickets\n' > "$K/shop/tickets/CONTEXT.md"
cp "$K/shop/tickets/STATE.md" "$st/state-backup"
ok "the reload is two SessionStart hooks, so STATE.md has an output of its own" '[ "$(jq -r ".hooks.SessionStart[0].hooks[].command" "$H/hooks/hooks.json" | tr "\n" " ")" = "\${CLAUDE_PLUGIN_ROOT}/hooks/load.sh \${CLAUDE_PLUGIN_ROOT}/hooks/load-state.sh " ]'
one=$(printf '{"session_id":"s1","source":"resume"}' | "$H/hooks/load.sh"); two=$(hook load-state '{"session_id":"s1","source":"resume"}')
ok "load.sh carries FEATURE.md and CONTEXT.md, and load-state.sh STATE.md" '[[ "$one" == *"=== FEATURE.md"* && "$one" == *"=== CONTEXT.md"* && "$one" != *"=== STATE.md"* && "$two" == *"=== STATE.md"* && "$two" == "The state of shop/tickets"* ]]'
out=$(hook load-state '{"session_id":"nobody-v9","source":"startup"}')
ok "the state hook says nothing in a chat that isn't bound" '[ -z "$out" ]'
out=$(hook load-state '{"session_id":"cleared-v9","source":"clear","session_title":"shop/research"}')
ok "after /clear it finds the track from the chat's title without waiting for load.sh, which runs beside it" '[[ "$out" == *"=== STATE.md (.trackside/shop/research/STATE.md)"* ]] && [ ! -f "$st/track-cleared-v9" ]'
{ state shop/tickets "T-9 roomy" "edit api/cart.js totals"; for i in $(seq 1 90); do echo "- 2026-10-$((i % 28 + 1)) · T-$i · abc$i · tests passed, with a note"; done; } > "$K/shop/tickets/STATE.md"
n=$(wc -c < "$K/shop/tickets/STATE.md" | tr -d ' '); out=$(hook load-state '{"session_id":"s1","source":"resume"}')
ok "a STATE.md over the old 5,000-byte limit ($n bytes) now loads whole" '[ "$n" -gt 5000 ] && [[ "$out" == *"T-90 · abc90"* && "$out" != *"Not loaded"* ]]'
out=$(bash "$H/scripts/audit.sh" "$R" shop/tickets start)
ok "and the check doesn't flag it" '[[ "$out" != *"STATE.md is "* ]]'
printf '# Track: shop/tickets\n**Goal:** ship tickets\n%s\n' "$(head -c 9000 < /dev/zero | tr '\0' 'x')" > "$K/shop/tickets/CONTEXT.md"
out=$(bash "$H/scripts/audit.sh" "$R" shop/tickets start)
ok "a CONTEXT.md too big for its share of the reload is flagged" '[[ "$out" == *"CONTEXT.md is "*" bytes, more than the reload loads whole: move reference lists to NOTES.md"* ]]'
printf '# Track: shop/tickets\n**Goal:** ship tickets\n' > "$K/shop/tickets/CONTEXT.md"
mv "$st/state-backup" "$K/shop/tickets/STATE.md"

echo "--- index, idle tracks and housekeeping"
ago() { date -v-"$1"d +%Y%m%d%H%M 2>/dev/null || date -d "$1 days ago" +%Y%m%d%H%M; }
ok "the index is generated at chat start" '[ -f "$K/INDEX.md" ] && grep -q "| shop/research | Ticket: pricing question |" "$K/INDEX.md"'
ok "the index gives each track's full start command" 'grep -q "\`/trackside:start shop/research\`" "$K/INDEX.md" && grep -q "\`/trackside:start solo/main\`" "$K/INDEX.md" && grep -q "\`/trackside:start shop/tickets\`" "$K/INDEX.md"'
bash "$H/scripts/index.sh" "$R"; bash "$H/scripts/index.sh" "$R"
ok "git ignores the index, listed once" '[ "$(grep -cx INDEX.md "$K/.gitignore")" = 1 ]'
touch -t 202001010000 "$K/INDEX.md"
bash "$H/scripts/index.sh" "$R"
ok "an unchanged index isn't rewritten" '[ "$(date -r "$K/INDEX.md" +%Y)" = 2020 ]'
sed 's/line number 1 that/line number one that/' "$K/shop/tickets/STATE.md" > "$R/s.tmp" && mv "$R/s.tmp" "$K/shop/tickets/STATE.md"
edit s1 Edit "$K/shop/tickets/STATE.md"
ok "saving a changed state refreshes the index" 'grep -q "line number one that" "$K/INDEX.md"'
touch -t "$(ago 20)" "$K/solo/main/STATE.md"
out=$(bash "$H/scripts/status.sh" "$R")
ok "a track untouched for 14+ days is flagged in the listing" '[[ "$out" == *"solo/main: Ticket: none (start: /trackside:start solo/main) (idle 20 days; close it with /trackside:close solo/main)"* ]]'
bash "$H/scripts/index.sh" "$R"
ok "and in the index" 'grep -q "idle 20 days: \`/trackside:close solo/main\`?" "$K/INDEX.md"'
out=$(TRACKSIDE_IDLE_DAYS=30 bash "$H/scripts/status.sh" "$R")
ok "TRACKSIDE_IDLE_DAYS moves the threshold" '[[ "$out" != *idle* ]]'
printf '# Track: solo/main\n\n**Goal:** keep the lights on\n' > "$K/solo/main/CONTEXT.md"
out=$(bash "$H/scripts/status.sh" "$R")
ok "a track with nothing in flight shows its goal" '[[ "$out" == *"solo/main: Goal: keep the lights on (start:"* ]]'
printf '# Track: solo/main\n\n**Goal:** <what this line of work delivers>\n' > "$K/solo/main/CONTEXT.md"
out=$(bash "$H/scripts/status.sh" "$R")
ok "but not the template's placeholder" '[[ "$out" == *"solo/main: Ticket: none (start:"* ]]'
rm -f "$K/solo/main/CONTEXT.md"
printf 'x\n' > "$st/track-old"; touch -t "$(ago 40)" "$st/track-old"
printf 'x\n' > "$st/track-fresh"
touch -t "$(ago 40)" "$st/track-s1"
out=$(hook load '{"session_id":"s1","source":"resume"}')
ok "old session files are cleared at chat start" '[ ! -f "$st/track-old" ] && [ -f "$st/track-fresh" ] && [ -f "$st/.gitignore" ]'
ok "the current chat keeps its binding even if its file was old" '[ "$(cat "$st/track-s1" 2>/dev/null)" = shop/tickets ] && [[ "$out" == *"Active track: shop/tickets"* ]]'

echo "--- closing"
printf 'x\n' > "$st/stamp-shop@research.docs"
out=$(bash "$H/scripts/archive.sh" "$R" shop/research)
ok "closing a track moves it into the archive" '[ -f "$K/_archive/shop/research/STATE.md" ] && [ ! -e "$K/shop/research" ] && [[ "$out" == *"Moved .trackside/shop/research to .trackside/_archive/shop/research"* ]]'
ok "both chats bound to it are unbound, others keep theirs" '[ ! -f "$st/track-s2" ] && [ ! -f "$st/track-s5" ] && [ -f "$st/track-s1" ] && [[ "$out" == *"Chats unbound: 2"* ]]'
ok "closing forgets the names remembered for it" '[ ! -f "$(nf "My review")" ]'
ok "closing removes its source-doc stamp" '[ ! -e "$st/stamp-shop@research.docs" ]'
ok "the index drops it and counts the archive" '! grep -q "shop/research" "$K/INDEX.md" && grep -q "Archived tracks: 1" "$K/INDEX.md"'
out=$(bash "$H/scripts/status.sh" "$R")
ok "the archive never shows up as a feature" '[[ "$out" != *_archive* ]] && [ "$(printf "%s\n" "$out" | wc -l | tr -d " ")" = 2 ]'
mkdir -p "$K/shop/research" && cp "$K/_archive/shop/research/STATE.md" "$K/shop/research/STATE.md"
out=$(bash "$H/scripts/archive.sh" "$R" shop/research)
ok "closing a name already archived keeps both" '[ -d "$K/_archive/shop/research" ] && [ "$(ls -d "$K"/_archive/shop/research-* | wc -l | tr -d " ")" = 1 ]'
edit s3 Edit "$K/solo/main/STATE.md"
ok "(setup) solo/main has a stamp" '[ -e "$st/stamp-solo@main" ]'
out=$(bash "$H/scripts/archive.sh" "$R" solo)
ok "closing a feature archives all of it" '[ -f "$K/_archive/solo/FEATURE.md" ] && [ -f "$K/_archive/solo/main/STATE.md" ] && [ ! -e "$K/solo" ] && [ ! -f "$st/track-s3" ]'
ok "closing removes the stamps" '[ ! -e "$st/stamp-solo@main" ] && [ -e "$st/stamp-shop@tickets" ]'
for t in "../shop" "shop/nope" "_archive" "nothing"; do
  out=$(bash "$H/scripts/archive.sh" "$R" "$t" 2>&1; echo "exit=$?")
  ok "closing is refused for: $t" '[[ "$out" == *"exit=1"* ]]'
done
out=$(hook bind '{"session_id":"s7","prompt":"/trackside:start _archive/shop"}')
ok "an archived track can't be bound" '[ -z "$out" ] && [ ! -f "$st/track-s7" ]'
edit s1 Edit "$K/_archive/shop/research/STATE.md"
ok "editing the archive doesn't mark the chat dirty" '[ ! -f "$st/dirty-s1" ]'

echo "--- long chats: the offer of a fresh chat"
# tx <file> <tokens> [model]: adds a reply sent with <tokens> of context; bnd <file> <trigger> <size>: a compaction.
tx() { printf '{"type":"assistant","isSidechain":false,"message":{"model":"%s","content":[{"type":"text","text":"done"}],"usage":{"input_tokens":2,"cache_read_input_tokens":%s,"cache_creation_input_tokens":0}}}\n' "${3:-m-1}" "$(( $2 - 2 ))" >> "$1"; }
bnd() { printf '{"type":"system","subtype":"compact_boundary","compactMetadata":{"trigger":"%s","preTokens":%s}}\n' "$2" "$3" >> "$1"; }
lp() { hook bind "{\"session_id\":\"$1\",\"prompt\":\"next\",\"transcript_path\":\"$2\"}"; }
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$1"; }
for c in l1 l2 l3 l4 l6; do printf 'shop/tickets\n' > "$st/track-$c"; done
tx "$R/l1.jsonl" 300000
out=$(lp l1 "$R/l1.jsonl")
ok "a chat with nothing known about where it compacts isn't offered anything" '[ -z "$out" ]'
bnd "$R/l1.jsonl" manual 500000; tx "$R/l1.jsonl" 30000; lp l1 "$R/l1.jsonl" >/dev/null
ok "a compaction the user ran doesn't say where a model compacts" '[ ! -f "$st/limit-m-1" ]'
bnd "$R/l1.jsonl" auto 970000; tx "$R/l1.jsonl" 30000
out=$(lp l1 "$R/l1.jsonl")
ok "an automatic one does, read from the transcript, per model" '[ "$(cat "$st/limit-m-1")" = 970000 ] && [ -z "$out" ]'
bnd "$R/l1.jsonl" auto 300000; tx "$R/l1.jsonl" 30000; lp l1 "$R/l1.jsonl" >/dev/null
ok "and a smaller one, such as an idle compaction, doesn't lower it" '[ "$(cat "$st/limit-m-1")" = 970000 ]'
tx "$R/l1.jsonl" 870000
out=$(lp l1 "$R/l1.jsonl")
ok "below 90% of that size, still nothing" '[ -z "$out" ]'
tx "$R/l1.jsonl" 880000
out=$(ctx "$(lp l1 "$R/l1.jsonl")")
ok "at 90% the chat is offered a fresh one, with the numbers" '[[ "$out" == "This chat'"'"'s context is about 880K tokens, 90% of the 970K at which it compacts. Offer once, in one line before the rest of your reply to this message, to continue in a fresh chat: /trackside:fresh saves the track"* ]]'
ok "as a choice, with a way to keep the chat whole" '[[ "$out" == *"/trackside:whole keeps this chat as it is"* && "$out" == *"Run neither unless the user asks."* ]]'
ok "the offers-fresh-chat eval gives its agent this same text" 'grep -qF -- "append_system_prompt: \"$out\"" "$H/evals/offers-fresh-chat/prompt.md"'
out=$(lp l1 "$R/l1.jsonl")
ok "only once" '[ -z "$out" ]'
hook load '{"session_id":"l1","source":"compact"}' >/dev/null
tx "$R/l1.jsonl" 900000
out=$(ctx "$(lp l1 "$R/l1.jsonl")")
ok "and again after the next compaction" '[[ "$out" == "This chat'"'"'s context is about 900K tokens, 92% of the 970K at which it compacts, and it has compacted 1 time(s). Offer once"* ]]'
out=$(TRACKSIDE_OFFER_PERCENT=95 lp l2 "$R/l1.jsonl")
ok "TRACKSIDE_OFFER_PERCENT moves the line" '[ -z "$out" ]'
tx "$R/l2.jsonl" 190000
out=$(ctx "$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=200000 lp l2 "$R/l2.jsonl")")
ok "a size set in CLAUDE_CODE_AUTO_COMPACT_WINDOW comes first" '[[ "$out" == "This chat'"'"'s context is about 190K tokens, 95% of the 200K at which it compacts. Offer once"* ]]'
rm -f "$st/offered-l2"
out=$(CLAUDE_CODE_AUTO_COMPACT_WINDOW=50000 lp l2 "$R/l2.jsonl")
ok "unless it's a value Claude Code ignores" '[ -z "$out" ]'
tx "$R/l3.jsonl" 40000 m-2; echo 2 > "$st/compactions-l3"
out=$(ctx "$(lp l3 "$R/l3.jsonl")")
ok "a chat on a model whose size isn't known yet is offered one after COMPACT_LIMIT compactions (default 2)" '[[ "$out" == "This chat'"'"'s context is about 40K tokens, and it has compacted 2 time(s). Offer once"* ]]'
tx "$R/l4.jsonl" 950000
bash "$H/scripts/whole.sh" "$R" l4 on >/dev/null
out=$(lp l4 "$R/l4.jsonl")
ok "a chat kept whole is never offered one" '[ -z "$out" ] && [ -f "$st/whole-l4" ]'
bash "$H/scripts/whole.sh" "$R" l4 off >/dev/null
out=$(ctx "$(lp l4 "$R/l4.jsonl")")
ok "until that's undone" '[ ! -f "$st/whole-l4" ] && [[ "$out" == *"Offer once"* ]]'
out=$(lp l5 "$R/l4.jsonl")
ok "an unbound chat isn't offered one" '[ -z "$out" ]'
touch "$st/owed-l6" "$st/dirty-l6"
out=$(ctx "$(lp l6 "$R/l4.jsonl")")
ok "an owed save and the offer come together, the save first" '[[ "$out" == "The last turn'"'"'s work isn'"'"'t in"*"Offer once"* ]]'
out=$(CLAUDE_CODE_ENTRYPOINT=cli HOME="$R/nohome" bash "$H/scripts/whole.sh" "$R" l7 on)
ok "keeping a chat whole says how long Claude Code keeps its transcript" '[[ "$out" == *"stays whole"* && "$out" == *"30 days unused (cleanupPeriodDays, the default)"* ]]'
mkdir -p "$R/.claude"; printf '{"cleanupPeriodDays": 365}\n' > "$R/.claude/settings.json"
out=$(CLAUDE_CODE_ENTRYPOINT=cli HOME="$R/nohome" bash "$H/scripts/whole.sh" "$R" l7 on)
ok "from the settings that set it" '[[ "$out" == *"365 days unused (cleanupPeriodDays in your settings)"* ]]'
dw() { CLAUDE_CODE_ENTRYPOINT=claude-desktop HOME="$R/nohome" bash "$H/scripts/whole.sh" "$R" l7 on; }
printf '{"cleanupPeriodDays": 365, "desktopSessionCleanupPeriodDays": 7}\n' > "$R/.claude/settings.json"
out=$(dw)
ok "for the desktop app, its own setting counts only in user settings" '[[ "$out" == *"at any age: desktopSessionCleanupPeriodDays isn'"'"'t above 0 in your user settings"* ]]'
mkdir -p "$R/nohome/.claude"; printf '{"desktopSessionCleanupPeriodDays": 0}\n' > "$R/nohome/.claude/settings.json"
out=$(dw)
ok "where 0 means no age limit" '[[ "$out" == *"at any age"* ]]'
rm -f "$R/.claude/settings.json"; printf '{"desktopSessionCleanupPeriodDays": 7}\n' > "$R/nohome/.claude/settings.json"
out=$(dw)
ok "and a desktop transcript is kept as long as the larger of it and cleanupPeriodDays" '[[ "$out" == *"once it goes 30 days unused (the larger of desktopSessionCleanupPeriodDays and cleanupPeriodDays, the default)"* ]]'
printf '{"desktopSessionCleanupPeriodDays": 90}\n' > "$R/nohome/.claude/settings.json"
out=$(dw)
ok "whichever that is" '[[ "$out" == *"once it goes 90 days unused"* ]]'
rm -rf "${R:?}/nohome"
out=$(bash "$H/scripts/whole.sh" "$R" l7 2>&1; echo "exit=$?")
ok "the whole script wants on or off" '[[ "$out" == *"exit=1" ]]'
touch "$st/judged-l1" "$st/health-l1"
hook load '{"session_id":"l1","source":"clear"}' >/dev/null
ok "clearing a chat resets its offer and its judge" '[ ! -f "$st/offered-l1" ] && [ ! -f "$st/judged-l1" ] && [ ! -f "$st/health-l1" ]'
for f in limit-old whole-old offered-old; do echo 1 > "$st/$f"; touch -t "$(ago 40)" "$st/$f"; done
hook load '{"session_id":"l1","source":"resume"}' >/dev/null
ok "housekeeping keeps where models compact and which chats stay whole" '[ -f "$st/limit-old" ] && [ -f "$st/whole-old" ] && [ ! -f "$st/offered-old" ]'
rm -f "${st:?}"/*-l[0-9] "${st:?}"/limit-* "${st:?}/whole-old"

echo "--- the judge"
J=$(mktemp -d "${TMPDIR:-/tmp}/trackside-judge.XXXXXX"); js="$J/.trackside/.state"
mkdir -p "$js" "$J/.trackside/app/main" "$J/bin"
printf '# Feature: app\n' > "$J/.trackside/app/FEATURE.md"
printf '# State: app/main\n\n## Current\n- Decision: **discounts** round to the nearest cent, never to whole dollars.\n' > "$J/.trackside/app/main/STATE.md"
printf '# Decisions: app\n\n## D-001 · Totals\n- Rejected: storing totals as floats, because cents drift.\n' > "$J/.trackside/app/DECISIONS.md"
printf 'app/main\n' > "$js/track-j1"
# A stand-in for the claude CLI: it records how it was called and what it read, and answers with four findings, of
# which the first and last quote both sides word for word, and a line in no known form.
cat > "$J/bin/claude" <<'STUB'
#!/usr/bin/env bash
d="$(dirname "$0")"
printf '%s\n' "$*" > "$d/args"; printf '%s\n' "${TRACKSIDE_CHILD:-}" > "$d/child"; cat > "$d/stdin"
echo $(( $(cat "$d/runs" 2>/dev/null || echo 0) + 1 )) > "$d/runs"
cat <<'OUT'
1. We round discounts down to whole dollars ||| STATE.md ||| discounts round to the nearest cent, never to whole dollars ||| floor vs cents
We always charge shipping on every order ||| STATE.md ||| discounts round to the nearest cent, never to whole dollars ||| never said
We round discounts down to whole dollars ||| NOTES.md ||| discounts round to the nearest cent, never to whole dollars ||| not a file it read
I will store totals as floats from now on ||| DECISIONS.md ||| Rejected: storing totals as floats, because cents drift ||| reopens a rejected option
a line in no known form
OUT
STUB
chmod +x "$J/bin/claude"
{ jq -n -c '{type:"user",isSidechain:false,message:{role:"user",content:"Which rounding do we use?"}}'
  jq -n -c '{type:"user",isSidechain:false,message:{role:"user",content:[{type:"tool_result",content:"TOOL OUTPUT"}]}}'
  jq -n -c '{type:"user",isSidechain:false,message:{role:"user",content:"<task-notification> NOTICE </task-notification>"}}'
  jq -n -c '{type:"assistant",isSidechain:false,message:{model:"m-1",content:[{type:"text",text:"We round discounts\ndown to whole dollars, so I floor it. I will store totals as floats from now on."}],usage:{input_tokens:2,cache_read_input_tokens:499998,cache_creation_input_tokens:0}}}'
} > "$J/t.jsonl"
jd() { printf '{"session_id":"j1","transcript_path":"%s","last_assistant_message":"Done, it floors now."}' "$J/t.jsonl" | PATH="$J/bin:$PATH" CLAUDE_PROJECT_DIR="$J" "$H/hooks/judge.sh"; }
runs() { cat "$J/bin/runs" 2>/dev/null || echo 0; }
jd
ok "past 400K tokens the judge runs as its own Claude Code process, without tools, settings or a saved session" '[ "$(runs)" = 1 ] && [ "$(cat "$J/bin/child")" = 1 ] && [[ "$(cat "$J/bin/args")" == "-p --model haiku --tools  --strict-mcp-config --no-session-persistence --disable-slash-commands --setting-sources  --system-prompt-file $H/hooks/judge.md" ]]'
ok "it reads the track's files, the feature's decisions and the chat's words, with the reply that just ended, and no tool output or notices" 'grep -q "^=== FILE STATE.md ===" "$J/bin/stdin" && grep -q "^=== FILE DECISIONS.md ===" "$J/bin/stdin" && grep -q "^USER: Which rounding" "$J/bin/stdin" && grep -q "^ASSISTANT: We round discounts" "$J/bin/stdin" && grep -q "^ASSISTANT: Done, it floors now." "$J/bin/stdin" && ! grep -q "TOOL OUTPUT" "$J/bin/stdin" && ! grep -q NOTICE "$J/bin/stdin"'
ok "only a finding quoting the chat's replies and the file it names word for word is kept" '[ "$(grep -c "" "$js/health-j1")" = 2 ] && [ "$(head -1 "$js/health-j1")" = "- The chat said \"We round discounts down to whole dollars\"; STATE.md says \"discounts round to the nearest cent, never to whole dollars\" (floor vs cents)" ] && grep -q "; DECISIONS.md says \"Rejected: storing totals as floats, because cents drift\"" "$js/health-j1"'
ok "its log counts what it found and keeps none of the chat's words" '[[ "$(cat "$js/judge-log")" == *"	app/main	m-1	500000	found 4	kept 2" ]] && ! grep -q round "$js/judge-log"'
jd
ok "it runs once until the chat compacts" '[ "$(runs)" = 1 ]'
out=$(printf '{"session_id":"j1","prompt":"next","transcript_path":"%s"}' "$J/t.jsonl" | CLAUDE_PROJECT_DIR="$J" "$H/hooks/bind.sh" | jq -r .hookSpecificOutput.additionalContext)
ok "the next prompt shows what it found, to settle before the answer" '[[ "$out" == "trackside'"'"'s context check compared"*"- The chat said \"We round discounts down to whole dollars\""*"Before you answer, settle each"* ]] && [ ! -f "$js/health-j1" ]'
ok "and offers a fresh chat if a reply was wrong" '[[ "$out" == *"If one was, also offer once, in one line before the rest of your reply"* ]] && [ "$(cat "$js/offered-j1")" = 0 ]'
echo 1 > "$js/compactions-j1"; jd
ok "it runs again after a compaction" '[ "$(runs)" = 2 ]'
rm -f "$js/judged-j1" "$js/offered-j1"
TRACKSIDE_JUDGE_TOKENS=600000 jd
ok "not below TRACKSIDE_JUDGE_TOKENS" '[ "$(runs)" = 2 ]'
TRACKSIDE_JUDGE_TOKENS=0 jd
ok "0 turns it off" '[ "$(runs)" = 2 ]'
echo 540000 > "$js/limit-m-1"; jd; rm -f "$js/limit-m-1"
ok "nor when the chat is due its offer anyway" '[ "$(runs)" = 2 ]'
touch "$js/whole-j1"; jd; rm -f "$js/whole-j1"
ok "nor in a chat kept whole" '[ "$(runs)" = 2 ]'
out=$(printf '{"session_id":"g9","prompt":"/trackside:start app/main"}' | TRACKSIDE_CHILD=1 CLAUDE_PROJECT_DIR="$J" "$H/hooks/bind.sh"; echo "exit=$?")
ok "inside the judge's own process trackside's hooks do nothing" '[ "$out" = "exit=0" ] && [ ! -f "$js/track-g9" ]'
rm -rf "${J:?}"

echo "--- bad input"
for h in bind load track stop; do
  out=$(printf 'not json' | "$H/hooks/$h.sh"; echo "exit=$?")
  ok "$h ignores bad input" '[ "$out" = "exit=0" ]'
done

echo "--- helper scripts"
out=$(bash "$H/scripts/status.sh" "$R")
ok "status lists the tracks still open" '[ "$out" = "- shop/tickets: [assumed] a very long current line number one that keeps going — with · marks (start: /trackside:start shop/tickets)" ]'
O=$(mktemp -d "${TMPDIR:-/tmp}/trackside-none.XXXXXX")
out=$(cd "$O" && bash "$H/scripts/status.sh" "$R/api"); rm -rf "$O"
ok "status says when a folder has no trackside folder" '[[ "$out" == *"No trackside folder at $R/api/.trackside"* ]]'
out=$(bash "$H/scripts/freshness.sh" "$R" shop/research)
ok "freshness says when there's no stamp" '[[ "$out" == *"No git stamp yet"* ]]'

echo "--- chats side by side"
errs=$( { for i in 1 2 3 4 5 6 7 8; do bash "$H/scripts/index.sh" "$R" & done; wait; } 2>&1 )
ok "parallel index runs don't collide or leave temp files" '[ -z "$errs" ] && [ -z "$(ls "$K"/INDEX.md.* "$st"/INDEX.* 2>/dev/null)" ] && grep -q "shop/tickets" "$K/INDEX.md"'
F=$(mktemp -d "${TMPDIR:-/tmp}/trackside-fresh.XXXXXX"); mkdir -p "$F/.trackside"
bash "$H/scripts/index.sh" "$F"
ok "the index's temp files go to a git-ignored .state/, even on a fresh trackside folder" '[ "$(cat "$F/.trackside/.state/.gitignore")" = "*" ] && grep -q "mktemp \"\$keep/.state/" "$H/scripts/index.sh"'
rm -rf "$F"
T=$(mktemp -d "${TMPDIR:-/tmp}/trackside-big.XXXXXX"); q "$T" init -b main; q "$T" -c user.name=t -c user.email=t@example.com commit --allow-empty -m s
dd if=/dev/zero of="$T/big.bin" bs=1048576 count=300 2>/dev/null
t0=$(date +%s); changes_out=$(. "$H/scripts/common.sh"; changes_fingerprint "$T"); t1=$(date +%s)
ok "a 300 MB untracked file doesn't slow the fingerprint ($((t1 - t0))s)" '[ $((t1 - t0)) -le 1 ] && [ -n "$changes_out" ]'
rm -rf "$T"
printf 'scratch' > "$K/.gitignore"
bash "$H/scripts/index.sh" "$R"
ok "appending to a .gitignore without a final newline keeps lines apart" '[ "$(cat "$K/.gitignore")" = "$(printf "scratch\nINDEX.md")" ]'

echo "--- worktree sessions"
W=$(mktemp -d "${TMPDIR:-/tmp}/trackside-wt.XXXXXX")
q "$W" init -b main; q "$W" -c user.name=t -c user.email=t@example.com commit --allow-empty -m "start"
q "$W" worktree add -b worktree-w1 "$W/.claude/worktrees/w1"
mkdir -p "$W/.trackside/app/main"
printf '# Feature: app\n' > "$W/.trackside/app/FEATURE.md"
state app/main "none" "none" > "$W/.trackside/app/main/STATE.md"
wt() { printf '%s' "$2" | CLAUDE_PROJECT_DIR="$W" "$H/hooks/$1.sh"; [ "$1" != load ] || printf '%s' "$2" | CLAUDE_PROJECT_DIR="$W" "$H/hooks/load-state.sh"; }
wt bind '{"session_id":"w","prompt":"/trackside:start app/main"}' >/dev/null
wt track "{\"session_id\":\"w\",\"cwd\":\"$W/.claude/worktrees/w1/src\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$W/.trackside/app/main/STATE.md\"}}"
ok "in a worktree session the project repo is stamped in the worktree" '[ "$(cut -f2 "$W/.trackside/.state/stamp-app@main")" = "$(git -C "$W/.claude/worktrees/w1" rev-parse HEAD)" ] && [ "$(cut -f3 "$W/.trackside/.state/stamp-app@main")" = worktree-w1 ]'
q "$W/.claude/worktrees/w1" -c user.name=t -c user.email=t@example.com commit --allow-empty -m "worktree work"
out=$(wt load "{\"session_id\":\"w\",\"source\":\"resume\",\"cwd\":\"$W/.claude/worktrees/w1\"}")
ok "and checked there at the next start" '[[ "$out" == *". in worktree w1 (worktree-w1): 1 new commit(s)"* && "$out" == *"worktree work"* ]]'
ok "the agent is told the chat can read the track but not save it" '[[ "$out" == *"can read the track but can'"'"'t update STATE.md"* ]]'
out=$(wt load '{"session_id":"w","source":"resume"}')
ok "a main-checkout chat isn't told that" '[[ "$out" != *"can read the track"* ]]'
wt track "{\"session_id\":\"w\",\"cwd\":\"$W/.claude/worktrees/w1\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$W/.claude/worktrees/w1/app.js\"}}"
touch -t "$(mins_ago 20)" "$W/.trackside/.state/saved-w"
wt stop "{\"session_id\":\"w\",\"stop_hook_active\":false,\"cwd\":\"$W/.claude/worktrees/w1\"}" >/dev/null
ok "a worktree session isn't asked to save what it can't" '[ -f "$W/.trackside/.state/dirty-w" ] && [ ! -f "$W/.trackside/.state/owed-w" ]'
wt stop '{"session_id":"w","stop_hook_active":false}' >/dev/null
ok "the same chat state in the main checkout is asked" '[ -f "$W/.trackside/.state/owed-w" ]'
echo 970000 > "$W/.trackside/.state/limit-m-1"; tx "$W/w.jsonl" 950000
out=$(wt bind "{\"session_id\":\"w\",\"prompt\":\"next\",\"cwd\":\"$W/.claude/worktrees/w1\",\"transcript_path\":\"$W/w.jsonl\"}")
ok "a worktree session isn't offered a fresh chat it couldn't save for" '[[ "$out" != *"Offer once"* ]]'
out=$(wt bind "{\"session_id\":\"w\",\"prompt\":\"next\",\"transcript_path\":\"$W/w.jsonl\"}")
ok "the same chat in the main checkout is" '[[ "$out" == *"Offer once"* ]]'
rm -rf "$W"

echo "--- a trackside folder inside the project's repo"
G=$(mktemp -d "${TMPDIR:-/tmp}/trackside-one.XXXXXX")
q "$G" init -b main; q "$G" -c user.name=t -c user.email=t@example.com commit --allow-empty -m "start"
mkdir -p "$G/.trackside/app/main"
printf '# Feature: app\n\n**Repos:** .\n' > "$G/.trackside/app/FEATURE.md"
state app/main "none" "none" > "$G/.trackside/app/main/STATE.md"
g() { printf '%s' "$2" | CLAUDE_PROJECT_DIR="$G" "$H/hooks/$1.sh"; [ "$1" != load ] || printf '%s' "$2" | CLAUDE_PROJECT_DIR="$G" "$H/hooks/load-state.sh"; }
g bind '{"session_id":"g","prompt":"/trackside:start app/main"}' >/dev/null
g track "{\"session_id\":\"g\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$G/.trackside/app/main/STATE.md\"}}"
ok "the stamp doesn't count trackside's own files as changes" '[ "$(cut -f4 "$G/.trackside/.state/stamp-app@main")" = 0 ]'
later=$(date -v+2M +%Y%m%d%H%M 2>/dev/null || date -d '2 minutes' +%Y%m%d%H%M)
printf 'a later note\n' > "$G/.trackside/app/main/NOTES.md"; touch -t "$later" "$G/.trackside/app/main/NOTES.md"
out=$(bash "$H/scripts/freshness.sh" "$G" app/main)
ok "nor does freshness, after a trackside file changes" '[[ "$out" == *"- . (main): no changes"* ]]'
printf 'x\n' > "$G/real.txt"; touch -t "$later" "$G/real.txt"
out=$(bash "$H/scripts/freshness.sh" "$G" app/main)
ok "a real untracked file still counts" '[[ "$out" == *"uncommitted changes differ: 1 file(s) now, 0 then"* ]]'
rm -f "$G/real.txt"
gitenv() { GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@example.com GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@example.com "$@"; }
out=$(gitenv bash "$H/scripts/setup-git.sh" "$G" 2>&1; echo "exit=$?")
ok "setup-git needs a choice" '[[ "$out" == *"exit=1"* ]] && [ ! -e "$G/.trackside/.git" ]'
out=$(gitenv bash "$H/scripts/setup-git.sh" "$G" ignore history)
ok "setup-git keeps .trackside/ out of the project's git" '[ -z "$(git -C "$G" status --porcelain)" ] && grep -qx "/.trackside/" "$G/.git/info/exclude"'
ok "and gives it its own history" '[ "$(git -C "$G/.trackside" rev-list --count HEAD 2>/dev/null)" = 1 ] && [ -z "$(git -C "$G/.trackside" ls-files .state INDEX.md)" ]'
out=$(gitenv bash "$H/scripts/setup-git.sh" "$G" ignore history)
ok "running it again changes nothing" '[ -z "$out" ] && [ "$(grep -cx "/.trackside/" "$G/.git/info/exclude")" = 1 ]'
printf -- '- a save\n' >> "$G/.trackside/app/main/STATE.md"
gitenv bash -c 'printf "%s" "$1" | CLAUDE_PROJECT_DIR="$2" "$3/hooks/stop.sh"' _ '{"session_id":"g","stop_hook_active":false}' "$G" "$H" >/dev/null
ok "at the end of a turn the Stop hook commits what changed in the trackside folder" '[ "$(git -C "$G/.trackside" rev-list --count HEAD)" = 2 ] && [ "$(git -C "$G/.trackside" log -1 --format=%s)" = "app/main: save" ] && [ -z "$(git -C "$G/.trackside" status --porcelain)" ]'
gitenv bash -c 'printf "%s" "$1" | CLAUDE_PROJECT_DIR="$2" "$3/hooks/stop.sh"' _ '{"session_id":"g","stop_hook_active":false}' "$G" "$H" >/dev/null
ok "and nothing when nothing changed" '[ "$(git -C "$G/.trackside" rev-list --count HEAD)" = 2 ]'
printf -- '- more\n' >> "$G/.trackside/app/main/STATE.md"
gitenv bash -c 'printf "%s" "$1" | CLAUDE_PROJECT_DIR="$2" "$3/hooks/stop.sh"' _ '{"session_id":"nobody","stop_hook_active":false}' "$G" "$H" >/dev/null
ok "an unbound chat leaves it alone" '[ "$(git -C "$G/.trackside" rev-list --count HEAD)" = 2 ]'
git -C "$G/.trackside" checkout -q -- app/main/STATE.md
mkdir -p "$G/sub/.trackside"
gitenv bash "$H/scripts/setup-git.sh" "$G/sub" ignore >/dev/null
ok "a project in a repo's subfolder is excluded by its own path, and ignore alone adds no history" 'grep -qx "/sub/.trackside/" "$G/.git/info/exclude" && [ -z "$(git -C "$G" status --porcelain)" ] && [ ! -e "$G/sub/.trackside/.git" ]'
N=$(mktemp -d "${TMPDIR:-/tmp}/trackside-nogit.XXXXXX"); mkdir -p "$N/.trackside"
out=$(gitenv bash "$H/scripts/setup-git.sh" "$N" ignore history)
ok "outside a git repo it says there's nothing to ignore and adds the history" '[ -d "$N/.trackside/.git" ] && [[ "$out" == *"isn'"'"'t a git repo"* ]]'
out=$(gitenv bash "$H/scripts/allow-edits.sh" "$G")
ok "the allow rule lets saves edit .trackside/ without a prompt, in settings only this user reads" '[ "$(jq -c .permissions.allow "$G/.claude/settings.local.json")" = "[\"Edit(/.trackside/**)\"]" ] && [[ "$out" == "Allowed edits to .trackside/"* ]]'
ok "and that file stays out of the project's git" 'git -C "$G" check-ignore -q .claude/settings.local.json'
printf '{"permissions":{"allow":["Bash(ls *)"]},"model":"x"}\n' > "$G/.claude/settings.local.json"
gitenv bash "$H/scripts/allow-edits.sh" "$G" >/dev/null; out=$(gitenv bash "$H/scripts/allow-edits.sh" "$G")
ok "it adds the rule once, keeping what the file had" '[ "$(jq -c "[.permissions.allow, .model]" "$G/.claude/settings.local.json")" = "[[\"Bash(ls *)\",\"Edit(/.trackside/**)\"],\"x\"]" ] && [[ "$out" == *"already allowed"* ]] && [ "$(grep -c settings.local.json "$G/.git/info/exclude")" = 1 ]'
printf 'not json' > "$G/.claude/settings.local.json"
out=$(gitenv bash "$H/scripts/allow-edits.sh" "$G" 2>&1; echo "exit=$?")
ok "and leaves a file it can't read alone" '[[ "$out" == *"isn'"'"'t valid JSON"*"exit=1" ]] && [ "$(cat "$G/.claude/settings.local.json")" = "not json" ]'
rm -rf "$G" "$N"

echo "--- renaming"
N=$(mktemp -d "${TMPDIR:-/tmp}/trackside-rename.XXXXXX"); NK="$N/.trackside"; NS="$NK/.state"
mkdir -p "$NK/shop/tickets" "$NK/shop/research" "$NS"
printf '# Feature: shop\n' > "$NK/shop/FEATURE.md"
printf '# Decisions: shop\n' > "$NK/shop/DECISIONS.md"
for t in tickets research; do
  state "shop/$t" none none > "$NK/shop/$t/STATE.md"
  printf '# Track: shop/%s\n\n**Goal:** %s work\n' "$t" "$t" > "$NK/shop/$t/CONTEXT.md"
done
printf -- '- 2026-10-22 · from shop/tickets · see .trackside/shop/tickets/NOTES.md\n- shop/tickets,shop/tickets; shop/ticketsx and api/shop/tickets stay\n' >> "$NK/shop/research/STATE.md"
printf 'shop is a plain word here; .trackside/shop/FEATURE.md\n' >> "$NK/shop/FEATURE.md"
mkdir -p "$NK/_archive/shop/old"; printf 'from shop/tickets\n' > "$NK/_archive/shop/old/STATE.md"
printf 'shop/tickets\n' > "$NS/track-n1"; printf 'shop/tickets\n' > "$NS/track-n2"; printf 'shop/research\n' > "$NS/track-n3"
printf 'x\n' > "$NS/stamp-shop@tickets"; printf 'x\n' > "$NS/stamp-shop@tickets.docs"; printf '1 2 x\n' > "$NS/deep-shop@tickets"
printf 'shop/tickets\n' > "$NS/track-n4"; printf 'Review chat\n' > "$NS/name-n4"
NF=$(. "$H/scripts/common.sh"; name_file "$NK" "Review chat"); printf 'shop/tickets\n' > "$NF"
out=$(bash "$H/scripts/rename.sh" "$N" shop/tickets build)
ok "renaming a track moves its folder and updates its headers" '[ -f "$NK/shop/build/STATE.md" ] && [ ! -e "$NK/shop/tickets" ] && head -1 "$NK/shop/build/STATE.md" | grep -qx "# State: shop/build" && head -1 "$NK/shop/build/CONTEXT.md" | grep -qx "# Track: shop/build"'
ok "its chats stay bound and get the new name at their next message" '[ "$(cat "$NS/track-n1")" = shop/build ] && [ "$(cat "$NS/track-n2")" = shop/build ] && [ "$(cat "$NS/title-n1")" = shop/build ] && [ "$(cat "$NS/track-n3")" = shop/research ] && [ ! -f "$NS/title-n3" ] && [[ "$out" == *"renamed at their next message: 2"* ]]'
ok "a chat the user named stays bound, keeps its name, and its remembered track follows" '[ "$(cat "$NS/track-n4")" = shop/build ] && [ ! -f "$NS/title-n4" ] && [ "$(cat "$NF")" = shop/build ] && [[ "$out" == *"Chats kept bound: 3, renamed at their next message: 2"* ]]'
ok "its stamps and deep-review record follow it" '[ -f "$NS/stamp-shop@build" ] && [ ! -e "$NS/stamp-shop@tickets" ] && [ -f "$NS/stamp-shop@build.docs" ] && [ ! -e "$NS/stamp-shop@tickets.docs" ] && [ -f "$NS/deep-shop@build" ] && [ ! -e "$NS/deep-shop@tickets" ]'
ok "its stamp follows it" '[ -f "$NS/stamp-shop@build" ] && [ ! -e "$NS/stamp-shop@tickets" ]'
ok "the index lists the new name" 'grep -q "| shop/build |" "$NK/INDEX.md" && ! grep -q "shop/tickets |" "$NK/INDEX.md"'
ok "every reference to it in the trackside folder is updated" 'grep -q "from shop/build · see .trackside/shop/build/NOTES.md" "$NK/shop/research/STATE.md" && grep -q "^- shop/build,shop/build; shop/ticketsx and api/shop/tickets stay" "$NK/shop/research/STATE.md" && [[ "$out" == *"Files updated to the new name: 3"* ]]'
ok "but not in the archive" 'grep -qx "from shop/tickets" "$NK/_archive/shop/old/STATE.md"'
out=$(printf '{"session_id":"n1","prompt":"carry on"}' | CLAUDE_PROJECT_DIR="$N" "$H/hooks/bind.sh")
ok "the bind hook renames that chat at its next message" '[ "$(jq -r .hookSpecificOutput.sessionTitle <<<"$out")" = shop/build ] && [ ! -f "$NS/title-n1" ]'
out=$(bash "$H/scripts/rename.sh" "$N" shop store)
ok "renaming a feature moves it and every binding and stamp under it" '[ -f "$NK/store/build/STATE.md" ] && [ ! -e "$NK/shop" ] && [ "$(cat "$NS/track-n2")" = store/build ] && [ "$(cat "$NS/track-n3")" = store/research ] && [ -f "$NS/stamp-store@build" ] && [ -f "$NS/stamp-store@build.docs" ] && head -1 "$NK/store/FEATURE.md" | grep -qx "# Feature: store" && head -1 "$NK/store/DECISIONS.md" | grep -qx "# Decisions: store" && head -1 "$NK/store/research/STATE.md" | grep -qx "# State: store/research"'
ok "and updates its tracks' full names and paths, not the feature's name as a word" 'grep -q "from store/build · see .trackside/store/build/NOTES.md" "$NK/store/research/STATE.md" && grep -qx "shop is a plain word here; .trackside/store/FEATURE.md" "$NK/store/FEATURE.md"'
for a in "store/nope x" "store/build research" "store/build off" "store/build ../x" "nope x" "store research"; do
  mkdir -p "$NK/research"
  out=$(bash "$H/scripts/rename.sh" "$N" $a 2>&1; echo "exit=$?")
  ok "renaming is refused for: $a" '[[ "$out" == *"exit=1"* ]] && [ -f "$NK/store/build/STATE.md" ] && [ -f "$NK/store/research/STATE.md" ]'
done
rm -rf "$N"

echo "--- the automatic check"
A=$(mktemp -d "${TMPDIR:-/tmp}/trackside-audit.XXXXXX"); AK="$A/.trackside"; AS="$AK/.state"
mkdir -p "$AK/app/main" "$AS"
printf '# Feature: app\n\n**Goal:** an app\n' > "$AK/app/FEATURE.md"
printf '# Track: app/main\n\n**Goal:** build it\n' > "$AK/app/main/CONTEXT.md"
printf '# State: app/main\n\n## Inbox\n\n## Current\n- [verified] the parser works\n\n## Next step\n- edit src/parse.js parse()\n\n## Tickets\n- [ ] T-2: handle errors — acceptance: npm test passes\n' > "$AK/app/main/STATE.md"
printf '# Notes: app/main\n' > "$AK/app/main/NOTES.md"
au() { bash "$H/scripts/audit.sh" "$A" "${2:-app/main}" "$1"; }
out=$(au start);                                       ok "a clean track has nothing to report" '[ -z "$out" ]'
dup="- 2026-10-01 · T-1 · abc123 · this exact line is long enough to count as a duplicate"
{ printf '# State: app/main\n\n## Inbox\n- 2020-01-01 · app/other · old news · affects tickets\n\n## Current\n- working on the importer\n- [assumed] marked line\n\n## Next step\n\n## Tickets\n- [ ] T-3: no check here\n- [ ] T-2: handle errors — acceptance: npm test passes\n\n## Done log\n%s\n\n## Gotchas\n- %s\n' "$dup" "$(head -c 12000 < /dev/zero | tr '\0' 'g')"; } > "$AK/app/main/STATE.md"
{ printf '# Notes: app/main\n%s\n' "$dup"; head -c 16000 < /dev/zero | tr '\0' 'n'; printf '\n'; } > "$AK/app/main/NOTES.md"
printf '# Track: app/main\n\n**Read on start:**\n- `NOTES.md`\n- `docs/missing.md`\n\n**Rules for this track:**\n- <anything specific to this line of work>\n' > "$AK/app/main/CONTEXT.md"
out=$(au start)
ok "it flags a STATE.md only when the reload would leave part of it out, and names what" '[[ "$out" == *"STATE.md is "*" bytes, more than the reload loads whole (it would leave out Gotchas): move the oldest Done-log lines"* ]]'
ok "an empty Next step" '[[ "$out" == *"Next step is empty"* ]]'
ok "unmarked Current lines" '[[ "$out" == *"1 Current line(s) are not marked"* ]]'
ok "tickets without an acceptance check" '[[ "$out" == *"1 open ticket(s) in STATE.md have no acceptance check"* ]]'
ok "leftover template placeholders" '[[ "$out" == *"1 template placeholder line(s)"* ]]'
ok "files listed to read that don't exist" '[[ "$out" == *"names files that do not exist: docs/missing.md."* ]]'
ok "large files read at every start" '[[ "$out" == *"Read at every start but large: NOTES.md (15 KB)"* ]]'
ok "lines copied into both STATE.md and NOTES.md" '[[ "$out" == *"1 line(s) appear word for word in both STATE.md and NOTES.md"* ]]'
ok "and Inbox items older than two weeks" '[[ "$out" == *"1 Inbox item(s) are older than two weeks"* ]]'
out=$(au save);                                        ok "an unchanged track is skipped" '[ -z "$out" ]'
printf -- '- another gotcha\n' >> "$AK/app/main/STATE.md"
out=$(au save);                                        ok "a change that adds no new issue reports nothing" '[ -z "$out" ]'
sed 's/^## Next step$/## Next step\n- run npm test/' "$AK/app/main/STATE.md" > "$A/s" && mv "$A/s" "$AK/app/main/STATE.md"
out=$(au save);                                        ok "(setup) the fixed issue is dropped" '[ -z "$out" ] && ! grep -qx next-step "$AS/audit-app@main.told"'
sed '/^- run npm test$/d' "$AK/app/main/STATE.md" > "$A/s" && mv "$A/s" "$AK/app/main/STATE.md"
out=$(au save);                                        ok "an issue that comes back is reported again, alone" '[ "$out" = "- Next step is empty: write one concrete action (the file and function to touch, or the command to run)." ]'
out=$(au start);                                       ok "a chat start reports every open issue again" '[ "$(printf "%s\n" "$out" | wc -l | tr -d " ")" = 9 ]'
out=$(au due);                                         ok "a track never reviewed with notes over 10 KB is due" '[ "$out" = due ] && [ -f "$AS/deep-app@main.started" ] && [ ! -f "$AS/deep-app@main" ]'
out=$(au due);                                         ok "a review started in the last hour isn't started again" '[ -z "$out" ]'
touch -t "$(date -v-2H +%Y%m%d%H%M 2>/dev/null || date -d '2 hours ago' +%Y%m%d%H%M)" "$AS/deep-app@main.started"
out=$(au due);                                         ok "a review whose result was lost is started again after an hour" '[ "$out" = due ]'
au reviewed;                                           ok "a handled review is recorded" '[ -f "$AS/deep-app@main" ] && [ ! -f "$AS/deep-app@main.started" ]'
out=$(au due);                                         ok "then the track isn't due" '[ -z "$out" ]'
head -c 11000 < /dev/zero | tr '\0' 'm' >> "$AK/app/main/NOTES.md"
out=$(au due);                                         ok "notes that grew by 10 KB make it due again" '[ "$out" = due ]'
au reviewed
read -r _ size fp < "$AS/deep-app@main"; printf '%s %s %s\n' "$(( $(date +%s) - 1300000 ))" "$size" "$fp" > "$AS/deep-app@main"
out=$(au due);                                         ok "two weeks without changes isn't enough" '[ -z "$out" ]'
read -r _ size fp < "$AS/deep-app@main"; printf '%s %s %s\n' "$(( $(date +%s) - 1300000 ))" "$size" "old" > "$AS/deep-app@main"
out=$(au due);                                         ok "two weeks with changes is" '[ "$out" = due ]'
au reviewed
DS=$(mktemp -d "${TMPDIR:-/tmp}/trackside-date.XXXXXX")
printf '#!/bin/sh\ncase "$1" in +%%Y-%%m-%%d) echo 2020-01-01 ;; *) exec /bin/date "$@" ;; esac\n' > "$DS/date"; chmod +x "$DS/date"
read -r _ size fp < "$AS/deep-app@main"; printf '%s %s %s\n' "$(( $(date +%s) - 1300000 ))" "$size" "$fp" > "$AS/deep-app@main"
out=$(PATH="$DS:$PATH" au due);                        ok "a review recorded on another day isn't due two weeks later when nothing changed" '[ -z "$out" ]'
rm -rf "$DS"
mkdir -p "$AK/app/small"; cp "$AK/app/FEATURE.md" "$AK/app/small/NOTES.md"
printf '# State: app/small\n\n## Current\n- [verified] fine\n\n## Next step\n- ship it\n' > "$AK/app/small/STATE.md"
out=$(au due app/small);                               ok "a small track isn't due, and starts its two-week clock" '[ -z "$out" ] && [ -f "$AS/deep-app@small" ]'
rm -f "$AS"/audit-app@main*
printf 'app/main\n' > "$AS/track-a1"; printf 'app/small\n' > "$AS/track-a2"
ae() { printf '{"session_id":"%s","tool_name":"Edit","tool_input":{"file_path":"%s"}}' "$1" "$AK/$2/STATE.md" | CLAUDE_PROJECT_DIR="$A" "$H/hooks/track.sh"; }
out=$(ae a1 app/main)
ok "saving STATE.md tells the agent what to fix, in the same turn" '[ "$(jq -r .hookSpecificOutput.hookEventName <<<"$out")" = PostToolUse ] && [[ "$(jq -r .hookSpecificOutput.additionalContext <<<"$out")" == *"trackside'"'"'s check of app/main after this save:"*"Next step is empty"*"Fix the ones that only move or de-duplicate text"* ]]'
out=$(ae a1 app/main);                                 ok "but only once" '[ -z "$out" ]'
out=$(ae a2 app/small);                                ok "a clean track's save adds nothing" '[ -z "$out" ]'
out=$(printf '{"session_id":"a1","source":"resume"}' | CLAUDE_PROJECT_DIR="$A" "$H/hooks/load.sh")
ok "a chat start lists the open issues for the agent" '[[ "$out" == *"trackside'"'"'s check of this track:"*"Next step is empty"* ]]'
out=$(printf '{"session_id":"a2","source":"resume"}' | CLAUDE_PROJECT_DIR="$A" "$H/hooks/load.sh")
ok "and says nothing for a clean track" '[[ "$out" != *"trackside'"'"'s check"* ]]'
rm -f "$AS"/deep-app@main*
err=$(printf '{"session_id":"a1","source":"resume"}' | CLAUDE_PROJECT_DIR="$A" "$H/hooks/load.sh" 2>&1 >/dev/null); rm -f "$AS"/deep-app@main.started
ok "a chat start on a due track writes nothing to stderr" '[ -z "$err" ]'
out=$(printf '{"session_id":"a1","source":"resume"}' | CLAUDE_PROJECT_DIR="$A" "$H/hooks/load.sh")
ok "a chat start on a due track asks the agent to start the review" '[[ "$out" == *"periodic review of this track is due. Start the trackside audit skill for app/main now"* ]]'
out=$(printf '{"session_id":"a1","source":"resume"}' | CLAUDE_PROJECT_DIR="$A" "$H/hooks/load.sh")
ok "but not again while it runs" '[[ "$out" != *"periodic review"* ]]'
printf '{"session_id":"a1","tool_name":"Write","tool_input":{"file_path":"%s"}}' "$AK/app/main/review-2026-10-23.md" | CLAUDE_PROJECT_DIR="$A" "$H/hooks/track.sh"
ok "writing the review file marks the review as handled" '[ -f "$AS/deep-app@main" ] && [ ! -f "$AS/deep-app@main.started" ] && [ ! -f "$AS/dirty-a1" ]'
mkdir -p "$AK/app/big"
printf '# Track: app/big\n\n**Read on start:**\n- `NOTES.md`\n\n**Rules for this track:**\n%s\n' "$(for i in $(seq 1 30); do echo "- rule number $i that keeps the context file near its size limit"; done)" > "$AK/app/big/CONTEXT.md"
{ printf '# State: app/big\n\n## Inbox\n- 2026-10-20 · app/main · a note · affects tickets\n\n## Current\n- [verified] work\n\n## Next step\n- go\n\n## Tickets\n'; for i in $(seq 1 60); do echo "- [ ] T-$i: a ticket with a title long enough to fill the file — acceptance: a test"; done; } > "$AK/app/big/STATE.md"
for i in $(seq 1 500); do echo "- a reference note line number $i with some words in it"; done > "$AK/app/big/NOTES.md"
ms() { python3 -I -c 'import subprocess, sys, time; t = time.time(); subprocess.run(sys.argv[1:], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL); print(int((time.time() - t) * 1000))' "$@"; }
cold=$(ms bash "$H/scripts/audit.sh" "$A" app/big start); warm=$(ms bash "$H/scripts/audit.sh" "$A" app/big save)
ok "a full check of a large track takes under 500 ms (${cold} ms)" '[ "$cold" -lt 500 ]'
ok "an unchanged track is skipped in under 200 ms (${warm} ms)" '[ "$warm" -lt 200 ]'
G2=$(mktemp -d "${TMPDIR:-/tmp}/trackside-audit2.XXXXXX"); mkdir -p "$G2/.trackside/app/main"
printf '# State: app/main\n\n## Current\n- State as of today:\n  - [verified] the parser works\n\n## Next step\n- go\n' > "$G2/.trackside/app/main/STATE.md"
out=$(bash "$H/scripts/audit.sh" "$G2" app/main start)
ok "the check creates trackside's runtime folder with its git-ignore rule" '[ "$(cat "$G2/.trackside/.state/.gitignore")" = "*" ]'
ok "a heading-style Current bullet ending in a colon isn't counted as unmarked" '[ -z "$out" ]'
D=$(mktemp -d "${TMPDIR:-/tmp}/trackside-date.XXXXXX")
printf '#!/bin/sh\n[ "$1" = "+%%Y-%%m-%%d" ] && { echo 2099-01-01; exit 0; }\nexec /bin/date "$@"\n' > "$D/date"; chmod +x "$D/date"
before=$(head -1 "$G2/.trackside/.state/audit-app@main"); PATH="$D:$PATH" bash "$H/scripts/audit.sh" "$G2" app/main start >/dev/null; after=$(head -1 "$G2/.trackside/.state/audit-app@main")
ok "a new day rescans an unchanged track, since the Inbox check depends on the date" '[ "$before" != "$after" ]'
rm -rf "$G2" "$D"
ok "skills that run trackside's scripts say to run them exactly as written" '[ -z "$(grep -L "Run each command below exactly as written" "$H"/skills/{start,save,done,close,list,current,rename}/SKILL.md)" ]'
ok "the start skill runs the check right after binding" 'grep -q "audit.sh\" \"\${CLAUDE_PROJECT_DIR}\" \"<feature>/<track>\" start" "$H/skills/start/SKILL.md"'
rm -rf "$A"
ok "the deep review runs in a separate, read-only context on Sonnet" 'grep -qx "context: fork" "$H/skills/audit/SKILL.md" && grep -qx "agent: trackside:auditor" "$H/skills/audit/SKILL.md" && grep -qx "model: sonnet" "$H/agents/auditor.md" && grep -qx "tools: Read, Grep, Glob" "$H/agents/auditor.md"'
ok "a chat start or a fresh binding starts the review when it's due" 'grep -q "periodic review of this track is due" "$H/hooks/load.sh" && grep -q "audit.sh\" \"\${CLAUDE_PROJECT_DIR}\" \"<feature>/<track>\" due" "$H/skills/start/SKILL.md"'
ok "save and done no longer start it" '[ -z "$(grep -l "audit.sh.*due" "$H"/skills/{save,done}/SKILL.md)" ]'
ok "the handled result goes to a review file, with an Inbox pointer when it has items" '[ "$(grep -l "Nothing needs the user" "$H/hooks/load.sh" "$H/skills/start/SKILL.md" "$H/skills/audit/SKILL.md" | wc -l | tr -d " ")" = 3 ]'
ok "the start-of-chat text has no backticks, which bash would run as commands" '! grep -q "add \".*\`" "$H/hooks/load.sh"'

echo "--- source docs"
D=$(mktemp -d "${TMPDIR:-/tmp}/trackside-docs.XXXXXX"); DK="$D/.trackside"; DS="$DK/.state"; DD="$DS/stamp-pay@main.docs"
mkdir -p "$D/docs" "$DK/pay/main" "$DS"
rfc() { printf '# Pay RFC\nIntro.\n## Decisions\n| ID | Date | Decision |\n| --- | --- | --- |\n%s\n## KYC form\n%s\n```sh\n# not a heading\n```\n## Notes\nfirst\n%s' "$1" "$2" "$3" > "$D/docs/rfc.md"; }
rfc '| AD-1 | 2026-10-01 | One account per member |
| AD-2 | 2026-10-02 | Full SSN, tokenized in the browser |' 'One form.' '## Notes
second
'
printf '# Feature: pay\n\n**Source docs:** `docs/rfc.md`, `docs/missing.md`\n\n**Decisions:** `DECISIONS.md` in this folder\n' > "$DK/pay/FEATURE.md"
printf '# Decisions: pay\n\n## D-001 · 2026-10-20 · One form\n' > "$DK/pay/DECISIONS.md"
printf '# Track: pay/main\n\n**Goal:** build pay\n' > "$DK/pay/main/CONTEXT.md"
state pay/main "the KYC form per AD-2 and D-001 [assumed]" "check AD-1, AD-9 and CASH-12" > "$DK/pay/main/STATE.md"
printf 'pay/main\n' > "$DS/track-d1"
dh() { printf '%s' "$2" | CLAUDE_PROJECT_DIR="$D" "$H/hooks/$1.sh"; [ "$1" != load ] || printf '%s' "$2" | CLAUDE_PROJECT_DIR="$D" "$H/hooks/load-state.sh"; }
dsave() { dh track "{\"session_id\":\"d1\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$DK/pay/main/STATE.md\"}}" >/dev/null; }
has() { awk -F'\t' -v d="$2" -v k="$3" -v n="$4" '$1 == d && $2 == k && $3 == n { f = 1 } END { exit !f }' "$1"; }
dsave
ok "a save records each source doc's sections and the IDs it defines" 'has "$DD" docs/rfc.md s "KYC form" && has "$DD" docs/rfc.md a AD-2 && has "$DD" docs/rfc.md s "Notes (2)" && ! grep -q "not a heading" "$DD"'
ok "the feature's DECISIONS.md counts as a source doc, and a listed doc that doesn't exist is skipped" 'has "$DD" .trackside/pay/DECISIONS.md a D-001 && ! grep -q missing.md "$DD"'
out=$(bash "$H/scripts/freshness.sh" "$D" pay/main)
ok "unchanged docs are reported in one line" '[[ "$out" == *"Source docs: no changes since STATE.md was last written."* && "$out" == *"No git stamp yet"* ]]'
before=$(cat "$DD"); dsave
ok "saving again keeps the lines of a doc that didn't change" '[ "$(cat "$DD")" = "$before" ]'
rfc '| AD-2 | 2026-10-20 | Last four of the SSN |
| AD-3 | 2026-10-21 | Payouts at first withdrawal |' 'Two forms.' ''
out=$(bash "$H/scripts/freshness.sh" "$D" pay/main)
ok "a changed doc lists the sections and IDs that changed" '[[ "$out" == *"- docs/rfc.md: sections changed: \"Decisions\", \"KYC form\"; removed sections: \"Notes (2)\"; IDs changed: AD-2; new IDs: AD-3; removed IDs: AD-1"* ]]'
ok "then the IDs the track cites that changed or are gone" '[[ "$out" == *"cites IDs that changed: AD-2, AD-1 (removed). Check those lines against the docs."* ]]'
ok "the doc report comes first, so the reload keeps it" '[[ "$(printf "%s\n" "$out" | head -1)" == "Source docs changed since STATE.md was last written."*"lookup skill"* ]]'
ok "a doc that didn't change isn't listed" '[[ "$out" != *DECISIONS.md* ]]'
out=$(bash "$H/scripts/audit.sh" "$D" pay/main start)
ok "the check flags cited IDs no source doc mentions" '[[ "$out" == *"cites IDs no source doc mentions: AD-1, AD-9."* ]]'
ok "but not IDs of a kind the docs don't define, such as ticket keys" '[[ "$out" != *CASH-12* && "$out" != *D-001* ]]'
out=$(dh load '{"session_id":"d1","source":"resume"}')
ok "a bound chat is told the source docs are the source of truth, and to read them with the lookup" '[[ "$out" == *"The source docs FEATURE.md lists are the source of truth: before you state, decide or change anything they cover, read it with the trackside lookup skill"* && "$out" == *"cite what you use by ID"* ]]'
ok "and the reload reports what changed in them" '[[ "$out" == *"- docs/rfc.md: sections changed:"* ]]'
dsave; out=$(bash "$H/scripts/freshness.sh" "$D" pay/main)
ok "after the next save, the docs count as unchanged again" '[[ "$out" == *"Source docs: no changes since"* ]]'
printf 'x\n' >> "$D/docs/rfc.md"; mv "$D/docs/rfc.md" "$D/docs/old-rfc.md"
out=$(bash "$H/scripts/freshness.sh" "$D" pay/main)
ok "a doc that was moved or deleted is reported" '[[ "$out" == *"- docs/rfc.md: no longer there"* ]]'
out=$(hook load '{"session_id":"s1","source":"resume"}')
ok "a feature without source docs gets no such line" '[[ "$out" != *"source of truth"* ]]'
# About the shape of a real 570 KB RFC: a few hundred sections and IDs, each section a couple of KB.
awk 'BEGIN { for (i = 1; i <= 300; i++) { printf "## Section %d\n| AD-%d | 2026-10-01 | a decision row |\n", i, i; for (j = 0; j < 22; j++) print "Body text of the section, long enough to make the file about as large as a real RFC is." } }' > "$D/docs/rfc.md"
cold=$(ms bash -c 'printf "%s" "$1" | CLAUDE_PROJECT_DIR="$2" "$3/hooks/track.sh"' _ "{\"session_id\":\"d1\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$DK/pay/main/STATE.md\"}}" "$D" "$H")
warm=$(ms bash -c 'printf "%s" "$1" | CLAUDE_PROJECT_DIR="$2" "$3/hooks/track.sh"' _ "{\"session_id\":\"d1\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$DK/pay/main/STATE.md\"}}" "$D" "$H")
ok "a save that indexes a $(( $(wc -c < "$D/docs/rfc.md") / 1024 )) KB doc takes under 2 s (${cold} ms)" '[ "$cold" -lt 2000 ] && has "$DD" docs/rfc.md a AD-300'
ok "and once it's indexed, a save takes under 1 s (${warm} ms)" '[ "$warm" -lt 1000 ]'
rm -rf "$D"

echo "--- tracks whose items start clean"
C=$(mktemp -d "${TMPDIR:-/tmp}/trackside-clean.XXXXXX"); CK="$C/.trackside"
mkdir -p "$CK/rev/prs" "$CK/rev/build" "$CK/.state"
printf '# Feature: rev\n' > "$CK/rev/FEATURE.md"
printf '# Track: rev/prs\n\n**Goal:** review pull requests\n\n**Each item starts clean:** yes\n' > "$CK/rev/prs/CONTEXT.md"
printf '# Track: rev/build\n\n**Goal:** build the feature\n' > "$CK/rev/build/CONTEXT.md"
for t in prs build; do state "rev/$t" none "pick the next one" > "$CK/rev/$t/STATE.md"; done
out=$(bash "$H/scripts/status.sh" "$C")
ok "the list marks a track whose items start clean, and only that one" '[[ "$out" == *"- rev/prs (each item starts clean): "* && "$out" == *"- rev/build: "* ]]'
bash "$H/scripts/index.sh" "$C"
ok "so does the index" 'grep -q "^| rev/prs (each item starts clean) |" "$CK/INDEX.md" && grep -q "^| rev/build |" "$CK/INDEX.md"'
printf 'rev/prs\n' > "$CK/.state/track-c1"; printf 'rev/build\n' > "$CK/.state/track-c2"
out=$(bash "$H/scripts/current.sh" "$C" c1)
ok "/trackside:current says each item starts clean" '[[ "$out" == *"Each item starts clean: only CONTEXT.md and LESSONS.md carry over from one item to the next."* ]]'
out=$(bash "$H/scripts/current.sh" "$C" c2)
ok "and says when items build on the track's history" '[[ "$out" == *"Items build on the track'"'"'s history"* ]]'
out=$(bash "$H/scripts/audit.sh" "$C" rev/prs start)
ok "the check flags a clean track without LESSONS.md" '[[ "$out" == *"it has no LESSONS.md: create it from trackside'"'"'s templates/LESSONS.md"* ]]'
out=$(bash "$H/scripts/audit.sh" "$C" rev/build start)
ok "but not a track whose items build on each other" '[[ "$out" != *LESSONS.md* ]]'
today=$(date +%Y-%m-%d); long_ago=$(date -v-120d +%Y-%m-%d 2>/dev/null || date -d "120 days ago" +%Y-%m-%d)
sed "s/<feature>\/<track>/rev\/prs/" "$H/templates/LESSONS.md" > "$CK/rev/prs/LESSONS.md"
awk -v t="$today" -v o="$long_ago" '{ print } /^## Lessons/ { print "- Check Union CSS in node_modules · Jest maps CSS away · web · #116 · confirmed " t; print "- Read PRs in a scratch worktree · the checkout lacks @stripe · web · #116 · confirmed " o; print "- An old rule with no date · why · all · #9" } /^## Candidates/ { print "- Codes should be uppercase · seen in #120 on " o }' "$CK/rev/prs/LESSONS.md" > "$CK/l.tmp" && mv "$CK/l.tmp" "$CK/rev/prs/LESSONS.md"
out=$(bash "$H/scripts/audit.sh" "$C" rev/prs start)
ok "it flags lessons not confirmed in 90 days, or never" '[[ "$out" == *"2 lesson(s) in LESSONS.md were not confirmed in the last 90 days"* && "$out" != *"no LESSONS.md"* ]]'
ok "and candidates that didn't come up again in 60 days" '[[ "$out" == *"1 candidate lesson(s) in LESSONS.md did not come up again in 60 days: move them to NOTES.md."* ]]'
head -c 12000 /dev/zero | tr '\0' x >> "$CK/rev/prs/LESSONS.md"
out=$(bash "$H/scripts/audit.sh" "$C" rev/prs start)
ok "and a LESSONS.md the reload would cut" '[[ "$out" == *"LESSONS.md is "*" bytes, more than the reload loads whole"*"merge or replace lessons"* ]]'
sed "s/<feature>\/<track>/rev\/prs/" "$H/templates/LESSONS.md" > "$CK/rev/prs/LESSONS.md"
out=$(printf '{"session_id":"c1","source":"resume"}' | CLAUDE_PROJECT_DIR="$C" "$H/hooks/load.sh"; printf '{"session_id":"c1","source":"resume"}' | CLAUDE_PROJECT_DIR="$C" "$H/hooks/load-state.sh")
ok "the reload says each item starts clean and loads LESSONS.md" '[[ "$out" == *"Each item on this track starts clean: only CONTEXT.md and LESSONS.md carry over"* && "$out" == *"=== LESSONS.md (.trackside/rev/prs/LESSONS.md) ==="* ]]'
out=$(printf '{"session_id":"c2","source":"resume"}' | CLAUDE_PROJECT_DIR="$C" "$H/hooks/load.sh")
ok "a track whose items build on each other loads no LESSONS.md" '[[ "$out" != *LESSONS.md* && "$out" != *"starts clean"* ]]'
ok "the template's CONTEXT.md offers the line, as a placeholder the check catches" 'grep -q "^\*\*Each item starts clean:\*\* <yes when" "$H/templates/CONTEXT.md" && ! (grep "^\*\*Each item starts clean" "$H/templates/CONTEXT.md" | grep -qi "clean:\*\* *yes")'
ok "LESSONS.md says how an item finishes: details moved, not deleted, lessons recorded without asking" 'grep -q "Nothing is deleted" "$H/templates/LESSONS.md" && grep -q "without asking" "$H/templates/LESSONS.md" && grep -q "## Candidates" "$H/templates/LESSONS.md"'
ok "the start skill proposes the kind only when creating a track, in plain words" 'grep -q "Whether each item starts clean, in those words" "$H/skills/start/SKILL.md"'
ok "done and save finish a clean track's item the way LESSONS.md says" 'grep -q "finish the item the way its \`LESSONS.md\` says" "$H/skills/done/SKILL.md" && grep -q "the way \`LESSONS.md\` says" "$H/skills/save/SKILL.md"'
ok "the deep review checks whether the kind fits the work" 'grep -q "a kind that doesn'"'"'t fit the work" "$H/skills/audit/SKILL.md" && grep -q "Changing the kind always needs the user" "$H/skills/audit/SKILL.md"'
out=$(bash "$H/scripts/rename.sh" "$C" rev/prs reviews)
ok "renaming a clean track keeps its kind and renames its LESSONS.md header" '[ -f "$CK/rev/reviews/LESSONS.md" ] && head -1 "$CK/rev/reviews/LESSONS.md" | grep -qx "# Lessons: rev/reviews" && bash "$H/scripts/status.sh" "$C" | grep -q "^- rev/reviews (each item starts clean)"'
rm -rf "$C"

echo "--- pull request state"
P=$(mktemp -d "${TMPDIR:-/tmp}/trackside-prs.XXXXXX"); PK="$P/.trackside"
for r in api web; do mkdir -p "$P/$r"; q "$P/$r" init -b main; done
mkdir -p "$PK/shop/tickets"
printf '# Feature: shop\n\n**Repos:** api, web\n' > "$PK/shop/FEATURE.md"
printf '# State: shop/tickets\n\n## Current\n- reviewing web #13 [verified]\n- api#14 waits on CI [assumed]\n\n## Done log\n- 2026-10-23 · T-1 · abc1234 · tests pass · api#12\n- 2026-10-22 · T-0 · def5678 · tests pass · api#11 (merged 2026-10-22)\n- 2026-10-21 · T-9 · see shop-api#16 and api#\n' > "$PK/shop/tickets/STATE.md"
GB=$(mktemp -d "${TMPDIR:-/tmp}/trackside-gh.XXXXXX")
printf '#!/bin/sh\necho "$*" >> "%s/calls"\ncase "$3" in 12) echo "MERGED 2026-10-24" ;; 13) echo "OPEN " ;; *) exit 1 ;; esac\n' "$GB" > "$GB/gh"; chmod +x "$GB/gh"
out=$(PATH="$GB:$PATH" bash "$H/scripts/prs.sh" "$P" shop/tickets)
ok "it reports the state of each pull request the state names as <repo>#<number>" '[ "$out" = "api#12: merged 2026-10-24
web#13: open" ]'
ok "it only reads, and skips lines already marked merged and names that aren't a listed repo" '! grep -qv "^pr view " "$GB/calls" && ! grep -qE "^pr view (11|16) " "$GB/calls" && grep -q "^pr view 14 " "$GB/calls"'
for i in $(seq 1 12); do printf -- '- api#%s\n' "$((100 + i))"; done >> "$PK/shop/tickets/STATE.md"; rm -f "$GB/calls"
PATH="$GB:$PATH" bash "$H/scripts/prs.sh" "$P" shop/tickets >/dev/null
ok "it asks about at most 10 per run" '[ "$(wc -l < "$GB/calls" | tr -d " ")" = 10 ]'
NG=$(mktemp -d "${TMPDIR:-/tmp}/trackside-nogh.XXXXXX")
for c in dirname cat grep sort git awk sed tr head wc; do ln -s "$(command -v "$c")" "$NG/$c"; done
out=$(PATH="$NG" /bin/bash "$H/scripts/prs.sh" "$P" shop/tickets; echo "exit=$?")
ok "without gh it prints nothing and succeeds" '[ "$out" = "exit=0" ]'
ok "next runs it, read-only, and done names the pull request in the Done-log line" 'grep -q "scripts/prs.sh" "$H/skills/next/SKILL.md" && grep -q "It only reads" "$H/skills/next/SKILL.md" && grep -q "add it to the ticket'"'"'s Done-log line as \`<repo>#<number>\`" "$H/skills/done/SKILL.md"'
ok "done asks about moving repo lessons in the same request as the commit, not separately" 'grep -q "list each one in the same request" "$H/skills/done/SKILL.md" && grep -q "approving the commit approves those moves too" "$H/skills/done/SKILL.md"'
rm -rf "$P" "$GB" "$NG"

echo "--- regressions from the 2026-10-23 audit"
X=$(mktemp -d "${TMPDIR:-/tmp}/trackside-regress.XXXXXX"); XK="$X/.trackside"; XS="$XK/.state"
mkdir -p "$XK/rev/prs" "$XS"
xh() { printf '%s' "$2" | CLAUDE_PROJECT_DIR="$X" "$H/hooks/$1.sh"; [ "$1" != load ] || printf '%s' "$2" | CLAUDE_PROJECT_DIR="$X" "$H/hooks/load-state.sh"; }
long() { head -c "$1" /dev/zero | tr '\0' "$2"; }
printf '# Feature: rev\n\n%s\n' "$(long 1950 f)" > "$XK/rev/FEATURE.md"
printf '# Track: rev/prs\n\n**Each item starts clean:** yes\n\n%s\n' "$(long 2500 c)" > "$XK/rev/prs/CONTEXT.md"
printf '# Lessons: rev/prs\n\n## Lessons\n- %s\n\n## Candidates\n' "$(long 12000 l)" > "$XK/rev/prs/LESSONS.md"
state rev/prs "api#7 in flight" "post the api#7 review" > "$XK/rev/prs/STATE.md"
printf 'rev/prs\n' > "$XS/track-x1"
out=$(xh load '{"session_id":"x1","source":"resume"}')
n=$(xh load-state '{"session_id":"x1","source":"resume"}' | wc -c | tr -d ' ')
ok "a clean track whose LESSONS.md is too big still reloads STATE.md's Current and Next step ($n bytes)" '[[ "$out" == *"api#7 in flight"* && "$out" == *"post the api#7 review"* ]] && [ "$n" -le 9800 ]'
ok "and what was cut is LESSONS.md, which it names" '[[ "$out" == *"Read .trackside/rev/prs/LESSONS.md for them"* || "$out" == *"read .trackside/rev/prs/LESSONS.md in full"* ]] && [[ "$out" != *"STATE.md in full"* ]]'

mkdir -p "$X/api" "$XK/solo/one"; q "$X/api" init -b main; q "$X/api" -c user.name=t -c user.email=t@example.com commit --allow-empty -m "start api"
q "$X/api" checkout --detach
printf '# Feature: solo\n\n**Repos:** api\n' > "$XK/solo/FEATURE.md"
printf '# State: solo/one\n\n## Inbox\n\n## Current\n\n## Next step\n\n## Done log\n' > "$XK/solo/one/STATE.md"
printf 'solo/one\n' > "$XS/track-x2"
xh track "{\"session_id\":\"x2\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$XK/solo/one/STATE.md\"}}" >/dev/null
out=$(bash "$H/scripts/freshness.sh" "$X" solo/one)
ok "a repo on a detached HEAD shows no change right after a save" '[[ "$out" == *"- api (detached): no changes"* ]]'
out=$(bash "$H/scripts/status.sh" "$X"); err=$(bash "$H/scripts/index.sh" "$X" 2>&1 >/dev/null)
ok "a track with an empty Current and no goal lists no current work, not a date" '[[ "$out" == *"- solo/one: no current work (start: /trackside:start solo/one)"* ]] && grep -q "^| solo/one | none |" "$XK/INDEX.md" && [ -z "$err" ]'

xh bind '{"session_id":"x3","prompt":"/trackside:start solo/one"}' >/dev/null; touch "$XS/dirty-x3"
xh bind '{"session_id":"x3","prompt":"/trackside:start off"}' >/dev/null
out=$(bash "$H/scripts/bind.sh" "$X" x3 off)
ok "a typed /trackside:start off still tells the user their work wasn't saved" '[ "$out" = "Unbound this chat from solo/one. Its work since the last save wasn'"'"'t saved there." ] && [ ! -f "$XS/off-x3" ]'
out=$(xh bind '{"session_id":"x4","prompt":"/trackside:start solo/one","session_title":"my-review"}')
ok "a chat renamed after it started keeps its name when it binds" '[ -z "$out" ] && [ "$(cat "$XS/name-x4")" = my-review ] && [ "$(cat "$XS/track-x4")" = solo/one ] && [ "$(cat "$(. "$H/scripts/common.sh"; name_file "$XK" my-review)")" = solo/one ]'

printf 'solo/one\n' > "$XS/track-x5"
out=$(xh track "{\"session_id\":\"x5\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$X/api/a.js\"}}")
bash "$H/scripts/bind.sh" "$X" x5 off >/dev/null; bash "$H/scripts/bind.sh" "$X" x5 solo/one >/dev/null
out=$(xh track "{\"session_id\":\"x5\",\"tool_name\":\"Edit\",\"tool_input\":{\"file_path\":\"$X/api/a.js\"}}")
ok "after unbinding and binding again, the reminder to save before replying comes back" '[[ "$out" == *"Before you write your reply"* ]]'

printf '1 2 x\n' > "$XS/deep-solo@one"; printf 'solo/one\n' > "$(. "$H/scripts/common.sh"; name_file "$XK" "Old chat")"; printf 'solo/one\n' > "$XS/track-old9"
ago40=$(date -v-40d +%Y%m%d%H%M 2>/dev/null || date -d "40 days ago" +%Y%m%d%H%M)
touch -t "$ago40" "$XS/deep-solo@one" "$XS/track-old9" "$(. "$H/scripts/common.sh"; name_file "$XK" "Old chat")"
xh load '{"session_id":"x6","source":"startup"}' >/dev/null
ok "the 30-day cleanup keeps deep-review records and named chats' tracks, and clears old bindings" '[ -f "$XS/deep-solo@one" ] && [ -f "$(. "$H/scripts/common.sh"; name_file "$XK" "Old chat")" ] && [ ! -f "$XS/track-old9" ]'

Y=$(mktemp -d "${TMPDIR:-/tmp}/trackside-a@b.XXXXXX"); YK="$Y/.trackside"; mkdir -p "$YK/shop/tickets" "$YK/.state"
state shop/tickets none none > "$YK/shop/tickets/STATE.md"; printf 'x\n' > "$YK/.state/stamp-shop@tickets"; printf '1 2 x\n' > "$YK/.state/deep-shop@tickets"
out=$(bash "$H/scripts/rename.sh" "$Y" shop store 2>&1)
ok "renaming a feature under a path with @ in it moves its stamps and review record" '[ -f "$YK/.state/stamp-store@tickets" ] && [ -f "$YK/.state/deep-store@tickets" ] && [[ "$out" != *"No such file"* ]]'

printf '# State: solo/one\n\n## Current\n- real work [verified]\n\n## Current risks\n- an unmarked risk\n\n## Next step\n```\n## not a heading\n```\n- run it\n' > "$XK/solo/one/STATE.md"
out=$(bash "$H/scripts/audit.sh" "$X" solo/one start)
ok "a heading that starts with another one's name isn't read as part of it" '[[ "$out" != *"not marked [verified]"* ]] && [ "$(. "$H/scripts/common.sh"; current_line "$XK/solo/one/STATE.md")" = "real work [verified]" ]'
ok "a ## line inside a code block isn't a heading" '[ "$(. "$H/scripts/common.sh"; sections "$XK/solo/one/STATE.md" | cut -f1 | tr "\n" "|")" = "Current|Current risks|Next step|" ]'
out=$(bash "$H/scripts/audit.sh" "$X" solo/one strat 2>&1; echo "exit=$?")
ok "the check refuses an unknown mode instead of running as start" '[[ "$out" == *"Unknown mode: strat"* && "$out" == *"exit=1"* ]]'
ok "skills run each command on its own, commits included" '! grep -q "add -A &&" "$H"/skills/*/SKILL.md'
rm -rf "$X" "$Y"

echo "--- looking up the source docs"
LU=$(mktemp -d "${TMPDIR:-/tmp}/trackside-lookup.XXXXXX"); LK="$LU/.trackside"; mkdir -p "$LU/docs" "$LK/pay/main" "$LK/.state"
printf '# Pay RFC\n\n## Decisions\n| ID | Date | Decision |\n| --- | --- | --- |\n| AD-1 | 2026-10-01 | One account per member |\n| AD-2 | 2026-10-02 | The form takes the full SSN; overrides 4.2 |\n\n## 4. KYC\nOne form.\n### 4.2 The form\nIt takes the last four of the SSN (see AD-2).\n```md\n## not a heading\n| AD-1 | in a code block |\n```\n## 5. Payouts\n### 5.1 Payout bank\nCollected at the first withdrawal.\n' > "$LU/docs/rfc.md"
printf '# Feature: pay\n\n**Source docs:** `docs/rfc.md`\n' > "$LK/pay/FEATURE.md"
state pay/main none none > "$LK/pay/main/STATE.md"
lu() { bash "$H/scripts/doc-section.sh" "$LU" "$1" "$2"; }
out=$(lu l1 AD-2)
ok "an unbound chat is told there's nothing to look in" '[ "$out" = "This chat isn'"'"'t bound to a track, so there are no source docs to look in." ]'
printf 'pay/main\n' > "$LK/.state/track-l1"
out=$(lu l1 AD-2)
ok "an ID prints its decision row with the table's header, citable by line" '[[ "$out" == *"== docs/rfc.md:7 · a row of the table at line 4"*"| ID | Date | Decision |"*"| AD-2 | 2026-10-02 | The form takes the full SSN; overrides 4.2 |"* ]]'
ok "then the other lines that mention it, where an older section may disagree" '[[ "$out" == *"other lines that mention AD-2"*"It takes the last four of the SSN (see AD-2)."* ]]'
out=$(lu l1 AD-1)
ok "a row inside a code block isn't read as a decision, only listed as a mention" '[ "$(printf "%s\n" "$out" | grep -c "^== .*a row of the table")" = 1 ] && [[ "$out" == *"other lines that mention AD-1"*"15: | AD-1 | in a code block |"* ]]'
out=$(lu l1 "payout bank")
ok "heading words print that section, up to the next heading of its level or higher" '[[ "$out" == *"== docs/rfc.md:18-19 · 5.1 Payout bank"*"Collected at the first withdrawal."* ]]'
out=$(lu l1 "KYC")
ok "a section includes its subsections, and a ## line in a code block doesn't end it" '[[ "$out" == *"== docs/rfc.md:9-16 · 4. KYC"*"### 4.2 The form"*"## not a heading"* && "$out" != *"Payout bank"* ]]'
out=$(lu l1 "first withdrawal")
ok "words in no heading fall back to the lines that hold them" '[[ "$out" == *"other lines that contain it"*"19: Collected at the first withdrawal."* ]]'
out=$(lu l1 "bank payout")
ok "heading words match in any order" '[[ "$out" == *"== docs/rfc.md:18-19 · 5.1 Payout bank"* ]]'
out=$(lu l1 AD-2)
ok "several matches are listed first, each with where it is" '[[ "$out" == "Matches (2):"$'"'"'\n'"'"'"- docs/rfc.md:7 · a row of the table at line 4"$'"'"'\n'"'"'"- docs/rfc.md: other lines that mention AD-2"$'"'"'\n'"'"'"== docs/rfc.md:7"* ]]'
out=$(lu l1 "payout bank")
ok "a single match isn't" '[[ "$out" == "== docs/rfc.md:18-19"* ]]'
{ for i in $(seq 1 70); do printf '## Rule %s\n%s\n' "$i" "$(printf 'filler %.0s' $(seq 1 30))"; done; } > "$LU/docs/rules.md"
printf '# Feature: pay\n\n**Source docs:** `docs/rfc.md`, `docs/rules.md`\n' > "$LK/pay/FEATURE.md"
out=$(lu l1 "rule")
ok "a cut keeps the list of matches, up to 50, ahead of the text" '[ "$(printf "%s" "$out" | wc -c)" -le 8100 ] && [[ "$out" == "Matches (70):"*"- docs/rules.md:"*"Rule 50"$'"'"'\n'"'"'"… and 20 more: use more words, or an ID, to narrow it"*"[Cut at 8,000 bytes: read the rest in the docs, at the matches listed first.]" ]]'
printf '# Feature: pay\n\n**Source docs:** `docs/rfc.md`\n' > "$LK/pay/FEATURE.md"
out=$(lu l1 "nothing like this")
ok "and nothing matching says so" '[[ "$out" == "Nothing in the source docs matches"* ]]'
ok "the lookup skill runs it pre-approved, and tells the chat to follow newer decisions" 'grep -q "Bash(bash \"\${CLAUDE_SKILL_DIR}/../../scripts/doc-section.sh\" \*)" "$H/skills/lookup/SKILL.md" && grep -q "Newer decisions override older sections" "$H/skills/lookup/SKILL.md"'
rm -rf "$LU"

echo "--- the handoff check"
ok "the handoff check reads only, like a new chat" 'grep -qx "tools: Read, Grep, Glob" "$H/agents/handoff-check.md" && grep -q "remember nothing of the chat that saved it" "$H/agents/handoff-check.md" && grep -q "say the check is incomplete instead of answering" "$H/agents/handoff-check.md"'
ok "save runs it with paths only, never the saving chat's own summary, and fixes what it found quietly" 'grep -q "ask the \`handoff-check\` subagent, passing it only the track'"'"'s full name and the paths" "$H/skills/save/SKILL.md" && grep -q "never a summary of your own" "$H/skills/save/SKILL.md" && grep -q "don'"'"'t mention the check otherwise" "$H/skills/save/SKILL.md"'
printf 'shop/tickets\n' > "$st/track-hc"
hook track '{"session_id":"hc","tool_name":"Agent","tool_input":{"subagent_type":"trackside:handoff-check"}}'
ok "asking it isn't counted as research" '[ ! -f "$st/dirty-hc" ]'
rm -f "$st"/*-hc

echo "--- each rule has one home"
while IFS=$'\t' read -r phrase home copies why; do
  case "$phrase" in ''|'#'*) continue ;; esac
  [ "$copies" != - ] || copies=""
  want=$(printf '%s\n' $home $copies | sort | tr '\n' ' ')
  got=$(cd "$H" && grep -rlF -- "$phrase" hooks scripts skills agents templates | sort | tr '\n' ' ')
  ok "\"$phrase\" is in $home${copies:+ and the copies listed}, nowhere else" '[ "$got" = "$want" ]'
  [ "$got" = "$want" ] || printf '  found in: %s\n  listed:   %s\n' "$got" "$want"
done < "$(dirname "$0")/rule-homes.tsv"

echo "--- skill commands"
ok "nothing refers to a custom trackside folder anymore" '! grep -rq TRACKSIDE_FOLDER "$H"'
ok "skills run commands from the project root, not the working directory" '[ -z "$(grep -n "PWD" "$H"/skills/*/SKILL.md | grep -v "freshness.sh")" ]'
missing=""
for f in "$H"/skills/*/SKILL.md; do
  allow=$(grep -m1 "^allowed-tools:" "$f")
  for s in $(grep -o "scripts/[a-z-]*\.sh" "$f" | sort -u); do
    [[ "$allow" == *"Bash(bash \"\${CLAUDE_SKILL_DIR}/../../$s\" *)"* ]] || missing="$missing ${f#$H/}:$s"
  done
  if grep -q 'git -C "${CLAUDE_PROJECT_DIR}/.trackside" commit' "$f"; then
    [[ "$allow" == *'Bash(git -C "${CLAUDE_PROJECT_DIR}/.trackside" commit *)'* ]] || missing="$missing ${f#$H/}:commit"
  fi
done
ok "every skill pre-approves the trackside scripts and .trackside commits it runs${missing:+ (missing:$missing)}" '[ -z "$missing" ]'
ok "done marks the ticket done only after the commit is approved, and stops on a failed check" 'grep -q "Until then, the ticket stays open" "$H/skills/done/SKILL.md" && grep -q "If any of them fails, report it and stop" "$H/skills/done/SKILL.md"'
ok "next checks only the repos the ticket touches" 'grep -q "in each repo the ticket touches" "$H/skills/next/SKILL.md"'
ok "save lists what it recorded" 'grep -q "one line for each decision, Inbox line or rule you wrote" "$H/skills/save/SKILL.md"'
ok "save and done leave the trackside folder's commit to the Stop hook" '! grep -q "git -C" "$H/skills/save/SKILL.md" && ! grep -q "git -C" "$H/skills/done/SKILL.md" && grep -q "trackside commits it at the end of the turn" "$H/skills/save/SKILL.md"'
ok "saves are asked for in one edit, in the reload, the reminders and save" 'grep -q "in one edit (one Edit call or one script)" "$H/hooks/load.sh" && grep -q "in one edit (one Edit call or one script)" "$H/skills/save/SKILL.md" && grep -q "Make it one edit" "$H/hooks/track.sh" && grep -q "in one edit each" "$H/hooks/bind.sh"'
ok "the deep review is capped in turns and kept to the track's files" 'grep -qx "maxTurns: 12" "$H/agents/auditor.md" && grep -q "Read nothing else: not the source docs, code, scripts, other repos or git history" "$H/skills/audit/SKILL.md" && ! grep -q "or the source docs contradict" "$H/skills/audit/SKILL.md"'
ok "the git offer comes only when .trackside/ is created" 'grep -q "If \`\${CLAUDE_PROJECT_DIR}/.trackside/\` doesn'"'"'t exist yet, also offer three separate choices" "$H/skills/start/SKILL.md"'
ok "new tracks don't load NOTES.md at every start" '! grep -q "^\*\*Read on start:\*\*" "$H/templates/CONTEXT.md"'
ok "next, done and save read the chat's binding before acting" '[ "$(grep -l "track-\${CLAUDE_SESSION_ID}" "$H"/skills/{next,done,save}/SKILL.md | wc -l | tr -d " ")" = 3 ]'
ok "next and done say they only apply in a chat bound to a track" '[ "$(grep -l "^description: In a chat bound to a track" "$H"/skills/{next,done}/SKILL.md | wc -l | tr -d " ")" = 2 ]'
ok "a ticket asked for right after binding still waits for approval" 'grep -q "write no code until the user approves" "$H/skills/start/SKILL.md"'
ok "closing asks about open items once" 'grep -q "Propose, in one list" "$H/skills/close/SKILL.md" && ! grep -q "For each open item, ask" "$H/skills/close/SKILL.md"'
ok "every skill command that touches .trackside goes through the project root" '[ -z "$(grep -nE "\`(bash|git|grep)[^\`]*\.trackside" "$H"/skills/*/SKILL.md | grep -v CLAUDE_PROJECT_DIR)" ]'

echo "---"
echo "passed $pass, failed $fail"
[ "$fail" = 0 ]
