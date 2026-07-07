# SPIKE — Credential Risk Classification (1Password Biometric Inventory)

> **OUTCOME (2026-07-06):** the engineer chose the simplest path — move ONLY the GitHub git-push key out of 1Password onto disk (personal, opt-in), leaving every other inventoried credential biometric/machine-bound. The elaborate provisioner/blocking-hook/team-rollout machinery was dropped as over-engineering. Decision recorded in `~/.claude/plans/active/remote-git-access/PLAN.md`. This spike's inventory and blast-radius findings remain the valid grounding.

## Investigation question

Rather than working around the 1Password Teams-Starter plan limit that closed the earlier
Service-Account attempt (see `~/.claude/plans/active/spike/remote-1password-ssh-approval/SPIKE.md`),
this spike inventories the developer-workstation credentials currently gated by the 1Password
biometric agent and classifies each by blast radius:

- **Low blast radius / simple operations** → candidate to move OUT of 1Password onto a dedicated
  on-disk key, making the operation remote-able (no biometric prompt, doable from a phone via
  Claude Code Remote Control).
- **High blast radius / large or destructive operations** (the engineer's example: `terraform
  apply`) → candidate to STAY in 1Password, biometric, machine-bound — the reasoning being that
  destructive/complex work must be done at the machine with full tooling and keyboard control, in
  case something goes wrong and needs maximum power to fix.

The deliverable is (1) an inventory of the actual credentials in play, (2) a per-credential
classification proposal on the remote-able-vs-machine-bound axis, and (3) the articulated
governing rule plus the open decisions the engineer needs to ratify.

## Sources consulted

- `~/.claude/plans/completed/terraform/credential-hygiene/PLAN.md` — the authoritative "KEPT in
  1Password" list this spike's scope is drawn from
- `~/.claude/plans/active/legal-compliance-documents/categorizacao-vaults-1password.md` and
  `mapa-de-vaults-1password.md` — existing vault-tiering study this spike extends with the
  remote-able-vs-machine-bound axis
- `~/.claude/plans/active/spike/remote-1password-ssh-approval/SPIKE.md` — grounding facts on how
  the 1Password SSH agent and `op` CLI Service Accounts actually work (cited by Finding number
  below; not re-derived)
- `~/.claude/docs/AWS-MFA.md`, `~/.claude/docs/IDENTITY-STACK.md`, `~/.claude/docs/TERRAFORM-POLICY.md`
- `~/.claude/commands/op-signin.md`
- `~/Projects/4Shark/terraform/` — grepped for `key_pair`/`key_name`, read `.envrc` files,
  `identity/github_repositories.tf`, `identity/providers.tf`, `identity/github.tf`, `dns/*.tf`,
  `vpn/main.tf`, `modules/pritunl/*.tf`, `integrator-*/mongodb.tf`, `integrator-atento/windows_machine.tf`
- `~/Projects/4Shark/ansible/README.md`, `~/Projects/4Shark/ansible/group_vars/all/all.yml`
- `~/Projects/4Shark/dot-claude/docs/runbooks/client-onboarding/ADD-INTEGRATOR-CLIENT.md`
- `~/.claude/docs/runbooks/vpn/PRITUNL-VPN-OPERATIONS.md`, `~/.claude/docs/runbooks/engineer-access/ECS-REMOTE-ACCESS.md`
- `~/.claude/scripts/ruby.sh` — confirms the Rails master key is already off the 1Password runtime
  path
- `~/.ssh/config` — **could not be read**: the file is in a directory denied by the local sandbox's
  permission settings. Every claim in this SPIKE that would depend on its contents is marked
  UNVERIFIED rather than assumed.
- See auxiliary: `credential-risk-classification_excerpt_1.md` — the two distinct EC2 SSH key
  pairs (`kp-4shark` vs `4Shark-key`) found in the terraform repo, with full grep results and
  representative `.tf`/`.tfvars` excerpts
- See auxiliary: `credential-risk-classification_excerpt_2.md` — the `Terraform ENV` bootstrap
  item's `.envrc` wiring and what its `GITHUB_TOKEN`/`CLOUDFLARE_API_TOKEN`/Atlas keys actually
  authorize in Terraform (branch protection, org membership, public DNS)
- See auxiliary: `credential-risk-classification_excerpt_3.md` — the interactive/automation
  SSH-to-a-box mechanics for `kp-4shark.pem`, the VPN prerequisite shared by SSH/RDP/ECS Exec, and
  the credentials already confirmed off the 1Password runtime path (master key, default AWS
  profile)

## Findings

### Finding 1: The credential-hygiene project already produced the authoritative "what stays in 1Password" list — this spike's scope is exactly that list, narrowed to developer-workstation operational credentials

**Evidence:**

> **KEPT (confirmed):** user logins (app4shark client accounts, personal SaaS, VPN PINs, personal
> AWS key); Elastic Index (human web-dashboard login — value is in SSM but the 1P purpose is the
> human login); Terraform ENV (bootstrap, read by `.envrc` via `op`); Amazon Root; 4Shark App
> Master Key; MongoDB - Ivo/Paulo (Atlas console logins); Redis (Redis Labs login); active SSH keys.

**Source:** `~/.claude/plans/completed/terraform/credential-hygiene/PLAN.md:51`

**Significance:** Every database/service credential that had a source of truth outside 1Password
was already removed (32 items, per the same document, line 62). What remains in 1Password by
deliberate decision is exactly the set this spike must classify: SSH keys, the Terraform ENV
bootstrap item, VPN PINs, and the AWS-elevation TOTP item. Personal SaaS logins, Atlas console
logins, and the Redis Labs login are human web-dashboard logins with no programmatic
Remote-Control-session use case, so they are treated as out of this spike's scope (they were never
part of the "a remote Claude Code session hit a Touch ID prompt mid-task" problem).

### Finding 2: There are (at least) two distinct AWS EC2 key pairs in play, not one — `kp-4shark` and `4Shark-key` — with materially different documented usage

**Evidence:**

```
integrator-almaviva/mongodb.tf:28:  key_name      = "kp-4shark"
vpn/main.tf:19:                     key_name      = "kp-4shark"
integrator-atento/windows_machine.tf:17: key_name = "kp-4shark"
modules/pritunl/variables.tf:30:    default     = "kp-4shark"
```
versus
```
app-shared-001/terraform.tfvars:5: key_name = "4Shark-key"
app-atento-001/terraform.tfvars:4: key_name = "4Shark-key"
app-beta-001/terraform.tfvars:5:   key_name = "4Shark-key"
app-demo-001/terraform.tfvars:5:   key_name = "4Shark-key"
setup/terraform.tfvars:5:          key_name = "4Shark-key"
```

**Source:** grep across `~/Projects/4Shark/terraform/**/*.tf` and `**/*.tfvars` (full result set in
`credential-risk-classification_excerpt_1.md`)

**Significance:** `kp-4shark` is attached to every MongoDB EC2 instance across all 5 integrator
stacks (almaviva, atento, redebrasil, maqnelson, commcenter — 3 instances each: primary, secondary,
arbiter), the Pritunl VPN EC2 host, and the Atento Windows RDP machine (also used to decrypt its
Administrator password — `integrator-atento/windows_machine.tf:66`). It is also the key
documented for interactive/automation use (Finding 3). `4Shark-key` is attached to the ECS-host
EC2 capacity of every app stack (shared-001, atento-001, beta-001, demo-001) and `setup` —
searching the entire `~/Projects/4Shark` tree for the literal string `4Shark-key` found no README,
runbook, or ansible playbook documenting who holds its private half or when it is used
interactively. **UNVERIFIED**: whether `4Shark-key`'s private key is actively used by any engineer
today (ECS containers are reached via ECS Exec/SSM per Finding 5, not SSH, so this key pair may be
attached to instances purely as a dormant emergency-access mechanism). This distinction matters
for classification — `kp-4shark` has confirmed, routine, production-data-touching use;
`4Shark-key`'s actual usage pattern is not established by this research pass.

### Finding 3: `kp-4shark.pem` is documented, in both the automation and the client-onboarding runbook, as a literal file on disk loaded via standard OpenSSH mechanisms — not confirmed as 1Password-SSH-agent-mediated for the interactive case

**Evidence:**

> **Be Aware**: In order to use this automation system you **must** be connected to 4Shark VPN and
> add `kp-4shark.pem`
>
> ssh-add ~/.ssh/kp-4shark.pem

**Source:** `~/Projects/4Shark/ansible/README.md:80,83`

> SSH to the MongoDB primary via VPN:
>
> ssh -i ~/.ssh/kp-4shark.pem ubuntu@{mongo-primary}.4shark.internal

**Source:** `~/Projects/4Shark/dot-claude/docs/runbooks/client-onboarding/ADD-INTEGRATOR-CLIENT.md:85`

**Significance:** Both documented flows reference `-i`/`ssh-add` against a literal path,
consistent with a standard (non-1Password) OpenSSH agent or direct key-file usage — not
explicitly the 1Password SSH agent's per-process authorization model described in Findings 1–2 of
`remote-1password-ssh-approval/SPIKE.md`. This spike's background premise states "every privileged
action ... raises a Touch ID prompt," which requires the developer's `~/.ssh/config` to route this
specific host at the 1Password agent socket AND the key material to live inside the 1Password
vault rather than as a bare file. **This research could not confirm which is true today** — reading
`~/.ssh/config` was blocked by the local sandbox's own directory permissions (a genuine access
boundary, not a research gap this spike could close). Flagged as an open question in "What remains
uncertain" below, since it changes whether kp-4shark is currently even part of the biometric-gated
inventory the engineer described, or whether (like the master key, Finding 5) it is already
effectively on-disk for at least the automation path.

### Finding 4: Reaching Mongo boxes, the Windows RDP machine, or ECS containers all require the Pritunl VPN first — the VPN credential gates network reachability independent of which credential authorizes the operation itself

**Evidence:**

> ## Step 5: Configure MongoDB Replica Set
>
> SSH to the MongoDB primary via VPN:
>
> ```
> # Connect via VPN first, then:
> ssh -i ~/.ssh/kp-4shark.pem ubuntu@{mongo-primary}.4shark.internal
> ```

**Source:** `~/Projects/4Shark/dot-claude/docs/runbooks/client-onboarding/ADD-INTEGRATOR-CLIENT.md:81-85`

> ### 1. VPN
>
> You must be connected to the company VPN to reach the ECS clusters. Without VPN access, all
> commands will fail with connection timeouts.

**Source:** `~/.claude/docs/runbooks/engineer-access/ECS-REMOTE-ACCESS.md:9-11`

**Significance:** The VPN credential (a Pritunl client PIN/profile per engineer) sits upstream of
three separate downstream operations with three separate blast radii (SSH to a Mongo box, RDP to
the Windows machine, ECS Exec into a container). Its own blast radius is narrower than any of
those — being connected to the VPN alone grants network reachability, not the ability to
authenticate to any specific resource on it. This makes the VPN credential a plausible candidate
for a different treatment than the resources it merely provides a path to.

### Finding 5: The Rails app master key and the default (read-only) AWS profile are already outside the 1Password-gated runtime path — useful contrast, not part of the inventory to reclassify

**Evidence:**

```bash
if [[ -f config/master.key ]]; then
  export RAILS_MASTER_KEY="$(< config/master.key)"
```

**Source:** `~/.claude/scripts/ruby.sh:63-64`

> This creates the **default profile** in `~/.aws/credentials`. It should have **read-only
> permissions** ... This is the profile Claude uses for day-to-day operations — no MFA required.

**Source:** `~/.claude/docs/AWS-MFA.md:110-112`

**Significance:** Both are read from a plain file on disk at invocation time — no `op` call, no
biometric prompt. They already have the property the engineer wants for the "low blast radius"
bucket (remote-able, no live approval needed), which confirms the mechanism ("put it on disk")
already exists and is already in production use elsewhere in the same workstation — this is not a
novel pattern being proposed, only an extension of one already running.

### Finding 6: The `Terraform ENV` bootstrap item is fetched via `op item get` in every stack's `.envrc`, for both `plan` and `apply` — today, retrieving it does not distinguish low-risk reads from high-risk writes

**Evidence:**

```bash
terraform_environment="$(op item get 'Terraform ENV' --vault 'Employee' --account=4shark.1password.com --format json)"

export CLOUDFLARE_API_TOKEN="$(echo "$terraform_environment" | jq -r '.fields[] | select(.label == "CLOUDFLARE_API_TOKEN").value')"
export GITHUB_TOKEN="$(echo "$terraform_environment" | jq -r '.fields[] | select(.label == "GITHUB_TOKEN").value')"
export MONGODB_ATLAS_PRIVATE_KEY="..."
export MONGODB_ATLAS_PUBLIC_KEY="..."
export ROLLBAR_API_KEY="..."
```

**Source:** `~/Projects/4Shark/terraform/identity/.envrc:6-12` (the `app-shared-001/.envrc:4-10`
variant pulls a different field subset — `MONGODB_ATLAS_*`, `REDISCLOUD_*`, `GITHUB_TOKEN` — from
the same item; full text in `credential-risk-classification_excerpt_2.md`)

> **READ commands run through the wrapper** ... it runs `init` only when needed, applies direnv
> try-first, rejects `-target`, and loads the stack env internally.

**Source:** `~/.claude/docs/TERRAFORM-POLICY.md:3`

**Significance:** The AWS-side MFA-elevation split (default profile for `plan`, `4shark-mfa` for
`apply`, per `~/.claude/docs/AWS-MFA.md:7-13`) is well-established and matches the engineer's
"terraform apply is high blast radius" framing. But the `Terraform ENV` item's non-AWS provider
credentials (Cloudflare, GitHub, MongoDB Atlas, Rollbar, Redis Cloud) are loaded identically
regardless of subcommand — a `terraform plan` on any stack today already triggers an `op item get`
against this item. Whether that specific call re-prompts Touch ID every time, or is silent within
an already-unlocked CLI-integration session, is **UNVERIFIED** in this research pass (not
independently confirmed against 1Password's CLI-integration caching behavior). What is confirmed
is that the *value* retrieved is the same high-privilege bundle whether the command is `plan` or
`apply`.

### Finding 7: The `Terraform ENV` item's `GITHUB_TOKEN` authorizes org-admin-level GitHub changes — including editing the branch-protection rules that are elsewhere relied on as a compensating control for a compromised git-push SSH key

**Evidence:**

```hcl
provider "github" {
  owner = var.github_org
}
```

**Source:** `~/Projects/4Shark/terraform/identity/providers.tf` (the `integrations/github`
provider reads `GITHUB_TOKEN` from the environment when no `token` attribute is set — none is set
here)

```hcl
resource "github_branch_protection" "master" {
  for_each = local.hubflow_repositories
  repository_id = github_repository.this[each.value].node_id
  pattern       = "master"
  enforce_admins      = false
  allows_force_pushes = false
  allows_deletions    = false
  required_pull_request_reviews {
    required_approving_review_count = 0
  }
}
```

**Source:** `~/Projects/4Shark/terraform/identity/github_repositories.tf:148-160` (the `develop`
variant is materially identical at lines 171-188; `github_team_repository` grants with
`permission = "admin"` on essentially every 4Shark repo are defined at lines 42-71/96-106 of the
same file)

**Significance:** This is the concrete mechanism behind Option D's risk-ranking question from
`remote-1password-ssh-approval/SPIKE.md` ("does the engineer agree that git push is materially
lower-stakes than terraform apply"). It shows the ranking is not fully independent: a leaked
`GITHUB_TOKEN` from the Terraform bootstrap item could, via a direct GitHub API call (bypassing
Terraform entirely), disable `allows_force_pushes`/`allows_deletions` protection on
`master`/`develop` for any HubFlow repository — the exact protections that make a compromised
git-push SSH key's blast radius look bounded in the first place. The two credentials are not
independent risk pools.

### Finding 8: The same bootstrap item's `CLOUDFLARE_API_TOKEN` manages public DNS for every 4Shark-owned domain

**Evidence:** Terraform files present under `~/Projects/4Shark/terraform/dns/`:
`public_dns_4shark_com_br.tf`, `public_dns_4sharkpay_com.tf`, `public_dns_app4shark_com.tf`,
`public_dns_app4shark_com_br.tf`, `public_dns_4shark_com.tf`, `redirect_app4shark_com.tf`,
`redirect_app4shark_com_br.tf` — all authenticated via the `cloudflare` provider, which sources
`CLOUDFLARE_API_TOKEN` from environment (per `identity/providers.tf:7` `provider "cloudflare" {}`
with no explicit token — same pattern as the GitHub provider).

**Source:** directory listing of `~/Projects/4Shark/terraform/dns/` (file names only; contents not
individually read in this pass — the provider-auth pattern is confirmed via `identity/providers.tf`)

**Significance:** A compromise of this single 1Password item reaches DNS control for 4Shark's
production domains (`4shark.com`, `4shark.com.br`, `4sharkpay.com`, `app4shark.com`,
`app4shark.com.br`) — a vector for phishing infrastructure or traffic interception that has
nothing to do with AWS IAM and is therefore not mitigated by the `4shark-mfa` elevation gate at
all.

### Finding 9: The AWS MFA elevation flow (`/elevate-aws-access`) is the credential the engineer's own worked example (`terraform apply`) already routes through, and it is deliberately biometric by design

**Evidence:**

> **Elevation is only needed when a write operation fails with `AccessDenied`** — including
> `terraform apply`. Read-only commands (`aws describe`, `terraform plan`, etc.) use the default
> profile and do not require elevation.

**Source:** `~/.claude/docs/AWS-MFA.md:11-13`

> The `/elevate-aws-access` skill automates the MFA elevation flow using 1Password and Windows
> Hello — the engineer never types a TOTP code manually.

**Source:** `~/.claude/docs/AWS-MFA.md:10-11`

**Significance:** This confirms the AWS write-path already implements the exact split the engineer
is proposing more generally: reads (`plan`, `describe`) are unrestricted/non-biometric; writes
(`apply`, any AWS mutation) require a live, biometric-gated elevation. This flow is the strongest
existing precedent for "high blast radius stays biometric," and it is scoped correctly for AWS —
but per Finding 6/7/8 it does **not** cover the non-AWS credentials (`GITHUB_TOKEN`,
`CLOUDFLARE_API_TOKEN`, Atlas keys) that ride along in the same `.envrc` load for every stack.

## Inventory and classification proposal

| Credential | Purpose / destination | Where it lives today | Blast radius if compromised | Reversibility of a mistake | Proposed classification | Existing mitigating control |
|---|---|---|---|---|---|---|
| **Personal GitHub SSH key** | `git push`/pull over SSH to GitHub (the original trigger incident) | 1Password SSH agent, biometric (Findings 1-2, `remote-1password-ssh-approval/SPIKE.md`) | Push access to repos the engineer's account can reach; cannot itself merge a PR or bypass branch protection | High — `git revert`, PR rejection, branch protection blocks force-push/deletion on `develop`/`master` (Finding 7 evidence) | **REMOTE-ABLE** — extraction mechanics (Service Account + `op read`, or a GitHub deploy key) already researched in full in `remote-1password-ssh-approval/SPIKE.md` Findings 10-17 | GitHub branch protection (`allows_force_pushes=false`, `allows_deletions=false` — Finding 7); PR review workflow |
| **`kp-4shark` EC2 key pair** | SSH into: 5× integrator MongoDB replica-set boxes (primary/secondary/arbiter each), the Atento Windows RDP machine (+ Administrator password decryption), the Pritunl VPN EC2 host (Findings 2-3) | Documented automation flow uses a literal `~/.ssh/kp-4shark.pem` file + `ssh-add`; whether the *interactive* developer session instead goes through the 1Password SSH agent is **UNVERIFIED** (Finding 3) | Direct shell access to boxes holding live, unencrypted-at-the-app-layer customer MongoDB data (any client, any collection) and the VPN host's internal view of the network; RDP password decryption for the Windows box | Low — a `db.dropDatabase()` or a bad `rs.reconfig()` run over an SSH session bypasses every application-layer guard/audit; recovery depends on backups/replica resync, not a git revert | **Candidate: MACHINE-BOUND** given the blast radius and low reversibility — but this is explicitly one of the genuinely debatable rows (see Open Decisions) | VPN required first (network-layer gate, Finding 4); no branch-protection-equivalent exists at the database layer |
| **`4Shark-key` EC2 key pair** | Attached to ECS-host EC2 capacity for app-shared-001, app-atento-001, app-beta-001, app-demo-001, `setup` (Finding 2) | Referenced only in `terraform.tfvars`; no README/runbook/ansible documents interactive use | **UNVERIFIED usage** — if genuinely unused (ECS Exec is the documented access path, Finding 5's sibling evidence), its practical blast radius today may be near-zero because nobody holds/uses the private half | N/A pending usage confirmation | **Not classifiable without engineer input** — first question is whether this key is used at all | ECS Exec (IAM + SSM) is the documented alternative access path, independent of this key |
| **Pritunl VPN client PIN/profile (per-engineer)** | Network-level access to the private VPC — prerequisite for SSH to Mongo/Windows boxes and for ECS Exec (Finding 4) | 1Password LOGIN item ("VPN PINs" — `credential-hygiene/PLAN.md:51`) | Network reachability only — does not itself authenticate to any specific resource; still requires `kp-4shark`/IAM on top | High — revoking a Pritunl user is immediate and has no data-destructive side effect on its own | **Candidate: REMOTE-ABLE** (low blast radius on its own) — but the on-disk equivalent is mechanically different from an SSH key (a VPN client profile/PIN, not a keypair); see Open Decisions | None specific — narrower blast radius is itself the mitigating factor |
| **Pritunl VPN *admin panel* login** | Managing all VPN users (infra-admin capability, not routine per-engineer use) | Slated for the restricted Break-Glass vault (`mapa-de-vaults-1password.md:24`, `categorizacao-vaults-1password.md:43`) | Could add/remove any engineer's VPN access org-wide | Medium — access revocation is reversible, but a malicious grant could persist unnoticed | **MACHINE-BOUND / out of general engineer scope** — already earmarked for the TI-responsible-only Break-Glass vault, not a per-engineer daily-use credential | Vault membership already restricted to one person (per the vault-tiering study) |
| **AWS MFA TOTP item ("Amazon AWS - <Name>", per-engineer)** | Drives `/elevate-aws-access` → temporary `4shark-mfa` STS session for all AWS write operations, including `terraform apply` | 1Password TOTP field, biometric via Windows Hello/Touch ID (`AWS-MFA.md:10-13`) | Everything the engineer's elevated IAM role can write in AWS — bounded by `identity/policy_engineer_terraform_*.tf` (per `IDENTITY-STACK.md`), but that scope is broad (ECS, RDS, S3, IAM policy edits) | Varies by the specific write — from an ECS scale change (trivially reversible) to a stateful-resource `terraform destroy` (not reversible) | **MACHINE-BOUND** — this is the engineer's own worked example | `identity/policies_baseline.tf` vs MFA-elevated split (`IDENTITY-STACK.md`); 1-hour session expiry |
| **"Terraform ENV" bootstrap item (shared, Employee vault)** | `.envrc` → `op item get` in every stack, for both `plan` and `apply` — exports `CLOUDFLARE_API_TOKEN`, `GITHUB_TOKEN`, `MONGODB_ATLAS_PRIVATE_KEY`/`PUBLIC_KEY`, `ROLLBAR_API_KEY`, and (per-stack) `REDISCLOUD_ACCESS_KEY`/`SECRET_KEY` (Finding 6) | 1Password item, read via `op` CLI on every terraform invocation | Very high, and **not bounded by the AWS MFA-elevation gate**: org-admin GitHub changes including branch protection (Finding 7), public DNS for every 4Shark domain (Finding 8), MongoDB Atlas org-level actions, Rollbar | Varies by provider — a DNS change or a disabled branch-protection rule can be silently exploited before anyone notices; not a git-revertable mistake | **MACHINE-BOUND** — reaches three external providers with no AWS-side compensating control | None specific to the non-AWS fields; the AWS profile split does not apply to this item |

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Move the GitHub SSH key to a dedicated on-disk/Service-Account-extracted credential (REMOTE-ABLE) | Unblocks the original incident (remote `git push`); mechanics already fully researched | Private key material leaves 1Password's "never leaves the vault" guarantee for that one key (Finding 11, `remote-1password-ssh-approval/SPIKE.md`) | `remote-1password-ssh-approval/SPIKE.md` Findings 10-17 |
| Keep `kp-4shark` machine-bound biometric | Matches the low-reversibility, high-blast-radius profile of direct production-database shell access | Forecloses any remote/mobile DBA-style task (e.g., checking replica set status) even when the specific action intended is itself read-only | This spike, Finding 2-3 |
| Keep the Terraform ENV item's retrieval biometric regardless of `plan` vs `apply` | Simpler mental model — one gate, no per-subcommand exception logic to get wrong | Blocks even a routine `terraform plan` from a remote session, even though `plan` itself has no side effects | This spike, Finding 6 |
| Split Terraform's `Terraform ENV` item's fields by provider risk (e.g., isolate `GITHUB_TOKEN`/`CLOUDFLARE_API_TOKEN` from a lower-risk field) | Would let a genuinely low-risk stack (no github/cloudflare/dns resources) run `plan` remotely without the high-risk fields ever being fetched | No such per-stack field-scoping exists today — every stack's `.envrc` pulls the fields it lists, but the underlying 1Password ITEM read is still a single biometric-gated retrieval; splitting would mean restructuring the 1Password item itself, a change this spike does not scope | This spike, Finding 6 (inferred; not independently sourced beyond the `.envrc` evidence) |

## What remains uncertain

- **UNVERIFIED**: whether the interactive developer SSH session to a Mongo/Windows/VPN box using
  `kp-4shark` actually routes through the 1Password SSH agent (biometric per-session) or a bare
  file/standard `ssh-agent` (as the documented automation flow does). `~/.ssh/config` could not be
  read in this research pass — the file lives in a directory the local sandbox denies access to.
  This is the single most consequential open fact for the `kp-4shark` row: if the interactive path
  is already a bare file (like the ansible automation path), it may already be effectively
  REMOTE-ABLE today, contradicting this spike's working assumption that it is biometric-gated.
- **UNVERIFIED**: `4Shark-key`'s actual usage. No documentation found anywhere in
  `~/Projects/4Shark` describing who holds its private half or when it is used. It may be a dormant
  emergency-access key attached to instances that are otherwise reached exclusively via ECS Exec.
- **UNVERIFIED**: whether `op item get 'Terraform ENV' ...` triggers a fresh Touch ID/biometric
  prompt on every single invocation, or is silent within an already-unlocked 1Password
  CLI-integration session (a caching/session-duration question this research did not independently
  confirm against 1Password's own CLI-integration documentation).
- **Not investigated**: the exact IAM permission boundary reachable via `4shark-mfa` (this spike
  cites `IDENTITY-STACK.md`'s description of the baseline/MFA-elevated split but did not enumerate
  every permission in `identity/policy_engineer_terraform_*.tf`).
- **Not investigated**: whether the 4 still-open 1Password service items from the credential-hygiene
  project (`Administrador Máquinas 4Shark`, `Setup 4Shark`, `Setup Authentication`, `Yubico API
  key` — `credential-hygiene/PLAN.md:53`) belong in this classification at all; they appear to be
  service credentials rather than developer-workstation operational credentials, so this spike
  treated them as out of scope, but that boundary was not confirmed with the engineer.

## Suggested options for main and the engineer

- **Option A** — Adopt the classification proposal above as-is: GitHub SSH key and the per-engineer
  VPN PIN move toward REMOTE-ABLE; `kp-4shark`, the AWS MFA TOTP item, and the Terraform ENV
  bootstrap item stay MACHINE-BOUND. `4Shark-key`'s classification is deferred pending a usage
  check with the engineer.
- **Option B** — Treat the `kp-4shark` row as genuinely undecided rather than a default
  MACHINE-BOUND, pending the `~/.ssh/config` confirmation (the UNVERIFIED item above) — if the
  interactive path turns out to already be a bare on-disk file, the "move it to disk" step may
  already be done in practice, and the open question becomes whether to *keep* it bare or
  *retroactively* wrap it back into 1Password's biometric model given the blast radius this spike
  surfaced.
- **Option C** — Narrow the Terraform ENV item's scope before deciding its classification: since
  Finding 6-8 show the same item's retrieval is undifferentiated across `plan`/`apply` and across
  providers, the engineer may want to split the 1Password item (or the fields it exposes) by
  provider risk before applying a single REMOTE-ABLE/MACHINE-BOUND label to "the Terraform ENV
  item" as a monolith.
- **Option D** — Defer the actual "how do we move a REMOTE-ABLE credential to disk safely"
  mechanics to a follow-on PLAN — this spike's Findings answer "which credentials, and why," not
  "what does the migration script look like." The GitHub SSH key's mechanics are already fully
  scoped in `remote-1password-ssh-approval/SPIKE.md` Findings 10-17; the VPN PIN and (if
  applicable) `kp-4shark` would need their own equivalent mechanics research before any migration
  work starts.

No option above picks a side — the evidence establishes the inventory, the blast-radius facts, and
where the AWS MFA-elevation precedent does and does not reach; the engineer ratifies which
credentials actually move and the exact governing-rule wording.

## Governing rule (draft for the engineer to ratify)

**Draft wording:** *A developer-workstation credential is MACHINE-BOUND (stays in 1Password,
biometric) when a mistake or compromise made with it is (a) not fully reversible through an
existing application-layer or platform-layer control (branch protection, PR review, a `terraform
plan` review step) and (b) recovering from that mistake plausibly requires full keyboard/tooling
access at a real machine, not a phone. A credential is REMOTE-ABLE (moves to a dedicated on-disk
key) when a mistake or compromise made with it is bounded and reversible through an existing
control, so acting on it from a remote/mobile session carries materially the same risk as acting
on it from the machine.*

**Where this spike's evidence complicates a clean line:**

- The AWS MFA-elevation precedent (Finding 9) cleanly matches this rule for AWS operations, but
  Finding 6-8 show the Terraform ENV item's non-AWS credentials are NOT covered by that same gate
  today — meaning "terraform apply is machine-bound, terraform plan is not" is not yet true in
  practice, because both currently fetch the same high-privilege bundle.
- The `kp-4shark` row's classification hinges on the still-open `~/.ssh/config` question (Finding
  3) — the rule may already be satisfied or already violated in practice, and this spike could not
  determine which.
- The VPN PIN is a case where the rule's REMOTE-ABLE side is easy to justify (low blast radius) but
  the "move to a dedicated on-disk key" *mechanism* does not map cleanly (a VPN client profile is
  not an SSH key) — the rule's classification and its migration mechanics are two different
  questions, and this spike only answers the first.
