# PLAN-SPIKE — Runbook Centralization

> No DDD documents present. Research grounded in codebase reading (2026-06-03).
> REVISION 2: Corrected inventory sourced from origin/develop (terraform was on feature/strip-enrich-and-filter during prior research run).

## Objective

Move all 4Shark operational runbooks — currently scattered across `terraform/docs/runbooks/` (22 files on origin/develop), `app/docs/operations/` (1 runbook + 1 policy JSON), and de-facto runbooks in `dot-claude/docs/` (4 files) — into `~/.claude/docs/runbooks/` (working copy: `~/Projects/4Shark/dot-claude/docs/runbooks/`), and provide a new `/runbook` skill that lets Claude Code find and follow the right runbook on demand. The consumer is Claude Code in every session regardless of which repo is open; dot-claude is the only repo always available. Runbooks are loaded Tier 3 (filesystem-discovered, never auto-injected) to avoid blowing the context window on every session start.

## Scope

### In scope
- Migrate terraform runbooks from `terraform/docs/runbooks/` (22 files, 8 categories + 1 nested subdirectory) — pending SSO decision for the 4 client-instruction files
- Migrate 1 runbook from `app/docs/operations/ECS_REMOTE_ACCESS.md`
- Migrate 4 de-facto dot-claude runbooks: `HUBFLOW.md`, `LGPD-DATA-ERASURE.md`, `SEARCHING-ACCOUNT-EVENTS.md`, `1PASSWORD-WSL2-SETUP.md`
- Create `~/.claude/docs/runbooks/INDEX.md`
- Create `~/Projects/4Shark/dot-claude/skills/runbook/SKILL.md`
- Update all cross-references per the corrected link-drift-audit.txt (now includes app/README.md:20 as a new hard link)
- Add `/runbook` entry to CLAUDE.md "Available Commands" and CHANGELOG.md
- Deliver via three PRs in strict sequence

### Out of scope (open question)
- Disposition of the 4 SSO client-instruction files (`sso-client-instructions/{ENTRA-OIDC,ENTRA-SAML,GOOGLE-OIDC,GOOGLE-SAML}.md`) — see Open Decision below
- Disposition of `app/docs/operations/ecs-remote-access-policy.json` (sibling of the app runbook, referenced by relative link from the runbook body) — see Open Questions
- Adding a `check_trigger` entry to `inject-skill-tip.sh` for proactive `/runbook` surfacing (low-priority; skill works without it)
- Whether `app/docs/operations/` directory should be fully removed after migration (depends on ecs-remote-access-policy.json decision)

---

## CORRECTION NOTICE — Inventory from prior research was sourced from wrong branch

The prior PLAN-SPIKE.md stated 18 terraform runbook files. This was wrong.

**Cause:** `git -C ~/Projects/4Shark/terraform branch --show-current` returns `feature/strip-enrich-and-filter`. The prior research ran `ls` against the working copy on this feature branch, which diverged from `origin/develop`. The working copy's `docs/runbooks/` differs from the canonical branch.

**Corrected count (sourced from `git -C ~/Projects/4Shark/terraform ls-tree -r --name-only origin/develop -- docs/runbooks/`):**

```
22 files across 8 categories:
  client-onboarding/   ADD-INTEGRATOR-CLIENT.md, ADD-SSO-CLIENT.md
                       sso-client-instructions/ENTRA-OIDC.md    ← nested subdirectory
                       sso-client-instructions/ENTRA-SAML.md
                       sso-client-instructions/GOOGLE-OIDC.md
                       sso-client-instructions/GOOGLE-SAML.md
  databases/           MONGODB-ATLAS-AUTH.md, MONGODB-REPLICA-SET-MIGRATION.md, MONGOSYNC-DISABLE-VERIFICATION.md
  engineer-access/     AWS-ENGINEER-SETUP.md, BREAK-GLASS.md
  migrations/          VPC-CROSS-VPC-CONNECTIVITY.md, VPC-DECOMMISSION-CHECKLIST.md, VPC-DEPOSED-SG-DEPENDENCY.md, VPC-DESIRED-COUNT-ZERO.md
  security/            PENTEST-ACTIVATION.md
  services/            AUTH-001-KEYCLOAK.md
  terraform-operations/ AMI-VERSION-UPGRADE.md, EMERGENCY-SINGLE-STACK-APPLY.md, STATE-RECOVERY.md
  vpn/                 AZURE-SQL-VPN-OVERRIDE.md, PRITUNL-VPN-OPERATIONS.md
```

The 4 extra files (`ENTRA-OIDC.md`, `ENTRA-SAML.md`, `GOOGLE-OIDC.md`, `GOOGLE-SAML.md`) live in a nested subdirectory `client-onboarding/sso-client-instructions/` and were absent from the working copy on the feature branch. Their nature is distinct — see the SSO Open Decision below.

**Total candidate count pending SSO decision:**
- Terraform: 18 standard runbooks + 4 SSO client-instruction files = 22 (if all migrate)
- App: 1 runbook (`ECS_REMOTE_ACCESS.md`)
- Dot-claude de-facto: 4 runbooks
- **Total if SSO files included:** 27 candidates
- **Total if SSO files excluded:** 23 candidates (matching the locked PLAN.md count exactly)

---

## OPEN DECISION — SSO Client-Instruction Files

**Files:**
- `terraform/docs/runbooks/client-onboarding/sso-client-instructions/ENTRA-OIDC.md`
- `terraform/docs/runbooks/client-onboarding/sso-client-instructions/ENTRA-SAML.md`
- `terraform/docs/runbooks/client-onboarding/sso-client-instructions/GOOGLE-OIDC.md`
- `terraform/docs/runbooks/client-onboarding/sso-client-instructions/GOOGLE-SAML.md`

**Verified character (from `git show origin/develop`):**

All four files begin with the same pattern:

```
# Client Instructions: Microsoft Entra ID — OIDC   (or SAML / Google Workspace)

Send this to the client (or their IT team) during **Step 3** of
[`ADD-SSO-CLIENT.md`](../ADD-SSO-CLIENT.md). The block below is written
**addressed to the client** and assumes no prior knowledge of 4Shark
internals — paste it into email or a ticket as-is.
```

Source: `git -C ~/Projects/4Shark/terraform show origin/develop:docs/runbooks/client-onboarding/sso-client-instructions/ENTRA-OIDC.md` (lines 1–8, verbatim).

They are referenced from `ADD-SSO-CLIENT.md:185-188` (origin/develop, verbatim):

```markdown
| IdP | Protocol | Send the client |
|---|---|---|
| Microsoft Entra ID | OIDC | [`ENTRA-OIDC.md`](sso-client-instructions/ENTRA-OIDC.md) |
| Microsoft Entra ID | SAML | [`ENTRA-SAML.md`](sso-client-instructions/ENTRA-SAML.md) |
| Google Workspace | OIDC | [`GOOGLE-OIDC.md`](sso-client-instructions/GOOGLE-OIDC.md) |
| Google Workspace | SAML | [`GOOGLE-SAML.md`](sso-client-instructions/GOOGLE-SAML.md) |
```

`ADD-SSO-CLIENT.md:180` (origin/develop) describes them: _"The block below is written **addressed to the client** and pasteable into email or a ticket as-is."_

**Language Policy angle:** Per `CLAUDE.md` § Language Policy, the document categories are:
- Internal engineering docs (runbooks) → English
- **Client-facing deliverables** → language of the intended reader

These four files are client-facing deliverables (written to be sent to the client or their IT team). They sit inside the `terraform/docs/runbooks/` tree only as a convenience for the engineer who consults `ADD-SSO-CLIENT.md`, not because they are internal operational procedures.

**Options — engineer decides:**

### SSO Option (a): Migrate with preserved nested subfolder

Include all 4 files in the migration. Place them at `~/.claude/docs/runbooks/client-onboarding/sso-client-instructions/` — the same relative structure under `client-onboarding/`.

**Pros:**
- `ADD-SSO-CLIENT.md` relative links (`sso-client-instructions/ENTRA-OIDC.md` etc.) remain valid after migration — no edits to ADD-SSO-CLIENT.md needed.
- Single location for all SSO onboarding material — engineer never needs to look in two places.
- Engineer can invoke `/runbook add sso client` and get both the procedure and the client templates from the same skill session.

**Cons:**
- Client-facing content lives in dot-claude alongside internal runbooks, which diverges from the Language Policy category separation.
- If a client needs the instructions in Portuguese or another language in the future, the templates would need to coexist with or override the English versions — dot-claude has no multi-language document convention today.
- dot-claude is an internal engineering tool; client-facing templates feel out of place there, even if convenient.
- The 4 files are not runbooks — they are distributable templates. INDEX.md entries for them would be misleading.

**Cost / effort:** Low. Copy the nested subfolder as-is. No edits to ADD-SSO-CLIENT.md.

**Risk:** Low-medium. Language Policy violation (Category 2 content in a Category 1 home). No functional breakage.

### SSO Option (b): Exclude from migration — leave in terraform

Do not migrate the 4 files. They remain at `terraform/docs/runbooks/client-onboarding/sso-client-instructions/` even after the rest of the runbooks are deleted. The `client-onboarding/sso-client-instructions/` subdirectory is kept in terraform.

`ADD-SSO-CLIENT.md` (now in dot-claude) must update its relative links from `sso-client-instructions/ENTRA-OIDC.md` to the terraform repo's absolute or described path (e.g., a prose note: "templates live in `terraform/docs/runbooks/client-onboarding/sso-client-instructions/`").

**Pros:**
- Respects the Language Policy category separation: client-facing templates stay in the source repo, internal runbooks go to dot-claude.
- Keeps dot-claude's runbooks/ as a purely internal engineer knowledge base.
- Leaves the distribution format decision to the engineer — templates can later be moved to a dedicated client-onboarding folder, translated, etc. without touching dot-claude.

**Cons:**
- After terraform's `docs/runbooks/` is deleted, the 4 files are orphaned in a directory that has no other content. The `terraform/docs/runbooks/` tree would be partially deleted (all categories gone except `client-onboarding/sso-client-instructions/`), which is architecturally awkward.
- `ADD-SSO-CLIENT.md` must be edited to update its relative links — adds a small edit surface.
- Engineers who clone a fresh copy of terraform but not dot-claude would have disconnected content (runbook in dot-claude, templates still in terraform).

**Cost / effort:** Low-medium. Edit ADD-SSO-CLIENT.md to update the 4 relative links to absolute references. Keep `sso-client-instructions/` intact in terraform.

**Risk:** Low. Language Policy alignment, at the cost of split locations during the transition.

### SSO Option (c): Exclude from migration — move to a non-runbooks location in terraform

Do not migrate the 4 files. Move them from `terraform/docs/runbooks/client-onboarding/sso-client-instructions/` to a more accurate home in terraform: e.g., `terraform/docs/client-onboarding/sso-client-instructions/` (outside `docs/runbooks/`, reflecting their non-runbook nature).

`ADD-SSO-CLIENT.md` in dot-claude must update its links to point to the new terraform path.

**Pros:**
- Clean separation: runbooks/ is fully deleted from terraform, and client templates live in a named place that signals their client-facing nature.
- Correct categorization inside the terraform repo.

**Cons:**
- Two moves instead of one: files move from `docs/runbooks/client-onboarding/sso-client-instructions/` to `docs/client-onboarding/sso-client-instructions/` in terraform, plus ADD-SSO-CLIENT.md links must be updated.
- Highest edit surface of the three options.
- This scope change requires a separate concern in the terraform PR (or an additional PR step).

**Cost / effort:** Medium. Requires creating a new directory in terraform, moving the 4 files there, and updating ADD-SSO-CLIENT.md.

**Risk:** Medium. More edit surface. Correct in principle.

---

## OPEN QUESTION — ecs-remote-access-policy.json sibling

**Finding (NEW — not in prior audit):**

`app/docs/operations/ECS_REMOTE_ACCESS.md:73` (origin/develop, verbatim):

```
> **Note**: If the `ECSRemoteAccess` policy does not exist yet, create it first:
  **IAM** → **Policies** → **Create policy** → **JSON** tab → paste the contents of
  [`ecs-remote-access-policy.json`](ecs-remote-access-policy.json) → name it `ECSRemoteAccess`.
```

`ecs-remote-access-policy.json` exists at `app/docs/operations/ecs-remote-access-policy.json` on origin/develop. The runbook references it via a relative link.

**Options — engineer decides:**

- **(a) Co-migrate the policy JSON alongside the runbook.** Move both files to `~/.claude/docs/runbooks/engineer-access/`. Update the relative link in `ECS-REMOTE-ACCESS.md` to `ecs-remote-access-policy.json` (same directory — link remains valid). `app/docs/operations/` becomes empty and can be removed.
- **(b) Update the link to an absolute reference, leave the JSON in app.** The migrated runbook body updates line 73 to reference the app repo path (e.g., prose: "see `app/docs/operations/ecs-remote-access-policy.json`"). The JSON stays in the app repo under `docs/operations/` (or wherever the engineer decides). `app/docs/operations/` is not removed (still contains the JSON).
- **(c) Inline the policy JSON content into the runbook body.** Replaces the relative link with a fenced JSON block directly in the runbook. The JSON file in app can then be deleted. `app/docs/operations/` becomes empty and can be removed.

---

## NEW FINDING — app/README.md hard link (missed by prior audit)

**Finding:**

`app/README.md:20` (origin/develop, verbatim):

```
* [ECS Remote Access](docs/operations/ECS_REMOTE_ACCESS.md) - Connect to production/staging via Rails console or bash
```

This is a **hard link** (markdown hyperlink) that will become a 404 when Phase 3 removes `app/docs/operations/ECS_REMOTE_ACCESS.md`. It was not captured in the prior audit because the prior audit only grepped the terraform repo.

**Action:** This must be added to Phase 3 scope. Update to `~/.claude/docs/runbooks/engineer-access/ECS-REMOTE-ACCESS.md`. The locked PLAN.md Phase 3 success criteria ("fix any remaining in-app references") covers this — but the specific file:line was not enumerated. The PLAN.md must be updated to name it explicitly.

---

## Candidate approaches (structural options — unchanged from prior research)

These options remain valid. The corrected inventory (22 terraform files instead of 18) does not change the structural trade-offs — the extra 4 files are handled by the SSO Open Decision above.

### Option A: Preserve terraform 8-category folder structure verbatim

**Approach summary:** Copy the existing 8-category tree from `terraform/docs/runbooks/` into `dot-claude/docs/runbooks/` unchanged. Add the app runbook under `engineer-access/`. Add two new categories (`development/`, `compliance/`) for the de-facto dot-claude runbooks. **This is the direction already locked by the engineer in PLAN.md.**

**Structure:**
```
~/.claude/docs/runbooks/
├── INDEX.md
├── client-onboarding/
│   ├── ADD-INTEGRATOR-CLIENT.md
│   ├── ADD-SSO-CLIENT.md
│   └── sso-client-instructions/   ← exists only if SSO Option (a) chosen
│       ├── ENTRA-OIDC.md
│       ├── ENTRA-SAML.md
│       ├── GOOGLE-OIDC.md
│       └── GOOGLE-SAML.md
├── compliance/
│   └── LGPD-DATA-ERASURE.md
├── databases/
│   ├── MONGODB-ATLAS-AUTH.md
│   ├── MONGODB-REPLICA-SET-MIGRATION.md
│   └── MONGOSYNC-DISABLE-VERIFICATION.md
├── development/
│   └── HUBFLOW.md
├── engineer-access/
│   ├── 1PASSWORD-WSL2-SETUP.md
│   ├── AWS-ENGINEER-SETUP.md
│   ├── BREAK-GLASS.md
│   └── ECS-REMOTE-ACCESS.md
├── migrations/
│   ├── VPC-CROSS-VPC-CONNECTIVITY.md
│   ├── VPC-DECOMMISSION-CHECKLIST.md
│   ├── VPC-DEPOSED-SG-DEPENDENCY.md
│   └── VPC-DESIRED-COUNT-ZERO.md
├── security/
│   ├── PENTEST-ACTIVATION.md
│   └── SEARCHING-ACCOUNT-EVENTS.md
├── services/
│   └── AUTH-001-KEYCLOAK.md
├── terraform-operations/
│   ├── AMI-VERSION-UPGRADE.md
│   ├── EMERGENCY-SINGLE-STACK-APPLY.md
│   └── STATE-RECOVERY.md
└── vpn/
    ├── AZURE-SQL-VPN-OVERRIDE.md
    └── PRITUNL-VPN-OPERATIONS.md
```

**Pros:**
- Zero cognitive overhead — engineers who know the terraform structure find files immediately
- Relative cross-runbook links inside `migrations/` remain valid (VPC-DECOMMISSION-CHECKLIST.md:75)
- `ECS-REMOTE-ACCESS.md` fits naturally under `engineer-access/`
- INDEX.md construction is mechanical — one entry per file, categories match folders

**Cons:**
- `migrations/` and `terraform-operations/` are Terraform-centric names
- If SSO Option (a): client-facing templates coexist with internal runbooks under the same INDEX

**Cost / effort:** Low.

**Risk:** Low. Already the locked direction.

**Source patterns referenced:**
- `git -C ~/Projects/4Shark/terraform ls-tree -r --name-only origin/develop -- docs/runbooks/` — verified 22 files (see CORRECTION NOTICE above)
- `~/Projects/4Shark/terraform/docs/runbooks/migrations/VPC-DECOMMISSION-CHECKLIST.md:75` — `[Deposed SG Dependency runbook](VPC-DEPOSED-SG-DEPENDENCY.md)` relative link
- See auxiliary: `link-drift-audit.txt` — corrected full reference inventory

---

### Option B: Flatten to a single directory (no categories)

**Approach summary:** All runbook files placed directly under `~/.claude/docs/runbooks/`, no subdirectories. INDEX.md is the only navigation surface.

*(Not the locked direction. Retained for reference.)*

**Pros:**
- Simpler `/runbook` skill implementation
- Consistent with existing flat `docs/` layout in dot-claude
- No SSO subdirectory question (flat structure — SSO templates would either be present at root or excluded)

**Cons:**
- Cross-runbook relative links in `migrations/` VPC runbooks still resolve in flat layout (both files at same level), but any future restructuring breaks them
- Loses categorical grouping
- 27-file flat directory is harder to browse

**Cost / effort:** Low-medium.

**Risk:** Low-medium.

**Source patterns referenced:**
- `~/Projects/4Shark/dot-claude/docs/` — existing flat layout pattern (verified)

---

### Option C: Hybrid — rename categories to be repo-agnostic

*(Not the locked direction. Retained for reference.)*

**Pros:** Future runbooks for non-Terraform work fit more naturally.
**Cons:** Higher edit surface than Option A; breaks all ADR cross-references by category name.

---

## Technical decisions to be made (NOT decided here)

The locked decisions from PLAN.md are not re-opened. Only the SSO and policy JSON decisions are new and open.

| Decision point | Options | Trade-off summary | Engineer to choose |
|----------------|---------|-------------------|---------------------|
| SSO client-instruction files | (a) Migrate with preserved subfolder / (b) Exclude, leave in terraform / (c) Exclude, move to non-runbooks terraform location | (a) = no link edits, Language Policy bend; (b) = Language Policy clean, partial terraform cleanup; (c) = cleanest categorization, most edits | □ |
| ecs-remote-access-policy.json sibling | (a) Co-migrate to engineer-access/ / (b) Leave in app, update link to prose ref / (c) Inline JSON into runbook body | (a) = self-contained runbook, co-migrates non-MD file to dot-claude; (b) = split locations, least change; (c) = fully self-contained, removes the JSON file | □ |

---

## Link drift — corrected complete reference inventory

See auxiliary: `link-drift-audit.txt` — fully regenerated from `origin/develop` (2026-06-03 correction run).

### Hard links that become 404s — MUST fix before or with respective PR

| File | Line | Current target | Fix | Phase |
|------|------|----------------|-----|-------|
| `terraform/SECURITY.md` | 31 | `docs/runbooks/engineer-access/BREAK-GLASS.md` | Update to `~/.claude/docs/runbooks/engineer-access/BREAK-GLASS.md` | PR 2 |
| `terraform/identity/README.md` | 27 | `../docs/runbooks/engineer-access/BREAK-GLASS.md` | Update to `~/.claude/docs/runbooks/engineer-access/BREAK-GLASS.md` | PR 2 |
| `app/README.md` | 20 | `docs/operations/ECS_REMOTE_ACCESS.md` | Update to `~/.claude/docs/runbooks/engineer-access/ECS-REMOTE-ACCESS.md` | PR 3 (NEW) |

### Soft refs requiring update

| File | Line | Current path | Action | Phase |
|------|------|--------------|--------|-------|
| `terraform/README.md` | 237 | `docs/runbooks/` | Update to `~/.claude/docs/runbooks/` | PR 2 |
| `terraform/identity/README.md` | 175 | `docs/runbooks/engineer-access/AWS-ENGINEER-SETUP.md` | Update path | PR 2 |
| `terraform/docs/adr/ADR-002-terramate.md` | 43 | `docs/runbooks/terraform-operations/EMERGENCY-SINGLE-STACK-APPLY.md` | Update path | PR 2 |
| `terraform/docs/adr/ADR-004-identity-model.md` | 48 | `docs/runbooks/engineer-access/BREAK-GLASS.md` | Update path | PR 2 |
| `terraform/docs/adr/ADR-005-ecs-multi-cluster-pattern.md` | 91 | `docs/runbooks/client-onboarding/ADD-INTEGRATOR-CLIENT.md` | Update path | PR 2 |
| `terraform/docs/adr/ADR-001-state-backend.md` | 41 | `docs/runbooks/terraform-operations/STATE-RECOVERY.md` | Update path | PR 2 |
| `terraform/dns/security_locals.tf` | 2 | `docs/runbooks/security/PENTEST-ACTIVATION.md` | Update comment | PR 2 |
| `dot-claude/docs/AWS-MFA.md` | 16, 240 | `docs/runbooks/AWS-ENGINEER-SETUP.md` (terraform repo) | Update to new dot-claude path | PR 1 |
| `dot-claude/docs/IDENTITY-STACK.md` | 5 | `docs/runbooks/engineer-access/BREAK-GLASS.md` (terraform repo) | Update to new dot-claude path | PR 1 |

### Pre-existing broken reference (fix in PR 2 regardless of migration)

| File | Line | Issue |
|------|------|-------|
| `terraform/modules/ami_versions/README.md` | 72 | Points to `docs/runbooks/ami-version-upgrade.md` (flat path, never existed); actual file is at `terraform-operations/AMI-VERSION-UPGRADE.md`. Already broken before migration. |

### Not requiring fix

| File | Line | Reason |
|------|------|--------|
| `terraform/CHANGELOG.md` | 152 | Historical prose entry in a changelog — not a navigable hyperlink; records what was announced at the time. Do not alter changelog history. |
| `dot-claude/skills/pr-triage/SKILL.md` | 41 | Path appears inside a JSON code block illustrating an example PR thread object — static example data, not a live reference. |
| `dot-claude/commands/cleanup-memories.md` | 156, 280 | Generic template placeholders (`<repo>/docs/runbooks/<area>/<NAME>.md`) in instructional prose — not references to any specific file. |

### Internal cross-runbook relative links (safe in Option A)

| File | Line | Link | Status |
|------|------|------|--------|
| `terraform/docs/runbooks/migrations/VPC-DECOMMISSION-CHECKLIST.md` | 75 | `[...](VPC-DEPOSED-SG-DEPENDENCY.md)` | Relative — safe if both files move together into `migrations/` (Option A). |
| `terraform/docs/runbooks/migrations/VPC-DEPOSED-SG-DEPENDENCY.md` | 97 | Prose mention of `VPC-DECOMMISSION-CHECKLIST.md` | Not a hyperlink — no breakage. |
| `terraform/docs/runbooks/client-onboarding/ADD-SSO-CLIENT.md` | 185-188 | Relative links to `sso-client-instructions/*.md` | Conditional — safe only if SSO Option (a) preserves the subfolder. Option (b) or (c) requires editing ADD-SSO-CLIENT.md. |

---

## Execution order (unchanged from locked PLAN.md; phase scopes updated with new findings)

Three PRs in strict sequence. Each PR merged before the next opens.

```
PR 1 — dot-claude: add runbooks + /runbook skill
  → Creates ~/.claude/docs/runbooks/ with 10-category structure
  → Migrates 18 terraform standard runbooks (+ 4 SSO files IF Option a)
  → Migrates 4 de-facto dot-claude runbooks into new categories
  → Migrates app ECS-REMOTE-ACCESS.md into engineer-access/
  → Co-migrates ecs-remote-access-policy.json IF Option (a) for policy JSON
  → Creates INDEX.md, creates skills/runbook/SKILL.md
  → Updates read-context.sh (INDEX pointer in, 3 Tier-2 pointers out)
  → Updates CLAUDE.md See: lines for moved runbooks
  → Updates AWS-MHA.md:16,240 and IDENTITY-STACK.md:5
  → Updates CHANGELOG.md
  MERGE PR 1 first.

PR 2 — terraform: fix link drift + delete runbooks
  → Fixes 2 hard links + 6 soft refs + 1 pre-existing broken ref
  → Deletes terraform/docs/runbooks/ (clean, no stubs)
  → RETAINS sso-client-instructions/ IF SSO Option (b) or (c)
     OR deletes it completely if SSO Option (a)
  MERGE PR 2 second.

PR 3 — app: remove app runbook + fix hard link
  → Updates app/README.md:20 (NEW — hard link to ECS_REMOTE_ACCESS.md)
  → Removes app/docs/operations/ECS_REMOTE_ACCESS.md
  → Co-removes or retains ecs-remote-access-policy.json per policy JSON decision
  → Removes app/docs/operations/ if empty after removal
  MERGE PR 3 third.
```

**Why this order is load-bearing:** PR 1 must land first so runbooks exist in dot-claude before they disappear from terraform/app. If PR 2 lands first, there is a window where no session has the runbooks.

---

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|------|--------|---------------------|
| SSO files excluded but ADD-SSO-CLIENT.md relative links not updated | After PR 2, ADD-SSO-CLIENT.md links to non-existent paths in dot-claude | SSO decision must be made before Phase 2 PR is opened; link changes are part of PR 2 scope if Option (b) or (c) |
| ecs-remote-access-policy.json left in app but link in runbook not updated | Migrated runbook body has a broken relative link | Phase 1 PR must resolve the relative link per the policy JSON decision |
| app/README.md:20 hard link missed — now explicitly found | After PR 3, app/README.md has a 404 hyperlink | Explicitly added to Phase 3 scope in the corrected plan |
| Pre-existing broken ref at `terraform/modules/ami_versions/README.md:72` left unfixed | Already broken, compounds with migration confusion | Fix included in Phase 2 scope |
| dot-claude PR not pulled between PR 2 and PR 3 | Short window where runbooks exist in neither location for engineers who pulled terraform but not dot-claude | State in PR 2 description: "Pull dot-claude before pulling terraform" |
| `/runbook` skill loads multiple large runbooks simultaneously | Context window pressure | SKILL.md must instruct loading ONE matched runbook body at a time |

---

## Open questions for the engineer

1. **SSO client-instruction files** — The 4 files (`ENTRA-OIDC.md`, `ENTRA-SAML.md`, `GOOGLE-OIDC.md`, `GOOGLE-SAML.md`) are client-facing templates (explicitly "addressed to the client and pasteable into email or a ticket as-is"). Three options with trade-offs are documented in the OPEN DECISION section above:
   - (a) Migrate with preserved nested subfolder into dot-claude runbooks
   - (b) Exclude — leave in terraform as a remnant under `client-onboarding/sso-client-instructions/`
   - (c) Exclude — move to a non-runbooks location in terraform (e.g., `docs/client-onboarding/`)

2. **ecs-remote-access-policy.json** — The app runbook references this sibling JSON file via a relative link (app/docs/operations/ECS_REMOTE_ACCESS.md:73). After migration, what should happen to it? Options: (a) co-migrate to engineer-access/, (b) leave in app with the runbook link updated to a prose reference, (c) inline the JSON content into the runbook body.

3. **PLAN.md Phase 3 update** — `app/README.md:20` is a hard link to `ECS_REMOTE_ACCESS.md` that was not in the locked PLAN.md's explicit enumeration. It is covered by the phase's general scope statement ("fix any remaining in-app references") but must be named explicitly in the PLAN.md update.

---

## Sources

- `git -C ~/Projects/4Shark/terraform branch --show-current` → `feature/strip-enrich-and-filter` (confirmed the prior-research error)
- `git -C ~/Projects/4Shark/terraform ls-tree -r --name-only origin/develop -- docs/runbooks/` → 22 files (authoritative inventory)
- `git -C ~/Projects/4Shark/terraform show origin/develop:docs/runbooks/client-onboarding/sso-client-instructions/ENTRA-OIDC.md` → `# Client Instructions: Microsoft Entra ID — OIDC` ... `"Send this to the client ... paste it into email or a ticket as-is"`
- `git -C ~/Projects/4Shark/terraform show origin/develop:docs/runbooks/client-onboarding/ADD-SSO-CLIENT.md` lines 180-188 → Step 3 table referencing the 4 sso-client-instructions files with relative links
- `git -C ~/Projects/4Shark/app ls-tree -r --name-only origin/develop -- docs/` → confirms `docs/operations/ECS_REMOTE_ACCESS.md` + `docs/operations/ecs-remote-access-policy.json`
- `git -C ~/Projects/4Shark/app show origin/develop:docs/operations/ECS_REMOTE_ACCESS.md` line 73 → relative link to `ecs-remote-access-policy.json`
- `git -C ~/Projects/4Shark/app grep -n "ECS_REMOTE_ACCESS" origin/develop -- "*.md"` → `app/README.md:20` hard link (new finding)
- `git -C ~/Projects/4Shark/dot-claude ls-tree -r --name-only origin/develop -- docs/ | grep -E "HUBFLOW|LGPD|SEARCHING|1PASSWORD"` → 4 de-facto runbooks confirmed at `docs/` paths
- `git -C ~/Projects/4Shark/terraform grep -n "docs/runbooks" origin/develop -- "*.md" "*.tf"` → 11 references (9 actionable + 1 CHANGELOG history + 1 corrected count)
- `git -C ~/Projects/4Shark/dot-claude grep -n "docs/runbooks" origin/develop -- "*.md" "*.sh"` → 5 references (3 actionable cross-repo refs + 2 no-action: pr-triage example JSON + cleanup-memories template)
- `git -C ~/Projects/4Shark/app grep -rn "docs/operations" origin/develop -- "*.md"` → 1 reference (`README.md:20`, new finding)
- `~/Projects/4Shark/dot-claude/skills/post-mortem/SKILL.md:1-4` — YAML frontmatter pattern
- `~/Projects/4Shark/dot-claude/scripts/auto-approve-local-skills.sh:53-56` — filesystem-based auto-approval
- `~/Projects/4Shark/dot-claude/scripts/read-context.sh:84-191` — Tier 1/2 lists
- `~/Projects/4Shark/dot-claude/settings.json:221-228` — `"matcher": "Skill"` PreToolUse hook
- See auxiliary files:
  - `link-drift-audit.txt` — corrected complete reference inventory (regenerated from origin/develop)
  - `skill-structure-findings.txt` — SKILL.md conventions, auto-approval mechanism (unchanged; not affected by the branch error)
