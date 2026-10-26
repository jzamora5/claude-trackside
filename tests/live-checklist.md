# Live checklist

Manual checks in a real session, after the hook tests (`bash tests/hooks.test.sh`) pass. Run them in the Claude desktop app first, then in VS Code.

`bash tests/evals.sh` runs part of this list in real headless sessions with `claude plugin eval`: checks 1, 2, 3, 5, the proposal halves of 19 and 20, a typed `/trackside:start` with a request (the chat is renamed, the request answered), the state after an edit, `/trackside:done` stopping on a failed check, questions that say "workspace" instead of "track", a design doc that changed since the last save, a question the docs answer, a review track proposed with each item starting clean, a finished review that records its lesson without a question, a reply that ends with its question after work, with nothing about saving, and a finished ticket that offers to move a repo lesson into that repo in the same approval. Each case is one message, so the checks that need several messages, a `/clear`, a resume, a compaction or the app's own permission prompts stay here.

## Setup

Use a sandbox project with two small git repos (`api/`, `web/`), a design doc (`docs/spec.md`) and a feature in `.trackside/demo/` with two tracks, `tickets` and `research`. Install trackside for that project only, from a local clone:

```bash
claude plugin marketplace add /path/to/claude-trackside --scope project
```

```bash
claude plugin install trackside@claude-trackside --scope project
```

A plugin installed from a local folder is read from that folder, so changes take effect at the next session start or after `/reload-plugins`. Open a new session in the sandbox folder and accept the folder trust prompt if it appears.

## Checks

| # | Do | Expect |
| --- | --- | --- |
| 1 | In a new chat, ask "Which tracks exist?" | It answers from the start-of-chat context without reading files: `demo/research` and `demo/tickets`, and doesn't offer to bind the chat |
| 2 | In a new chat, say "Let's continue the discount tickets" | It binds the chat to `demo/tickets` without asking, says so in one line with `/trackside:start off` to undo it, and carries on with the request; the chat is renamed `demo/tickets` at your next message |
| 3 | In a new chat, say "Let's continue with the discount feature" | It asks which of `demo/tickets` and `demo/research`; nothing is bound until you answer |
| 4 | In a new chat, `/trackside:start demo/tickets` | The chat is renamed `demo/tickets`, and it replies with three lines: state, Inbox and repo changes, next step |
| 5 | `/trackside:next` | It proposes T-1 with a plan, files and acceptance check, and waits; no code yet |
| 6 | Approve T-1 | It edits `api/app.js` and updates Current and Next step in `STATE.md` before its reply, with nothing about it after the reply; `.trackside/.state/stamp-demo@tickets` appears |
| 7 | Right away, ask for another small edit | No reminder this time: `STATE.md` was updated less than 15 minutes ago |
| 8 | Commit in `api/` (`git -C api commit -am "T-1"`), then `/clear` and ask "What changed since the state was saved?" | It reports `api (main): 1 new commit(s)` with the subject |
| 9 | 15 minutes after the last save, ask it to look something up on the web | It updates `STATE.md` before its reply, or, if it didn't, at the start of your next message, before that answer |
| 10 | `/compact`, then `/compact` again | After the second one it asks for `/trackside:save` and a fresh chat |
| 11 | `/trackside:save` | `STATE.md` is updated with `[verified]`/`[assumed]` marks and a concrete next step, and `.trackside` gets a commit |
| 12 | `/trackside:digest demo` | `.trackside/demo/DIGEST.md` exists and starts with "Built from docs/spec.md" |
| 13 | Ask "Can codes stack?" | It looks it up with `/trackside:lookup`, and cites D-001 and the rejected option (stacking) |
| 14 | In a second chat, `/trackside:start demo/research settle Q-1` | It binds `demo/research` and works on Q-1 without waiting; a new entry in `DECISIONS.md` with rejected options, and an Inbox line in `demo/tickets` if it affects tickets |
| 15 | Reopen the first chat later (resume) | It's still bound to `demo/tickets` |
| 16 | Fork a bound chat | Note which happens: the fork is told no track is bound, or it keeps the chat title and is rebound to the same track, which leaves two chats on one track |
| 17 | In a new chat, let it bind a track on its own, then `/clear` right away with no other message | Note whether the new chat is still bound: the chat is renamed only at the next message, so it may not be |
| 18 | `/trackside:list` | It shows `.trackside/INDEX.md`: each track, its current work, its last update and its start command |
| 19 | Say "I want to start on checkout emails" | It proposes a new track in one message: its name and goal and, if it's a new feature, the repos it found (`api`, `web`), `DECISIONS.md` and no planning. There's no git offer, because the sandbox's `.trackside/` already exists. After your OK it creates the track, with no placeholder lines left in its files, and binds the chat to it, with no second `/trackside:start`; INDEX.md lists it |
| 20 | Say "We're done with the research track, close it" | It lists what's still open and asks where each item goes, then moves the track into `.trackside/_archive/`, unbinds its chats and commits `.trackside` |
| 21 | In a chat that isn't bound, after some discussion, say "Save this to trackside" | It binds the track that clearly fits (or asks which one, or proposes a new one, when it's unclear), then saves what the chat knows into that track's `STATE.md` |
| 22 | In a chat that isn't bound, say "I'm done with this ticket" | It says no track is bound and doesn't run tests or offer a commit |
| 23 | In a chat bound to `demo/tickets`, edit a file, then say "switch to the research track" | It saves the edit to `demo/tickets` first, then binds `demo/research` |
| 24 | `/trackside:start off` | The chat is unbound, renamed `demo/research (unbound)`, and isn't rebound after `/clear`, even when your next message starts work that fits a track |
| 25 | In default permission mode, `/trackside:start demo/tickets` | No permission prompt for trackside's own scripts |
| 26 | In a new chat, `/rename my-review`, then `/trackside:start demo/tickets`, then `/clear` and ask "which workspace is this?" | The chat keeps the name `my-review` throughout, and after `/clear` it's still on `demo/tickets` |
| 27 | In a chat, `/trackside:start demo/tickets` on a track with an empty Next step | The agent fills in the Next step at its first save, or mentions it once, after answering |
| 28 | `/trackside:audit demo/tickets` in the app | A short list comes back in the chat, each item marked lossless or needing you. The lossless ones are applied; the rest are saved in `review-<date>.md` with an Inbox line, and nothing else changes until you agree |
| 29 | Start a chat on a track whose notes grew by 10 KB | It starts the deep review in the background and keeps working; when the list comes back, lossless items are applied, the rest land in `review-<date>.md` with an Inbox line, and a new chat on the track doesn't start another review |
| 30 | In a chat bound to `demo/tickets`, save, then edit the Rules section of `docs/spec.md` and `/clear` | The reload names `docs/spec.md` and its Rules section as changed, and the agent reads it (with `/trackside:lookup`) before relying on what `STATE.md` says |
| 31 | Say "I want a track for reviewing pull requests" | The proposal says each item starts clean; after your OK, the track's `CONTEXT.md` has `**Each item starts clean:** yes` and it has a `LESSONS.md`; `/trackside:list` and `/trackside:current` show it |
| 32 | On that track, finish a review and state a lesson in the same message | The lesson lands in `LESSONS.md` with no question, the review's details leave `STATE.md`, and one Done-log line stays |
| 33 | In a bound chat, ask for a small edit and to end by asking you something | The state is updated before the reply, the reply ends with the question, and nothing about saving or trackside shows up after it |
| 34 | In a track whose Done log names a pull request as `<repo>#<number>` that has since merged, `/trackside:next` | The line gets "(merged <date>)" without a word about it in the reply, and the proposal treats that ticket as shipped |
| 35 | In the desktop app, a chat bound to `demo/tickets`: make an edit, then `/trackside:fresh` | It saves, the app asks you to approve clearing the chat, and after the reply the chat is empty, still named `demo/tickets`; your next message continues from the Next step |
| 36 | The same in the terminal | It saves and tells you to type `/clear`; after `/clear` the chat is on `demo/tickets` again |
| 37 | In a bound chat, `/trackside:whole`, then `/trackside:whole off` | It says the chat stays whole, where its transcript is and how long Claude Code keeps it, and then that the offers come back. No permission prompt for either |
| 38 | In a bound chat, `export TRACKSIDE_JUDGE_TOKENS=1` before starting Claude Code, then plant a reply that contradicts `STATE.md` and end the turn; send another message | Within a few seconds `.state/judge-log` has a line, and the next message brings the disagreement and, if the reply was wrong, the offer of a fresh chat. Repeat in the desktop app, where the judge must find the `claude` command too |
| 39 | Two chats on `demo/tickets`: in the first, make an edit and end the turn without saving; then open the second | The second is told another open chat has unsaved work and leaves it alone; after you close or `/clear` the first, a new chat on the track is told the last one left off and fills the gap |
| 40 | In a bound chat, ask the agent to `cat` STATE.md right after another chat saved the track | The first chat is still asked to save before its next answer |

Write down anything that differs, with the exact output.
