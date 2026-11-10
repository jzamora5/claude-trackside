---
name: rename
description: Rename a track (the user may call a track a workspace) or a whole feature, keeping its chats bound. Run it when the user types /trackside:rename <feature>/<track> <new name> (or <feature> <new name>) or asks in words to rename one; never on your own.
allowed-tools: Bash(bash "${CLAUDE_SKILL_DIR}/../../scripts/rename.sh" *) Bash(git -C "${CLAUDE_PROJECT_DIR}/.trackside" add *) Bash(git -C "${CLAUDE_PROJECT_DIR}/.trackside" commit *)
---
If `${CLAUDE_PROJECT_DIR}` has no `.trackside/` folder, which happens when a chat moves to another folder after it starts, use the nearest folder at or above the current one that has a `.trackside/` wherever this says `${CLAUDE_PROJECT_DIR}`.

Run each command below exactly as written, one per call, apart from that folder when it applies: trackside pre-approves them in that form, so they run without permission prompts.

Arguments: $ARGUMENTS

1. Work out what to rename and the new name. "This track" means the one this chat is bound to: `cat "${CLAUDE_PROJECT_DIR}/.trackside/.state/track-${CLAUDE_SESSION_ID}" 2>/dev/null`. A track's new name stays in its feature. Ask only if either is unclear; ask nothing else. If the user asked in words rather than typing /trackside:rename, first confirm in one line, naming the old and new names and the files outside `.trackside/` that step 3 would change, and wait for their yes.
2. Rename it: `bash "${CLAUDE_SKILL_DIR}/../../scripts/rename.sh" "${CLAUDE_PROJECT_DIR}" "<feature>[/<track>]" "<new name>"`. It moves the folder, updates every reference to it inside `.trackside/`, keeps every chat bound to it (chats that took the track's name from trackside's offer, numbered or not, get the new name at their next message, with a notice; every other chat keeps its name), moves its git stamps and review record, and refreshes the index.
3. Update mentions of the old name outside `.trackside/` yourself, with no further question (for a track, its full name `<feature>/<track>` and its `.trackside/` path; for a feature, its tracks' full names and its `.trackside/<feature>/` path): the project's `CLAUDE.md` files and the user's saved memory notes for this project (the `memory/` folder under `~/.claude/projects/` whose name is the project folder's path with every `/` turned into `-`). Don't write anything about the rename in `STATE.md`.
4. If the trackside folder is its own git repo, commit it: `git -C "${CLAUDE_PROJECT_DIR}/.trackside" add -A`, then `git -C "${CLAUDE_PROJECT_DIR}/.trackside" commit -m "Rename <old> to <new>"`.
5. Reply in at most three lines: the old and new names, how many chats stayed bound, the new start command (`/trackside:start <feature>/<track>`), and the files outside `.trackside/` you updated.
