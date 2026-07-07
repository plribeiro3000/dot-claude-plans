<!-- Auxiliary file for SPIKE.md — credential-risk-classification -->
<!-- Raw evidence: interactive/automation use of kp-4shark.pem, VPN prerequisite, and what is
     already off the 1Password-gated path (master key, ECS Exec, default AWS profile) -->

# Excerpt 3 — SSH-to-a-box mechanics, VPN prerequisite, and what is already NOT gated

## `~/Projects/4Shark/ansible/README.md` (lines 80–84)

```
**Be Aware**: In order to use this automation system you **must** be connected to 4Shark VPN and add `kp-4shark.pem`

ssh-add ~/.ssh/kp-4shark.pem
```

## `~/Projects/4Shark/ansible/group_vars/all/all.yml` (line 6)

```yaml
ansible_ssh_private_key_file: "~/.ssh/kp-4shark.pem"
```

## `dot-claude/docs/runbooks/client-onboarding/ADD-INTEGRATOR-CLIENT.md` (lines 79–97)

```
## Step 5: Configure MongoDB Replica Set

SSH to the MongoDB primary via VPN:

    # Connect via VPN first, then:
    ssh -i ~/.ssh/kp-4shark.pem ubuntu@{mongo-primary}.4shark.internal

    # Initialize replica set (first time only)
    mongosh
    rs.initiate({...})
```

**Note on an open question this raises:** both documented flows reference a literal file at
`~/.ssh/kp-4shark.pem` loaded via `ssh-add` / `-i`, i.e., the standard OpenSSH agent/file
mechanism — not explicitly the 1Password SSH agent. This SPIKE's background premise states "every
privileged action ... raises a Touch ID prompt," which would only be true for this key if the
developer's `~/.ssh/config` routes the relevant `Host` (or `IdentityAgent`) at the 1Password
socket AND the private key material is stored inside 1Password rather than as a bare file on disk.
`~/.ssh/config` could not be read in this research pass (denied by the local sandbox's directory
permissions), so this SPIKE cannot confirm which of the two mechanisms governs the *interactive*
developer SSH session today — only that the documented *automation* (ansible) flow uses a literal
file. Flagged as UNVERIFIED / an open question for the engineer in the main SPIKE document.

## `~/.claude/docs/runbooks/vpn/PRITUNL-VPN-OPERATIONS.md` (lines 1–52, key excerpts)

```
# Runbook: Pritunl VPN Operations

Operational notes for the Pritunl VPN server — log access, restart implications, lockout
recovery, and DNS requirements.

Pritunl stores logs in MongoDB, not in a flat file...

Stopping or restarting the Pritunl server disconnects all connected clients immediately. There is
no graceful drain.

- Plan how you will reach the admin panel without VPN access (typically: bastion access, or a
  temporary AWS console session). The admin panel is not reachable from the public internet by
  default.
```

## `~/.claude/docs/runbooks/engineer-access/ECS-REMOTE-ACCESS.md` (lines 1–11)

```
# ECS Remote Access

Remote access to production and staging environments via ECS Exec. This tool allows you to open a
Rails console or run commands directly on the ECS containers.

## Prerequisites

### 1. VPN

You must be connected to the company VPN to reach the ECS clusters. Without VPN access, all
commands will fail with connection timeouts.
```

**Significance:** ECS Exec (the standard way to reach a running container) uses AWS IAM + SSM
Session Manager — no SSH key at all — but it still requires the VPN to be up first. This confirms
the VPN credential gates network reachability for MULTIPLE downstream operations (SSH to Mongo
boxes, RDP to the Windows machine, ECS Exec), independent of which specific credential authorizes
the operation itself once on the network.

## What this research confirms is already OFF the 1Password-gated path (context, not part of the inventory)

### `~/.claude/scripts/ruby.sh` (lines 63–64)

```bash
if [[ -f config/master.key ]]; then
  export RAILS_MASTER_KEY="$(< config/master.key)"
```

The Rails app master key is read directly from a per-repo, git-ignored file on disk — not fetched
from 1Password at invocation time. (A copy is separately kept in 1Password as the source-of-truth
backup — see `credential-hygiene/PLAN.md` "KEPT" list, "4Shark App Master Key" — but the *runtime*
path for a Ruby command never touches 1Password.)

### `~/.claude/docs/AWS-MFA.md` (lines 105–113, 134–146)

```
1. AWS CLI installed and configured with base credentials (read-only access):
   aws configure
   # Set: AWS Access Key ID, AWS Secret Access Key, Default region (us-east-1)
   This creates the default profile in ~/.aws/credentials. ... This is the profile Claude uses for
   day-to-day operations — no MFA required.
```

The default (read-only) AWS profile's access keys are entered once into `~/.aws/credentials` during
initial setup and are not re-fetched from 1Password on each command — this profile is already a
static on-disk credential for day-to-day read operations, independent of the biometric-gated
`4shark-mfa` elevation flow used for writes.
