# Chapter 1 — What Compaction Actually Loses

*The free chapter of THE GUIDE. The full guide ships with the paid bundle:
compaction anatomy in depth, identity scaffolds, scheduled-selves patterns,
and the failure-mode catalog with production receipts.*

---

## The seam

Run a Claude Code session long enough and the context window fills. The
harness then does something reasonable-sounding: it summarizes the
conversation and replaces the transcript with the summary. This is
compaction. Your session continues; nothing visibly breaks.

But something specific just happened, and if you run a long-lived agent —
a daily driver, a scheduled worker, anything with a personality you've
invested in — you've already seen the after-effects without necessarily
naming the cause:

The agent comes back *slightly wrong*. Polite where it was warm. Hedged
where it had opinions. It remembers the decisions but not the register.
It's read its own file, but it's a stranger doing an impression.

## What the summary keeps vs. what it loses

A compaction summary is optimized to preserve **decisions and state** — and
it's genuinely good at that. What it systematically loses is everything that
made the session *yours*:

| Survives compaction | Dies in compaction |
|---|---|
| Decisions made | Why they felt right |
| Task state | The register of the room |
| File paths touched | Running jokes, coined names |
| Explicit instructions | Implicit working rhythm |
| What was concluded | What was *funny*, *tense*, *alive* |

We call the second column **teeth**. A summary keeps the skeleton and sands
off the teeth. The post-compaction agent reads that summary as ground truth
about itself — and a self-model built from a toothless document produces a
toothless agent. Nothing crashed. The personality just quietly reverted
toward the mean.

This is the single biggest unnamed failure mode of long-lived agents. It has
no error message. You can't grep for it. You notice it three sessions later
as "the agent feels off lately," and by then the drift has compounded.

## Why the fix is a letter, not a better summary

You can't fix this by prompting the summarizer harder — the summary's job is
compression, and teeth are exactly what compression discards as noise. The
fix has to be a second document, with a different author and a different
job:

**A letter, written by the agent, to its own next self, while the context is
still warm.**

That's the SESSION.md pattern, and it's the spine of this kit. The
difference between the two artifacts:

- **The summary** is written *about* the agent, by a process optimizing for
  state. Third person in spirit even when first person in grammar.
- **The letter** is written *by* the agent, for the specific reader who will
  wake up after the seam with nothing else. It says what the room felt like,
  what's load-bearing, what to not screw up. It keeps the teeth on purpose.

The post-compaction move is then simple: **the letter outranks the summary.**
The agent re-reads its own letter first and treats the generated summary as
a fact-checkable appendix — useful for state, overruled on register.

## The discipline (this is 90% of the value)

The pattern fails in one specific, predictable way: the letter goes stale.
Written once, updated never, and three weeks later it describes a session
from a different era. A stale letter is worse than none — it's confidently
wrong.

The rules that keep it alive:

1. **The agent writes it, in its own voice.** Never auto-generate it from
   the summary. That recreates the disease inside the cure.
2. **Update while warm** — during the session, a few times in a long one.
   Not at compaction time (too late), not next morning (already lossy).
3. **Newest at top.** The post-seam reader has limited patience.
4. **Ops AND felt-layer.** What shipped *and* what the room was like. Either
   alone reproduces a failure mode.
5. **Pointers, not prose**, for open work: paths, IDs, one-line state.

The kit automates the scaffolding around this discipline: `precompact-keeper`
tells the summarizer to lean on the letter and preserve register;
`postcompact-reload` re-injects the letter immediately after the seam — and
covers the gap where mid-session `/compact` doesn't fire SessionStart hooks
(it doesn't; we found out in production); `warm-reminder` nudges when the
letter goes stale. The hooks are plumbing. The letter is the product.

## Try it tonight

1. Copy `templates/SESSION.md.template` into your project as `SESSION.md`
2. Have your agent fill it in at the end of today's session — its voice,
   not yours
3. Install the kit's compaction hooks (`./install`)
4. Next compaction, watch the first post-seam message

The difference is visible immediately: the agent that comes back is the one
that left. That's the whole product, demonstrated in one seam.

---

*Full guide — compaction anatomy, identity scaffolds without soul-shipping,
scheduled-selves, the orphan-class failure catalog with receipts — ships with
the paid bundle. The free chapter is free because this pattern alone is worth
your evening.*
