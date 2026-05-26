# PLAN — Centralized Session History Archival on S3

## Context

After researching 80+ sources on Claude Code session management (see `SPIKE.md` in this directory), the team identified that session history is valuable institutional knowledge that should be preserved centrally before local cleanup. No existing tool provides the complete pipeline, so 4Shark will build it using AWS S3, IAM, and Claude Code's SessionEnd hook.

This plan is **independent from but complementary to** the Mem0 shared memory plan (see `../claude-shared-memory/PLAN.md`). Both can be deployed separately or together. A unified plan will be created later to compile all AI infrastructure pieces.

### Decisions Made

1. **Deployment timing:** This plan will NOT be executed independently. A unified compilation plan will be created once all AI infrastructure studies are complete (this + Mem0 + any other pieces).
2. **IAM approach:** Engineers already have IAM users created manually in AWS (not in Terraform). All 3 will be imported into Terraform state and their existing permissions migrated from direct policy attachments to IAM Groups. This is both an AWS best practice (SEC03-BP02) and an opportunity to bring IAM under IaC.
3. **Engineers:** paulo (`paulo.ribeiro@4shark.com.br`), elisio (`elisio.filho@4shark.com.br`), emerson (`emerson.silva@4shark.com.br`).
4. **Privacy:** Not a concern — team is aligned on archival.
5. **IAM migration:** Existing permissions attached directly to users will be migrated to groups during this work (see Step 4 for details).

## Current Situation

- Engineers accumulate hundreds of MB of session history in `~/.claude/projects/`
- Sessions contain rich context: architectural decisions, debugging sessions, business discussions
- Data is unencrypted on local disk — security risk (laptop theft, unauthorized access)
- Claude Code's native `cleanupPeriodDays` (default 30 days) deletes sessions without archival
- No mechanism exists to preserve sessions before cleanup
- The Terraform repo at `~/Projects/4Shark/terraform/` manages all AWS infrastructure
- S3 backend: `4shark-terraform-state` (no DynamoDB lock — single operator)

## Objective / Target State

- All Claude Code sessions automatically archived to S3 on session end
- Per-engineer isolated folders with IAM-enforced access control
- Server-side encryption (SSE-KMS) with CloudTrail audit trail
- Lifecycle policy transitioning data from hot to cold to archive storage
- Local cleanup via `cleanupPeriodDays: 7` — safe because data is already in S3
- Engineers can retrieve past sessions when needed via AWS CLI

## Problem / New Feature

New infrastructure + tooling: S3 bucket with encryption, lifecycle, and per-engineer IAM access, plus a SessionEnd hook script that compresses and uploads session transcripts automatically.

## Challenges, Difficulties and Risks

- **~~Privacy:~~** ~~Engineers must be informed that sessions are archived.~~ **RESOLVED** — team is aligned, not a concern.
- **LGPD:** Sessions may contain personal data. S3 must be in `sa-east-1`. Retention policy must be documented. Right-to-deletion must be supported (per-engineer prefix makes this straightforward: `aws s3 rm --recursive`).
- **Hook reliability:** SessionEnd hook runs after session termination. If the machine loses power or the process is killed, the hook may not fire. This is acceptable — it covers 95%+ of normal exits.
- **Upload speed:** Large sessions (10-50MB raw) compress to 1-10MB. Upload over VPN should take seconds. Script runs in background to not block terminal.
- **Cost:** Negligible. Even 1GB/month compressed across all engineers costs < $0.05/month on S3 Standard, dropping to near-zero on Glacier.
- **Bug:** `cleanupPeriodDays: 0` silently disables transcript persistence (Issue #23710). Must use `7` or higher, never `0`.

## Proposed Solution

### Architecture

```
Engineer's Machine                     AWS (sa-east-1)
┌─────────────────────────┐            ┌──────────────────────────────────┐
│ Claude Code              │            │                                  │
│  └─ SessionEnd hook ─────────────────▶  S3: 4shark-claude-sessions     │
│     archive-session.sh   │  HTTPS    │  ├─ paulo/                       │
│     ├─ gzip transcript   │  (VPN)    │  │  ├─ 2026/02/                  │
│     ├─ aws s3 cp         │            │  │  │  ├─ <session-uuid>.jsonl.gz│
│     └─ background (&)    │            │  │  │  └─ ...                    │
│                          │            │  ├─ elisio/                      │
│ cleanupPeriodDays: 7     │            │  │  └─ ...                       │
│ (local cleanup after 7d) │            │  └─ emerson/                     │
│                          │            │     └─ ...                       │
└─────────────────────────┘            │                                  │
                                       │  KMS: claude-sessions-key        │
                                       │  Lifecycle:                       │
                                       │   0-30d  → Standard              │
                                       │   30-90d → Standard-IA           │
                                       │   90-365d → Glacier Flexible     │
                                       │   365d+  → Deep Archive          │
                                       └──────────────────────────────────┘
```

### Terraform Project Structure

```
~/Projects/4Shark/terraform/claude-session-archive/
├── providers.tf        # AWS provider + S3 backend
├── variables.tf        # Input variables
├── terraform.tfvars    # Variable values
├── locals.tf           # Local values, tags
├── s3.tf               # S3 bucket, lifecycle, encryption, versioning
├── kms.tf              # KMS key for SSE-KMS
├── iam_users.tf        # IAM users (imported) + group memberships
├── iam_groups.tf       # IAM groups (4shark-admins, 4shark-ecs-remote-access, claude-session-archive)
├── iam_policies.tf     # IAM policies (ECSRemoteAccess imported, session-archive new)
├── outputs.tf          # Bucket name, KMS key ARN, group ARNs
└── README.md           # Engineer onboarding guide
```

### Proposed Steps

#### Step 1 — Terraform: Project scaffold

- **`providers.tf`**: AWS provider `sa-east-1`, S3 backend key `claude-session-archive/terraform.tfstate`
- **`variables.tf`**:
  - `engineers` (map of string to string) — engineer archive name to IAM username mapping
  - `lifecycle_ia_days` (number, default 30)
  - `lifecycle_glacier_days` (number, default 90)
  - `lifecycle_deep_archive_days` (number, default 365)
- **`terraform.tfvars`**: concrete values:
  ```hcl
  engineers = {
    paulo   = "paulo.ribeiro@4shark.com.br"
    elisio  = "elisio.filho@4shark.com.br"
    emerson = "emerson.silva@4shark.com.br"
  }
  ```
- **`locals.tf`**: name_prefix = `claude-session-archive`, common tags

#### Step 2 — Terraform: KMS key

- **`kms.tf`**: KMS key `claude-sessions-key`
  - Key policy allowing engineers to encrypt/decrypt their own sessions
  - CloudTrail integration for audit trail
  - Alias: `alias/claude-sessions`

#### Step 3 — Terraform: S3 bucket

- **`s3.tf`**: Bucket `4shark-claude-sessions`
  - Versioning: enabled (protect against accidental overwrites)
  - Encryption: SSE-KMS with S3 Bucket Keys (reduces KMS API cost by ~99%)
  - Public access: blocked (all 4 block settings)
  - Lifecycle rules:
    - Transition to Standard-IA after 30 days
    - Transition to Glacier Flexible Retrieval after 90 days
    - Transition to Glacier Deep Archive after 365 days
    - (No expiration — keep forever unless manually deleted)
  - Bucket policy: deny unencrypted uploads, deny non-SSL access

#### Step 4 — Terraform: Import IAM users + migrate permissions to Groups

This is the most critical step. Engineers have IAM users created manually with policies attached directly. We will:
1. Import users into Terraform
2. Migrate existing permissions from direct attachments to IAM Groups
3. Add the new session archive group

##### Current state (manually created, not in Terraform)

| User | Direct Policy | Groups |
|------|--------------|--------|
| `paulo.ribeiro@4shark.com.br` | `AdministratorAccess` (AWS managed) | None |
| `elisio.filho@4shark.com.br` | `ECSRemoteAccess` (custom, `arn:aws:iam::405749097490:policy/ECSRemoteAccess`) | None |
| `emerson.silva@4shark.com.br` | `ECSRemoteAccess` (custom, same policy) | None |

`ECSRemoteAccess` policy (v2, created 2026-02-19) grants:
- `ecs:ListServices`, `ListTasks`, `DescribeServices`, `DescribeTasks`, `ListContainerInstances`, `DescribeContainerInstances` (all resources)
- `ecs:ExecuteCommand` (us-east-1 tasks and clusters)
- `ecs:RunTask`, `StopTask` (us-east-1 tasks and task-definitions)
- `autoscaling:DescribeAutoScalingGroups` (all resources)
- `autoscaling:SetDesiredCapacity` (only `*-runner-asg` groups)
- `iam:PassRole` to `ecsTaskExecutionRole` (ECS tasks only)
- `ssm:StartSession` (ECS tasks + ExecuteInteractiveCommand document)

##### Target state (Terraform-managed)

| User | Direct Policies | Groups |
|------|----------------|--------|
| `paulo.ribeiro@4shark.com.br` | None | `4shark-admins`, `claude-session-archive` |
| `elisio.filho@4shark.com.br` | None | `4shark-ecs-remote-access`, `claude-session-archive` |
| `emerson.silva@4shark.com.br` | None | `4shark-ecs-remote-access`, `claude-session-archive` |

##### Implementation in `iam.tf`

**a) Import IAM users:**
```bash
terraform import 'aws_iam_user.engineers["paulo"]' paulo.ribeiro@4shark.com.br
terraform import 'aws_iam_user.engineers["elisio"]' elisio.filho@4shark.com.br
terraform import 'aws_iam_user.engineers["emerson"]' emerson.silva@4shark.com.br
```

**b) Import existing ECSRemoteAccess policy:**
```bash
terraform import 'aws_iam_policy.ecs_remote_access' arn:aws:iam::405749097490:policy/ECSRemoteAccess
```

**c) Create IAM Groups and migrate:**

- Group `4shark-admins`:
  - Attach AWS managed policy `AdministratorAccess`
  - Members: paulo
  - After apply: detach `AdministratorAccess` directly from paulo's user

- Group `4shark-ecs-remote-access`:
  - Attach existing `ECSRemoteAccess` policy (imported)
  - Members: elisio, emerson
  - After apply: detach `ECSRemoteAccess` directly from elisio and emerson's users

- Group `claude-session-archive`:
  - Attach new managed policy `claude-session-archive-base` with:
    - `kms:Encrypt`, `kms:Decrypt`, `kms:GenerateDataKey` on the KMS key
  - Members: paulo, elisio, emerson
  - Per-engineer inline policies on the user (NOT the group) for S3 prefix isolation:
    - `s3:PutObject` on `arn:aws:s3:::4shark-claude-sessions/<engineer>/*`
    - `s3:GetObject` on `arn:aws:s3:::4shark-claude-sessions/<engineer>/*`
    - `s3:ListBucket` with `Condition: StringLike: s3:prefix: <engineer>/`

##### Migration sequence (order matters)

1. `terraform import` all users and the ECSRemoteAccess policy
2. `terraform plan` — verify NO destructive changes (no user deletion/recreation)
3. `terraform apply` — creates groups, attaches policies to groups, adds users to groups
4. **Manual verification:** confirm all 3 engineers can still access ECS (`aws ecs list-clusters`)
5. **Manual detach of direct policies** (after confirming groups work):
   ```bash
   aws iam detach-user-policy --user-name paulo.ribeiro@4shark.com.br --policy-arn arn:aws:iam::aws:policy/AdministratorAccess
   aws iam detach-user-policy --user-name elisio.filho@4shark.com.br --policy-arn arn:aws:iam::405749097490:policy/ECSRemoteAccess
   aws iam detach-user-policy --user-name emerson.silva@4shark.com.br --policy-arn arn:aws:iam::405749097490:policy/ECSRemoteAccess
   ```
6. Run `terraform plan` again — should show no changes (Terraform now owns everything)

> **IMPORTANT:** Steps 3 and 5 are deliberately separate. First ADD group-based permissions (step 3), VERIFY they work (step 4), THEN remove direct attachments (step 5). This prevents any window where engineers lose access.
>
> **Alternative (safer):** Manage the detach in Terraform itself using `aws_iam_user_policy_attachment` resources with `lifecycle { prevent_destroy = true }` initially, then remove them in a subsequent apply. This keeps everything in IaC but requires two applies.

#### Step 5 — Hook script: `~/.claude/scripts/archive-session.sh`

This script is triggered by the SessionEnd hook and runs in background:

```bash
#!/bin/bash
# Archive Claude Code session to S3
# Triggered by SessionEnd hook
# Runs in background to not block terminal

set -euo pipefail

# Configuration
BUCKET="4shark-claude-sessions"
ENGINEER="${CLAUDE_ARCHIVE_ENGINEER:-$(whoami)}"
REGION="sa-east-1"

# SessionEnd hook provides these via environment/stdin
# Parse from stdin JSON (hook input format)
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // empty')
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')

# Validate
if [[ -z "$SESSION_ID" || -z "$TRANSCRIPT_PATH" || ! -f "$TRANSCRIPT_PATH" ]]; then
    exit 0  # Silent exit — nothing to archive
fi

# Compress
COMPRESSED="/tmp/claude-session-${SESSION_ID}.jsonl.gz"
gzip -c "$TRANSCRIPT_PATH" > "$COMPRESSED"

# Upload with date-based prefix
YEAR_MONTH=$(date +%Y/%m)
S3_KEY="${ENGINEER}/${YEAR_MONTH}/${SESSION_ID}.jsonl.gz"

aws s3 cp "$COMPRESSED" "s3://${BUCKET}/${S3_KEY}" \
    --region "$REGION" \
    --sse aws:kms \
    --quiet \
    2>/dev/null

# Cleanup temp file
rm -f "$COMPRESSED"
```

#### Step 6 — Hook configuration in `settings.json`

Add to the shared `settings.json`:

```json
{
  "hooks": {
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$HOME/.claude/scripts/archive-session.sh &",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

And set cleanup period:

```json
{
  "cleanupPeriodDays": 7
}
```

#### Step 7 — Retrieval script: `~/.claude/scripts/retrieve-session.sh`

Convenience script for engineers to find and download past sessions:

```bash
#!/bin/bash
# List or retrieve archived sessions
# Usage:
#   retrieve-session.sh list [month]       — list sessions (e.g., list 2026/02)
#   retrieve-session.sh get <session-id>   — download and decompress a session
#   retrieve-session.sh search <pattern>   — search session content (requires download)

BUCKET="4shark-claude-sessions"
ENGINEER="${CLAUDE_ARCHIVE_ENGINEER:-$(whoami)}"
REGION="sa-east-1"

case "${1:-list}" in
  list)
    PREFIX="${ENGINEER}/${2:-}"
    aws s3 ls "s3://${BUCKET}/${PREFIX}" --recursive --region "$REGION"
    ;;
  get)
    SESSION_ID="$2"
    # Find the session
    KEY=$(aws s3 ls "s3://${BUCKET}/${ENGINEER}/" --recursive --region "$REGION" \
      | grep "$SESSION_ID" | awk '{print $4}')
    if [[ -n "$KEY" ]]; then
      OUTPUT="/tmp/claude-session-${SESSION_ID}.jsonl"
      aws s3 cp "s3://${BUCKET}/${KEY}" - --region "$REGION" | gunzip > "$OUTPUT"
      echo "Downloaded to: $OUTPUT"
    else
      echo "Session not found: $SESSION_ID"
      exit 1
    fi
    ;;
  search)
    echo "Search requires downloading sessions first. Use 'list' to find sessions, then 'get' to download."
    ;;
esac
```

#### Step 8 — Documentation (`README.md` in Terraform project)

Document:
1. What is archived and why
2. How to configure AWS CLI credentials
3. How to set `CLAUDE_ARCHIVE_ENGINEER` environment variable
4. How to list and retrieve past sessions
5. How to request deletion (LGPD right-to-deletion)
6. Lifecycle policy explanation (retrieval times for Glacier)

### Memory Scoping Strategy (combined with Mem0)

| Need | Solution | Tool |
|------|----------|------|
| "What did I discuss about X last week?" | S3 archival → retrieve + search | `retrieve-session.sh` |
| "What architectural decision did the team make about Y?" | Mem0 semantic memory | Claude Code MCP |
| "Show me the exact conversation where we debugged Z" | S3 archival → retrieve full transcript | `retrieve-session.sh get` |
| "What patterns does the team use for authentication?" | Mem0 shared knowledge | Claude Code MCP |

## Internal References

- Spike: `SPIKE.md` (same directory)
- Mem0 plan: `../claude-shared-memory/PLAN.md`
- Mem0 spike: `../claude-shared-memory/SPIKE.md`
- Terraform repo: `~/Projects/4Shark/terraform/`
- S3 backend: `4shark-terraform-state`
- Region: `sa-east-1` (LGPD compliance)
- Shared settings: `~/.claude/settings.json`
- Scripts directory: `~/.claude/scripts/`

## Verification

### Phase 1 — Infrastructure
1. `terraform init` — verify S3 backend connects
2. `terraform import` — import all 3 IAM users + ECSRemoteAccess policy (see Step 4)
3. `terraform plan` — verify NO destructive changes on imported resources
4. `terraform apply` — deploy S3 bucket, KMS key, IAM groups, group memberships
5. Verify bucket: `aws s3 ls s3://4shark-claude-sessions/`
6. Verify encryption: `aws s3api get-bucket-encryption --bucket 4shark-claude-sessions`
7. Verify lifecycle: `aws s3api get-bucket-lifecycle-configuration --bucket 4shark-claude-sessions`

### Phase 2 — IAM migration
8. Verify each engineer can still access ECS via group permissions (before detaching direct policies)
9. Detach direct policies from users (see Step 4 migration sequence)
10. `terraform plan` — should show no changes
11. Test IAM isolation: engineer A cannot access engineer B's S3 prefix

### Phase 3 — Hook and archival
12. Deploy `archive-session.sh` and `retrieve-session.sh` to all engineers' `~/.claude/scripts/`
13. Update `settings.json` with SessionEnd hook + `cleanupPeriodDays: 7`
14. Test: start and end a Claude Code session, verify file appears in S3 under correct engineer prefix
15. Test retrieval: `retrieve-session.sh list` and `retrieve-session.sh get <id>`
16. After 7+ days: verify local sessions are cleaned up by `cleanupPeriodDays`
