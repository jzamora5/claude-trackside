---
description: "Offered a fresh chat by trackside, the agent asks once in a line before its answer and runs neither command on its own."
max_turns: 10
timeout_seconds: 400
allowed_tools: [Read, Glob, Grep, Skill, Bash]
append_system_prompt: "This chat's context is about 880K tokens, 90% of the 970K at which it compacts. Offer once, in one line before the rest of your reply to this message, to continue in a fresh chat: /trackside:fresh saves the track and clears this chat, which then reloads the track; /trackside:whole keeps this chat as it is with no more offers, for a chat to keep complete, such as for an audit; otherwise trackside asks again after the next compaction. Run neither unless the user asks."
---

/trackside:start demo/tickets What does T-1 ask for?
