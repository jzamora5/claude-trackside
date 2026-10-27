---
name: done
description: In a chat bound to a track (the user may call a track a workspace), verify the current ticket, update the feature's docs and the track's STATE.md, summarize for review, and commit only after approval.
---
If `${CLAUDE_PROJECT_DIR}` has no `.trackside/` folder, which happens when a chat moves to another folder after it starts, use the nearest folder at or above the current one that has a `.trackside/` wherever this says `${CLAUDE_PROJECT_DIR}`.

Run each command below exactly as written, one per call, apart from that folder when it applies: trackside pre-approves them in that form, so they run without permission prompts.

`cat "${CLAUDE_PROJECT_DIR}/.trackside/.state/track-${CLAUDE_SESSION_ID}" 2>/dev/null` prints the track this chat is bound to, as `<feature>/<track>`. If it prints nothing, say that no track is bound and stop.

1. Run the ticket's acceptance check plus the test and lint commands for each repo it touched. If any of them fails, report it and stop: the ticket isn't done.
2. Summarize for review: what changed per file, how it was verified (command and result), what was left out, and any deviation from the source docs.
3. Keep the feature's documents current: update the source docs, or the tickets they track, that this change makes outdated. If none is affected, add "Docs: no change, because …" to the Done-log line.
4. Check that every decision made during the ticket, deviations and resolved unknowns included, is recorded where FEATURE.md says decisions go, with the options rejected and why; record any that aren't. If one affects another track, add a line to that track's Inbox: date · from · what changed · affects.
5. Ask for approval to commit, and wait. If this ticket left lessons that are about a repo's own code or tooling and would help any chat in that repo, list each one in the same request, not only this track (a command, a build or test quirk, a convention), with the file it would move to: that repo's `CLAUDE.md`, or the file the project's `CLAUDE.md` says holds that repo's commands and gotchas. It's one question: approving the commit approves those moves too, unless the user strikes one. When there are none, don't mention them. If the user wants changes instead, make them and start again from step 1. If the ticket changed no files in a repo, such as a review, there's nothing to commit: go on to the STATE.md update in step 6.
6. Only after approval, commit in each repo in its own style (check its `git log`), with the approved lessons moved into that repo's file in the same commit; a file outside the repo, such as a project rules file, is edited without a commit. Then update the track's STATE.md in `${CLAUDE_PROJECT_DIR}/.trackside/<feature>/<track>/`: check off the ticket, add a Done-log line (date · ticket · commit hashes · how verified · its pull request as `<repo>#<number>` once there is one), clear Current, and add Dead ends and the Gotchas that didn't move to a repo's file; on a track whose `CONTEXT.md` says each item starts clean, finish the item the way its `LESSONS.md` says instead. Until then, the ticket stays open in STATE.md.
7. Pushing and opening a pull request need a separate go-ahead. When a pull request is opened, add it to the ticket's Done-log line as `<repo>#<number>`, with `<repo>` as FEATURE.md's Repos line names it, so a later chat can check whether it merged. If the feature plans with OpenSpec, archive the change once it's merged.
8. If trackside's check listed issues for this track in this chat, fix now the ones that only move or de-duplicate text or fill in what's missing, and list the others for the user in your reply. If it listed none, skip this.
9. Don't commit the trackside folder: when it has its own git history, trackside commits it at the end of the turn.
10. End with: "Type /clear, then say next."
