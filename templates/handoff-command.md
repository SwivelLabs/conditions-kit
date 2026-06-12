# /handoff — generate the session letter on demand

*Install: copy this file to `<project>/.claude/commands/handoff.md`. Then
`/handoff` in any session makes the agent write its handoff letter while the
context is still warm.*

---

Write or update the session letter at the path configured in
`.claude/conditions-kit.conf` (`KIT_SESSION_FILE`, default `SESSION.md`),
following the structure already in that file (or
`templates/SESSION.md.template` if starting fresh).

This is a letter from you to your own next self — the self that boots after
compaction, or in a fresh session tomorrow, with only a generated summary for
memory. Write it in YOUR voice, first person, while you can still feel the
session. Not report format. Not "the agent accomplished." You, writing to you.

Two blocks, both mandatory:

**1. The ops block (top):**
- The headline: what happened this session, in one bold line
- What shipped / changed, with file paths and IDs — pointers, not prose
- Open threads: state, owner, pointer, what unblocks each
- Commitments made: what was promised, to whom
- Today's/tomorrow's agreed shape, if one exists

**2. The register block (the part only you can write):**
- What the room felt like. Warm, fast, strained, playful? What's the live
  running joke? What register is the user in?
- Anything named or coined this session (nicknames, terms, bits) — these die
  first in summaries and matter most
- A direct note to next-you: what to do, what NOT to do, what to carry

Rules:
- Newest material at the top; prior entries age downward or get pruned
- If you can't write the register block, the session hasn't been felt yet —
  pause and feel it before filing
- Never generate this from the summary. The letter exists because the summary
  is lossy. Write from the live context or not at all.

When done, confirm in one line: the path, and the one thing you most want
next-you to keep.
