---
name: whole
description: Keep this chat whole, such as for an audit: trackside stops offering to continue it in a fresh chat and stops checking it. Run it when the user types /trackside:whole or asks to keep this chat whole or as it is; /trackside:whole off undoes it.
allowed-tools: Bash(bash "${CLAUDE_SKILL_DIR}/../../scripts/whole.sh" *)
---
If `${CLAUDE_PROJECT_DIR}` has no `.trackside/` folder, which happens when a chat moves to another folder after it starts, use the nearest folder at or above the current one that has a `.trackside/` wherever this says `${CLAUDE_PROJECT_DIR}`.

Run each command below exactly as written, one per call, apart from that folder when it applies: trackside pre-approves them in that form, so they run without permission prompts.

Arguments: $ARGUMENTS

Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/whole.sh" "${CLAUDE_PROJECT_DIR}" "${CLAUDE_SESSION_ID}" on`, with `off` in place of `on` when the arguments or the user ask to undo it, and reply with what it prints.
