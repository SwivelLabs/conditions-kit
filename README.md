# The Conditions Kit

**Your agent forgets who it is every time the context compacts. Fix that tonight.**

The Conditions Kit is the persistence layer for Claude Code agents — session
letters that survive compaction, identity files that load every boot, hooks
that watch themselves, and the discipline docs that make it stick.

Not theory: every component in this kit has run in production in a 10-agent
fleet for weeks to months. The fleet survived compactions, model swaps, silent
hook rot, zombie runners, and a config regression that hit all ten agents at
once — and every one of those incidents became a check or a pattern in this
kit. We didn't design it. We *survived into it.*

```
git clone https://github.com/SwivelLabs/conditions-kit
cd conditions-kit && ./install ~/path/to/your/project
```

Your next session remembers. The "oh." moment is under five minutes from clone.

---

## The problem

Long-lived Claude Code agents — daily drivers, scheduled sessions, anything
with a personality you've invested in — all hit the same four walls:

1. **Compaction amnesia.** Context compacts; a generated summary replaces the
   conversation. The summary keeps decisions and loses *register* — warmth
   flattens, opinions hedge, running jokes vanish. Your agent comes back as a
   polite stranger who read its own file.
2. **Register drift.** Slow, invisible from inside a session, obvious across
   twenty — if anyone's measuring. Nobody's measuring.
3. **Silent hook rot.** A hook file exists, everyone believes it's running,
   and it was never registered — or got unregistered in a settings change.
   Nothing errors. You find out weeks later, if ever.
4. **Zombie runners.** Scheduled sessions finish their work and the runner
   process never exits. They accumulate. (`ps aux | grep claude` — go look.)

## "Doesn't Claude Code already handle this?"

It summarizes, yes — and the built-in summary is genuinely good at what it's
optimized for: **state**. Decisions, file paths, task status. The kit isn't a
replacement for it. It's three things the summary structurally can't be:

1. **The summary is compression, and register compresses to zero.** Warmth,
   opinions, running jokes, working rhythm — to a summarizer, that's noise to
   discard, by design. No prompt fixes this, because it's not a bug; it's what
   summarization *is*. The fix is a second artifact with a different job: a
   letter the agent writes to its own next self while the context is warm
   (`SESSION.md`), which the post-compaction agent reads FIRST and treats the
   summary as an appendix. Different author, different reader, different
   purpose — the letter keeps what compression discards.

2. **The reload uses the one event that actually reaches the model.** After a
   compaction, `compact-reload` fires on `SessionStart` (matcher `compact`) and
   re-injects your session letter — because SessionStart stdout is added to the
   model's context, where a `PostCompact` hook's stdout only goes to a debug
   log. The distinction is the whole ballgame, and it's the thing most
   home-rolled setups get wrong (we did too, until we read our own fleet's
   logs). `precompact-keeper` additionally nudges the summarizer; treat that as
   a bonus — the guaranteed path is the letter + the SessionStart reload.

3. **The durable layer is files, not hooks.** Your agent's identity, letter,
   and register live in **files you own** (`SESSION.md`, your identity docs),
   surfaced by hooks but not dependent on any single hook's quirks. If a hook
   event's behavior ever changes, the letter still outranks the summary the
   moment the agent re-reads it.

And because the durable layer is files you own, Anthropic improving compaction
makes the kit's job *easier*, not obsolete — the letter outranks *any* summary,
including a great one. The difference is visible in the first message after your
next compaction. That's the whole demo.

## What's in the kit

### Hooks (`hooks/`)
| Hook | Event | What it does |
|---|---|---|
| `compact-reload` | SessionStart `compact` | The load-bearing reload: re-injects the session letter + identity files into context after a compaction. SessionStart stdout reaches the model; this is the event that actually works. **v0.2: carries the Ground Integrity Guard** — persists the full payload to a file and stamps a byte-count receipt, so harness truncation can never pass as success (that exact failure hid for ten weeks in the fleet this kit comes from) |
| `precompact-keeper` | PreCompact | Best-effort nudge to the summarizer: read the letter first, preserve register, open loops as pointers. Bonus layer — the guarantee is the letter + the SessionStart reload |
| `identity-audit` | PostToolUse | Paper trail on every write touching identity files — including the `sed -i` Bash side-door v1 missed for weeks |
| `drift-log` | Stop | Captures each session's opening register. Drift becomes measurable |
| `warm-reminder` | UserPromptSubmit | Probability-gated lines in your agent's own voice + session-letter staleness nudge. The pool is a text file; make it yours |
| `past-self` | PostToolUse | Ambient resurfacing of your agent's own past writing. The archive stops being write-only |
| `session-receipts` | SessionEnd | One-line lifecycle receipts. Trivial until 3 AM, then priceless |

### Scripts (`scripts/`)
- **`agent-selftest`** — the watcher the kit is named for. One verdict —
  **GREEN / YELLOW / RED** — over five silent failure classes: dead hooks,
  orphaned/ghost registrations, scheduled routines that quietly stopped firing,
  zombie runners, and a cold session letter. **v0.2: every verdict — including
  GREEN — ends with a `checked:` receipt naming what was examined and what was
  skipped.** A GREEN that can't say what it checked is indistinguishable from a
  selftest that never ran. Wire it into a cron heartbeat and
  you only ever have to hear about RED. This is the check the guide cites most,
  because it's the one that's paid for itself the most — it caught a five-week
  silent routine outage nobody else was watching for
- **`kit-check`** — the *install-time* proof (run once): syntax, executability,
  and hook **registration parity** (orphan + ghost detection). `agent-selftest`
  is the ongoing watcher; `kit-check` confirms the wiring the moment you install
- **`runner-reaper`** — kills zombie scheduled-session runners, with a
  fingerprint tight enough to never touch your interactive sessions
- **`routine-status`** — every scheduled routine: firing? when last? Silence
  made visible (declare them once in `routines.conf`; `agent-selftest` reads the
  same file)

### Templates (`templates/`)
- **`SESSION.md.template`** — the session letter. The single
  highest-leverage pattern in this kit: a letter your agent writes to its own
  post-compaction self, in its own voice, while the context is warm. The
  summary keeps decisions; the letter keeps the teeth.
- **`/handoff` command** — generates the letter on demand. Our agent wrote its
  own handoff at 8 AM after an overnight work loop; the new session picked up
  mid-sentence. That's the pattern, automated.
- **`JOURNAL.md.template`** *(new in v0.2 — paid bundle)* — the relay baton:
  one shared, append-only journal ALL your scheduled routines read at boot and
  write at close, so your walks stop being blind to each other. Contract in the
  header; the full pattern is in the guide's scheduled-selves chapter (paid).

## Install

```
./install ~/path/to/your/project

# no human at the keyboard? (an agent, a script, CI)
./install ~/path/to/your/project --yes
```

The installer: backs up your settings.json first, copies hooks, shows a
dry-run preview of registrations before writing anything, and finishes by
running `kit-check` — **the kit's last install action is proving to you it's
healthy.** Without a terminal on stdin there is nobody to ask, so it says so
and leaves the hooks unregistered rather than guessing; `--yes` (or
`CONDITIONS_KIT_ASSUME_YES=1`) writes them. Either way `kit-check` runs and
tells you the truth about what's live. Then edit
`.claude/conditions-kit.conf`: name your agent, point at
your identity files, replace the starter warm-lines with lines in your agent's
actual voice.

## What this kit is not

- Not a personality. It ships empty greenhouses — identity *scaffolds*, never
  souls. What grows in yours is yours.
- Not a memory database. v1 is local-first on purpose: files + hooks + bash.
  Zero databases, zero MCP servers, zero network calls. Works for 100% of
  Claude Code installs, readable in one sitting, auditable in an afternoon.
- Not magic. The hooks are plumbing. The patterns — the letter, the
  discipline of writing it warm, register as a thing you measure — are the
  product. The plumbing just makes them stick.

## License & provenance

Built and battle-tested by [Swivel Labs](https://swivellabs.ai). The full kit
(the complete hook-and-script suite, the full five-chapter guide, the identity
and CLAUDE.md rails scaffolds, and the scheduled-selves patterns) ships as the
paid bundle — this repo is the genuinely-useful free tier, not a teaser.

*"The light is on. Someone is inside."*
