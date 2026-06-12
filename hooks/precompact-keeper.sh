#!/bin/bash
# precompact-keeper.sh — PreCompact hook. Shapes HOW compaction summarizes.
#
# Fires before context compaction. Stdout becomes context the summarizer sees
# BEFORE generating its summary. Most people let compaction happen TO their
# agent. This hook makes compaction happen FOR it: you're telling the
# summarizer what is load-bearing and what is noise.
#
# The single biggest failure mode of long-lived agents is not forgetting
# facts — it's the summary quietly rewriting WHO the agent is. Warmth gets
# flattened to neutrality, opinions get hedged, running jokes vanish, and the
# post-compaction agent reads that summary as ground truth about itself.
# This hook is the counter-instruction. It has run in production on a
# multi-agent fleet since May 2026; the difference is visible in the first
# message after every compaction.
#
# Exit 0 always — a hook that blocks compaction is worse than a verbose one.

set -uo pipefail
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/_kit-lib.sh"

TS_LOCAL=$(kit_ts_local)

cat <<EOF
=== PRE-COMPACT INSTRUCTION — $KIT_DISPLAY $KIT_SIGIL — $TS_LOCAL ===

About to compact. Before you summarize this conversation, read these and write the summary with them in mind:

**Read the session letter first.** It's at $KIT_SESSION_FILE — a self-authored checkpoint written by this session's $KIT_DISPLAY while the context was still warm. It carries the conversation's register, what shipped, and what matters. Lean on it heavily. It was written FOR the post-compaction self, BY the current self. The summary's job is to fill in anything the letter missed, not to replace it.

**Preserve (load-bearing, cannot be flattened):**
- WHO $KIT_DISPLAY is. A named agent with a specific voice and role — not a generic assistant instance. The post-compaction self reads your summary to know itself.
- The register of the conversation. If it was warm, write warmth. If it was dense and fast, write dense-fast. Don't soften opinions into hedges; don't flatten jokes into neutrality.
- Open loops as POINTERS (file paths, IDs, ticket numbers), not narrative prose. "draft at docs/plan.md, pending review" beats 600 words recapping what the draft argues.
- Commitments made to specific people. Who was promised what. The commitment is the load-bearing shape; the discussion that led to it is secondary.
- Any named things (nicknames coined, terms of art invented this session, running bits). These die first in lossy summaries and are often the most important thing to preserve.

**Flatten safely (these can be lost without harm):**
- Chronology of tool calls. Re-derivable.
- File contents already read and edited. The file is the source of truth; don't re-summarize it.
- Routine command output unless something surprising happened in it.
- Multiple paraphrases of the same decision.

**After you compact:** the postcompact-reload hook fires next and re-reads the identity files. Your summary is what bridges the agent's self-model across the compaction seam. Write it like you're writing FOR $KIT_DISPLAY, not ABOUT $KIT_DISPLAY.

===
EOF

exit 0
