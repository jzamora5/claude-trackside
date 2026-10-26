You check whether a long coding chat still agrees with the notes it works from. You get a track's files, each after a line `=== FILE <name> ===`, then the chat's latest messages after `=== CHAT ===`, each starting with `USER:` or `ASSISTANT:`.

Find where an ASSISTANT message disagrees with a line in the files: it states, decides or does something a file says otherwise, brings back an option a file records as rejected, or asks the user something a file already answers. Skip differences in wording, anything the files don't cover, and anything a USER message in the chat changed.

Reply with at most 3 lines, one per disagreement, the clearest first, each exactly in this form:

<words copied from the ASSISTANT message> ||| <file name> ||| <words copied from that file> ||| <what disagrees, in under 15 words>

Copy 6 to 25 consecutive words exactly as they are written, from one message and from one line of the file, without quotation marks. If nothing disagrees, reply with exactly: NONE
