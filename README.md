# claude-trackside

Keep an AI coding agent's working state current across chats, organized by feature.

## The problem

Long agent chats lose precision as they fill up and get compacted, so you start fresh ones. Each new chat then needs a briefing: what's half-done, on which branch, what's failing, what was decided and what was ruled out, what's waiting on someone else, and what comes next. Writing that handoff by hand is tedious, and it's written at the end, from the same context that was losing precision.

It's harder when you own a whole feature rather than one ticket. The build, research for later phases and reviews all rest on the same source docs, and the plan keeps changing as vendors, stakeholders and the implementation turn up new facts. That work runs across many chats, side by side and for weeks.

## How trackside is different

**From spec-driven tools** such as OpenSpec or Spec Kit. They solve another layer: agreeing on *what to build* before code is written, and tracking which tasks are done. trackside covers the *work in progress*: where each line of work stands right now, kept current while you work. The two fit together, and a feature can plan its tickets with OpenSpec.

**From session handoff tools**, which write a summary when you ask for one, at the end of a session or just before a compaction, for one session or one repo:

- **It's enforced, not remembered, and it stays out of your way.** When a chat edits files or does research, a hook asks it to update the state before it replies, at most once every 15 minutes. A turn that still ends without saving gets the request at the start of your next message, before that answer, so nothing ever lands after a reply you're reading. The update happens quietly: replies don't report saves, trims or trackside commits, and anything trackside needs from you comes before the reply's last question, never after it. Nothing depends on the agent remembering, or on you running a command before you stop. [What the gate covers](#what-the-gate-covers) has the details.
- **It's organized by feature, with tracks.** Several chats can work on one feature at once (tickets, a research topic, reviews), share its source docs, and pass decisions to each other through an Inbox.
- **It's checked against reality.** Each save stamps the feature's repos with their commits, so the next chat sees what changed since (new commits, a different branch, uncommitted files) before it trusts the state.

Everything is plain Markdown in your project, and the hooks make no network or model calls. You stay in control: trackside never starts work on its own, and every ticket and every code commit waits for your approval. If you give `.trackside/` its own history, keep commits the state there as it saves.

## How it works

- **Files.** A feature lives in `.trackside/<feature>/` with a `FEATURE.md` that points to its source docs (an RFC, PRD, design doc or spec) instead of copying them. Each track (call it a workspace if you like; the agent understands both words) has a `CONTEXT.md` (what it's for), a `STATE.md` (where it stands) and a `NOTES.md` (reference).
- **Start.** In a new chat, say what you want to work on. When a message starts work (not a quick question) and one track clearly fits it, the agent binds the chat to that track and carries on with your request, saying so in one line; `/trackside:start off` undoes it, and a chat you unbound stays unbound, `/clear` included. When more than one track could fit, it asks which; when none does, it offers to create one, and creates nothing until you agree. A ticket still waits for your approval of its plan. You can also type `/trackside:start <feature>/<track>`, always with the full name, and your request after it: `/trackside:start legal/terms check the new vendor doc`. A chat you haven't named is named after its track; a chat you named keeps its name, and trackside remembers which track that name is on. Either way, `/clear`, a resume or a compaction then reloads the feature and the track by themselves. A name you give a chat partway through is picked up at its next start or `/clear`, and two chats with the same name share one remembered track, the most recent.
- **Opt in mid-chat.** trackside does nothing in a chat until it's bound, so an ongoing chat can opt in at any point: ask the agent to work on a track or to save the chat to trackside, or type `/trackside:start`. If no track fits, the agent proposes a new track, in an existing feature when one fits. When you bind a chat that already has work in it, the agent offers `/trackside:save` so what the chat already knows reaches the track.
- **Stays under the limit, with no fixed sizes.** Claude Code caps each hook's output at 10,000 characters, so the reload comes in two outputs: `STATE.md` in one of its own, with `LESSONS.md` after it on a track whose items start clean, and `FEATURE.md` and `CONTEXT.md` in the other, with trackside's instructions. Each always includes `STATE.md`'s Inbox, Current and Next step, adds whole sections while they fit, and names the ones it left out. The files have no byte limits: the check flags one only when the reload would leave part of it out.
- **Decisions.** Each decision is recorded when it's made, with the options it rejected and why, so a later chat doesn't propose them again. The save reminder asks for any decision not recorded yet.
- **Only what a new chat needs.** A save writes down what a new chat couldn't get from the code, git, the docs or a command, and points to file contents, diffs and test output instead of copying them.
- **Repo lessons go to the repo.** When you finish a ticket or close a track, a lesson about a repo's own code or tooling that would help any chat in that repo, such as a command, a build or test quirk or a convention, is offered for that repo's `CLAUDE.md`, or the file your project keeps for that repo's commands and gotchas. It's part of the approval you already give; there's no extra question. The periodic review flags such lessons still sitting in a track.
- **Pull requests.** A Done-log line names its pull request as `<repo>#<number>`. `/trackside:next` checks those with `gh`, read-only, and marks the ones that merged or closed, so a new chat knows what shipped.
- **Some tracks start each item clean.** For a stream of separate items, such as pull request reviews, only the track's `CONTEXT.md` and a short `LESSONS.md` carry over from one item to the next. A finished item leaves one Done-log line, and its details move to `NOTES.md` or stay in the item's own file, so nothing is deleted. A lesson you stated, or a correction you made, goes into `LESSONS.md` without a question. One the agent noticed goes in as a candidate, and becomes a lesson the second time it comes up. Lessons nobody has confirmed in 90 days are flagged. The agent proposes this only when it creates a track, as part of the proposal you confirm. The list, the index, `/trackside:current` and the reply after binding all show it, and the periodic review flags a track whose kind doesn't fit its work. Other tracks, such as features, research or docs, build on their history as before.
- **The source docs stay the source of truth.** In a feature with source docs, the agent asks `doc-expert` before it states, decides or changes anything they cover, instead of trusting what the state says about them, and cites what it uses by ID (such as AD-28) or heading. Each save records a checksum of every section of the docs and of every ID they define (in a table's first column or in a heading), so the next chat is told which sections and IDs changed since, starting with the ones its state cites. The feature's `DECISIONS.md` counts as a source doc. A save indexes only the docs that changed: about a second for a 580 KB doc.
- **You always know what exists.** `.trackside/INDEX.md` is regenerated at every chat start and every state save: each track, its current work (or its goal when nothing is in flight), its last update and the command to start it. A new track is proposed in one message, with its name, its goal and, for a new feature, the repos and settings the agent found; nothing is created until you confirm or correct it.
- **Kept tidy on its own.** After every save, at every chat start and right after a chat is bound, a quick check flags what would trip up a new chat:
  - a file the reload would no longer load whole, an empty Next step, unmarked Current lines, and tickets without an acceptance check;
  - leftover template placeholders, and files listed to read that don't exist or are large;
  - lines copied into both state and notes, and Inbox items older than two weeks;
  - IDs the state cites that no source doc mentions anymore, for the kinds of ID the docs define, so ticket keys from elsewhere aren't flagged.

  The check is a few text scans of small files, skipped when nothing changed that day, and each issue is raised once. The agent fixes what only moves, de-duplicates or fills in text in the same save, and asks you about the rest once per chat, at a natural pause.
- **A deep review when a track is due.** When a track's notes grow by 10 KB, or two weeks pass with changes, the next chat on that track starts `/trackside:audit` in the background on Sonnet, so the result lands in a chat that's still open. It reads the track and your saved memory notes for this project, then proposes merges, contradictions to fix, decisions to record, and a short summary to load instead of large notes. Lossless edits are applied without asking; the rest waits for you in the track's `review-<date>.md`, with an Inbox line pointing to it. A review counts as done only once that file is written, so a result lost to `/clear` is retried an hour later.
- **Cleanup is one command.** `/trackside:close` hands off what's still open, then moves the track or feature into `.trackside/_archive/` and unbinds its chats; the track's own files are never deleted. Tracks untouched for 14 days are flagged as idle, and runtime files of old sessions are cleared after 30 days.

## What the gate covers

- **Counted:** edits with Edit, Write and NotebookEdit to files in the project folder, including Claude Code worktrees under `.claude/worktrees/`; web fetches and searches; and subagents, except trackside's `doc-expert`, which only reads the feature's own source docs. Edits inside `.trackside/`, to the project's own `.claude/` settings, and to files outside the project folder, such as scratch files and Claude's files in `~/.claude/` (memory, plans), aren't counted.
- **Not counted:** project files changed through shell commands (`sed -i`, code generators, `git checkout`). Run `/trackside:save` after work like that. A shell command that saves the track's own STATE.md does count as a save.
- **How hard it pushes:** at the first counted work once a save is due, the edit hook asks the chat to update Current and Next step in STATE.md and record any new decision before it writes its reply. If the turn still ends without that, trackside doesn't send the chat back after its reply: your next message starts with the request, before its answer. A chat you `/clear` or close instead leaves a note, and the next chat on that track is told the last one ended with work STATE.md doesn't have yet. It asks at most once every 15 minutes after this chat's last save; another chat editing the same STATE.md, for example to add an Inbox line, doesn't reset that clock. A save counts whether it's made with Edit or through the shell, such as `sed` on STATE.md. `TRACKSIDE_SAVE_MINUTES=0` asks after every working turn.
- **Worktree sessions:** freshness checks the worktree the session works in. In a `--worktree` or `EnterWorktree` session, Claude Code blocks edits to the main checkout, so if `.trackside/` is inside the repo the worktree came from, the chat can read its track but can't save it. trackside doesn't ask it to, and the agent says so in its first reply. Keep `.trackside/` in a folder above your repos, or work on the track from a session in the main checkout.

## Commands

You only need `/trackside:start`, or just say what you want to work on. The agent brings up the others when they're due: `/trackside:save` at the compaction limit and when a chat opts in midway, `/trackside:digest` when a feature has source docs but no digest, and `/trackside:close` appears next to idle tracks.

| Command | What it does |
| --- | --- |
| `/trackside:start <feature>/<track>` | Binds the chat to a track, and names the chat after it unless you named the chat yourself; it takes only the full name, and your request can follow it. The agent runs it too, when one track clearly fits the work you start or once you pick one. Without a name, lists the tracks, or proposes a new one and creates it once you confirm. `/trackside:start off` unbinds the chat. A chat with unsaved work on one track saves it before switching to another |
| `/trackside:current` | Shows which track this chat is on, with its current work, next step and start command, or says it isn't bound |
| `/trackside:list` | Shows every track with its current work or goal, its last update and the command to start it |
| `/trackside:next` | Marks the pull requests that merged or closed, then proposes the next ticket with a short plan, and waits for your approval before any code |
| `/trackside:done` | Verifies the ticket and updates the feature's docs; after your approval, which also covers moving repo lessons into the repo, commits and marks the ticket done in the state. A failed check stops it |
| `/trackside:save` | Saves the state for the next chat, before `/clear` or when stopping. In a chat that isn't bound yet, it binds the track that clearly fits, or asks which one when it's unclear |
| `/trackside:rename <feature>[/<track>] <new name>` | Renames a track within its feature, or a whole feature. Every reference to it in `.trackside/` is updated, and the agent updates the project's `CLAUDE.md` files and its saved notes too, without questions. Its chats stay bound, and the ones named after the track get the new name at their next message. The agent runs it too when you ask |
| `/trackside:audit <feature>/<track>` | Runs the deep review of a track now. trackside starts it on its own when a track is due |
| `/trackside:close <feature>[/<track>]` | Hands off what's still open, then archives the track or the whole feature. The agent runs it too when you ask it to close one |
| `/trackside:digest <feature>` | Builds a 1–2 page digest of the feature's source docs in a separate context |

The `doc-expert` subagent answers questions from the source docs, so a chat never has to load them whole.

## Files

```text
.trackside/
  INDEX.md           generated list of tracks, ignored by git
  <feature>/
    FEATURE.md       goal, source docs, where decisions go, repos, rules
    DIGEST.md        optional, built by /trackside:digest
    DECISIONS.md     optional, when decisions aren't recorded in a source doc
    <track>/
      CONTEXT.md     what the track is for, and whether each item starts clean
      LESSONS.md     only when each item starts clean: what carries over between items
      STATE.md       Inbox, Current, Next step, Tickets, Done log, Dead ends, Gotchas, Open questions
      NOTES.md       reference, read on demand
  _archive/          closed tracks and features
  .state/            runtime files and each track's git stamp, ignored by git
```

The trackside folder is always `.trackside/` in the project root. A chat that moves to another folder after it starts keeps the project root it started in; when that has no `.trackside/`, trackside uses the nearest one at or above the folder the chat works in. The git stamps describe this machine's checkouts, so they live in `.state/` and never travel with the state. Freshness leaves `.trackside/` out when it checks a repo, so the state's own files never count as code changes. When it creates `.trackside/`, the agent offers two separate choices: keeping `.trackside/` out of the project's git, through the local exclude file that isn't shared, and giving `.trackside/` its own history, which keep then commits to as it saves. These environment variables change the defaults:

| Variable | Default | What it sets |
| --- | --- | --- |
| `TRACKSIDE_SAVE_MINUTES` | 15 | Minutes between requests to update STATE.md; 0 asks after every working turn |
| `COMPACT_LIMIT` | 2 | Compactions before the agent suggests saving and starting a fresh chat |
| `TRACKSIDE_IDLE_DAYS` | 14 | Days without a state update before a track is flagged as idle |
| `TRACKSIDE_STATE_DAYS` | 30 | Days before runtime files of old sessions are cleared; git stamps, deep-review records and the tracks remembered for chats you named are kept |

## Install

Requires bash, `jq` and `git`.

```bash
claude plugin marketplace add jzamora5/claude-trackside
```

```bash
claude plugin install trackside@claude-trackside
```

To use it in one project only, add this to that project's `.claude/settings.json`:

```json
{
  "extraKnownMarketplaces": {
    "claude-trackside": { "source": { "source": "github", "repo": "jzamora5/claude-trackside" } }
  },
  "enabledPlugins": { "trackside@claude-trackside": true }
}
```

Then type `/trackside:start` in your project and describe what you're working on: the agent proposes the first track. After that, it offers the right track whenever a chat starts work.

trackside's skills run their own scripts without asking. Saving STATE.md outside a skill, when the reminder asks for it, is a normal file edit, so with default permissions it asks each time. To allow edits to `.trackside/` in a project, add this to its `.claude/settings.json`:

```json
{
  "permissions": { "allow": ["Edit(/.trackside/**)"] }
}
```

## Status

Version 0.18.0, early ([changelog](CHANGELOG.md)). Until 0.15.0 the plugin was called keep: two other Claude Code plugins use that name, and Claude Code runs the hooks of only one enabled plugin per name. The hooks and scripts are tested with simulated hook inputs (`bash tests/hooks.test.sh`) on macOS's bash 3.2, and 21 behaviors are checked in real headless sessions with `claude plugin eval` (`bash tests/evals.sh`, cases in `plugins/trackside/evals/`). `tests/rule-homes.tsv` lists each rule stated in more than one file, with its home and why each copy exists, and the tests fail when a rule turns up anywhere else. `tests/live-checklist.md` lists the checks that still need a person: several messages in a row, `/clear`, resume, compaction and the app's permission prompts.

## Credits

Ideas borrowed from other handoff tools: verified versus assumed state and dead ends ([blader/baton](https://github.com/blader/baton)), a commit stamp and a next step that names a file ([Dereknalox123/claude-code-baton](https://github.com/Dereknalox123/claude-code-baton)), binding a session to a named workstream ([mattpollak/relay](https://github.com/mattpollak/relay)), naming what a reload left out ([nickthelegend/loom](https://github.com/nickthelegend/loom)), the decision format ([EdytaKucharska/keel](https://github.com/EdytaKucharska/keel)), writing rules for checkpoints ([arcAman07/claude-cairn](https://github.com/arcAman07/claude-cairn)), loading whole sections under the cap ([eugeniughelbur/obsidian-second-brain](https://github.com/eugeniughelbur/obsidian-second-brain)), and moving lasting repo lessons into the repo's own `CLAUDE.md`, a bar for what gets written down, a checklist of where each rule lives, and pull request state ([lackeyjb/claude-keep](https://github.com/lackeyjb/claude-keep)). The approach follows Anthropic's [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents).

## License

MIT. See [LICENSE](LICENSE).
