<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="assets/logo-dark.svg">
    <img alt="trackside: your agent's work, kept on track across chats" src="assets/logo-light.svg" width="600">
  </picture>
</p>

A Claude Code plugin that keeps an AI coding agent's working state current across chats, organized by feature.

Long agent chats lose precision as they fill up and get compacted, so you start fresh ones. Each new chat then needs a briefing: what's half-done, on which branch, what was decided and ruled out, what's waiting on someone, and what comes next. trackside keeps that briefing written as the agent works, in plain Markdown in your project, and reloads it in every new chat.

## Quick start

Requires bash, `jq` and `git`.

```bash
claude plugin marketplace add jzamora5/claude-trackside
```

```bash
claude plugin install trackside@claude-trackside
```

1. **Start a track.** In your project, type `/trackside:start` and say what you're working on. The agent proposes a feature and a track, and creates them once you confirm.
2. **Work as usual.** The agent keeps the track's state current as it works. `/clear`, a resume or a compaction reloads it on its own, and later chats bind to the right track when you start work.
3. **When a chat gets long,** take the offer to clear it and continue: `/trackside:fresh` saves the track, clears the chat, and the cleared chat picks up where it left off.

To use it in one project only, add this to that project's `.claude/settings.json` instead of installing it globally:

```json
{
  "extraKnownMarketplaces": {
    "claude-trackside": { "source": { "source": "github", "repo": "jzamora5/claude-trackside" } }
  },
  "enabledPlugins": { "trackside@claude-trackside": true }
}
```

## What it does

- **Saves on its own.** When a chat edits files or does research, a hook asks it to update the state before it replies, at most every 15 minutes, so nothing depends on anyone remembering. [Details](docs/how-it-works.md#saving-what-the-gate-covers)
- **Organizes work by feature.** Several chats can work on one feature at once, as tracks for tickets, research or reviews, and pass decisions to each other. [Details](docs/how-it-works.md#binding-a-chat-to-a-track)
- **Checks the state against reality.** Each save stamps the repos, so the next chat sees new commits, branch changes and uncommitted files before it trusts the state. [Details](docs/how-it-works.md#reloading)
- **Keeps your docs the source of truth.** The agent reads the exact text of your RFC or spec with `/trackside:lookup` instead of trusting a summary, and is told which sections changed. [Details](docs/how-it-works.md#source-docs-and-decisions)
- **Looks after long chats.** It offers to clear a chat near its limit and continue the track, and a background judge checks long chats against the track. [Details](docs/how-it-works.md#long-chats)
- **Stays tidy.** Quick checks after each save and a periodic deep review catch gaps a new chat would hit. [Details](docs/how-it-works.md#checks-and-reviews)

You stay in control. trackside never starts work on its own, and every ticket and every code commit waits for your approval. The hooks make no network calls of their own; the one model call is the judge, which runs Haiku through your own `claude` command.

## Commands

You only need `/trackside:start`, or just say what you want to work on. The agent brings up the others when they're due.

| Command | What it does |
| --- | --- |
| `/trackside:start <feature>/<track>` | Binds the chat to a track, with your request after it. Without a name, lists the tracks or proposes a new one. `off` unbinds the chat |
| `/trackside:current` | Shows which track this chat is on, its current work and next step |
| `/trackside:list` | Shows every track with its current work, last update and start command |
| `/trackside:next` | Marks merged pull requests, then proposes the next ticket with a plan and waits for your approval |
| `/trackside:done` | Verifies the ticket, updates the docs, and after your approval commits and marks it done |
| `/trackside:save` | Saves the state for the next chat, then checks it the way a new chat would read it |
| `/trackside:fresh` | Saves the track, then clears this chat, which reloads the track |
| `/trackside:whole` | Keeps this chat as it is: no offers to clear it, no judge. `off` undoes it |
| `/trackside:lookup <ID or heading words>` | Prints the exact sections and decisions of the source docs that match |
| `/trackside:audit <feature>/<track>` | Runs the deep review of a track now |
| `/trackside:rename <feature>[/<track>] <new name>` | Renames a track or feature, keeping its chats bound |
| `/trackside:close <feature>[/<track>]` | Hands off what's open, then archives the track or feature |
| `/trackside:digest <feature>` | Builds a 1–2 page digest of the feature's source docs |

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

## Settings

These environment variables change the defaults:

| Variable | Default | What it sets |
| --- | --- | --- |
| `TRACKSIDE_SAVE_MINUTES` | 15 | Minutes between requests to update STATE.md; 0 asks after every working turn |
| `COMPACT_LIMIT` | 2 | Compactions after which a chat is offered a clear, whatever its size |
| `TRACKSIDE_OFFER_PERCENT` | 90 | Share of the size at which the chat's model compacts that brings the offer |
| `TRACKSIDE_JUDGE_TOKENS` | 300000 | Context size at which the judge first checks a chat; 0 turns the judge off |
| `TRACKSIDE_JUDGE_STEP` | 200000 | More context before the judge checks again; 0 checks once per compaction |
| `TRACKSIDE_JUDGE_MODEL` | haiku | Model the judge runs on |
| `TRACKSIDE_IDLE_DAYS` | 14 | Days without a state update before a track is flagged as idle |
| `TRACKSIDE_STATE_DAYS` | 30 | Days before runtime files of old sessions are cleared |

Saving STATE.md outside a skill is a normal file edit, so with default permissions it asks each time. To allow edits to `.trackside/` in a project, add this to its `.claude/settings.json`, or accept the agent's offer when it creates the folder:

```json
{
  "permissions": { "allow": ["Edit(/.trackside/**)"] }
}
```

## How it compares

- **Spec-driven tools** such as OpenSpec or Spec Kit agree on *what to build* before code is written. trackside covers the *work in progress*: where each line of work stands right now. The two fit together; a feature can plan its tickets with OpenSpec.
- **Session handoff tools** write a summary when you ask for one, for one session or one repo. trackside saves while the chat works, organizes chats by feature, and checks the state against the repos before a new chat trusts it.

## Status

Version 0.24.0, early ([changelog](CHANGELOG.md)). Until 0.15.0 the plugin was called keep; two other Claude Code plugins use that name, and Claude Code runs the hooks of only one enabled plugin per name.

- **Hooks and scripts:** tested with simulated hook inputs (`bash tests/hooks.test.sh`) on macOS's bash 3.2.
- **Agent behavior:** 30 behaviors are checked in real headless sessions with `claude plugin eval` (`bash tests/evals.sh`, cases in `plugins/trackside/evals/`).
- **Where each rule lives:** `tests/rule-homes.tsv` lists each rule stated in more than one file, and the tests fail when a rule turns up anywhere else.
- **Manual checks:** `tests/live-checklist.md` lists what still needs a person, such as several messages in a row, `/clear`, resume, compaction and the app's permission prompts.

[How trackside works](docs/how-it-works.md) has the details.

## Credits

Ideas borrowed from other handoff tools:
- verified versus assumed state, and dead ends: [blader/baton](https://github.com/blader/baton);
- a commit stamp, and a next step that names a file: [Dereknalox123/claude-code-baton](https://github.com/Dereknalox123/claude-code-baton);
- binding a session to a named workstream: [mattpollak/relay](https://github.com/mattpollak/relay);
- naming what a reload left out: [nickthelegend/loom](https://github.com/nickthelegend/loom);
- the decision format: [EdytaKucharska/keel](https://github.com/EdytaKucharska/keel);
- writing rules for checkpoints: [arcAman07/claude-cairn](https://github.com/arcAman07/claude-cairn);
- loading whole sections under the cap: [eugeniughelbur/obsidian-second-brain](https://github.com/eugeniughelbur/obsidian-second-brain);
- moving lasting repo lessons into the repo's own `CLAUDE.md`, a bar for what gets written down, a checklist of where each rule lives, and pull request state: [lackeyjb/claude-keep](https://github.com/lackeyjb/claude-keep).

Other sources:
- The handoff check, a reader with no memory of the chat checking what it left behind, follows the Goldfish reviewers of [google/elephant-goldfish-model](https://github.com/google/elephant-goldfish-model).
- Weighing each subagent against a skill in the main chat, and keeping it only when an eval says so, follows Anthropic's [When to fold subagents into your main agent loop](https://claude.com/resources/articles/building-agents-when-to-fold-subagents-into-your-main-agent-loop).
- Offering to clear a chat before quality drops, and checking a long chat against its notes rather than assuming it drifted, follows Chroma's [Context Rot](https://research.trychroma.com/context-rot) report and Anthropic's [context windows](https://platform.claude.com/docs/en/build-with-claude/context-windows) docs.
- The approach follows Anthropic's [Effective harnesses for long-running agents](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents).

## License

MIT. See [LICENSE](LICENSE).
