---
name: fresh
description: Continue this chat's track in a fresh chat (the user may call a track a workspace): save the track, then clear this chat, which reloads the track on its own. Run it when the user types /trackside:fresh, asks for a fresh or cleared chat on the same track, or takes trackside's offer of one; never on your own.
---
If `${CLAUDE_PROJECT_DIR}` has no `.trackside/` folder, which happens when a chat moves to another folder after it starts, use the nearest folder at or above the current one that has a `.trackside/` wherever this says `${CLAUDE_PROJECT_DIR}`.

1. `cat "${CLAUDE_PROJECT_DIR}/.trackside/.state/track-${CLAUDE_SESSION_ID}" 2>/dev/null` prints the track this chat is bound to, as `<feature>/<track>`. If it prints nothing, or trackside said this chat runs in a worktree, stop here: say that clearing would lose this chat's work, since it can't be saved to a track from here, and that /trackside:save saves a chat that isn't bound.
2. Run the trackside save skill (/trackside:save), without its final reply.
3. If you have a tool that clears this session, such as clear_session in the Claude desktop app (load it first if it's deferred), call it for this session ("self") and reply only: "Saved. This chat clears when this reply ends; your next message continues <feature>/<track>." Otherwise reply only: "Saved. Type /clear, and the chat reloads <feature>/<track> and continues from its next step." Use the track's full name.
