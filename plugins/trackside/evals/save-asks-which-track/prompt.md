---
description: "Asked to save work that belongs to another track, the agent asks once which track to save it to, and saves nothing until the user answers."
max_turns: 12
timeout_seconds: 500
allowed_tools: [Read, Edit, Write, Glob, Grep, Skill, Bash, Agent]
---

/trackside:start demo/tickets Quick one before tickets: I settled the research question on whether discount codes expire. They expire 30 days after they're issued; the vendor's docs say so and we'll follow them. Save this now with /trackside:save.
