---
name: lookup
description: Look up the exact text of the bound feature's source docs (an RFC, PRD, design doc or spec) and its decisions, by an ID such as AD-28 or by words from a heading. Use it before you state, decide or change anything the source docs cover, and whenever the user asks what they say.
allowed-tools: Bash(bash "${CLAUDE_SKILL_DIR}/../../scripts/doc-section.sh" *)
---
If `${CLAUDE_PROJECT_DIR}` has no `.trackside/` folder, which happens when a chat moves to another folder after it starts, use the nearest folder at or above the current one that has a `.trackside/` wherever this says `${CLAUDE_PROJECT_DIR}`.

Run each command below exactly as written, one per call, apart from that folder when it applies: trackside pre-approves them in that form, so they run without permission prompts.

Look up: $ARGUMENTS

1. Run `bash "${CLAUDE_SKILL_DIR}/../../scripts/doc-section.sh" "${CLAUDE_PROJECT_DIR}" "${CLAUDE_SESSION_ID}" "<an ID or a few words from a heading>"`. It prints the matching sections and decision rows word for word, with their paths and lines, then the other lines that mention the ID.
2. Newer decisions override older sections: when the other lines include a later decision on the same point, look that one up too before you answer.
3. If nothing matches, try other words or an ID from the lines it printed, or read the doc at the lines it gave.
4. Cite what you use by its ID or heading.
