# How trackside works

The details behind the [README](../README.md): how chats bind to tracks, when state is saved and reloaded, how long chats are handled, and what trackside checks on its own.

- [Features, tracks and files](#features-tracks-and-files)
- [Binding a chat to a track](#binding-a-chat-to-a-track)
- [Saving: what the gate covers](#saving-what-the-gate-covers)
- [Reloading](#reloading)
- [Long chats](#long-chats)
- [Source docs and decisions](#source-docs-and-decisions)
- [Checks and reviews](#checks-and-reviews)
- [Tracks whose items start clean](#tracks-whose-items-start-clean)
- [Pull requests and repo lessons](#pull-requests-and-repo-lessons)
- [Closing and cleanup](#closing-and-cleanup)
- [Worktree sessions](#worktree-sessions)
- [The .trackside folder](#the-trackside-folder)

## Features, tracks and files

A feature lives in `.trackside/<feature>/`, with a `FEATURE.md` that points to its source docs (an RFC, PRD, design doc or spec) instead of copying them. Each track has:

- `CONTEXT.md`: what it's for;
- `STATE.md`: where it stands;
- `NOTES.md`: reference material.

You can call a track a workspace; the agent understands both words.

Several chats can work on one feature at once, on tickets, a research topic or reviews. They share its source docs and pass decisions to each other through each track's Inbox.

## Binding a chat to a track

**Starting work.** In a new chat, say what you want to work on. When a message starts work (not a quick question) and one track clearly fits it, the agent binds the chat to that track. It says so in one line and carries on with your request.
- When more than one track could fit, it asks which.
- When none does, it offers to create one, and creates nothing until you agree.
- A ticket still waits for your approval of its plan.

**Typing the command.** You can also type `/trackside:start <feature>/<track>`, always with the full name, followed by your request: `/trackside:start legal/terms check the new vendor doc`. Only `/trackside:start` binds or unbinds; a bare `/start` may be another plugin's command. `/trackside:start off` unbinds the chat, and a chat you unbound stays unbound, through compactions, resumes and `/clear`. A chat with unsaved work on one track saves it before switching to another.

**Names.** trackside never renames a chat on its own. When a chat is bound to a track for the first time, it offers once to rename the chat after the track: a typed `/trackside:start` shows the offer as a trackside notice, and when the agent binds the chat, it makes the offer in the line that says so. Reply `rename` (or "rename it") to take it; any other message keeps the chat's name, and the offer stays open until the chat is bound elsewhere, unbound or cleared. A track you already declined isn't offered again, and a track whose `CONTEXT.md` says `**Name chats after the track:** no`, such as one whose own rules name its chats, offers none. When another chat has the name, the offer is numbered: `wedding-fund/phase-1 · 2`. A fork, which starts with its parent's name, is offered the next number once, and a chat that moves to another track while it still has the old track's name is offered the new one. trackside remembers which track each chat's title is on, so a named chat finds its track after `/clear`, a resume or a fork, and a chat you unbound stays off. A `/clear` also hands the track to the chat it starts, so a chat with no name keeps its track too. Two chats with the same name share one remembered track, the most recent. In VS Code, `/clear` leaves the conversation it ended in the chat list under the same name, as the terminal's `/resume` list does; the newest is the one you're in.

**Opting in mid-chat.** trackside does nothing in a chat until it's bound, so an ongoing chat can opt in at any point: ask the agent to work on a track or to save the chat to trackside, or type `/trackside:start`. If no track fits, the agent proposes a new one, in an existing feature when one fits. When you bind a chat that already has work in it, the agent offers `/trackside:save`, so what the chat already knows reaches the track.

**Proposing a track.** A new track is proposed in one message, with its name, its goal and, for a new feature, the repos and settings the agent found. Nothing is created until you confirm or correct it.

**Work that drifts.** A chat stays on its track however far its work drifts. `/trackside:save` checks first whether the work since the last save plainly belongs to another track. If it does, the save asks you once which track to save it to, and moves the chat there with that work.

## Saving: what the gate covers

**When it asks.** At the first counted work once a save is due, a hook asks the chat to update Current and Next step in `STATE.md` before it writes its reply, in one edit, and to record any new decision.
- It asks at most once every 15 minutes after this chat's last save (`TRACKSIDE_SAVE_MINUTES`; 0 asks after every working turn).
- Another chat editing the same `STATE.md`, for example to add an Inbox line, doesn't reset that clock.
- The update happens quietly: replies don't report saves or trims.

**What counts as work:**
- edits with Edit, Write and NotebookEdit to files in the project folder, including Claude Code worktrees under `.claude/worktrees/`;
- web fetches and searches;
- subagents, except trackside's own `auditor` and `handoff-check`, which only read the track's files.

**What doesn't:**
- edits inside `.trackside/`, to the project's own `.claude/` settings, and to files outside the project folder, such as scratch files and Claude's files in `~/.claude/`;
- project files changed through shell commands (`sed -i`, code generators, `git checkout`). Run `/trackside:save` after work like that.

A shell command that changes the track's own `STATE.md` counts as a save; one that only reads it doesn't.

**When a turn ends unsaved.** trackside doesn't send the chat back after its reply, so nothing lands after a reply you're reading. Instead, once a save is due, your next message starts with the request, before its answer. Whenever a turn ends with unsaved work, even before a save is due, the chat leaves its own line in the track's note, so several open chats never hide each other's work. Resuming a chat that has a line makes its save due again.
- Another chat opened on that track while the first is still open is told to leave that work to it.
- Once the first chat ends or is cleared, or leaves the note for a day, the next chat on the track is told the last one left off with unsaved work. It fills the gap from the code and git, marks those lines `[assumed]`, and tells you in one line.

**What a save writes.** Only what a new chat couldn't get from the code, git, the docs or a command. It points to file contents, diffs and test output instead of copying them. Each decision is recorded when it's made, with the options it rejected and why, so a later chat doesn't propose them again.

**The handoff check.** `/trackside:save` then has a subagent with no memory of the chat read the track the way a new chat would, and fills the gaps it finds.

**Commits.** If `.trackside/` has its own git history, the Stop hook commits it at the end of each turn that changed it. The commit message names the tracks and feature folders that changed, so the agent spends no calls on it.

## Reloading

**When it reloads.** `/clear`, a resume or a compaction reloads the feature and the track on their own. A fork of a chat with a name stays on the track, as a second chat on it; a fork of a chat with no name starts unbound until your next request binds it. When a chat starts on a track, after `/clear`, in a fork or by its name, you're shown which one: `trackside: this chat is bound to <feature>/<track>.` If the app starts a cleared chat without its title, trackside puts the chat back on its track at your first message, by its name, with the whole reload it would have had, and shows you the same line then. That happens only at the first message after the app starts a chat, never after a compaction or resume, so a chat you unbind stays unbound. Right after a compaction, a chat with unsaved work saves it, and records any decision or ruled-out option the summary holds that the track doesn't: the context is at its smallest then, so the save costs the least, and the summary is the last place those decisions still exist.

**Staying under the limit.** Claude Code caps each hook's output at 10,000 characters, so the reload comes in two outputs:
- `STATE.md` in one of its own, with `LESSONS.md` after it on a track whose items start clean;
- `FEATURE.md` and `CONTEXT.md` in the other, with trackside's instructions.

Each output always includes `STATE.md`'s Inbox, Current and Next step. It adds whole sections while they fit, and names the ones it left out. The files have no byte limits: the check flags one only when the reload would leave part of it out.

**What changed since.** Each save stamps the feature's repos with their commit, branch and uncommitted files. The next chat sees what changed since (new commits, a different branch, uncommitted files) before it trusts the state.

## Long chats

**The offer.** At each message, trackside reads the chat's context size from its transcript. The agent asks once, in a line before its answer, once the context reaches 90% of the size at which that model's chats compact on their own (`TRACKSIDE_OFFER_PERCENT`), or after two compactions (`COMPACT_LIMIT`). The choices are:
- clear this chat and continue the track (`/trackside:fresh`);
- keep the chat whole (`/trackside:whole`);
- carry on. It asks again only after the next compaction.

trackside learns the compaction size from the first automatic compaction it sees for each model, or takes it from `CLAUDE_CODE_AUTO_COMPACT_WINDOW` when you set it.

**`/trackside:fresh`** saves the track, then clears the chat. In the desktop app it asks the app to clear the chat when the reply ends. In VS Code and the terminal, where `/clear` would leave the chat in the list beside a new one with the same name, it gives you a `/compact` line to type instead, which keeps one chat; that compaction starts the count of compactions over, like a clear. Either way, you type only `/trackside:fresh`, and the chat reloads the track on its own. It runs:
- when you type it;
- when you ask to clear this chat;
- when you say yes to a question that said plainly it would clear this chat, such as trackside's offer.

Any suggestion of it says that it clears the chat. A request to start work "in a fresh chat" clears nothing.

**`/trackside:whole`** keeps a chat as it is, such as one you want to keep for an audit: no more offers and no judge. `/trackside:whole off` undoes it. It also says where the chat's transcript is and how long Claude Code keeps it:
- terminal transcripts: until 30 days after their last use, by default;
- desktop app transcripts: at any age, unless your user settings set `desktopSessionCleanupPeriodDays` above 0. Then they're kept for the larger of that and `cleanupPeriodDays`.

**The judge.** Anthropic's docs say accuracy and recall degrade as a context grows, but nobody publishes by how much for current models at a given size, so trackside checks rather than assumes.
- **When it runs:** once a chat passes 300K tokens (`TRACKSIDE_JUDGE_TOKENS`), and again every 200K more (`TRACKSIDE_JUDGE_STEP`), until the chat compacts or is offered a fresh start.
- **What it does:** a cheaper model (Haiku) compares the chat's last 20 messages, without tool output, with the track's `FEATURE.md`, `CONTEXT.md`, `LESSONS.md` and `STATE.md` and the feature's `DECISIONS.md`. Each file is cut at 40 KB. Because it reads the decisions, it also catches an option the decisions rejected coming back.
- **What it costs:** it runs in the background after a reply ends, as its own Claude Code process with no tools, MCP tools included, so the chat spends nothing on it. Each run is about 5K tokens on the tracks it was tried on, at most about 20K, and takes a few seconds.
- **What counts as a finding:** only one whose quotes appear word for word in the chat's replies and in the file it names.

Your next message brings what it found, shown to you as a warning as well as to the agent:
- where a reply of the agent's was wrong, the agent says so;
- where the track looks out of date, it says what it would change and asks before editing it.

Each run logs its counts, never the chat's words, to `.state/judge-log`.

## Source docs and decisions

The source docs stay the source of truth. In a feature with source docs, the agent reads the exact text with `/trackside:lookup` before it states, decides or changes anything they cover, instead of trusting what the state says about them. It cites what it uses by ID (such as AD-28) or heading.

**What `/trackside:lookup` prints:** the matching sections and decision rows with their lines.
- When there are several matches, it first lists where each one is (up to 50), so a cut never hides where to read the rest.
- Heading words match in any order.
- It replaced a `doc-expert` subagent in 0.19.0: on the same questions, the main chat answered as well, at the same cost, from the text itself rather than a summary.

**Digest.** `/trackside:digest <feature>` builds a 1–2 page digest of the feature's source docs, in a separate context. The agent suggests it when a feature has source docs but no digest.

**Change tracking.** Each save records a checksum of every section of the docs, and of every ID they define (in a table's first column or in a heading). The next chat is told which sections and IDs changed since, starting with the ones its state cites. The feature's `DECISIONS.md` counts as a source doc. A save indexes only the docs that changed: about a second for a 580 KB doc.

## Checks and reviews

**The quick check.** After every save, at every chat start and right after a chat is bound, a quick check flags what would trip up a new chat:
- a file the reload would no longer load whole, an empty Next step, unmarked Current lines, and tickets without an acceptance check;
- leftover template placeholders, and files listed to read that don't exist or are large;
- lines copied into both state and notes, and Inbox items older than two weeks;
- IDs the state cites that no source doc mentions anymore, for the kinds of ID the docs define, so ticket keys from elsewhere aren't flagged.

The check is a few text scans of small files, skipped when nothing changed that day, and each issue is raised once. The agent fixes what only moves, de-duplicates or fills in text in the same save. It asks you about the rest once per chat, at a natural pause.

**The deep review.** When a track's notes grow by 10 KB, or two weeks pass with changes, the next chat on that track starts `/trackside:audit` in the background on Sonnet, so the result lands in a chat that's still open. It runs on its own at most once a week per track (`TRACKSIDE_REVIEW_DAYS`); `/trackside:audit` runs one whenever you ask.
- **What it reads:** only the track's files, the feature's decisions, and the memory notes about this feature or track. Never the source docs, code or other repos. It stops after 12 turns.
- **What it proposes:** merges, contradictions to fix, decisions to record, and a short summary to load instead of large notes.
- **What happens next:** lossless edits inside `.trackside/` are applied without asking. The agent brings the rest to you in the chat at a natural pause, never as a pointer to a file. That includes anything touching memory notes or a repo's `CLAUDE.md`. It first confirms what it can from the files, git or GitHub. Then it lists the changes in plain words, to approve all at once or skip by number, and asks a real choice, such as moving notes to another track, as its own question with its recommendation. What you postpone stays in the track's `review-<date>.md`, with an Inbox line pointing to it.
- **Retries:** a review counts as done only once that file is written, so a result lost to `/clear` is retried an hour later.

**The index.** `.trackside/INDEX.md` is regenerated at every chat start, every save and every bind by the start skill, so a new track is listed right away. It lists each track, its current work (or its goal when nothing is in flight), its last update and the command to start it.

## Tracks whose items start clean

For a stream of separate items, such as pull request reviews, only the track's `CONTEXT.md` and a short `LESSONS.md` carry over from one item to the next. A finished item leaves one Done-log line, and its details move to `NOTES.md` or stay in the item's own file, so nothing is deleted.

**Lessons:**
- a lesson you stated, or a correction you made, goes into `LESSONS.md` without a question;
- one the agent noticed goes in as a candidate, and becomes a lesson the second time it comes up;
- lessons nobody has confirmed in 90 days are flagged.

**When it's set up.** The agent proposes this kind of track only when it creates a track, as part of the proposal you confirm. The list, the index, `/trackside:current` and the reply after binding all show it. The deep review flags a track whose kind doesn't fit its work. Other tracks, such as features, research or docs, build on their history.

## Pull requests and repo lessons

**Finishing a ticket.** `/trackside:done` verifies the ticket's acceptance check and updates the feature's docs. A failed check stops it. After your approval, it commits and marks the ticket done.

**Pull requests.** A Done-log line names its pull request as `<repo>#<number>`. `/trackside:next` checks those with `gh`, which it only reads from, and its script marks the ones that merged or closed, so a new chat knows what shipped.

**Repo lessons.** When you finish a ticket or close a track, the agent offers to move lessons about a repo's own code or tooling into that repo's `CLAUDE.md`, or the file your project keeps for that repo's commands and gotchas. That means anything that would help any chat in that repo, such as a command, a build or test quirk, or a convention. The move is part of the approval you already give, with no extra question. The deep review flags such lessons still sitting in a track.

## Closing and cleanup

**`/trackside:close`** hands off what's still open, then moves the track or feature into `.trackside/_archive/` and unbinds its chats. The track's own files are never deleted.

**`/trackside:rename`** renames a track or a feature. Every reference to it inside `.trackside/` is updated, and its chats stay bound. If you ask in words rather than typing the command, the agent first confirms in one line, naming the files outside `.trackside/` it would change: the project's `CLAUDE.md` files and its saved notes.

**Idle and old files.** Tracks untouched for 14 days are flagged as idle (`TRACKSIDE_IDLE_DAYS`), with `/trackside:close` offered next to them. Runtime files of old sessions are cleared after 30 days (`TRACKSIDE_STATE_DAYS`). Git stamps, deep-review records, the tracks remembered for chats you named, chats kept whole, and the size at which each model compacts are kept.

## Worktree sessions

Freshness checks the worktree the session works in. In a `--worktree` or `EnterWorktree` session, Claude Code blocks edits to the main checkout. So if `.trackside/` is inside the repo the worktree came from, the chat can read its track but can't save it. trackside doesn't ask it to, and the agent says so in its first reply. Keep `.trackside/` in a folder above your repos, or work on the track from a session in the main checkout.

## The .trackside folder

The trackside folder is always `.trackside/` in the project root. A chat that moves to another folder after it starts keeps the project root it started in. When that root has no `.trackside/`, trackside uses the nearest one at or above the folder the chat works in.

**Stamps and freshness.** The git stamps describe this machine's checkouts, so they live in `.state/` and never travel with the state. Freshness leaves `.trackside/` out when it checks a repo, so the state's own files never count as code changes.

**Setup choices.** When it creates `.trackside/`, the agent offers three separate choices, and makes only the ones you name:
- keeping `.trackside/` out of the project's git, through the local exclude file that isn't shared;
- giving `.trackside/` its own history, which trackside then commits to at the end of each turn that changed it;
- an `Edit(/.trackside/**)` allow rule in the project's `.claude/settings.local.json`, which only you read, so saves don't ask for permission each time.

**Permissions.** trackside's skills run their own scripts without asking. Saving `STATE.md` outside a skill, when the reminder asks for it, is a normal file edit, so with default permissions it asks each time unless you allow edits to `.trackside/`.
