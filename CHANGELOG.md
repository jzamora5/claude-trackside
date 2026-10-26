# Changelog

## 0.20.0 · 2026-10-26

- Long chats are offered a fresh start, and never pushed into one. At each message trackside reads the chat's context size from its transcript. Once it reaches 90% of the size at which that model's chats compact on their own (`TRACKSIDE_OFFER_PERCENT`), or after `COMPACT_LIMIT` compactions, the agent asks once, in a line before its answer, and again only after the next compaction. trackside learns that size per model from the automatic compactions it sees (the largest, since an idle compaction can run early), or takes it from `CLAUDE_CODE_AUTO_COMPACT_WINDOW`. This replaces the reload's request to save and `/clear` after two compactions.
- `/trackside:fresh` saves the track, then clears the chat: in the desktop app through the app's clear tool, which asks you to approve, and in the terminal by telling you to type `/clear`. The cleared chat reloads the track as before.
- `/trackside:whole` keeps a chat as it is, with no offers and no judge, for a chat you want to keep complete, and says where its transcript is and how long Claude Code keeps it under your settings.
- A judge checks long chats against their track. Past `TRACKSIDE_JUDGE_TOKENS` (400K), at most once between compactions, a Stop hook in the background runs Haiku as its own `claude -p` process (no tools, settings, plugins or saved session) on the track's files and the chat's last 20 messages, without tool output. Only findings whose quotes appear word for word in the chat's replies and the named file are kept; the next message brings them, and the agent fixes the track or its reply, offering a fresh chat only when a reply was wrong. On the tracks it was tried on, a run reads about 5K tokens and takes a few seconds; the chat itself spends nothing on it. `.state/judge-log` keeps each run's counts, never the chat's words. A subagent was rejected for this: launching one and reading its result would cost the chat two more calls at its full size, far more than the judge.
- Evals: `offers-fresh-chat` and `fresh-saves-then-clears`.

## 0.19.0 · 2026-10-26

- `/trackside:save` checks the handoff the way a new chat would read it. A read-only `handoff-check` subagent that remembers nothing of the chat gets only the track's name and file paths, never the saving chat's summary. It reads what a new chat reads, says what's in flight, the next action, what's decided and what's waiting, and lists everything it had to guess. The saving chat fills those gaps quietly and tells the user only what it can't fill. The idea follows the Goldfish reviewers of google/elephant-goldfish-model: a chat that wrote the state assumes what it knows is obvious. In an eval with an undefined ticket input planted in the state, saves with the check raised it in 2 of 2 runs, and saves without it in 1 of 2, for about $0.07 more per save.
- `doc-expert` is gone, folded into the main chat as `/trackside:lookup <ID or heading words>`. `scripts/doc-section.sh` prints the exact sections and decision rows that match, with their lines and the other lines that mention the ID, so a later decision that overrides one shows up. The chat reads and cites the source itself, rather than a summary. Following Anthropic's "When to fold subagents into your main agent loop", it was kept only after an eval: on three questions about a 150 KB RFC (one answered by a decision that overrides an older section), both answered all 6 runs correctly, at the same cost ($1.47) and about the same time (34.5 s with doc-expert, 33.2 s with the lookup). With doc-expert, the main chat often read the RFC itself as well.
- Evals: `save-checks-handoff`, `continues-from-state` (a fresh chat picks up the right next step and avoids a recorded dead end) and three `doc-q-*` cases on a generated RFC.

## 0.18.0 · 2026-10-26

- Nothing lands after a reply anymore. The Stop hook no longer sends a chat back to save once its reply is written; it notes that the save is owed. Your next message then starts with the request, so the save comes before that answer. A chat you `/clear` or close instead leaves a note on the track, and the next chat on it is told the last one ended with work `STATE.md` doesn't have yet.
- A save made through the shell, such as `sed` on `STATE.md`, now counts like an Edit: the edit hook also sees Bash, and counts a command that names the bound track's `STATE.md`, by its path or from the track's folder, when the file just changed. Before this, a chat that saved that way looked unsaved for days, so its reminder before the reply never came back and the Stop hook fired after every working turn. Other shell commands still don't count as work.

## 0.17.0 · 2026-10-23

- The reload is two hook outputs. Claude Code caps each hook's output at 10,000 characters and measures each hook on its own, so `STATE.md`, with `LESSONS.md` after it on a track whose items start clean, now has an output of its own (`hooks/load-state.sh`), and `FEATURE.md` and `CONTEXT.md` share the other with trackside's instructions. The two hooks run in parallel, so the state hook works out the chat's track the same way, reading only. On TKWW's tracks every file now reloads whole, where the largest used to leave four sections of `STATE.md` out.
- No more fixed sizes: the 5,000, 2,600, 2,000 and 4,000-byte limits on `STATE.md`, `CONTEXT.md`, `FEATURE.md` and `LESSONS.md` are gone. The check flags a file only when the reload would leave part of it out, names what it would leave out, and asks for a fix about 1,000 bytes under.
- The reload's routines (`emit_file`, `reload_files`, `reload_state`, `chat_binding`) moved to `common.sh`, so the hooks and the check share them.

## 0.16.1 · 2026-10-23

Fixes from an audit of 0.16.0, each with a regression test that fails on 0.16.0:

- On a track where each item starts clean, `STATE.md` now loads before `LESSONS.md`, with the room `LESSONS.md` needs held back from its budget. With every file at its size limit, the reload used to leave out `STATE.md` entirely, Current and Next step included.
- A repo on a detached HEAD no longer reports a branch change and uncommitted changes right after a save, and a track with an empty Current and no goal no longer lists a date as its current work. Both came from empty fields in tab-separated records, which now hold "-".
- The deep review no longer comes due every two weeks when nothing changed: its record now compares the track's files and source docs, without the date.
- A typed `/trackside:start off` with unsaved work tells the user that work wasn't saved, as the start skill's own unbinding does.
- A chat the user renamed after it started keeps that name when it binds. The prompt hook now reads the chat's title too.
- Unbinding or closing a track clears the save reminder's marker, so after binding again the reminder comes before the reply again.
- The 30-day cleanup keeps deep-review records and the tracks remembered for chats the user named.
- Renaming a feature works when the project's path contains "@", as Google Drive folders do.
- One section parser, shared by the reload, the check and the state readers. It matches a heading's whole name, so "## Current risks" is no longer read as part of "## Current", and it skips "## " lines inside code blocks.
- The check rejects an unknown mode instead of running as start. The skills commit the trackside folder in two commands, one per call, as they say. Two leftover mentions of the old name now say trackside.

## 0.16.0 · 2026-10-23

Ideas from an earlier plugin with the old name, lackeyjb/claude-keep:

- `/trackside:done` lists each lesson that's about a repo's own code or tooling and would help any chat in that repo, with the repo's `CLAUDE.md` (or the project's rules file for that repo) it would move to, in the same request as the commit: approving the commit approves the moves. `/trackside:close` offers the same destination in its one list, and the periodic review flags such lessons still in a track.
- A save writes down only what a new chat couldn't get from the code, git, the docs or a command, and points to file contents, diffs and test output instead of copying them.
- Done-log lines name their pull request as `<repo>#<number>`. `scripts/prs.sh` reads each one's state with `gh pr view` in that repo's folder, at most 10 per run, and prints nothing without `gh`. `/trackside:next` runs it and marks merged and closed pull requests in the state, without mentioning it. Hooks still make no network calls.
- `tests/rule-homes.tsv` lists each rule stated in more than one file, with the file that is its home and why each copy exists. The hook tests fail when a rule's phrase shows up anywhere else, or goes missing from a listed file.

## 0.15.0 · 2026-10-23

**Breaking:** keep is now **trackside**. Two other Claude Code plugins are named `keep`, and when two enabled plugins share a name, Claude Code runs the hooks of only one of them, so the reload, the save reminder and the stamps could silently stop.

- Install `trackside@claude-trackside` from github.com/jzamora5/claude-trackside; the old URL redirects. Commands are `/trackside:start`, `/trackside:save` and the rest, and the subagents are `trackside:doc-expert` and `trackside:auditor`.
- The state folder is `.trackside/` instead of `.keep/`. To move a project's tracks, rename the folder, replace `.keep/` with `.trackside/` in its files and in your `CLAUDE.md`, and update a `/.keep/` line in `.git/info/exclude` if `setup-git.sh ignore` wrote one. The chat bindings in `.state/` move with the folder.
- `KEEP_SAVE_MINUTES`, `KEEP_IDLE_DAYS` and `KEEP_STATE_DAYS` are now `TRACKSIDE_SAVE_MINUTES`, `TRACKSIDE_IDLE_DAYS` and `TRACKSIDE_STATE_DAYS`.

## 0.14.0 · 2026-10-23

- The state is saved before the reply, not after it. Once a save is due, the first edit or research of a turn asks the agent to update `STATE.md` before it writes its reply, once per save. The Stop hook still catches a turn that ended without saving, and now asks for a quiet update that ends with no more text, or with the reply's question repeated so it stays the last thing you see.
- keep's bookkeeping stays out of replies: no reports of saves, trims, fixes from the automatic check or keep commits. Anything keep needs from you goes in a line before the reply's last question, never after it. A size fix the check asks for is one edit, not several small trims.
- The `/keep:digest` suggestion appears only in the status reply of a plain `/keep:start`, not in replies to a request.

## 0.13.0 · 2026-10-23

- A track can start each item clean: `**Each item starts clean:** yes` in its `CONTEXT.md`, for a stream of separate items such as pull request reviews. Only `CONTEXT.md` and the track's `LESSONS.md` carry over from one item to the next, and both load at every chat start.
- When such an item is finished, it leaves one Done-log line, and its details move to `NOTES.md` or stay in the item's own file. A lesson the user stated goes into `LESSONS.md` right away, without a question. One the agent inferred goes in as a candidate, and is promoted the second time it comes up. `LESSONS.md` says how, so every chat on the track has the rule.
- The agent proposes the kind only when it creates a track, in plain words, as part of the proposal the user confirms. The list, the index, `/keep:current` and the first reply after binding show it.
- keep's check flags a clean track without `LESSONS.md`, a `LESSONS.md` over 4,000 bytes, lessons not confirmed in 90 days, and candidates that didn't come up again in 60 days. The periodic review flags a kind that doesn't fit the work.
- `/keep:done` on a ticket that changed no repo files, such as a review, goes straight to updating `STATE.md` instead of asking to commit.

## 0.12.0 · 2026-10-23

- In a feature with source docs, every chat is told they're the source of truth: before it states, decides or changes anything they cover, the agent asks `doc-expert` instead of relying on what `STATE.md` says about them, and cites what it uses by ID (such as AD-28) or heading. `doc-expert` returns the IDs and headings its answer comes from.
- Each save records a checksum of every section of the feature's source docs and of every ID they define, in a table's first column or a heading, with the feature's `DECISIONS.md` counted as a source doc. At chat start and after `/clear`, a resume or a compaction, the agent is told which sections and IDs changed since that save, first the IDs the track cites. A save indexes only the docs that changed: about a second for a 580 KB doc with 300 sections, a checksum for one that didn't change.
- keep's check flags IDs that `STATE.md` or `CONTEXT.md` cite and no source doc mentions anymore, for the kinds of ID the docs define, so ticket keys from elsewhere aren't flagged.
- The one line saying the chat was bound and how to undo it shows only when the agent bound the chat on its own.
- Closing a track asks whether to close it with the proposed list, so confirming the list is clearly confirming the close.

## 0.11.0 · 2026-10-23

- When a chat that isn't bound starts work that clearly fits one track, the agent binds it to that track and carries on, saying so in one line with `/keep:start off` to undo it, instead of asking first. It asks only when more than one track could fit, and still creates a track only after you agree. `/keep:save` in a chat that isn't bound works the same way.
- A chat you unbound stays unbound, `/clear` included: keep remembers the `off` for a chat you named, as it does for the chats it names `<feature>/<track> (unbound)`.

## 0.10.0 · 2026-10-23

**Breaking:** `/keep:start` takes only a track's full name, `<feature>/<track>`. A bare name such as `/keep:start tickets` no longer binds, even when only one track has it: it was ambiguous to read, and could start meaning another track once one was added. The start skill lists the full names it could mean instead. Every listing, the index, `/keep:current` and the save and compaction messages show the full command.

- `/keep:rename` updates every reference to the old name inside `.keep/`: full names, `.keep/` paths and headers, including other tracks' Inbox lines. It leaves the archive alone, and a feature's name used as a plain word. The agent then updates the project's `CLAUDE.md` files and its saved notes, asks nothing unless the names are unclear, writes nothing about the rename in `STATE.md`, and replies in three lines.
- Edits to a `CLAUDE.md` file no longer count as project work.

## 0.9.0 · 2026-10-23

- A quick check runs after every save, at every chat start and right after a chat is bound. It flags a `STATE.md` over its size, an empty Next step, unmarked Current lines, tickets without an acceptance check, leftover placeholders, files listed to read that don't exist or are large, lines copied into both state and notes, and Inbox items older than two weeks. It skips tracks whose files haven't changed that day and raises each issue once. A full check of a large track takes about 0.2 seconds; an unchanged one, about 0.05.
- The agent fixes what only moves, de-duplicates or fills in text in the same save, and asks about the rest once per chat, at a natural pause.
- `/keep:audit` reviews a track in the background on Sonnet, reading only: it proposes merges, contradictions to fix, decisions to record and a summary for large notes. The next chat on a track starts it on its own when the track's notes grew by 10 KB or two weeks passed with changes. Its lossless items are applied; the rest are saved in the track's `review-<date>.md` with an Inbox pointer. A review counts as done only once that file is written, so a lost result is retried after an hour.

## 0.8.0 · 2026-10-22

- keep no longer renames a chat you named yourself. It remembers which track that name is on instead, and since Claude Code keeps your name through `/clear`, the chat still finds its track again. Chats with only an auto-generated title are still named after their track. A name you give a chat partway through is picked up at its next start or `/clear`.

## 0.7.0 · 2026-10-22

- `/keep:current`, or asking which track or workspace this chat is on, shows the chat's track with its current work, next step and start command, or says the chat isn't bound and lists the tracks.
- The agent understands "workspace" as another word for a track: the skills and the start-of-chat context say so.

## 0.6.0 · 2026-10-22

- `/keep:rename` renames a track within its feature, or a whole feature, when you type it or ask in words. The folder moves, its headers and git stamps follow, chats bound to it stay bound and get the new name at their next message, and files that still mention the old name are listed rather than changed.
- After `/clear`, a resume or a compaction, a track's `CONTEXT.md` reloads whole up to about 2,600 bytes (was 1,500), so its rules aren't cut off. When space runs short, `STATE.md`'s later sections are left out and named instead.

## 0.5.1 · 2026-10-21

- A chat that moves to another folder after it starts keeps `CLAUDE_PROJECT_DIR` from the folder it started in. When that folder has no `.keep/`, the hooks, scripts and skills now use the nearest `.keep/` at or above the folder the chat works in, instead of finding nothing and staying silent.
- An eval suite in `plugins/keep/evals/` checks eight behaviors in real headless sessions with `claude plugin eval`; `bash tests/evals.sh` runs it.

## 0.5.0 · 2026-10-21

- Say yes to a track the agent suggests, and it binds the chat and carries on with your request: there's no command to type. A ticket still waits for your approval of its plan, as with `/keep:next`. The agent can now run the start skill, but only after you agree. The chat is named after the track at your next message.
- `/keep:start <name> <request>` binds and starts on the request in one message.
- A new track is proposed in one message, with its goal and, for a new feature, the repos, decisions file and planning filled in from what the agent finds. Once you confirm, it's created and the chat is bound to it, with no second `/keep:start`.
- The Stop hook asks at most once every 15 minutes (`KEEP_SAVE_MINUTES`; 0 restores asking after every working turn), and only for Current and Next step.
- Edits to files outside the project folder, such as scratch files, no longer count as work.
- Worktree sessions that can't save to `.keep/` are no longer asked to after every turn; the agent says the chat can read the track but not save it.
- When a feature names source docs but has no digest, the agent suggests `/keep:digest`. Ending a ticket says "Type /clear, then say next".
- The agent offers a track only when your message starts work on it, not for a quick question.
- Ask the agent to close a track and it runs `/keep:close`, which still asks about every open item before changing anything.
- Freshness and the git stamps leave `.keep/` out, so in a project whose repo holds `.keep/`, the state's own files no longer show up as code changes. The first check after upgrading may still report a difference once.
- `/keep:next`, `/keep:done` and `/keep:save` act only in a chat bound to a track, so they don't start in an unrelated chat. In a chat that isn't bound, next and done say so, and save asks which track to bind first.
- Closing proposes where each open item goes in one list, and asks once.
- Switching a chat to another track while it has unsaved work saves that work to its own track first, instead of leaving it for the new one. `/keep:start off` unbinds a chat.
- `/keep:done` stops when a check fails, and marks the ticket done in STATE.md only after you approve the commit.
- The skills run keep's own scripts and `.keep/` commits without permission prompts (`allowed-tools`). The README shows a rule that allows the STATE.md edits the reminder asks for.
- When a message starts work that matches no track, the agent offers once to create one. The README says what to do first.
- `/keep:next` checks only the repos the ticket touches, and a new feature lists only the repos the work involves.
- The 15-minute clock is each chat's own last save, so another chat editing the same STATE.md doesn't silence the reminder. The reminder and the start of each chat also ask for decisions to be recorded when they're made, and `/keep:save` lists what it recorded.
- The track list and the index show a track's goal when nothing is in flight.
- NOTES.md is no longer read at every start; new tracks read it when needed.
- The git offer comes once, when `.keep/` is created, as two separate choices (`setup-git.sh ignore history`).
- Without jq, binding says that keep's hooks are off.
- New tracks drop template lines that can't be filled in, and the save and compaction messages give the track's short start command.

## 0.4.0 · 2026-10-21

- `/keep:start` takes a single name when only one track matches it: a feature with one track, or a track name used by only one feature. The index and the listings show the shortest command for each track.
- In a chat that isn't bound yet, the agent's first reply names the track that matches what you asked about, with its start command. It only suggests; nothing is bound until you run the command.
- Binding a chat that already has work in it offers `/keep:save`, so what the chat knew before reaches the track.

## 0.3.1 · 2026-10-20

- Edits to Claude's own files under `~/.claude/` (memory, plans, settings) no longer mark the chat dirty.
- Only keep's own `doc-expert` subagent is exempt from the gate; another plugin's agent with a similar name counts as research.
- Saving the state no longer hashes the contents of untracked files, so a large untracked file can't slow the hooks. Freshness still reports an untracked file that changed after the last save.
- The index writes its temporary file inside `.keep/.state/`, so a run that's killed midway can't leave a file for git to pick up.

## 0.3.0 · 2026-10-20

**Breaking:** `KEEP_FOLDER` is removed. The keep folder is always `.keep/` in the project root; a setup that used another folder falls back to `.keep/` without a warning. To keep your tracks, rename that folder to `.keep`.

- Edits inside Claude Code worktrees (`.claude/worktrees/`) mark the chat dirty.
- Skills run their commands from the project root instead of the working directory.
- Freshness reports a reset to an older commit and changes to files that were already uncommitted.
- Chats side by side no longer collide on temporary files.
- `/keep:start <feature>` with a single track uses that track in the skill too, as the bind hook does.
- The Stop hook answers with Stop hook feedback instead of an error.
- Git stamps move to `.keep/.state/` and are removed when a track is closed.
- In a worktree session, the project's own repo is stamped and checked in the worktree.
- The README describes what the gate covers, including its limits.

## 0.2.0 · 2026-10-20

- `.keep/INDEX.md`, generated at every chat start and state save.
- `/keep:list` and `/keep:close`, which archives a track or feature into `.keep/_archive/`.
- `/keep:start` asks you to approve a name before creating a feature or track.
- Idle tracks are flagged after 14 days, and old session files are cleared after 30.

## 0.1.0 · 2026-10-20

- First version: features and tracks, the Stop-hook gate, reload after a compaction, git stamps, and `/keep:start`, `/keep:next`, `/keep:done`, `/keep:save` and `/keep:digest`.
