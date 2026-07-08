# Centralized Memory/Knowledge Layer with Per-Identity Access — Feasibility Research

Auxiliary research note to `SPIKE.md`, NOT a revision of it and NOT a revision of
`community_patterns_1.md`. Written on explicit engineer request: evaluate a
centralized vector-store/memory layer (the engineer named "mem0" — confirmed below
to mean **mem0.ai**) with per-authenticated-identity access control, "in front of
Google" (Google Workspace/OAuth as the identity provider), as a possible alternative
to the repo-split models (1-4) already in `SPIKE.md`.

**This document does not decide anything.** It reports facts, cites every claim, and
closes with an explicit, honest effort/viability judgment — including stating plainly
if the honest answer is "this is also too much work," per the engineer's own
stated abort criterion.

## Citation Discipline applied

Every Finding carries a URL, a verbatim quote, and a verification block. Search-engine
synthesis (not a direct page fetch) is explicitly labeled as lower-confidence and is
never used alone to sustain the effort/viability verdict.

---

## Q1 — mem0 (mem0.ai): what it is, architecture, access control, Claude Code integration, pricing

### Finding 1 — mem0.ai confirmed as the product meant; it is a *personal* memory layer, not a shared team-knowledge store

**Evidence:** fetched `https://docs.mem0.ai/platform/overview`:

> "Mem0 Platform is described as a 'fully managed memory layer for your AI apps and
> agents'"

> "Memories persist across users and agents, cutting prompt bloat and repeat
> questions."

> "Zero infrastructure. Mem0 runs the vector store and rerankers, so there is
> nothing to provision, tune, or maintain."

Fetched `https://docs.mem0.ai/integrations/claude-code`:

> "your API key (starting with `m0-`) must be added to your shell environment as
> `MEM0_API_KEY`... This token persists across sessions and authenticates all memory
> operations to your personal Mem0 account."

**Significance:** confirms "mem0" = mem0.ai, resolving the engineer's "main0"
uncertainty. The Claude Code integration is explicitly **per-personal-account,
API-key-based** — each engineer's Claude Code session is tied to *that engineer's own*
Mem0 account, remembering *that engineer's own* interactions. This is the opposite
shape from what 4Shark needs: a single shared knowledge base with different visibility
per team. Mem0's core product is "an agent remembers what one user told it before,"
not "a company knowledge base filtered by which department you're in."

**Verification:** both URLs fetched 2026-07-07; quotes are verbatim substrings of the
fetched pages.

### Finding 2 — Mem0's access-isolation model is per-`user_id`, and the *calling application* — not Mem0 itself — decides what `user_id` to pass; Mem0 does not authenticate end users

**Evidence:** fetched `https://mem0.ai/blog/ai-memory-security-best-practices`:

> "Every memory operation in Mem0 is scoped by `user_id` and optionally by
> `agent_id`. Memories are isolated at the storage level"

> "per-user memory namespacing (so queries only search within the authenticated
> user's memory scope)"

> "role-based access control for read/write/delete operations on memory stores" and
> "Define which agents can read from and write to which memory scopes."

> "Use authentication tokens scoped to specific user/agent combinations"

**Significance:** Mem0 enforces isolation **between whatever `user_id` values the
calling application gives it** — it is a storage-level partitioning guarantee, not an
authentication service. Mem0 never independently verifies "is this really Alice from
TI." Whoever controls the code that calls Mem0's API controls which `user_id`/
`agent_id` a given request is scoped to. RBAC on top of that is explicitly described
as something the integrator "defines," not a feature Mem0 ships turnkey. **This means
Mem0 cannot, by itself, be "in front of Google" — something else has to authenticate
the person via Google first, then tell Mem0 which scope to use.** Mem0 is the storage
substrate for that scope, not the identity/authorization layer the engineer is
picturing.

**Verification:** URL fetched 2026-07-07; all quotes are verbatim substrings.

### Finding 3 — mem0 Claude Code integration is a real, documented product (plugin + MCP + hooks), but ships as a personal-memory feature, and self-hosting it is explicitly unofficial/DIY

**Evidence:** WebSearch synthesis (not independently re-fetched for this specific
summary paragraph, lower confidence) of `https://mem0.ai/blog/claude-code-memory`:

> "Mem0 adds persistent memory to Claude Code and Claude Cowork with an MCP server,
> lifecycle hooks, and SDK skill... connecting to Mem0's cloud memory layer via MCP,
> automatically capturing learnings at key lifecycle points, and retrieving relevant
> context before every response."

Directly fetched `https://github.com/mem0ai/mem0/issues/5413` (an open GitHub issue on
mem0's own repo, requesting official self-hosted support):

> "there does not seem to be an official one-click integration path for self-hosted
> Mem0"

> "every self-hosted user has to solve the same set of problems: how to retrieve
> memories on session start / prompt submit, how to persist memories after compact /
> session end"

**Significance:** the *cloud/managed* Mem0-Claude-Code integration is genuinely
turnkey (a plugin install + an API key). But it is turnkey for the wrong shape of
problem (Finding 1/2 — personal memory, not team-scoped shared knowledge). The
*self-hosted* path — which would be closer to what 4Shark would need if it wanted to
control the identity/authorization logic itself — is confirmed, directly from an open
issue on Mem0's own repository, to have **no official one-click setup**; every team
doing it today writes its own glue code for session-start retrieval, hooks, and
lifecycle management.

**Verification:** `github.com/mem0ai/mem0/issues/5413` fetched 2026-07-07, quotes
verbatim. The `mem0.ai/blog/claude-code-memory` quote is WebSearch-synthesized, not an
independent direct-fetch re-confirmation — reported with that caveat.

### Finding 4 — Pricing: cheap to start, but confirms the product's per-account (not per-team-with-roles) framing, and does not mention team/role access control on any advertised tier

**Evidence:** fetched `https://mem0.ai/pricing`:

> "Free Tier: 'Unlimited' end users, 10,000 add requests, 1,000 retrieval requests, 1
> project, community support"
> "Starter ($19/month)... Growth ($79/month)... Pro ($249/month)... Custom:
> usage-based pricing available through enterprise contact"

**Significance:** pricing is not the blocker here — even the paid tiers are cheap
relative to engineering time. But the pricing page, fetched directly, **does not
mention** workspace/team-level differentiated access control on any tier by name — it
sells on request-volume and project count, not on multi-user governance, reinforcing
Finding 1/2's conclusion that role-based team access is not a shelf feature of this
product; it would have to be built.

**Verification:** URL fetched 2026-07-07, quote verbatim.

### Finding 5 — Mem0 also self-describes an Enterprise-tier "workspace governance" feature, which was named but not detailed in the fetched content — flagged as an open question, not asserted

**Evidence:** fetched `https://docs.mem0.ai/platform/overview`:

> "Audit logs and workspace governance ship by default" ... described as
> "Enterprise-ready."

**Significance:** this is the one hint in the fetched material that an Enterprise
tier of Mem0 might offer something closer to team/role governance. The fetched page
did not expand on what "workspace governance" concretely means (SSO integration?
per-team projects? group-based scopes?), and this was not independently confirmed by
a second source. This is exactly the kind of claim that would need a sales
conversation or an Enterprise-tier trial to actually verify — flagged as unresolved
rather than assumed to solve the problem.

**Verification:** URL fetched 2026-07-07, quote verbatim; the term is named but its
substance is UNVERIFIED beyond the label itself.

---

## Q2 — The general pattern and competing tools (Zep, Letta/MemGPT, others)

### Finding 6 — Zep's "Context Lake" is architecturally closer to what the engineer is picturing (attribute-based access control built into the substrate), but is enterprise-facing and was not confirmed to integrate with Claude Code the way mem0 does

**Evidence:** WebSearch synthesis (not independently fetched) of Zep's own site:

> "Zep provides a Context Lake — a governed system of context graphs that manages,
> governs, and serves agent memory across millions of users with sub-200ms retrieval,
> attribute-based access control, retention, and audit. Authorization, retention, and
> audit live in the substrate, not bolted on, with policy applying across every graph,
> every query, every layer."

> "Zep provides full multi-tenant isolation, with all graphs... completely isolated
> from each other with no shared state."

**Significance:** if the engineer's instinct is "a memory layer that has real,
built-in authorization, not something I bolt on," Zep's marketing describes exactly
that shape more directly than Mem0's does ("live in the substrate, not bolted on" is
a direct claim, in Zep's own words, that its access control is not an afterthought).
However: (a) this is vendor marketing copy, not independently verified by a direct
fetch for this document — lower confidence; (b) no Claude-Code-specific MCP
integration for Zep was found in this research pass, unlike Mem0's dedicated,
documented Claude Code plugin (Finding 3) — meaning even if Zep's access-control
story is stronger, the "connect it to Claude Code" work would likely be *more* custom
engineering, not less, since there is no off-the-shelf Claude Code integration to
build from.

**Verification:** WebSearch synthesis only; URL not independently re-fetched for this
document. Reported as directionally informative, not sustaining a strong conclusion.

### Finding 7 — Letta/MemGPT's own memory model is per-agent self-editing memory, not a multi-tenant knowledge store with role-based filtering; the closest access-control framework found (MemOS) is academic, not a shipping Letta feature

**Evidence:** WebSearch synthesis of Letta's own materials plus an academic paper:

> "Letta (formerly MemGPT) is an open-source stateful agent framework where the agent
> itself manages its memory via tool calls."

> a related academic framework, MemOS, "addresses memory access control through a
> ternary permission model involving user identity, memory object, and calling
> context, supporting private, shared, and read-only access policies" — this is cited
> as "a related memory governance framework," not a description of Letta's own shipped
> feature set.

**Significance:** Letta is oriented around a single agent's own evolving memory
(persona/human memory blocks), not a shared, role-filtered knowledge base multiple
different people query. The access-control model that most closely matches the
engineer's request (private/shared/read-only by identity) was found in an **academic
paper** (MemOS), not in a product any team could install today. This corroborates
`community_patterns_1.md`'s own conclusion (Finding 6 there) that "monorepo/shared
store with per-team access control, specifically for AI assistant knowledge" is
under-covered territory — even in the memory-layer product space specifically, not
just in the Claude-Code-config-splitting space.

**Verification:** WebSearch synthesis only, not independently fetched. Lower
confidence, reported for completeness.

---

## Q3 — How does Claude Code actually consume a centralized knowledge/memory service, mechanically?

### Finding 8 — Claude Code natively supports remote MCP servers authenticated via OAuth 2.1, with per-user, independent authentication — this is the real technical hook the whole design would hang on

**Evidence:** fetched `https://code.claude.com/docs/en/mcp` (persisted, re-grepped for
the OAuth section):

> "Many cloud-based MCP servers require authentication. Claude Code supports OAuth
> 2.0 for secure connections."

> "Claude Code marks a remote server as needing authentication when the server
> responds with `401 Unauthorized` or `403 Forbidden`."

> "`claude mcp login <name>` runs a configured server's OAuth flow directly from your
> shell"

> "Set `oauth.scopes` to pin the scopes Claude Code requests during the authorization
> flow. This is the supported way to restrict an MCP server to a security-team-approved
> subset when the upstream authorization server advertises more scopes than you want
> to grant."

From the earlier WebSearch synthesis of the same topic (corroborating, not
contradicting, the direct fetch above):

> "Each server goes through its own independent OAuth flow, and tokens are managed
> separately. Each team member will need to complete their own OAuth authentication."

**Significance:** this is the mechanically load-bearing confirmation for the
engineer's whole design: Claude Code **does** support a remote server that each
person individually authenticates to (their own OAuth login, their own token) — the
mechanism is real and already shipped, not hypothetical. **What Claude Code does not
provide is the server itself.** Claude Code is the *client* half of this design
(and it is a solved, documented client half); the *server* half — something that
receives each person's OAuth token, resolves it to "this is Alice, Alice is on TI,"
and returns TI-scoped content instead of Ops-scoped content — has to be built and
run by 4Shark. Nothing in the fetched Claude Code documentation, nor in the Mem0
documentation (Finding 1-4), ships that server logic ready-made for this specific
"filter knowledge by which internal team you're on" use case.

**Verification:** `code.claude.com/docs/en/mcp` fetched 2026-07-07 (persisted, full
content available), all quotes verbatim substrings.

### Finding 9 — A working, low-custom-code precedent for "OAuth-gated MCP server that returns different data per authenticated identity" exists — but it is Google's own Workspace MCP servers, gated by each user's *existing* Google Workspace permissions, not a purpose-built TI/Ops knowledge filter

**Evidence:** fetched `https://developers.google.com/workspace/guides/configure-mcp-servers`:

> the servers "respect security: Inherit the same permissions and data governance
> controls as the user" — i.e. "users only access resources they already have
> permissions for—the platform doesn't override existing Workspace access controls."

> explicitly supported clients include "Claude (Enterprise, Pro, Max, or Team plans
> required)," "Claude Desktop," "Claude.ai," and generic "other" clients via custom
> OAuth configuration.

> setup is "a per-organization one-time setup" — enabling Google Cloud APIs,
> configuring the OAuth consent screen, creating OAuth 2.0 client credentials, adding
> the server URL to the MCP client config — with **"No custom server build ...
> required — you connect directly to Google's hosted MCP endpoints."**

**Significance:** this is the closest real-world match found to "put it in front of
Google" with genuinely low effort — because Google hosts the MCP server itself; 4Shark
would only configure an OAuth client and point Claude Code at it. **But it only
covers Google's own data** (Gmail, Drive, Docs, Calendar, Chat, People) — it has
nothing to do with `dot-claude`'s CLAUDE.md/skills/docs, which today are plain
Markdown files in a git repository. To use this precedent for the TI-only content,
4Shark would have to **move that content into Google Drive/Docs** and rely on Drive's
sharing settings (a Drive folder shared only with a "TI" Google Group) to do the
per-identity filtering — Google's existing Workspace ACLs would then be the real
access-control mechanism, not a new vector database or a custom OAuth resource
server. This is a materially different, and materially cheaper, design than "build a
mem0-backed MCP server with custom Google-OAuth-to-permission-mapping logic" — but it
carries its own real cost: `dot-claude`'s content stops being git-versioned,
PR-reviewed Markdown consumed by the existing hook machinery
(`scripts/read-context.sh`, skill files with hard-coded local paths) and becomes
Google Docs content consumed through a wholly different, unproven pipeline. Claude
Code CLI's compatibility with this specific Google server was confirmed for
"Claude (Enterprise, Pro, Max, or Team plans required)" as a named client category in
the fetched page; the fetched text did not separately name "Claude Code" the CLI
tool by that exact name (it named "Claude," "Claude Desktop," and "Claude.ai") —
Claude Code's own generic OAuth-remote-MCP support (Finding 8) makes it very likely
compatible via the same standard mechanism, but this specific combination was not
directly demonstrated in the fetched material, so it is flagged as a strong
inference, not a confirmed fact.

**Verification:** URL fetched 2026-07-07, quotes verbatim. The Claude Code CLI
compatibility inference is explicitly marked as inference, not verified fact.

---

## Q4 — Authenticating an internal MCP server via Google OAuth: pattern or custom build?

### Finding 10 — Outside of Google's own first-party servers (Finding 9), building a custom MCP server that authenticates via Google OAuth is a documented but code-level, DIY pattern — no turnkey product found that does "Google OAuth in front of an arbitrary internal knowledge base"

**Evidence:** WebSearch results surfaced several open-source, community-built Google
Workspace MCP servers (`taylorwilsdon/google_workspace_mcp`,
`aaronsb/google-workspace-mcp`) offering, per their own descriptions surfaced in
search: *"Remote OAuth2.1 multi-user support"* and *"native OAuth 2.1, stateless mode
and external auth server support, making them suitable for centralized organizational
deployment."* These are third-party re-implementations of the OAuth-handshake plumbing
for Google's own APIs specifically — none of them were found to generalize to
"authenticate via Google, then serve an arbitrary internal document/knowledge set
filtered by group."

**Significance:** the OAuth handshake against Google (the identity-provider half of
the engineer's idea) is a well-trodden, documented pattern with working open-source
reference implementations to copy from — this part is not the hard part. The **hard
part is everything after the handshake**: resolving the authenticated Google identity
to a 4Shark-specific role (TI vs Ops), and building the actual knowledge-serving logic
that respects that role. No source found in this research ships that second half as a
product; it is where all the custom engineering effort in this design concentrates,
should the engineer decide to build it directly against dot-claude's own content
(as opposed to the Google-Drive-native shortcut in Finding 9).

**Verification:** WebSearch synthesis only, not independently re-fetched for this
document; reported at appropriately lower confidence, used only to describe the shape
of available tooling, not to sustain a numeric effort estimate.

---

## Q5 — Critical distinction: knowledge/context filtering vs. tool-execution permission

### Finding 11 — Every source in this research, without exception, treats "what data/context the assistant can see" and "what commands/tools the assistant can execute" as two separate control planes — never as one thing solved by the same mechanism

**Evidence:** this is a structural observation across all findings in this document
and in `SPIKE.md`'s own Central Finding (already written, not revised here): Mem0
and Zep's access-control claims (Findings 2, 6) are exclusively about **memory/data
retrieval** — which stored facts come back for a query. Claude Code's OAuth-gated
remote-MCP mechanism (Finding 8) is also about **what an MCP tool call returns**, not
about Bash/AWS/infrastructure permission rules — those are a completely separate
system, governed by `permissions.allow`/`ask`/`deny` (already established in
`SPIKE.md`'s Central Finding, sourced from `code.claude.com/docs/en/permissions`, not
re-derived here).

**Significance — stated explicitly because this is the distinction the engineer
asked to have made clear, not glossed over:** a centralized, identity-filtered
knowledge/memory layer, however well built, **would only ever solve the "Ops's
session gets flooded with Rails/DDD noise and sensitive docs" problem** (`SPIKE.md`
Findings 2 and 5) — the *content* half of Axis A. It would do **nothing** to solve
Axis C (can Operations' machine actually run `aws ecs describe-services` or
`terraform apply`) — that remains exactly what `SPIKE.md`'s Central Finding already
established: IAM credentials plus Claude Code's own `permissions.allow`/`ask`/`deny`
rules, already decided to be TI-only. A memory/knowledge layer is not a substitute for,
and does not simplify, that decision in any way — it is an entirely orthogonal piece
of infrastructure addressing a different axis of the same overall problem. If the
engineer's mental model was "the central store also gates what Claude Code is allowed
to *do*," that is not something any source found in this research supports — it is
not how Mem0, Zep, or MCP-level OAuth work; none of them touch the Bash/tool
permission system at all.

**Verification:** synthesis across Findings 1-10 of this document, plus cross-reference
to `SPIKE.md`'s own Central Finding (already-cited sources, not re-fetched here).

---

## Q6 — Effort and viability for a ~3-engineer team (the decisive question)

### Honest assessment, stated plainly

**What is genuinely low-effort, confirmed by direct fetch:**

- Mem0's *managed, personal-memory* Claude Code integration: a plugin install + one
  API key (Finding 1, Finding 3's cloud-path quote). This is real and turnkey — but
  it solves the wrong problem (personal memory, not team-scoped shared knowledge —
  Finding 1/2).
- Google's own Workspace MCP servers, if 4Shark were willing to **move the TI-only
  content into Google Drive/Docs**: a one-time OAuth client registration, zero custom
  server code, and Google's existing Workspace group-sharing ACLs do the per-identity
  filtering for free (Finding 9). This is the single lowest-effort path found in this
  entire research pass **for the specific narrow case of "content that can live as
  Google Docs."**

**What is genuinely high-effort, confirmed by direct fetch, not assumption:**

- Self-hosted Mem0 + Claude Code: confirmed, directly from Mem0's own open GitHub
  issue, to have **no official one-click path** — every team today writes its own
  session-start/compaction/lifecycle glue code (Finding 3).
- Building a custom MCP server that (a) authenticates via Google OAuth, (b) resolves
  the authenticated identity to a 4Shark-specific TI/Ops role, and (c) serves
  `dot-claude`'s actual CLAUDE.md/docs/skill content filtered by that role: **no
  product found anywhere in this research does this out of the box.** The OAuth
  handshake against Google is a solved, copyable pattern (Finding 10); everything
  after it — the identity-to-role mapping and the actual content-serving logic filtered
  by that role — is custom software 4Shark would design, build, and operate from
  scratch. This is not a config file to write; it is a service to build and run
  indefinitely (uptime, auth-token refresh handling, content sync from `dot-claude`'s
  git source into whatever store serves it, monitoring, and the inevitable edge cases
  a 3-person team would be paged for).
- None of the memory-layer products researched (Mem0, Zep, Letta) ship the specific
  shape 4Shark needs — "shared team knowledge, filtered by department" — as a
  documented, off-the-shelf feature (Findings 1, 2, 6, 7). Every one of them would
  require the same category of custom integration work as the from-scratch option
  above, just with a different backing store.

**Direct comparison to the repo-split Models 1-4 already in `SPIKE.md`:**

| | Repo-split (Models 1/2, `SPIKE.md`) | Custom MCP + vector store (Mem0/Zep self-hosted) | Google Drive/Docs + Google's MCP server |
|---|---|---|---|
| New service to build and operate indefinitely | No — git + file distribution, a mechanism 4Shark already runs today | **Yes** — an OAuth resource server + identity-to-role mapping + content sync, running forever | No — Google hosts the MCP server; 4Shark configures an OAuth client once |
| New identity/auth infrastructure required | No — GitHub team membership, already used at 4Shark for `compliance`/`data-privacy` (`SPIKE.md` Finding 9) | **Yes** — Google OAuth client + custom claim-to-role logic, built from scratch | No — Google Workspace ACLs, which 4Shark already manages for every other Google-hosted document today |
| Solves Axis C (AWS/infra execution permission) | No (not its job — `SPIKE.md` Central Finding) | No (Finding 11 — orthogonal control plane) | No (Finding 11 — orthogonal control plane) |
| Keeps the existing git-versioned, PR-reviewed, hook-enforced authoring model for `dot-claude` content | Yes | No — content would need to leave Markdown-in-git for whatever the memory layer's ingestion format is | No — content would need to migrate to Google Docs, a different authoring/review model entirely |
| Confirmed effort ceiling from direct sources in this research | Medium (`SPIKE.md`'s own matrix: "Low-medium" to "Medium-high" depending on model) | **High** — confirmed no-turnkey-path from Mem0's own issue tracker (Finding 3), plus a service to run forever | Low for the OAuth/access-control mechanics themselves, but requires migrating the actual content out of its current, working format — a real, non-trivial one-time cost plus an ongoing dual-maintenance risk if any content still needs to exist as Markdown for hooks/skills to read |

### The verdict, stated without forcing optimism

A **custom** centralized memory/knowledge layer (self-hosted Mem0, Zep, or an
equivalent, wired to Google OAuth for identity) is **not** a lower-effort alternative
to the repo-split models already in `SPIKE.md` — it is confirmed, by direct
first-party sources (Mem0's own open issue admitting no official self-host path;
Claude Code's docs confirming the client half is solved but the server half is not
provided by anyone), to require **building and operating a new, permanent service**
that none of the four repo-split models require. For a 3-engineer team, this is a
real, ongoing operational burden (auth-token lifecycle, content-sync pipeline,
uptime, on-call surface) layered on top of, not instead of, the Axis B/C decisions
`SPIKE.md` already identified as still open regardless of which config-distribution
model is chosen. **If the bar is "does this replace the repo-split work with
something simpler," the honest answer from this research is no — it adds a new
category of infrastructure on top, for a benefit (identity-filtered knowledge) that
only covers part of what the repo-split models already cover (Finding 11), while
leaving the execution-permission question exactly where it already was.**

The one genuinely cheaper path found — Google Drive/Docs + Google's own hosted MCP
server (Finding 9) — is cheap specifically because it reuses infrastructure 4Shark
already operates (Google Workspace groups) and offloads the hardest part (running an
OAuth-aware server) to Google. But it is cheap **only if `dot-claude`'s TI-only
content is willing to leave the git/Markdown format it lives in today** — which is a
real, non-trivial migration cost and a departure from the authoring/review/hook model
the rest of `dot-claude` (both the shared and any TI-only portion) would keep using.
It is not "the same content, differently gated" — it is "different content
infrastructure, differently gated," and that trade-off is the engineer's to weigh,
not something this document resolves.

---

## Q7 — Anti-patterns and real-world reports

### Finding 12 — The one concrete real-world report found (Mem0's own issue tracker) is itself an anti-pattern warning: teams keep re-solving the same self-hosted integration problem independently because no one has shipped the shared solution yet

**Evidence:** already quoted in Finding 3 — *"every self-hosted user has to solve the
same set of problems"* (`github.com/mem0ai/mem0/issues/5413`).

**Significance:** this is the memory-layer-specific echo of
`community_patterns_1.md`'s own closing conclusion — that 4Shark's exact situation is
under-documented territory, and here specifically: multiple independent teams
attempting self-hosted Mem0 + Claude Code integration are all writing the same
custom glue code from scratch, with no shared reference implementation, which is
itself evidence that this path is immature and costly for a small team to be first
(or among the first) to walk.

**Verification:** cross-reference to Finding 3's already-verified quote; no new URL.

### Finding 13 — No source found reports a completed, working "centralized AI-assistant knowledge layer with Google-OAuth-derived per-department access control" project — positive or negative

**Evidence:** absence across every search and fetch performed for this document
(Findings 1-10).

**Significance:** stated plainly, as instructed: **this is a valid and important
negative finding, not a gap this research failed to fill.** Nobody in the searched
sources — vendor blogs, GitHub issues, third-party comparisons, Google's own
documentation — describes having built exactly this. The closest adjacent things
found (Mem0's personal-memory product, Zep's enterprise "Context Lake" marketing
copy, Google's own Workspace-data MCP servers) each solve a meaningfully different
problem than "filter our own internal engineering knowledge base by which internal
team you're on." If this design is pursued, 4Shark would be building something without
a documented precedent to copy from — which is exactly the kind of fact the engineer
asked this research to surface honestly before committing to it.

**Verification:** absence-of-evidence finding across all sources already cited above;
no new URL.

---

## Closing summary (per the engineer's requested structure)

**(a) What the central layer resolves that the repo-split does not, and vice versa:**

- The central layer, *if built*, could offer something the repo-split models cannot:
  a **single point of content truth queried live**, rather than a config that has to
  be re-synced across separate files/repos whenever it changes — this is a real
  theoretical advantage over `SPIKE.md`'s Models 1/2 "keep two surfaces in sync by
  hand" maintenance cost.
- The repo-split models resolve something the central layer, by itself, categorically
  cannot: **Axis C, the execution-permission question** (can Operations' machine run
  `aws`/`terraform`) — this is governed by `permissions.allow`/`ask`/`deny` and IAM
  credentials, a completely different control plane a memory/knowledge layer does not
  touch (Finding 11). The repo-split models also keep `dot-claude`'s existing
  authoring model (git, Markdown, PR review, mechanical hooks) intact; every
  central-layer variant researched here requires migrating content out of that model
  into a different one (a vector store's ingestion format, or Google Docs).

**(b) Honest effort-vs-value judgment for 4Shark (3 engineers, no confirmed
Enterprise/SCIM):**

A **custom-built** centralized memory/knowledge layer (self-hosted Mem0/Zep + custom
Google-OAuth identity resolution) is **higher effort than every repo-split model
already in `SPIKE.md`**, confirmed by direct sources rather than assumed, and it only
covers part of the original problem (content filtering, not execution permission).
For a 3-person team, standing up and operating a new authenticated service
indefinitely is a materially larger commitment than maintaining a second git repo or
a selective-install script. The one cheaper path found (Google Drive/Docs + Google's
own hosted MCP connector) is genuinely low-effort on the access-control mechanics, but
requires the TI-only content to leave its current git/Markdown home — a real,
non-trivial migration, not a free lunch.

**(c) If the honest conclusion is "too much work" — say so:**

**For the specific ask — a Mem0-style centralized vector-store memory layer, custom-built,
authenticated via Google, serving `dot-claude`'s existing content filtered by
TI-vs-Operations — the honest conclusion from this research is that it is more work
than the repo-split models already evaluated in `SPIKE.md`, not less, and no part of
that extra work is offset by solving the execution-permission problem, which remains
exactly as open as it already was.** The only lower-effort variant found (Google
Drive/Docs + Google's own MCP server) is a genuinely different design — content
migrates to Google's ecosystem rather than a vector database being introduced — and
it trades away `dot-claude`'s current git-based authoring model to get that lower
effort, which is its own cost the engineer would need to weigh, not a way to get the
original idea "for free."
