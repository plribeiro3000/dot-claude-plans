# SPIKE — Operations Team Claude Code Access Model

## Decision & Outcome (2026-07-07) — CLOSED, no action

**Decision: do nothing.** No repo-split (Models 1-4), no plugin, no centralized
memory/vector layer (mem0/Zep), no custom OAuth MCP gateway. Every option was
evaluated and judged higher-effort-than-value for a ~3-person team.

**What drove the decision — the two-axis reframing:**

- **Security (Axis C — Operations running `aws`/touching infra), the only real risk,
  is solved for ~zero cost** by simply not provisioning AWS credentials on
  Operations' machines (IAM/1Password) — independent of any `dot-claude` change. No
  config work is needed to close the actual attack vector.
- **Content-noise (Axis A — dev rules + sensitive docs landing in Operations'
  sessions) is discomfort/token-cost, not risk**, and does not justify building
  anything now. The community research found no consolidated pattern and no precedent
  for 4Shark's size/toolchain; the centralized-memory layer was confirmed *higher*
  effort than the repo-split and covers only content-filtering, never
  execution-permission.

**Action for now:** create a Claude Code account/seat for the Operations team so they
can do what they previously did on ChatGPT — as a **plain general assistant**.
Explicitly: **no infrastructure access** (no AWS credentials on their machines),
**no access to 4Shark's `dot-claude` config/documentation** (they run Claude Code
*without* the shared config cloned to `~/.claude/`). Nothing else.

**Revisit triggers (documented lowest-effort paths, not commitments):** if the
content-noise or a health-check use case later becomes worth the effort, repo-split
**Model 1** (a curated, static `dot-claude-ops`, GitHub-team-gated per Finding 9) is
the documented lowest-effort path; **Axis B** (read access to the application source
repos, for the "does an API exist?" use case) remains an independent GitHub-team
decision that no `dot-claude` model grants or withholds.

The research below is preserved as-is for that future revisit.

## Investigation question

4Shark's IT/engineering team (~3 engineers) uses Claude Code today, configured by the
shared `dot-claude` repository (working copy `~/Projects/4Shark/dot-claude/`, active
config `~/.claude/`). A separate Operations team (previously on ChatGPT, now
cancelled) is being given Claude Code access. The engineer does **not** want to give
Operations the full `dot-claude` repository/config as-is. The question this spike
answers:

1. What does Operations actually need from `dot-claude`, given their stated use case
   (investigation that crosses code + infrastructure, never code-writing)?
2. Structured across three distinct access axes — (A) the `dot-claude` config/rules
   themselves, (B) read access to the 4Shark application source repos, (C) read
   access to AWS infrastructure — what does each axis require, and where is each
   axis already solved vs. still open?
3. **The central technical question, raised explicitly by the engineer mid-investigation
   and treated as the primary finding of this spike**: can a Claude Code *plugin*
   genuinely invert a restrictive rule set in the shared "core" configuration — e.g.
   core says "no infrastructure access", installing the TI plugin makes "has
   infrastructure access" true? Or does a plugin only ever *add* capability, never
   *change* what the core forbids?
4. What are the technically viable models for splitting `dot-claude` so Operations
   gets a curated minimum instead of the whole repo — evaluated in light of the
   answer to (3), since only a model that can actually deliver "base restricted / TI
   layer enables" satisfies the engineer's stated design intent.
5. For each model: technical viability, maintenance cost, real strength of any access
   control, fit to the Operations use case, and risk of leaking sensitive material —
   without recommending one, per Ask-Don't-Decide.

## Operations' actual use case, and the amended security premise

Operations does not write code. Three concrete activities, as stated by the engineer:

1. **Application-behavior questions answered by reading code** — "does an API exist to
   group X?", "does an API exist to delete Y?" — questions about the application's
   contract, answered by reading source, not by asking a human.
2. **Health-check / observability** — "is everything OK with the shared app?", "how
   do the logs look?", "is there an error log?", "is something happening with any
   application?".
3. **Customer-ticket support crossing code + infra** — a client reports "I sent API X
   then API Y"; with code access AND infra access, Claude Code can see which
   **version** is actually running (infra), read that version's code, and tell
   Operations "yes, the code guarantees that" or "no, it does not" — also a learning
   tool for the Operations team, not a sole source of truth.

**Amended premise, decided by the engineer during this investigation**: by default,
the base/core configuration that ships to Operations does **not** include AWS/infra
read access, regardless of how convenient it would be for use case #3. Engineer's own
words: *"por mais que é legal, não vale, é inseguro, é melhor não ter esse vetor de
entrada pra não ter risco"* — the extra attack surface is judged not worth the
convenience. This directly changes what use case #3 can deliver as originally framed
— see the Tension callout after the Central Finding below.

The engineer also rejected, explicitly, a per-user runtime-flag design ("pode/não
pode resolvido baseado em quem está logado", stacked on top of the existing
configuration). The preferred shape is structural, not conditional: one minimal base
config that ships to everyone (Operations + TI), plus one advanced layer for TI,
built as a Claude Code plugin.

## Sources consulted

- `~/Projects/4Shark/dot-claude/CLAUDE.md` (1498 lines, all ~65 sections) — read in
  full at session start (injected) and re-verified with `grep -n '^### '` for exact
  line numbers; see `ops_content_inventory_1.md` Part 1 for the per-section
  classification
- `~/Projects/4Shark/dot-claude/docs/*.md` (49 files) — filesystem-listed via `find`;
  10 read in full, the rest classified by filename + their `CLAUDE.md` "See"
  description (Full-Read Discipline scope note — see auxiliary file header)
- `~/Projects/4Shark/dot-claude/skills/*/SKILL.md` (14 skills) — all read in full
- `~/Projects/4Shark/dot-claude/commands/*.md` (7 commands) — all read in full
- `~/Projects/4Shark/dot-claude/agents/*.md` (14 agents) — names/roles only (all are
  part of the DDD/plan/task/PR-review pipeline per `CLAUDE.md:1093-1195`, none opened
  in full — Ops-relevance was unambiguous from role alone)
- `~/Projects/4Shark/dot-claude/scripts/*.sh` (40 files) + `settings.json` (726 lines,
  hooks section and full `permissions` block read) — filenames + matcher/hook wiring
  read via `grep`; grouped by function in `ops_content_inventory_1.md` Part 6
- `~/Projects/4Shark/dot-claude/README.md` (712 lines) — read in full
- https://code.claude.com/docs/en/discover-plugins — plugin distribution/install
  mechanics
- https://code.claude.com/docs/en/plugins-reference — plugin component schema,
  settings-file support, skills-directory plugins
- https://code.claude.com/docs/en/plugin-marketplaces — marketplace hosting, private
  repos, `strictKnownMarketplaces`, `enabledPlugins`
- https://code.claude.com/docs/en/permissions — **the central source for this
  spike's primary finding**: permission rule evaluation order, deny/ask/allow
  precedence across scopes, hooks vs. permission rules, permission modes
- https://code.claude.com/docs/en/settings — settings precedence (WebFetch summary
  for the general table; the `permissions`-specific precedence text is independently
  and more authoritatively confirmed by the `/en/permissions` fetch above)
- https://code.claude.com/docs/en/memory — CLAUDE.md scope table, managed-policy
  CLAUDE.md deployment path, concatenation-not-override behavior
- See auxiliary: `ops_content_inventory_1.md` — the full per-file/per-section Ops
  utility × sensitivity classification (Eixo A, all six parts)
- See auxiliary: `ops_plugin_capabilities_1.md` — verbatim official-doc excerpts on
  plugin component types, private-repo distribution, and the enterprise
  managed-settings tier

## Central Finding — Can a plugin invert a restrictive base rule?

This is the finding the engineer asked to be treated as the spike's main point,
placed above the model comparison because it determines which of the four models can
actually deliver the "restricted base / TI layer enables" design the engineer wants.

### 1. Permission precedence is exact and documented: deny always wins, from any scope, unconditionally

**Evidence — quote-verified against `https://code.claude.com/docs/en/permissions`,
fetched 2026-07-07:**

> "Rules are evaluated in order: deny, then ask, then allow. The first match in that
> order determines the outcome, and rule specificity doesn't change the order."

> "If a tool is denied at any level, no other level can allow it. For example, a
> managed settings deny can't be overridden by `--allowedTools`, and
> `--disallowedTools` can add restrictions beyond what managed settings define."

> "The same holds across settings scopes: if user settings allow a permission and
> project settings deny it, the deny rule blocks it. The reverse is also true: a
> user-level deny blocks a project-level allow, because deny rules from any scope are
> evaluated before allow rules."

**Significance:** this directly confirms the engineer's suspicion for the literal
scenario they described. **If** the shared core config sets an explicit
`permissions.deny` entry for AWS (e.g. `Bash(aws *)`), **and** every machine — TI's
included — loads that same core config as one of its settings layers, **then no
other layer, including anything a plugin could theoretically contribute, can
override that deny.** Deny-first precedence is unconditional and scope-agnostic. The
"base denies, plugin re-allows" design, taken literally, does not work — confirmed,
not merely suspected.

### 2. Plugins cannot contribute permission rules at all — the question of overriding a deny is moot before it's reached

**Evidence — quote-verified against `https://code.claude.com/docs/en/plugins-reference`
(persisted fetch, `ops_plugin_capabilities_1.md` Source 2):**

> "**Settings**      | `settings.json`              | Default configuration applied
> when the plugin is enabled. Only the `agent` and `subagentStatusLine` keys are
> currently supported"

**Significance:** a plugin's own `settings.json` schema has no `permissions` key at
all. A plugin cannot add an `allow`, `ask`, or `deny` entry, for AWS or anything
else, through its own bundled settings. This means the question "can a plugin's
allow override the core's deny" is moot one level earlier than finding 1 already
shows — plugins are not a permission-rule-contributing mechanism in the first place.
Whatever "the plugin gives TI AWS access" ends up meaning technically, it cannot mean
"the plugin's `settings.json` adds `Bash(aws * describe-*:*)` to `allow`" — that
capability does not exist for plugins.

### 3. The absence-vs-prohibition reconciliation — confirmed as the only design that can work, with an important caveat

**The hypothesis to test**: is there a difference between "the base explicitly denies
infra" (a `deny` rule) and "the base simply has no infra capability" (no AWS-related
`allow` entries, no AWS-related skills, no CLAUDE.md mention) — and if the base is
*absence* rather than *prohibition*, can the plugin genuinely *add* capability without
needing to override anything?

**Evidence on what "no rule matches" resolves to — quote-verified against
`https://code.claude.com/docs/en/permissions`:**

> "| `default`           | Standard behavior: prompts for permission on first use of
> each tool. |"
> "| `dontAsk`           | Auto-denies tools unless pre-approved via `/permissions`
> or `permissions.allow` rules |"

`dot-claude`'s own `settings.json:643` sets `"defaultMode": "acceptEdits"` (verified
by direct read of the file) — a third mode, described as: "Automatically accepts file
edits and common filesystem commands such as `mkdir`, `touch`, `mv`, and `cp` for
paths in the working directory or `additionalDirectories`" — which does not mention
Bash commands generically, so a Bash invocation with no matching `allow`/`ask`/`deny`
rule falls back to the same prompt-based behavior as `default` mode for anything
outside the small `acceptEdits` filesystem-command list.

**Significance:** the reconciliation holds, with one caveat the spike states plainly
rather than glossing over. If the shared core has **no** `aws`-related `allow`/`ask`/
`deny` entries at all (today's actual `dot-claude` `settings.json` has AWS **reads**
in `allow` at lines 531-541 and Terraform **writes** in `ask` at lines 601-618, but
**no explicit `deny` for any `aws` verb** — confirmed by direct read of
`settings.json:644-714`, whose `deny` array covers credential files, `.ssh`, `.aws`
credential *files*, and destructive local commands, never a `Bash(aws ...)` pattern):

- An **absent** rule is not a block. Under `acceptEdits` (4Shark's configured mode),
  a bare `aws s3 ls` Ops might type would still fall through to a permission
  **prompt** — not an automatic denial, not an automatic block. A determined Ops user
  who is prompted can still click "allow", and if their machine happens to hold
  working AWS credentials, the command runs. **The absence design is a soft
  boundary at the Claude Code layer.**
- The mechanism that actually prevents the command from *doing* anything, even if
  approved at the prompt, is external to Claude Code entirely: whether Operations'
  machine's `~/.aws/credentials [default]` profile exists and what IAM policy it
  carries (Axis C, restated below). **This is the real backstop, not the
  permission-rule absence.**
- The plugin genuinely *adds* rather than *overrides* under this design: it adds the
  AWS-aware skills (`apps`, `integrators`, `authenticators`, etc.) as capability
  content, and — separately, since plugins cannot carry permission rules (finding
  2) — TI engineers need the `aws`/`terraform` `allow`/`ask` entries to exist
  *somewhere* they individually load, which is not part of the plugin's own
  manifest.

This is, in the terms the engineer used, the *only* one of the two designs that is
technically sound: **absence-in-the-base + addition-in-the-plugin** is coherent with
how Claude Code plugins actually work; **deny-in-the-base + allow-in-the-plugin** is
not, and is directly contradicted by finding 1.

### 4. CLAUDE.md prose cannot enforce this either way — it is advisory, not mechanical

**Evidence — quote-verified against `https://code.claude.com/docs/en/permissions`:**

> "Permission rules are enforced by Claude Code, not by the model. Instructions in
> your prompt or `CLAUDE.md` shape what Claude tries to do, but they don't change
> what Claude Code allows."

**Evidence — quote-verified against `https://code.claude.com/docs/en/memory`:**

> "If two rules contradict each other, Claude may pick one arbitrarily."

**Significance:** even setting permission rules aside — if the base `CLAUDE.md`
contained a prose sentence like "you do not have infrastructure access" and a
TI-installed plugin injected contradicting prose (which, per Finding 8 below, it
cannot do via CLAUDE.md itself, only via a skill's body once invoked) — the doc's own
troubleshooting guidance says a contradiction between two loaded instruction sources
is resolved by the model **arbitrarily**, not deterministically. This is explicitly
named as non-enforcement: a prose "you may/may not" statement is behavioral guidance
the model tries to follow, never a technical boundary. The only mechanically
deterministic layer is `permissions.allow`/`ask`/`deny` (findings 1-3) and, beneath
that, IAM/credentials (Finding 6, restated below). A design that relies on
contradicting CLAUDE.md prose between a base and a plugin is fragile by the
documentation's own admission, independent of anything about plugins specifically.

### 5. The literal boundary of what a plugin can and cannot change

**Evidence — quote-verified across the fetches above:**

- A plugin CAN add: skills, flat commands, agents (with restrictions — see below), MCP
  servers, LSP servers, monitors, themes, output styles, and its own `hooks/hooks.json`
  which "respond to the same lifecycle events as user-defined hooks"
  (`ops_plugin_capabilities_1.md` Source 2).
- A plugin's own hooks, per `https://code.claude.com/docs/en/permissions`, can only
  ever **tighten**, never loosen: *"Hook decisions don't bypass permission rules. Deny
  and ask rules are evaluated regardless of what a PreToolUse hook returns... This
  preserves the deny-first precedence"* and *"A blocking hook also takes precedence
  over allow rules. A hook that exits with code 2 stops the tool call before
  permission rules are evaluated, so the block applies even when an allow rule would
  otherwise let the call proceed."* A plugin hook can add a **new** block on top of
  whatever the core allows; it cannot make an already-blocked call succeed.
- A plugin-shipped agent explicitly cannot bring its own `hooks`, `mcpServers`, or
  `permissionMode` in its frontmatter — *"For security reasons, hooks, mcpServers, and
  permissionMode are not supported for plugin-shipped agents"*
  (`ops_plugin_capabilities_1.md` Source 2) — closing off a narrower route (an
  individual agent trying to loosen its own permission mode) the same way.
- A plugin CANNOT: ship CLAUDE.md as loaded context (Finding 4 above and
  `ops_plugin_capabilities_1.md` Source 2), add `permissions.allow`/`ask`/`deny`
  entries (Finding 2 above), or, by the deny-first precedence (Finding 1), reverse any
  deny rule that exists anywhere in the settings chain the session loads.

**Significance:** this directly and literally addresses the engineer's own framing —
*"plugin adiciona funcionalidades, não muda comportamento"* is correct, and the
documentation's own security design confirms it is correct **on purpose**: every
mechanism a plugin has (hooks, agent restrictions, settings-key restrictions) is built
to be additive-only in the restrictive direction, never additive in the permissive
direction. A plugin is not a privilege-escalation surface by design.

### Tension surfaced by the amended AWS decision (not resolved here)

With the base excluding AWS/infra access by default, use case #3 as originally stated
— "Claude sees the version running in infra, reads that version's code, tells
Operations whether the code guarantees the client's claim" — is **partially
compromised** for an Operations-only session: Operations can still read code (Axis B,
still open — see below) but cannot independently confirm which version is deployed
where. Two shapes this could take, presented without a recommendation:

- Operations reads the code and asks a TI engineer (or files a request) for the
  currently-deployed version/commit before drawing a conclusion — a manual handoff.
- A narrow, explicitly-scoped read-only capability is added to the base later (e.g. "which
  commit SHA is deployed on `<environment>`" without the broader `apps`/`integrators`
  health-check surface) — a deliberate, scoped exception the engineer would decide on
  its own merits, not a byproduct of this spike's structural analysis.

## Findings — Axis A/B/C content and viability

### Finding 1 — The three axes are genuinely separate, and only one is a `dot-claude` question

**Evidence:** the engineer's own framing separates "an API question, answered by
reading code" from "infra health" from "ticket support crossing both" — none of these
is answered by `dot-claude`'s CLAUDE.md/skills/docs alone.

**Significance:**

- **Axis A — `dot-claude` config/rules** (CLAUDE.md, docs, skills, agents,
  scripts/hooks, `settings.json`, templates). This is what the engineer originally
  asked the spike to evaluate, and it is the only axis a `dot-claude` split can
  actually change.
- **Axis B — read access to the 4Shark application source repos** (`app`,
  `integrator`, `onboarding`, `setup`, and any others Operations' questions touch).
  This is **GitHub repository access**, not a Claude Code configuration question. No
  amount of restructuring `dot-claude` grants or withholds this — it is decided
  separately, by adding (or not adding) Operations' GitHub accounts to the teams that
  can read those repos. Still fully open after this spike — Operations' code-reading
  use case (#1) depends on it and it was not resolved here.
- **Axis C — read access to AWS infrastructure**. Per the amended premise above, the
  engineer has decided the base excludes this by default; the Central Finding shows
  the mechanically sound way to keep that decision technically enforced even after a
  TI plugin is installed is the **absence** design (Central Finding §3), backstopped
  by which IAM user each machine's default AWS profile is bound to (restated in
  Finding 6).

### Finding 2 — Axis A content, by the numbers: roughly 16% of `CLAUDE.md` is Ops-relevant

**Evidence:** per-section classification in `ops_content_inventory_1.md` Part 1. The
sections tagged `OP` (Production Access `CLAUDE.md:238`, Research-First Policy
`CLAUDE.md:498`, Lookup Resolution `CLAUDE.md:656`, Output Policy `CLAUDE.md:668`,
AWS Policy `CLAUDE.md:861`, Command Safety Policy `CLAUDE.md:915`) total roughly 240
of the file's 1498 lines. The remainder is git/PR/commit mechanics, Ruby/Rails/RSpec
code conventions, the DDD/plan/task agent pipeline, and Terraform-repo-specific rules
— none of which Operations' three use cases touch, since Operations does not write
code, does not commit, and does not run the planning pipeline. Note: under the
amended premise, the `Production Access` and `AWS Policy` sections themselves would
need to be **excluded or rewritten** for the Operations base, since they currently
describe read-only AWS access as a given — see Finding 6.

**Significance:** this is direct, line-counted evidence for the engineer's own
diagnosis ("vai mais confundir que ajudar") — a raw `dot-claude` install would put
~84% irrelevant rule surface in front of Operations from the first prompt, and per
`ops_content_inventory_1.md` Part 6, `scripts/read-context.sh`
(`settings.json:22,64` wiring) mechanically **inlines every Tier 1 + Tier 2 doc into
every session and subagent start regardless of who is running it** — so this is not
merely a discoverability annoyance, it is unconditional context injection of
Rails/RSpec/DDD material for a team that never touches Ruby.

### Finding 3 — A handful of docs/skills are exactly on-target for the health-check use case

**Evidence:** `ops_content_inventory_1.md` Part 2/3 marks `AUTHENTICATION-ARCHITECTURE.md`,
`DATA-STORES-ARCHITECTURE.md`, `WHITE-LABEL-ARCHITECTURE.md`, and
`ECS-SERVICE-TOPOLOGY.md` as `OP`/`NORM`. `ECS-SERVICE-TOPOLOGY.md:9`: *"The failure
this prevents: reading a service at `desiredCount=0` and concluding"* (continues at
line 10) *"'the environment is down' when it is not."* — this is precisely
Operations' health-check use case (#2), and is already cross-referenced from the
`apps` skill (`skills/apps/SKILL.md:90`: *"Full concept:
`~/.claude/docs/ECS-SERVICE-TOPOLOGY.md`"*). Similarly `skills/apps/SKILL.md`,
`skills/integrators/SKILL.md`, `skills/harvesters/SKILL.md`,
`skills/authenticators/SKILL.md`, `skills/connection-poolers/SKILL.md`,
`skills/onboarding/SKILL.md`, `skills/setup/SKILL.md`, and `skills/ec2-instances/SKILL.md`
are all read/list/log operations against ECS clusters and EC2 instances.

**Significance:** all of this content is exactly what the amended AWS premise now
excludes from the default base (Central Finding, tension callout). Under the
"absence in the base" design, these eight skills and four architecture docs are
precisely the kind of content that belongs in the **TI plugin**, not the base — they
are AWS-touching by construction (every one of them calls `aws ecs describe-*` /
`aws logs tail` / the `ecs-scale.sh` wrapper). If the engineer later decides
Operations should retain the health-check use case (#2) despite the amended AWS
decision, that is a deliberate exception to record explicitly, not an automatic
consequence of "these docs are operationally useful" — usefulness and the new
security premise now point in different directions for this specific content,
unlike the rest of the inventory (Finding 5).

### Finding 4 — The customer-ticket use case (#3) already needed a capability `dot-claude` does not package as read-only

**Evidence:** the closest existing tool is `skills/integration-debug/SKILL.md`, which
explicitly generates **mutation** scripts against production Rails console / MongoDB
(`skills/integration-debug/SKILL.md:11`: *"Phase 2 (Execution) — manual,
non-negotiable. Mutations to integrator MongoDB and app RDS always go through the
engineer pasting hand-written scripts into `bin/ecs run`"*), and requires reading
`app`/`integrator` repo code from `origin/master`
(`skills/integration-debug/SKILL.md:43`: *"Always read integrator code from
`origin/master`... Read files via `git -C ~/Projects/4Shark/integrator show
origin/master:<path>`"*) — i.e. it already assumes local clones of those repos exist
(Axis B).

**Significance:** use case #3 was never a fully-solved read-only flow in
`dot-claude` even before the amended AWS decision — no existing skill packages "read
infra version → read matching code → answer a yes/no contract question" as pure
investigation. The amended decision removes the infra-reading half of that gap
entirely from the default base (tension callout above); the code-reading half
remains a genuine Axis B gap regardless.

### Finding 5 — Sensitive material in `dot-claude` clusters around three sources, and is separable from the operational content

**Evidence:** `ops_content_inventory_1.md` flags `SENS` on: `JURISDICTION.md`
(`docs/JURISDICTION.md:31-58`, a live client-name × backend × jurisdiction table),
`runbooks/compliance/LGPD-DATA-ERASURE.md` (internal Google Sheet links, mailbox
owner names, single-owner-CTO process note at line 22-30), and the
`client-onboarding/*` runbooks (SSO client secrets, integrator client creation). One
borderline case: `runbooks/security/SEARCHING-ACCOUNT-EVENTS.md` and the matching
`CLAUDE.md:244` section — not client-identifying, but a security-investigation
capability (CloudTrail audit) the engineer may or may not want Operations defaulting
into (moot under the amended AWS decision, since it requires AWS access the base no
longer grants by default).

**Significance:** none of the three confirmed-sensitive sources overlaps with the
`OP`-tagged, non-AWS content (Research-First Policy, Output Policy, Command Safety,
Lookup Resolution) that survives the amended premise — the sensitive material is
concentrated in client-onboarding, compliance, and jurisdiction docs that Operations'
code-reading use case (#1) never needs to touch.

### Finding 6 — Axis C (AWS infra), restated under the amended premise

**Evidence:** `~/.claude/docs/AWS-MFA.md:7`: *"Default profile — read-only access for
day-to-day operations"*; `CLAUDE.md:861-870` (AWS Policy) and
`settings.json:531-541` show the `permissions.allow` list pre-approving only
`describe-*`/`get-*`/`list-*`/`wait`/`logs tail` shapes, while
`settings.json:601-641` (`ask`) gates `terraform apply/destroy/import/taint/...`.
Elevation to write access requires a **separate, per-engineer 1Password TOTP item**
named `"Amazon AWS - <Name>"` plus a registered MFA device on that IAM user
(`~/.claude/docs/AWS-MFA.md:118-126`).

**Significance:** under the amended premise, this entire finding describes **TI's**
setup, not Operations'. For Operations, per Central Finding §3, the intended design
is that Operations' machine either (a) has no AWS default-profile credentials
configured at all, or (b) has credentials scoped to nothing (or a policy the engineer
explicitly decides), so that even the soft "prompted, could click allow" gap in the
Claude Code permission layer resolves to an actual `AccessDenied`/no-credentials
failure if ever triggered. This is an IAM/1Password provisioning decision, external
to `dot-claude`, that the engineer still needs to make explicitly for Operations'
machines — the spike surfaces it as a decision, not a default that falls out of
`dot-claude` alone.

### Finding 7 — Claude Code's settings/CLAUDE.md loading model supports selective installs, but the mechanism differs by content type

**Evidence:** per `ops_plugin_capabilities_1.md` Source 5 / this spike's own memory
fetch, CLAUDE.md files load from four scopes in a fixed order (managed policy → user
`~/.claude/CLAUDE.md` → project → local), and *"All discovered files are concatenated
into context rather than overriding each other."*

**Significance:** there is no native Claude Code mechanism to give one user a
*subset* of a single `~/.claude/CLAUDE.md`/`settings.json` file — the file at
`~/.claude/` is loaded whole, every session, for whoever's machine it lives on.
Selectivity has to happen **before** that file is written to `~/.claude/` — i.e. by
controlling *what gets installed/cloned* per person (Models 1-3), or by moving content
out of CLAUDE.md into skills, which genuinely do load selectively (on invocation or
when Claude judges relevance) rather than unconditionally (Model 4, with the caveat in
Finding 8).

### Finding 8 — Model 4 (plugin) is technically real for skills/agents/hooks, but CLAUDE.md and the Bash permission surface cannot be plugin-ized

**Evidence:** `ops_plugin_capabilities_1.md` Source 2, quoting the official Plugins
Reference verbatim: *"A CLAUDE.md file at the plugin root is not loaded as project
context. Plugins contribute context through skills, agents, and hooks rather than
CLAUDE.md."* And on settings: *"Only the `agent` and `subagentStatusLine` keys are
currently supported"* for a plugin's own `settings.json` (also cited in the Central
Finding §2).

**Significance:** this is the load-bearing technical fact for Model 4, and it is what
makes the Central Finding's "absence design" necessary rather than optional. What a
plugin *can* carry cleanly: skills (`SKILL.md`), agents (with restrictions), hooks
(additive-restrictive only, per Central Finding §5), and slash commands. `dot-claude`
today uses exactly these four component types and no MCP/LSP/monitor/theme components
(`ops_plugin_capabilities_1.md` finding 1) — so the skill/agent/hook/command layer of
`dot-claude` is plugin-izable in principle, but the CLAUDE.md rule surface and the
Bash allow-list are not, and would need a different, file-level splitting mechanism
regardless of whether the plugin route is taken for the rest.

### Finding 9 — The realistic access-control mechanism for a "TI-only" plugin is a private GitHub repo, which 4Shark already uses for exactly this purpose elsewhere

**Evidence:** `ops_plugin_capabilities_1.md` Source 3, quoting verbatim: *"Claude Code
supports installing plugins from private repositories. For manual installation and
updates, Claude Code uses your existing git credential helpers, so HTTPS access via
`gh auth login`... works the same as in your terminal."* 4Shark's own
`docs/PROJECTS-CATALOG.md:114`: *"These two repos are owned by **secret** GitHub
teams (access-restricted)"* (referring to `compliance` and `data-privacy`, listed at
lines 116-119).

**Significance:** the mechanism that would actually gate "only TI can install this
plugin" is GitHub repository read access via a secret/restricted GitHub team — not a
Claude Code permission feature. This is a pattern 4Shark has already operationalized
twice. It requires no new infrastructure beyond creating a `dot-claude-ti` (or
similarly named) private repo and a restricted team, exactly mirroring the existing
`compliance`/`data-privacy` precedent. Note this control gates **installation**
(whether the plugin's skills/agents/hooks exist on TI's machine at all), which is a
separate, and — per the Central Finding — the *only* real, mechanically-backed
control available without new MDM infrastructure; it does not and cannot touch
permission rules (Central Finding §2).

### Finding 10 — The enterprise-tier plugin controls the engineer asked about exist, but require new infrastructure 4Shark does not run today

**Evidence:** `ops_plugin_capabilities_1.md` Source 3/5 — `strictKnownMarketplaces`
and the `enabledPlugins` managed-scope enforcement are *"set in [managed
settings]"*, deployed as a `managed-settings.json`/`managed CLAUDE.md` file at an
OS-level system path (`/Library/Application Support/ClaudeCode/` on macOS,
`/etc/claude-code/` on Linux/WSL, `C:\Program Files\ClaudeCode\` on Windows) that
*"typically requires administrator or root access"* per the fetched settings-page
summary, or via MDM/server-managed delivery tied to a `claude.ai` admin console.
Separately, `allowManagedPermissionRulesOnly` — *"When `true`, prevents user and
project settings from defining `allow`, `ask`, or `deny` permission rules. Only rules
in managed settings apply"* (quote-verified, `https://code.claude.com/docs/en/permissions`)
— is the enterprise setting that would let an administrator enforce that **only** a
centrally-managed permission file decides AWS access, closing the "soft
prompt-and-click-allow" gap named in Central Finding §3 entirely, if 4Shark ever
stands up managed settings.

**Significance:** 4Shark's current distribution model — each engineer running
`git clone` into `~/.claude` — is entirely at the **user** settings scope, not the
**managed** scope. Reaching for `strictKnownMarketplaces`/`allowManagedPermissionRulesOnly`
would require standing up MDM or root-level file deployment across every machine (a
materially larger operational project than a private repo), and it was **not
confirmed in this spike** whether 4Shark's current Claude Code plan/subscription tier
exposes the admin console this requires at all — flagged as an open question below,
not asserted either way. Without it, the absence-design's soft gap (Central Finding
§3) is the practical ceiling of what Claude Code's own permission system enforces;
the IAM/credentials layer (Finding 6) remains the actual backstop.

### Finding 11 — Slicing `dot-claude` breaks assumptions baked into the current hooks, independent of which model is chosen

**Evidence:** `ops_content_inventory_1.md` Part 6: `scripts/read-context.sh`
unconditionally inlines Tier 1 + Tier 2 docs on every `SessionStart`/`SubagentStart`
(`settings.json:22,64`) — if a curated Ops config removes some of those docs from
disk without also updating (or having an already-generic) `read-context.sh`, the
hook will either error on a missing file or silently produce a smaller inlined
context, depending on how it is written (not verified in this spike — the script's
own tolerance for missing Tier 1/2 files was not read in full). Several
AWS-touching skills (`apps`, `integrators`, `onboarding`, `setup`, `authenticators`,
`connection-poolers`, `ec2-instances`) all invoke the **shared** wrapper
`~/.claude/scripts/ecs-scale.sh` (e.g. `skills/apps/SKILL.md:106`) and
`start-instance.sh`/`stop-instance.sh` — these scripts live in the common
`scripts/` directory alongside the DEV-only ones (Rails/Terraform hooks).

**Significance:** none of the four models below is a clean, zero-risk file copy.
Under the amended premise, this finding matters most for **Model 4**: since the
AWS-touching skills now belong in the TI plugin (Finding 3), the plugin needs its own
copy of (or a path back to) `ecs-scale.sh`/`start-instance.sh`/`stop-instance.sh`
rather than assuming the core `scripts/` directory — which, under the absence design,
would no longer ship these AWS-write wrappers to Operations at all — is always
present at the fixed path the skill's `SKILL.md` currently hard-codes.

## Trade-offs surfaced — Decision matrix (options × criteria)

**Re-framed per the Central Finding**: the decisive new criterion is whether a model
can deliver "base restricted (no AWS by default) / TI layer enables (has AWS)"
without relying on a deny-then-override design the Central Finding shows does not
work.

| Criterion | Model 1 — Separate repo (`dot-claude-ops`) | Model 2 — Subset install of same repo | Model 3 — Same repo, same config for everyone | Model 4 — Minimal universal core + TI-only plugin |
|---|---|---|---|---|
| **What it is** | New repo with a curated subset (enxuto CLAUDE.md + operational skills + operational runbooks, AWS-touching content excluded per the amended premise), cloned to Ops' `~/.claude/` instead of `dot-claude` | Ops clones/installs `dot-claude` but only a chosen subset of files is written to `~/.claude/` | Ops gets the exact same `~/.claude/` as TI, no filtering | A minimal `CLAUDE.md`/`settings.json`/skill set (no AWS content) ships to everyone; the DEV-only material AND the AWS-touching skills/docs ship only as a TI plugin, private-repo-gated |
| **Can it deliver "base restricted / TI enables" without a deny-override design?** | **Yes, trivially.** Ops's and TI's `settings.json`/CLAUDE.md are two genuinely different files from the start — there is no shared file where a deny could even need overriding. TI simply has a config that always included the AWS `allow` entries | **Yes, trivially**, same reasoning as Model 1 — the two installed file sets are independently assembled, not one file layered with an override | **No — by construction.** One config means one capability set; there is no "restricted base" in this model at all | **Yes, but only via the absence design (Central Finding §3), and only for the skill/agent/hook/command layer.** The Bash `allow`/`ask` entries for AWS still cannot live in the plugin (Finding 2/8) — they need a TI-specific settings layer *outside* the plugin mechanism, meaning Model 4's "plugin" is necessarily paired with a second, narrower Model-1/2-style split applied just to `settings.json`'s permission block |
| **Technical viability** | High — plain git repo, same install pattern (`git clone` to `~/.claude`) already documented in `README.md:14-20` | Medium — no existing selective-install script; would need to be built | Trivial — zero new work, but see previous row | Partial — skills/agents/hooks/commands ARE plugin-izable (Central Finding §5); CLAUDE.md and the Bash `permissions.allow` list are NOT, confirmed twice over (Finding 8, Central Finding §2) |
| **Maintenance cost (keeping the surfaces in sync)** | Highest — every universal rule change (Output Policy, Command Safety, credential handling) must be applied and kept identical in two independent repos by hand | Medium — one repo, one source of truth; the selective-install step needs re-syncing whenever the subset definition changes | Lowest — one repo, one config, nothing to keep in sync | Medium-high — one repo can hold both the shared core and the plugin subtree, so universal rules are edited once; but the plugin's components are versioned/cached independently (`~/.claude/plugins/cache`) and the *separate* settings-permission split (previous row) still needs manual sync the same way Model 1/2 do, just for a narrower slice |
| **Real strength of the access control** | Strong and simple — a private GitHub repo Ops literally cannot clone without repo access; identical mechanism to `compliance`/`data-privacy` (Finding 9) | None inherent — same repo-read access as TI; the "control" is only the install script choosing not to write certain files | None — by construction | Strong for the plugin-packaged skill/agent/hook/command layer (same private-repo gate as Model 1, Finding 9); the AWS permission-rule layer's real strength is capped at the "soft, prompt-then-click, credential-backstopped" ceiling described in Central Finding §3 **unless** 4Shark separately stands up managed settings (Finding 10) — a materially bigger project |
| **Fit to Operations' stated use case, under the amended premise** | Good — new repo purpose-built around Findings 2/5 (the non-AWS `OP`-tagged content), explicitly excludes the AWS-touching skills now reserved for TI | Good — same end state as Model 1 without a second repo, if the subset is defined the same way | Poor — floods Operations with ~84% DEV-only content (Finding 2) AND grants AWS access the engineer explicitly decided against | Good for the shared-core content (universal rules guaranteed identical for both teams); requires the extra settings-permission split (this table's first row) to fully honor the amended AWS decision — not automatically covered by "install the plugin on TI's machine" alone |
| **Risk of leaking sensitive material** | Low — sensitive docs (Finding 5) and AWS-touching skills (Finding 3) are simply never copied into the new repo | Low, contingent on the selective-install step being correctly maintained as `dot-claude` grows | High — `JURISDICTION.md`'s live client map, the LGPD runbook, `SEARCHING-ACCOUNT-EVENTS.md`, and full AWS access all ship as-is | Low for whatever is packaged as the TI-only plugin (same private-repo gate as Model 1); the residual risk is the same "soft prompt-approval" ceiling noted above if the engineer expects the plugin boundary alone to be airtight against AWS |
| **New engineering effort required** | Low-medium — create the repo, port the `OP`-tagged, non-AWS content (Findings 2/3/5) | Low-medium — design and build the selective-install mechanism (does not exist today) | None | Medium-high — (a) build a proper `.claude-plugin/plugin.json`-structured plugin for the skills/agents/hooks/commands, (b) **still** solve the settings-permission split via a Model-1/2-style mechanism for just `permissions.allow`/`ask`, since the plugin cannot carry it, (c) learn/operate a distribution mechanism (`marketplace.json`, private repo team, `/plugin install`) 4Shark has never used before |

## What remains uncertain

- Whether 4Shark's current Claude Code subscription/plan tier exposes the `claude.ai`
  admin console needed for **server-managed** settings delivery, which would let
  `allowManagedPermissionRulesOnly` close the "soft prompt-approval" gap in Central
  Finding §3 entirely — not confirmed in this spike; only the file-based
  `managed-settings.json` path (which requires per-machine root/admin file
  deployment) was independently verified.
- Whether `scripts/read-context.sh` degrades gracefully (skips missing files) or
  errors when a Tier 1/2 doc referenced in the script is absent from disk — the
  script's own error-handling was not read in full for this spike (Finding 11); this
  determines whether Model 1/2/4's core config needs a *modified* `read-context.sh`
  or can reuse the existing one unchanged.
- Whether `skills/integrators/SKILL.md`'s referenced `environments.json` (a per-skill
  data file, not opened in this spike) contains client names or other `SENS`-tagged
  content — flagged in `ops_content_inventory_1.md` Part 3 as unaudited.
- How the engineer wants to resolve the tension surfaced above: use case #3 (customer
  tickets crossing code + infra) is now structurally incomplete for an Operations-only
  session under the amended AWS decision — this spike surfaces the two possible
  shapes (manual TI handoff, or a narrow scoped exception) without choosing.
- The exact GitHub-team / IAM-user provisioning steps for Axis B and Axis C (Findings
  1, 6) were named as decisions the engineer still needs to make; this spike does not
  propose a specific team name, repo name, or IAM policy document.

## Suggested options for main and the engineer

- **Option A (Model 1) — New `dot-claude-ops` repo**: purpose-built, curated minimum
  (no AWS content per the amended premise), private-repo access control proven at
  4Shark already (`compliance`/`data-privacy`). Trivially delivers the
  "base-restricted / TI-enabled" property because the two configs were never one
  file to begin with. Trade-off: manual sync burden on every universal-rule change
  going forward.
- **Option B (Model 2) — Selective install from the existing `dot-claude` repo**:
  single source of truth, no second repo, same trivial delivery of the
  restricted/enabled split as Model 1, but the selective-install mechanism does not
  exist yet and would need to be designed and built.
- **Option C (Model 3) — Same repo, same config for both teams**: zero new work, but
  cannot deliver the amended AWS decision at all (by construction, one config = one
  capability set) and ships the confirmed-sensitive docs (Finding 5) to Operations
  as-is.
- **Option D (Model 4) — Minimal universal core (everyone) + TI-only plugin
  (private-repo-gated)**: keeps universal, non-AWS rules (credentials, Output Policy,
  Command Safety) in exactly one shared place for both teams; the DEV-only and
  AWS-touching skills/agents/hooks/commands become a genuinely plugin-packaged,
  access-controlled bundle for TI. **Does not, by itself, fully satisfy the
  "base-restricted / plugin-enables" design for the permission-rule layer** — the
  Central Finding shows the AWS `allow`/`ask` Bash entries cannot travel inside the
  plugin and need a second, narrower Model-1/2-style mechanism layered on top of just
  `settings.json`'s permission block. This is the newest mechanism of the four,
  requires 4Shark to learn/operate the Claude Code plugin system for the first time,
  and is not a single clean solution but a hybrid of "true plugin" (for capability)
  plus "narrow file split" (for permissions).

No option is recommended here — the engineer decides based on which criteria in the
decision matrix carry the most weight (sync-drift risk vs. proven-mechanism speed vs.
zero-effort-now vs. single-shared-core guarantee for universal rules), and separately
decides the Axis B (GitHub repo access) and Axis C (IAM read-only/no-access user)
provisioning that every option still requires regardless of which Axis-A model is
chosen, plus how to resolve the use-case-#3 tension the amended AWS decision surfaced.
