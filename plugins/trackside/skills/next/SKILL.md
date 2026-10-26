---
name: next
description: In a chat bound to a track (the user may call a track a workspace), propose the next ticket from the track's STATE.md with a short plan, and wait for approval before writing any code.
allowed-tools: Bash(bash "${CLAUDE_SKILL_DIR}/../../scripts/prs.sh" *)
---
If `${CLAUDE_PROJECT_DIR}` has no `.trackside/` folder, which happens when a chat moves to another folder after it starts, use the nearest folder at or above the current one that has a `.trackside/` wherever this says `${CLAUDE_PROJECT_DIR}`.

Run each command below exactly as written, one per call, apart from that folder when it applies: trackside pre-approves them in that form, so they run without permission prompts.

`cat "${CLAUDE_PROJECT_DIR}/.trackside/.state/track-${CLAUDE_SESSION_ID}" 2>/dev/null` prints the track this chat is bound to, as `<feature>/<track>`. If it prints nothing, say that no track is bound and offer to bind one with the start skill; continue only once it's bound.

1. Read the bound track's STATE.md in `${CLAUDE_PROJECT_DIR}/.trackside/<feature>/<track>/`. Handle the Inbox first: for each item, say which ticket it affects and propose how to fold it in (a new ticket, a change to one, a gotcha or an open question).
2. Check the pull requests the state names as `<repo>#<number>`: `bash "${CLAUDE_SKILL_DIR}/../../scripts/prs.sh" "${CLAUDE_PROJECT_DIR}" "<feature>/<track>"`. It only reads. For each one it reports as merged or closed, add that to the line that names it, for example `api#12 (merged 2026-10-24)`, without mentioning it in your reply, and count a merged one's ticket as shipped.
3. If Current has work in progress, propose continuing it. Otherwise take the first unchecked ticket.
4. If the ticket touches code, check where the code stands first, in each repo the ticket touches: `git status`, `git log --oneline -10`, then that repo's baseline tests. Report uncommitted work, a branch that's behind, or failing tests before anything else.
5. Read only what the ticket needs. For the feature's source docs, use the lookup skill (`/trackside:lookup <ID or heading words>`), which prints the exact text.
6. If FEATURE.md says the feature plans with OpenSpec, draft the plan with its propose step. Otherwise, reply with: the ticket, a plan of at most about 8 steps, the files you expect to touch, the acceptance check you'll run, any open question that blocks it, and any recorded decision or rejected option the plan would go against.
7. Write no code until the user approves. If something is unknown, propose a spike or ask; never guess.
