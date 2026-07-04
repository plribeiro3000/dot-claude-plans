# SPIKE — Keycloak / authenticator documentation coverage in dot-claude

## Question

Before starting the pgbouncer → connection-pooler rename (a large infra rework), is the dot-claude documentation "round" on Keycloak? Specifically:

1. Is it documented that Keycloak is called the **authenticator** throughout the infra, that **`auth` is the single sanctioned abbreviation** (`auth-001` everywhere), and that the **GitHub repo carries the technology name** (`keycloak`) while the **infra carries the role name** — the same split pgbouncer → connection-pooler will follow?
2. Is the **version-upgrade process** documented and discoverable?
3. Is **how we keep Keycloak on the latest version** (Renovate + 7-day min-age + verify-minimum-age) documented and connected to the Docker-image tool repos?

And: where does each missing piece belong?

## Method

Read-only audit of `~/.claude/docs/` (grep + targeted reads). Every claim below carries a `file:line` citation. No dot-claude file was edited (Configuration Changes Policy — doc changes are a follow-up PR).

## Findings — current coverage

| Topic | Where it lives | State | Evidence |
|---|---|---|---|
| Domain-naming principle ("name = what it is") + `app` / `app-webclient` / `app-mobileclient` examples | `PROJECTS-CATALOG.md:14-29` | Present | "a repository's name says what it **is** in the business, not how it is built" (`:14-16`); the three examples at `:18,21,22` |
| Keycloak → authenticator naming | `PROJECTS-CATALOG.md:23`, `:87`, `:150-153` | Present but partial | `:23` "**`keycloak`** — the exception that proves the rule: it is named after the tool, not the role. Its domain role is the **authenticator**"; `:87` "The **authenticator** (a Keycloak deployment, the `auth-001` instance)" |
| No-abbreviations rule | `CODE-STYLE-RULES.md:180` | Present; conflicts with `auth` | "An abbreviation is an abbreviation; there is no list of \"allowed\" short forms ... it is banned" — applies to variables/params/locals/SQL aliases/HCL |
| How Keycloak is used at runtime (SSO broker) | `AUTHENTICATION-ARCHITECTURE.md` (239 lines) | Well covered | "## Mode 2 — SSO via Keycloak broker" (`:74`), the shared JWT (`:116`), per-client wiring (`:212`) |
| Keycloak operations (stack ref, gotchas) | `runbooks/services/AUTH-001-KEYCLOAK.md` (33 lines) | Present; indexed | cluster `auth-001-cluster`, URL `auth-001.app4shark.com/auth`; `X-Frame-Options` gotcha. `INDEX.md:69` |
| Version-upgrade process | `runbooks/services/KEYCLOAK-VERSION-UPGRADE.md` (106 lines) | Present; discoverable | `INDEX.md:70` with rich triggers ("Infinispan upgrade", "maintenance window upgrade", "keycloak base image") |
| Stay-latest machinery (Renovate + 7-day + CI) | `AUTOMATED-DEPENDENCY-UPDATES.md` (420 lines) | Thorough but **generic** | Full three-layer machinery; grep for `keycloak\|pgbouncer\|base image` → **zero matches**. Not connected to the tool repos |
| Docker-image tool-repo pattern | `DOCKER-IMAGE-TOOL-REPOS.md` (132 lines) | Present | pgbouncer reference, keycloak first adopter; mentions Renovate tracks the base image, but does not cross-link the dependency-update doc |

## Gaps

**G1 — The repo-vs-infra naming split is not stated as a rule, and pgbouncer is missing.**
`PROJECTS-CATALOG.md:23` frames keycloak as a lone "exception" (repo named after the tool) and names the authenticator role, but it does not state the general principle that a **third-party-tool wrapper repo carries the technology name while the infra carries the role name**. It also never mentions **pgbouncer** (absent from the catalog) or **connection-pooler**, so the parallel that justifies the upcoming rename is undocumented. The `/authenticators` and `/connection-poolers` skills already apply the role naming, but nothing states *why*.

**G2 — `auth` as the single sanctioned abbreviation is undocumented and in tension with `CODE-STYLE-RULES.md:180`.**
The variable rule says there is "no list of 'allowed' short forms". `auth` is an abbreviation of *authentication/authenticator* and is used pervasively in the infra (`auth-001`, `auth-001-cluster`, `auth-001-staging`, ECR, tags). The clean reconciliation: the variable rule governs **code identifiers** (variables, params, locals, aliases); **infrastructure component names** (stack / cluster / service / ECR / role) are a distinct category, and `auth` is the one sanctioned short form for the authenticator role. That carve-out is written nowhere.

**G3 — "How we keep Keycloak on the latest version" is scattered across three docs with no wiring.**
A reader answering that question must assemble `AUTOMATED-DEPENDENCY-UPDATES.md` (the machinery, generic) + `DOCKER-IMAGE-TOOL-REPOS.md` (the repo pattern) + `KEYCLOAK-VERSION-UPGRADE.md` (the runbook). None cross-links the others for the base-image case.

## Placement proposal

### G1 — repo-vs-infra split + pgbouncer parallel → **extend `PROJECTS-CATALOG.md` § Naming**
Single obvious home (the engineer confirmed it is *the* naming doc). Add, right after `:23`: the two-context rule (tool-wrapper repo = technology name; infra = role name), and pgbouncer → connection-pooler as the second instance of the same shape. Low ambiguity — recommend directly.

### G2 — `auth` abbreviation exception → **DECISION NEEDED** (present to engineer)

| Option | Home | Trade-off |
|---|---|---|
| **A (recommended)** | `CODE-STYLE-RULES.md` § Variable Naming — add an "Infrastructure component names" carve-out stating they are a separate category from code identifiers, with `auth` as the single sanctioned short form | Puts the exception exactly where the "no abbreviations" rule lives, so the two can never be read in contradiction. Also mirror one line into `CLAUDE.md` § Variable Naming |
| **B** | `PROJECTS-CATALOG.md` § Naming — document `auth` next to the authenticator role | Keeps all naming in one doc, but leaves `CODE-STYLE-RULES.md:180` looking absolute (a reader there won't know about the exception) |
| **C** | New Tier-2 doc `INFRASTRUCTURE-NAMING.md` — infra names by resolved role + `auth` exception + repo-vs-infra split | Cleanest conceptual home and room to grow, but a new doc is heavier and splits naming guidance across two files |

### G3 — stay-latest wiring → **DECISION NEEDED** (present to engineer)

| Option | Home | Trade-off |
|---|---|---|
| **A (recommended)** | Add a short "Keeping the tool current" section to `DOCKER-IMAGE-TOOL-REPOS.md` that cross-links `AUTOMATED-DEPENDENCY-UPDATES.md` (the 7-day machinery) and the version-upgrade runbook | Anchors the answer in the doc that already describes these repos; two cross-links, minimal new prose |
| **B** | Add a Docker-tool-repos paragraph to `AUTOMATED-DEPENDENCY-UPDATES.md` | Puts it with the machinery, but that doc is generic across all repos and would gain a tool-repo-specific aside |

## Recommendation

- **G1**: extend `PROJECTS-CATALOG.md` § Naming — recommend directly, no decision needed.
- **G2**: **Option A** (carve-out in `CODE-STYLE-RULES.md`, mirrored in `CLAUDE.md`) — keeps the exception un-contradictable next to the rule.
- **G3**: **Option A** (cross-links in `DOCKER-IMAGE-TOOL-REPOS.md`).

Coverage is stronger than expected: runtime usage, operations, and the upgrade runbook are all present and indexed. The real gaps are three naming/wiring seams, all resolvable by extending existing docs — no large new documentation effort, and nothing blocks the pgbouncer rename beyond deciding G2/G3 placement.

## Next step

Engineer picks G2 and G3 placement (G1 is unambiguous). Then a single follow-up PR to dot-claude applies all three edits (per Configuration Changes Policy).
