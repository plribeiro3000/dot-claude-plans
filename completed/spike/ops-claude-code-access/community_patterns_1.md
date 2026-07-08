# Community Patterns — How Others Distribute AI Assistant Intelligence Across Teams with Different Access Levels

Auxiliary research note to `SPIKE.md`, NOT a revision of it. Written on explicit
engineer request: before fixing any design for splitting `dot-claude` between the TI
and Operations teams, find out how the broader community — Claude Code specifically,
but also ChatGPT/GPT, and the wider AI-agent-security community — actually solves
this in practice today, versus everyone inventing their own approach.

**Research question (verbatim from the engineer):** *"How are people sharing the
INTELLIGENCE (config/prompts/skills/agents/knowledge) of an AI coding assistant —
Claude Code especially, but also ChatGPT/GPT — between teams with DIFFERENT needs and
access levels, specifically an IT/engineering team vs. an Operations/support team? Is
there a CONSOLIDATED PATTERN in the community, or is everyone inventing their own?"*

This document does not decide anything and does not revise `SPIKE.md`. It reports
what was found, cites every claim, and states plainly where the community has not
covered the exact scenario 4Shark is in.

## Citation Discipline applied

Every Finding below carries a URL, a verbatim quote, and a verification block. Where
a fetch returned `403 Forbidden` or produced no substantive content, it is marked
**UNVERIFIED** and is not used to sustain any conclusion — only reported as "search
engines indexed X but the primary source could not be fetched directly."

---

## Q1 — Is there a NAMED, consolidated pattern for role-based/profile-based AI assistant config distribution?

### Finding 1 — Engineering-focused Claude Code enterprise rollout guides do not name or address role-based config distribution at all

**Evidence:** fetched `https://systemprompt.io/guides/claude-code-organisation-rollout`
(an independent "Claude Code Enterprise Rollout Playbook for 50+ Developers") and
searched its content for the four elements the engineer asked about. Direct fetch
result: *"The playbook treats the organization as a homogeneous developer population
expanding in phases, not as distinct functional roles requiring separate
configurations."* The one differentiation the guide does name is per-**project**, not
per-**role**: *"Permission modes can also be set per-project using
`.claude/settings.json` in the project root. This lets different projects have
different risk profiles."*

Separately, fetched `https://www.eesel.ai/blog/admin-controls-claude-code` (a
"complete guide for IT and DevOps teams"). Direct fetch result: *"The guide focuses
narrowly on IT/DevOps governance for engineering organizations using Claude Code, not
on cross-functional or multi-team access patterns."*

**Significance:** two independently-authored, fairly comprehensive third-party
enterprise-rollout guides for Claude Code — the genre of content that would name a
pattern if one existed — do not address "give a non-engineering team a different,
restricted Claude Code config" at all. This is negative evidence, not proof of
absence, but it is evidence from exactly the content category where a named pattern
would most likely surface.

**Verification:** both URLs fetched 2026-07-07; both quotes are the tool's direct
summary of the fetched page content (not searched-engine paraphrase), each stating
explicitly that the requested topic is absent from the source.

### Finding 2 — The most visible OSS tool for "Claude Code config per context" solves a different problem (personal work-context switching) with the exact self-declaration mechanism the engineer already rejected

**Evidence:** fetched `https://github.com/blackwell-systems/dotclaude` — described in
search results as *"The definitive profile management system for Claude Code. Manage
configurations across different work contexts."* Direct fetch of the README:

> "Stop manually editing `~/.claude/CLAUDE.md` every time you switch projects."

> "Each profile merges your base configuration with project-specific additions - no
> duplication across profiles."

Profile activation, quoted from the README's own example:

> "# Morning: OSS work
> dotclaude activate my-oss-project
>
> # Afternoon: Client work
> dotclaude activate client-work"

**Significance:** this is the closest thing the OSS community has produced to a named
"profile management system" for Claude Code, and its access model is **exactly** the
installer-with-flag pattern the engineer already rejected — the user runs `dotclaude
activate <profile>` and the tool trusts that self-declaration completely. The tool's
own scope is explicitly personal (switching between OSS/client/employer contexts for
one person on one machine), not a multi-party, different-trust-level scenario. It
does not claim to, and does not, solve access *control* — only configuration
*convenience*. This is a concrete, named, real-world instance of the exact failure
mode the engineer flagged, existing in the wild.

**Verification:** URL fetched 2026-07-07 (`github.com/blackwell-systems/dotclaude`,
README content); every quote above is a verbatim substring of the fetched README as
returned by the fetch tool. Note: a separate fetch of the project's docs site
(`blackwell-systems.github.io/dotclaude/`) returned only a loading placeholder with no
substantive content — that specific URL is UNVERIFIED and not used to sustain any
claim above; the GitHub README fetch is the sustaining source.

### Finding 3 — No design-pattern name (analogous to "RBAC" or "gateway") has been coined specifically for AI-assistant-config-by-team; vendors and the community reuse general access-control vocabulary instead

**Evidence:** across every source fetched for this document (Findings 1-9), no
source uses a specific coined term for this scenario. The vocabulary used is always
borrowed from general security practice: "least privilege," "role-based access
control (RBAC)," "group-level permissions," "defense in depth," "zero trust." The
closest thing to vendor-specific naming is Anthropic's own product terminology for
its enterprise plugin visibility controls (Finding 6) — "group-level override," "org-wide
installation preference" — which are feature names inside Claude's own admin console,
not a portable pattern name the wider community has adopted.

**Significance:** this directly answers the engineer's Q1. There is no consolidated,
named pattern the way "blue-green deployment" or "circuit breaker" are named
patterns. The vocabulary in use is the pre-existing general RBAC/least-privilege
vocabulary, applied ad hoc to this specific AI-assistant-config case by whichever
vendor or blog author is writing about it.

**Verification:** this is a synthesis across the sourced findings below, not a single
quote; each contributing source is independently cited in its own Finding.

---

## Q2 — How do teams do "one source of truth + team-specific cuts"? Monorepo with layering? Enterprise managed settings? Internal marketplaces? Trade-offs discussed?

### Finding 4 — Anthropic's own answer, shipped as a product feature: one org-wide default per plugin, with per-group overrides, backed by IdP groups — not a config-layering convention the community converged on independently

**Evidence:** fetched `https://support.claude.com/en/articles/13837433-manage-claude-cowork-plugins-for-your-organization`
(re-fetched twice for self-check, same result both times):

> "For each plugin, you can set one of four options: Installed by default, Available
> for install, Not available, Required."

> "Enterprise admins can override a plugin's organization-wide installation
> preference for specific groups."

> "When you set a group-level override for a plugin, it replaces the org-wide setting
> for members of that group."

> "For example, you can auto-install a plugin for the Engineering group, make it
> available for Legal to install on their own, and hide it from everyone else."

> "Members can't edit organization-managed plugins, which prevents conflicting
> changes to shared tooling."

**Significance:** this is a literal, first-party example naming "Engineering" as one
group and a different department ("Legal") as another, each with a different
plugin-visibility outcome — structurally identical in shape to 4Shark's TI-vs-Operations
split. It is the single closest match found in this research to the engineer's exact
scenario. Two qualifications matter: (a) this is a **Claude Cowork/Enterprise**
product feature, not a general Claude Code CLI mechanism available to a `git clone`-based
individual/Pro setup — see Finding 8 on the plan-tier gate; (b) the "group" in "group-level
override" is not admin-typed ad hoc — see Finding 5.

**Verification:** URL fetched 2026-07-07, re-fetched a second time to confirm the two
load-bearing quotes ("auto-install... hide it from everyone else" and "Members can't
edit organization-managed plugins") were still present verbatim on re-fetch — both
confirmed identical on both fetches.

### Finding 5 — The "group" in Anthropic's group-level plugin control is backed by SCIM/IdP sync, not a self-declared or admin-freehand label

**Evidence:** WebSearch results (not a single-page fetch, but converging across
several independently-indexed Claude Help Center articles reachable via search)
report:

> "SCIM provisioning is available on Enterprise plans and eligible Console
> organizations only. Both JIT and SCIM can be combined with Enable group mappings to
> control role or seat tier assignment based on IdP group membership."

> "Create groups in your IdP for each role you want to assign."

**Significance:** the group an org-level plugin override targets is not a label an
admin types once per user by hand — it is synced from the company's own identity
provider (Okta, Entra ID, etc.), i.e. from an external, already-authenticated source
of truth about who belongs to which team. This is the mechanism-level answer to the
engineer's Q4 (see also Findings 7 and 9 below): the community/vendor answer to "how
do you stop a user from self-declaring their own access level" is **don't let the AI
tool's own config decide it at all — derive it from the company's existing identity
system**, the same system that already knows who is on the TI team and who is on the
Operations team.

**Verification:** these two quotes come from WebSearch's synthesis across indexed
`support.claude.com` SCIM/Okta articles, not a single verbatim page fetch (the direct
`help.openai.com`/`support.claude.com` article URLs for SCIM setup returned `403
Forbidden` on direct WebFetch attempts during this research — see the UNVERIFIED note
below). **Confidence caveat**: because this rests on search-engine synthesis rather
than a directly fetched and re-confirmed page, it is reported with slightly lower
confidence than Finding 4, but is corroborated independently by Finding 9 (Anthropic's
own engineering blog on containment philosophy) reaching the same conclusion from a
completely different document.

**UNVERIFIED note:** direct WebFetch of `help.openai.com/en/articles/8266401-...`
(ChatGPT Enterprise roles/seats) and `help.openai.com/en/articles/8798878-...`
(sharing/publishing GPTs) both returned `403 Forbidden` during this research. Their
content is **not used to sustain any Finding** in this document — search-engine
summaries suggested ChatGPT Enterprise has an analogous "share a GPT with specific
groups" mechanism, but this could not be independently verified by a direct fetch and
is therefore excluded from the findings above rather than asserted on secondhand
authority.

### Finding 6 — No source found describes a monorepo-with-layering convention (a shared base file + team-specific override files, git-merged) as an established practice for AI assistant config specifically

**Evidence:** none of the fetched sources — the two Claude Code enterprise rollout
guides (Finding 1), the plugin marketplace documentation (Finding 4), or the dotclaude
tool (Finding 2) — describe a git-native "base config + per-team override files merged
at build/install time" pattern. The closest adjacent concept found is dotclaude's own
"layered composition" (Finding 2: *"Each profile merges your base configuration with
project-specific additions - no duplication across profiles"*), but that layering is
explicitly for one person's own personal profiles, selected by that same person, not
for enforcing a boundary between two different people/teams with different trust
levels.

**Significance:** this is a genuine gap, not merely something this research missed —
the three closest-adjacent sources found (enterprise rollout guides, the vendor's own
enterprise plugin-visibility feature, and the most popular OSS config-layering tool)
each either don't address it or solve a different problem. A monorepo-with-layering
scheme for *this specific* purpose (config for two differently-trusted teams) does not
appear to be documented community practice — it would be, if attempted, a novel
construction rather than an adoption of an established pattern.

**Verification:** absence-of-evidence finding across the sources already cited in
Findings 1, 2, and 4 above; no new URL to verify.

---

## Q3 — Has anyone documented giving an AI assistant to a NON-DEV team (ops/support/CS) with restricted scope, and HOW they did least-privilege?

### Finding 7 — Anthropic's own Claude Cowork product ships an "Operations" plugin bundle as a named peer to "Engineering" — content-tailored, not confirmed to be security-scoped

**Evidence:** fetched `https://claude.com/blog/cowork-plugins-across-enterprise`:

> "New plugins include: HR, Design, Engineering, Operations, Brand voice, Financial
> analysis, Investment banking, Equity research, Private equity, Wealth management."

> Each was "designed with practitioners in the relevant field, so workflows,
> terminology, and outputs reflect how that work actually gets done."

> "Admins get more control over what plugins their teams can access, including
> org-specific marketplaces, private GitHub repositories as plugin sources (in
> private beta), per-user provisioning, and auto-install."

**Significance:** this is the most directly on-point first-party example found:
Anthropic itself treats "Operations" as a distinct, named plugin bundle alongside
"Engineering" — structurally the exact TI-vs-Operations split 4Shark is designing
for. Two important limits on how far this finding reaches: (a) the fetched content
emphasizes **content/workflow tailoring** ("workflows, terminology, and outputs
reflect how that work actually gets done"), not an explicit statement that the
Operations bundle carries *fewer infrastructure permissions* than the Engineering
one — this document does not claim Anthropic solved the security-scoping half of the
problem, only that the department-differentiated-bundle half is a shipped,
documented pattern; (b) *"private GitHub repositories as plugin sources"* — the
mechanism this spike's own `SPIKE.md` central finding relies on for a TI-only plugin
— is explicitly labeled **"(in private beta)"**, i.e. not generally available at the
time of this fetch.

**Verification:** URL fetched 2026-07-07; every quote above is a verbatim substring
of the fetched page.

### Finding 8 — This mechanism requires Claude's paid Team/Enterprise tier and SCIM/IdP integration — not available to a plain `git clone`-based individual/Pro setup

**Evidence:** synthesized from Finding 5 (*"SCIM provisioning is available on
Enterprise plans and eligible Console organizations only"*) and Finding 4's framing
("Enterprise admins can override..."), both naming Enterprise-tier features.

**Significance:** this directly parallels and corroborates `SPIKE.md`'s own Finding
10 (written before this research phase): the enterprise-tier mechanism that would
give 4Shark a clean, identity-backed answer to "which team gets which plugins"
requires infrastructure (a Claude Team/Enterprise plan, SCIM/IdP sync) that 4Shark's
current git-clone-to-`~/.claude/` distribution model does not have. This research
phase does not resolve whether 4Shark's plan tier includes this — it independently
confirms the SPIKE's own open question is the correct one to be asking, from a
completely separate research pass.

**Verification:** derived from Findings 4 and 5 above; no new URL.

---

## Q4 — How does the community solve "the user cannot self-declare their own access level" (the installer-with-flag gap the engineer already flagged)?

### Finding 9 — Anthropic's own security engineering team states the general principle directly: containment must live in the environment/credential layer, never in the model or the user-facing instruction layer

**Evidence:** fetched `https://www.anthropic.com/engineering/how-we-contain-claude`:

> "Credentials stay in the host keychain, the VM gets a per-session scoped-down
> token"

> "When the user is the one typing the instruction, there's nothing anomalous for a
> classifier to catch."

> "Defenses should overlap and complement each other. When environmental defenses
> aren't available, the model layer has to pick up the slack."

> "Design for containment at the environment layer first, then steer behavior at the
> model layer."

**Significance:** this is Anthropic's own official engineering position, independent
of the Claude Code permissions documentation this spike's `SPIKE.md` already cites —
it converges on the identical conclusion from a different document and a different
team's writing: a boundary that depends on the user (or the tool's config) declaring
their own trust level is not a real boundary, because a legitimate-looking request
from the person actually typing it looks the same whether or not they should be
allowed to make it. The environment (credentials, host-level scoping) has to do the
actual work; instructions (CLAUDE.md, a flag, a prompt) are, at best, a secondary
layer that "picks up the slack" when the environmental layer cannot cover a case —
never the primary mechanism.

**Verification:** URL fetched 2026-07-07; all four quotes are verbatim substrings of
the fetched page as returned by the fetch tool.

### Finding 10 — The wider AI-agent-security community names the same principle via the "AI agent gateway" pattern: identity must come from an external, already-authenticated system, never from the agent or a self-asserted role

**Evidence:** fetched `https://www.infoq.com/articles/building-ai-agent-gateway-mcp/`
(InfoQ, describing an MCP + Open Policy Agent + ephemeral-runner architecture):

> "Agents never interact with infrastructure APIs directly. Instead, every request
> passes through a centralized gateway that validates intent, enforces authorization
> rules"

> "The actor identity is extracted from JWT/mTLS" before policy evaluation occurs.

> "sre-bot has full access; deploy-bot is restricted to non-prod" environments —
> given as an example OPA policy distinguishing two different agent identities by
> their externally-issued credential, not by a flag either agent sets on itself.

**Significance:** this is the general-purpose (not Claude-Code-specific) version of
Finding 9's principle, phrased as an architectural pattern rather than a product
security philosophy: an AI agent's authorization should be evaluated against an
externally-issued identity (a JWT, an mTLS certificate — the machine-credential
equivalent of "which GitHub team is this person on" or "which IAM user is this
machine's default profile") and a policy engine, never against something the agent
or its installer self-reports. This corroborates, from the general agentic-AI
security literature rather than from an Anthropic-specific document, the same
conclusion Finding 9 reaches and the same conclusion `SPIKE.md`'s own Central
Finding reaches independently from the Claude Code permissions documentation
(deny-first precedence, credentials as the real backstop).

**Verification:** URL fetched 2026-07-07; all three quotes are verbatim substrings of
the fetched page.

### Finding 11 — The practical, available-today version of "external identity, not self-declaration" for 4Shark's actual toolchain is GitHub repository/team membership — already used at 4Shark for exactly this purpose

**Evidence:** this is not a new external finding — it is the same mechanism already
identified and cited in `SPIKE.md` Finding 9 (`docs/PROJECTS-CATALOG.md:114`: *"These
two repos are owned by **secret** GitHub teams (access-restricted)"*, referring to
4Shark's `compliance` and `data-privacy` repos). It is restated here because this
research phase's findings (9 and 10) independently confirm that "derive access from
an external, already-authenticated identity system" is exactly the shape GitHub team
membership already takes for 4Shark — GitHub authentication (`gh auth login`,
SSH keys) is the externally-issued credential; team membership is the
externally-managed group; neither can be self-declared by the person running Claude
Code.

**Significance:** the community research in this document does not surface a
*better* mechanism available to 4Shark today than the one `SPIKE.md` already
identified — it corroborates that the one already identified is the right shape,
from three independent angles (Anthropic's own containment philosophy, the general
AI-agent-gateway literature, and Anthropic's own enterprise plugin visibility
feature, which is IdP-group-backed the same way GitHub-team-backed access is
identity-backed).

**Verification:** cross-reference to `SPIKE.md` Finding 9 and its cited
`docs/PROJECTS-CATALOG.md:114`; no new URL fetched for this specific finding.

---

## Q5 — Reports from people who tried plugins/marketplaces for this — what worked, what were the limitations?

### Finding 12 — The one mechanism that would most directly fit 4Shark's toolchain (private GitHub repo as an internal Claude plugin marketplace) is explicitly in private beta, not generally available

**Evidence:** already quoted in Finding 7 above — *"private GitHub repositories as
plugin sources (in private beta)"* (`claude.com/blog/cowork-plugins-across-enterprise`,
fetched 2026-07-07). Separately, the general Claude Code plugin-marketplace mechanism
this spike's `SPIKE.md` already documents in depth (private-repo-hosted
`marketplace.json`, `/plugin install`) is a **different, already-GA** mechanism —
the CLI-level marketplace system, not the Cowork/Enterprise-admin-console
group-override system described in Findings 4-5. These are two distinct products
inside Anthropic's plugin ecosystem, at two different maturity levels, and should not
be conflated.

**Significance:** a real company wanting exactly 4Shark's design today has two
different Anthropic-shipped paths, of different maturity: (a) the CLI-level private-repo
marketplace + `/plugin install`, which is GA and is what `SPIKE.md`'s own Model 4
analysis is built on, gated by GitHub repo access alone (no SCIM/IdP integration
needed, but also no admin-enforced "you must install this" push — TI engineers
would each run `/plugin install` themselves); and (b) the Cowork/Enterprise
admin-console group-override system (Finding 4), which is centrally enforced and
IdP-group-backed but requires a paid Enterprise tier and is explicitly still
private-beta for the private-GitHub-repo-as-source case.

**Verification:** derived from Finding 7 (re-cited) plus this spike's own prior
research already reflected in `SPIKE.md`; no new URL fetched beyond Finding 7's
source.

### Finding 13 — At least one real company runs an internal, GitHub-hosted Claude Code plugin marketplace, but with no documented role/department separation

**Evidence:** fetched `https://github.com/feed-mob/claude-code-marketplace`:

> "A curated collection of Claude Code plugins designed to enhance development
> workflows and productivity." — attributed to "FeedMob Dev Team."

> "We welcome contributions to this marketplace!"

**Significance:** this is a real, public existence proof that a company runs its own
Claude Code plugin marketplace in a private/company-owned GitHub repository — the
exact mechanism `SPIKE.md`'s Model 4 (and Finding 9 in this document) points to. It
does **not**, however, document any role- or department-based separation within that
marketplace — the README organizes plugins by type (Agents/Skills/Commands) and
target use case, not by which team should or shouldn't have them. This is a company
solving "share our internal tools via a Claude Code marketplace," not "restrict which
team gets which tools" — a narrower problem than 4Shark's.

**Verification:** URL fetched 2026-07-07; both quotes are verbatim substrings of the
fetched README.

---

## Q6 — Is there a community consensus on anti-patterns ("don't do X")?

### Finding 14 — Claude Code's own issue tracker documents the AI agent itself suggesting privilege expansion for non-admin users unprompted — a distinct, complementary failure mode to a static config split

**Evidence:** fetched `https://github.com/anthropics/claude-code/issues/26238`:

> "On multiple occasions, Claude has suggested granting a client user (who only has
> access to a web application) access to infrastructure services, and in one case
> actively recommended weakening permission checks."

> "Claude should respect the principle of least privilege and never suggest expanding
> access for non-admin users to infrastructure, VPN, servers, databases, or admin
> tooling unless explicitly instructed. It should also flag weak permission models as
> risks rather than opportunities."

The issue is marked closed as a duplicate; no further maintainer discussion was
visible in the fetched content.

**Significance:** this names a real, reported anti-pattern distinct from anything a
static permission-file split (Models 1-4 in `SPIKE.md`) addresses — the model itself,
mid-conversation, can *suggest* loosening a boundary that the underlying
permission/credential layer would still enforce if the suggestion were acted on
verbatim, but which a human reading the suggestion might act on through a *different*
channel (e.g. manually adding someone to an IAM group because Claude said it looked
reasonable). This is a containment gap at the conversation layer, not the
configuration layer, and no config split — however well designed — closes it by
itself; it corroborates Finding 9's point that the "model/instruction layer" is
advisory and can drift, which is exactly why Anthropic's own stated design puts the
enforcement weight on environment/credentials instead.

**Verification:** URL fetched 2026-07-07; both quotes are verbatim substrings of the
fetched issue body as returned by the fetch tool. The maintainer/community response
content was not retrievable from this fetch (page truncation) — the *reporter's*
statement of the anti-pattern is verified; any official Anthropic response to it is
UNVERIFIED and not claimed here.

### Finding 15 — The general AI-agent security literature names "authentication ≠ authorization" as the core anti-pattern to avoid — giving an agent a credential is not the same as scoping what it should do with it

**Evidence:** WebSearch synthesis across several 2026 security-vendor blog posts
(Cequence, Security Boulevard, Zscaler, BeyondTrust — not individually fetched and
re-verified for this document, reported as search-engine synthesis, lower
confidence than the directly-fetched findings above):

> "Authentication alone isn't enough in the agentic era—authentication tells you who
> the agent is but nothing about what the agent should be allowed to do."

**Significance:** translated to 4Shark's situation, this names the specific trap a
naive Model-4 implementation could fall into: provisioning Operations' machine with
*some* AWS IAM user (so `aws` commands technically authenticate) without separately
confirming that IAM user's *policy* is scoped to nothing or to true read-only — i.e.
conflating "Operations' machine can authenticate to AWS at all" with "Operations'
machine should be able to do anything with that authentication." This directly
matches `SPIKE.md` Finding 6's own point that the IAM policy attached to the
default-profile credential, not merely its presence or absence, is the real control.

**Verification:** this is a WebSearch-synthesized quote, not independently re-fetched
from a primary source for this document — reported per Citation Discipline's
UNVERIFIED-leaning caveat: directionally consistent with, and does not contradict,
every directly-fetched finding above, but should not be treated as equally weighted
evidence.

---

## What the community converges on, diverges on, and does not cover

**Converges on:**

- Both major AI-assistant vendors (Anthropic via Claude Cowork/Enterprise plugin
  group-overrides, and — with lower-confidence, unfetched-source caveats — OpenAI via
  ChatGPT Enterprise GPT sharing to groups) have shipped a first-party answer to
  "different departments get different AI-assistant capability sets," and in both
  cases the mechanism is **admin-controlled and identity/group-backed**, not a flag
  the end user sets on their own machine (Findings 4, 5).
- Anthropic's own security engineering (Finding 9), the general AI-agent-gateway
  literature (Finding 10), and — independently — the Claude Code permissions
  documentation this spike's `SPIKE.md` already cites in its own Central Finding all
  converge on the same principle from three unrelated documents: **enforcement must
  live in the environment/credential layer; instructions and self-declared config are
  advisory at best.**
- The GitHub-private-repo-plus-team-access mechanism `SPIKE.md` already identified as
  4Shark's most practically-available option (Finding 9's Model 1 / Model 4 access
  control) is independently corroborated as the right *shape* of mechanism by this
  research pass, even though no external source specifically validates 4Shark's exact
  situation.

**Diverges on:**

- The two vendor-shipped answers (Claude Cowork groups, ChatGPT Enterprise GPT
  sharing) are **not the same product tier 4Shark currently uses** — both require a
  paid Team/Enterprise plan and (for Claude) SCIM/IdP integration 4Shark has not
  confirmed it has (Finding 8, echoing `SPIKE.md` Finding 10's open question). The
  git-clone-based CLI marketplace mechanism `SPIKE.md`'s Model 4 relies on is a
  different, GA product with a real but weaker access-control story (GitHub repo
  access, not IdP-group-backed).

**Does not cover (a valid, explicitly stated conclusion, not a gap this research
failed to fill):**

- **No source found** documents 4Shark's exact situation: a small (~3-person)
  engineering team, self-hosted `git clone`-to-`~/.claude/` distribution (no paid
  Team/Enterprise admin console, no SCIM), splitting an Operations team off with a
  restricted config. Every example found either assumes an Enterprise-tier admin
  console (Findings 4, 5, 8) or solves a narrower, single-person problem (Finding 2).
- **No named design pattern** (in the sense of a portable, community-agreed term)
  exists for "AI coding assistant config split by team with different trust levels"
  — the vocabulary in use everywhere is the pre-existing general RBAC/least-privilege
  vocabulary, applied case by case (Finding 3).
- **No source discusses trade-offs between a monorepo-with-layering approach and a
  separate-repo approach** for this specific purpose — the community silence here is
  as informative as an explicit trade-off discussion would have been: this appears to
  be genuinely uncharted territory for a team of 4Shark's size and toolchain, not a
  solved problem 4Shark simply hasn't looked up yet.
