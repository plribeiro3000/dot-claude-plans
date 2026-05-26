# SPIKE — AWS EC2 Key Pair Management and Standardization

**Conducted by:** Engineering Team
**Date:** 2026-02-27
**Status:** Research complete — decision made (see below)

---

## Goal

The 4Shark infrastructure has key pairs created inconsistently across regions and environments, with names like "PRD", "4Shark", or ad-hoc environment names. This investigation answers the following questions:

1. Can key pairs be replaced on running EC2 instances without downtime?
2. What does the community recommend for key pair organization (per environment, per service, per region)?
3. What are the best practices for key pair naming conventions?
4. What are the modern alternatives to key pairs in 2026?
5. What are the security risks of shared keys, and what does the AWS Well-Architected Framework recommend?
6. What is the safest rollout strategy for rotating keys across existing infrastructure?

---

## Method

- Reviewed AWS official documentation (EC2 User Guide, Systems Manager, Well-Architected Framework)
- Researched community articles from cloudonaut, The Hidden Port, Red Hat, Fedora Magazine, and Medium
- Reviewed Ansible documentation for the `amazon.aws.ec2_key` module and the `amazon.aws.aws_ssm` connection plugin
- Reviewed AWS re:Post knowledge base articles

---

## Evidence

### Question 1: Can you replace a key pair on a running EC2 instance?

**Yes — and without stopping the instance.** AWS supports this, but the mechanism is important to understand.

The `authorized_keys` file is what AWS actually uses during login, not the key pair name registered in the EC2 console. The console key pair is only used when the instance is launched — specifically to inject the initial public key. After that, the `~/.ssh/authorized_keys` file on the instance is the authoritative source.

**Method 1 — Direct SSH (requires current access):**
If you have SSH access to the instance, you can edit `~/.ssh/authorized_keys` directly:
1. Connect to the instance using the current key
2. Add the new public key to `~/.ssh/authorized_keys`
3. Verify login works with the new key before removing the old one
4. Remove the old key from `~/.ssh/authorized_keys`

This is the safest method and causes zero downtime. The AWS console will still show the old key pair name, but that is cosmetic only — it does not reflect actual access.

**Method 2 — EC2 Instance Connect (for Amazon Linux 2 / AL2023 / Ubuntu):**
EC2 Instance Connect can be used to push a one-time SSH public key to an instance through the instance metadata service, valid for 60 seconds. This can be used to bootstrap access when the original key is unavailable.

**Method 3 — AWSSupport-ResetAccess SSM Runbook (last resort):**
The AWS-provided `AWSSupport-ResetAccess` automation runbook uses EC2Rescue to inject a new SSH key into a Linux instance. It **requires stopping the instance**, creates a helper VPC, and attaches the root volume to a temporary instance to modify the keys. This causes downtime and a public IP change if no Elastic IP is assigned. This should only be used as a recovery method when all other access is lost.

**Method 4 — Ansible playbook targeting `authorized_keys`:**
For fleet-wide rotation, an Ansible playbook can SSH into all instances using the current key and add/remove entries in `~/.ssh/authorized_keys`. This is the recommended approach for 4Shark given the existing Ansible infrastructure.

**Source:** [Add or replace a public key on your Linux instance — AWS Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/replacing-key-pair.html)

---

### Question 2: Key pair organization — one per environment, service, or region?

There is no single authoritative AWS answer, but the community converges on a clear direction:

**Option A — One key for the entire infrastructure**
- Simple to manage
- Maximum blast radius: a single compromise exposes every instance in every environment
- Strongly discouraged for production by the security community

**Option B — One key per environment (prod, staging, dev)**
- Reduces blast radius between environments
- Still shares keys across all services within an environment
- Acceptable minimum floor for small teams

**Option C — One key per service/application**
- Aligns with the principle of least privilege
- A compromised key only exposes one service, not the whole environment
- Increases the number of keys to manage, but automation (Ansible) handles this well

**Option D — One key per region**
- Addresses the AWS technical constraint (keys are region-scoped)
- Does NOT address the security blast-radius problem — one key still covers all services/environments in that region
- Can be combined with Options B or C

**Community consensus (cloudonaut, AWS re:Post, Medium):**
The recommended approach is **per-user keys**, not per-environment or per-service. Every engineer should have their own SSH key, and that key should be pushed to the instances they are authorized to access. The EC2 console key pair construct is a legacy mechanism; modern practice uses `authorized_keys` directly (via Ansible/cloud-init/IaC).

For organizations still relying on key pairs, the recommended minimum is: **separate keys per environment**, with each key pushed to the relevant instances during provisioning.

For 4Shark's context (multiple engineers, Ansible automation, multi-region), the pragmatic recommended structure is:
- One key pair **per environment** (production, staging, dev) registered in AWS
- The key pair is used only for the initial instance bootstrap (cloud-init)
- Each engineer has their own personal SSH key added to `authorized_keys` via Ansible at provisioning time
- The shared "bootstrap" key pair is stored in AWS Secrets Manager

**Sources:**
- [Avoid Sharing Key Pairs for EC2 — cloudonaut](https://cloudonaut.io/avoid-sharing-key-pairs-for-ec2/)
- [Best Practices for Managing SSH Keys on EC2 Instances — Medium](https://medium.com/@krishtech/best-practices-for-managing-ssh-keys-on-ec2-instances-500260e9f035)
- [Can I use a single key pair for multiple EC2 instances? — Quora](https://www.quora.com/Can-I-use-a-single-key-pair-for-multiple-EC2-instances-in-AWS)

---

### Question 3: Naming conventions for key pairs

AWS documentation does not prescribe a specific naming format for key pairs. The community converges on the following pattern:

**Recommended pattern:**
```
{company}-{environment}-{region}-{purpose}
```

**Examples for 4Shark:**
```
4shark-production-us-east-1-default
4shark-production-sa-east-1-default
4shark-staging-us-east-1-default
4shark-staging-sa-east-1-default
4shark-development-us-east-1-default
```

**Why this structure:**
- `{company}` — prevents name collision when multiple organizations share an account (uncommon but safe)
- `{environment}` — the most critical component; separates prod from staging from dev
- `{region}` — key pairs are region-scoped; encoding the region prevents operational confusion (trying to use `4shark-production-us-east-1` in `sa-east-1` will fail)
- `{purpose}` — use `default` for the standard bootstrap key; use a specific name if the key serves a specialized role

**What to avoid:**
- Names like `PRD`, `4Shark`, `key-pair-1` — lack environment, region, and purpose context
- Uppercase — inconsistent with AWS CLI conventions and automation tooling
- Spaces and special characters — cause quoting issues in scripts

**AWS guidance:** AWS itself notes that names should encode ownership and environment to support audits and security reviews. The general standard for AWS resource naming is `lowercase-hyphen-separated` with environment and region identifiers.

**Sources:**
- [7 Key AWS Naming Standards — Taytly](https://www.taytly.com/blog/aws-naming-standards)
- [Amazon AWS pem key naming conventions — Coderwall](https://coderwall.com/p/dvwfaw/amazon-aws-pem-key-naming-conventions)
- [AWS Naming Conventions Best Practices — Carlos Requena](https://cjrequena.com/2020-06-05/aws-naming-conventions-en)

---

### Question 4: Modern alternatives to key pairs in 2026

Three mature alternatives exist. All three are generally available and used in production by major organizations.

**Alternative 1 — AWS Systems Manager Session Manager**

Session Manager provides browser-based or CLI-based shell access to EC2 instances without requiring SSH keys, open inbound ports, or bastion hosts. Authentication is handled entirely through IAM.

Requirements:
- SSM Agent installed on the instance (pre-installed on Amazon Linux 2, AL2023, Ubuntu 16.04+)
- IAM role with `AmazonSSMManagedInstanceCore` policy attached to the instance
- Outbound HTTPS (port 443) access from the instance to AWS endpoints

Key properties:
- Every session is logged to CloudWatch Logs or S3
- Access is revoked by revoking IAM permissions — no need to remove keys from instances
- Works without a public IP address
- Supports SSH tunneling via `ProxyCommand` — existing SSH tooling (including Ansible) continues to work

**Ansible integration:** The `amazon.aws.aws_ssm` connection plugin (promoted to full Red Hat support in version 10.0.0) allows Ansible to connect to instances via SSM instead of SSH. This is the current recommended approach for Ansible-based infrastructure in 2025/2026.

**Alternative 2 — EC2 Instance Connect**

EC2 Instance Connect generates a one-time-use SSH key pair per session, valid for 60 seconds. IAM credentials authorize the connection. Unlike Session Manager, it still uses SSH under the hood but eliminates long-lived key management.

Important caveat (cloudonaut): EC2 Instance Connect is **enabled by default on Amazon Linux 2 and Ubuntu AMIs** and may allow any IAM user with the right policy to SSH into any instance. This is a security risk if IAM permissions are not tightly scoped. The cloudonaut team explicitly calls this an "insecure default" and recommends either configuring it properly or preferring Session Manager.

**Alternative 3 — EC2 Instance Connect Endpoint (EICE)**

Released in 2023, EICE is an identity-aware TCP proxy that allows SSH and RDP access to instances **without a public IP address** and **without opening inbound security group rules**. It supports both EC2 Instance Connect and standard SSH. It bridges the gap for teams that need SSH access to private instances.

**Verdict for 2026:**
The security community (AWS, cloudonaut, Red Hat) converges on Session Manager as the modern standard. Key pairs are a legacy mechanism — they remain supported but are no longer the recommended primary access method for production infrastructure.

**Sources:**
- [AWS Systems Manager Session Manager — AWS Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [Securing EC2 Access with AWS Systems Manager Session Manager — The Hidden Port](https://thehiddenport.dev/posts/aws-securing-ec2-access-with-ssm/)
- [Still Using EC2 Key Pairs? Switch to Session Manager Now! — QloudX](https://www.qloudx.com/still-using-ec2-key-pairs-switch-to-session-manager-now/)
- [EC2 Instance Connect is an insecure default! — cloudonaut](https://cloudonaut.io/ec2-instance-connect-is-an-insecure-default/)
- [Goodbye SSH, use AWS Session Manager instead — cloudonaut](https://cloudonaut.io/goodbye-ssh-use-aws-session-manager-instead/)
- [What's new in cloud automation: Red Hat Ansible AWS 10.0.0](https://www.redhat.com/en/blog/whats-new-in-cloud-automation-red-hat-ansible-aws-10.0.0)
- [amazon.aws.aws_ssm connection plugin — Ansible Documentation](https://docs.ansible.com/projects/ansible/latest/collections/amazon/aws/aws_ssm_connection.html)

---

### Question 5: Security risks — shared keys vs per-service keys, and Well-Architected guidance

**Risks of shared keys:**

1. **Blast radius:** A single compromised key grants SSH access to every instance sharing that key. With one key covering all of production, a single leaked `.pem` file is a full production breach.

2. **No individual accountability:** Shared keys cannot be attributed to a specific engineer. Audit logs show logins from the same key regardless of which person used it, breaking the forensics trail.

3. **Revocation complexity:** To revoke access for one engineer from a shared key, you must rotate the key on every instance — affecting every other engineer simultaneously.

4. **Long-lived credentials:** Key pairs are permanent unless explicitly rotated. They do not expire. This violates the AWS Well-Architected principle of eliminating reliance on long-term static credentials.

5. **Leak surfaces:** The `.pem` file travels across machines, email, Slack, password managers, and developer laptops. Each copy is a potential leak.

**AWS Well-Architected Framework guidance:**

The Security Pillar's Identity and Access Management section identifies two relevant design principles:
- **Strong identity foundation:** Implement the principle of least privilege; centralize identity management.
- **Eliminate long-term static credentials:** Prefer temporary credentials via IAM roles; avoid credentials that do not expire.

SSH key pairs are long-lived static credentials. The Well-Architected Framework implicitly points away from them in favor of IAM-based access (Session Manager). AWS's own security team, as of July 2025, explicitly recommends using EC2 Instance Connect with IAM policies instead of managing SSH keys.

**Specific risk for 4Shark:**
The current state (inconsistently named keys, unclear ownership) suggests that audit and revocation procedures are undefined. If any engineer leaves the company or a key is accidentally committed to a repository, there is no clear procedure to identify which instances are affected or how to rotate the key.

**Sources:**
- [Security Pillar — AWS Well-Architected Framework](https://docs.aws.amazon.com/wellarchitected/latest/security-pillar/identity-and-access-management.html)
- [Avoid Sharing Key Pairs for EC2 — cloudonaut](https://cloudonaut.io/avoid-sharing-key-pairs-for-ec2/)
- [EC2 Key Sharing: Issues and Remedies — Tensult / Medium](https://medium.com/tensult/ec2-key-sharing-issues-and-remedies-d4ff677a88be)
- [Reducing the Blast Radius — Blast Security](https://blast.security/blog/reducing-the-blast-radius-a-practical-guide-to-containing-cloud-risk-before-it-spreads/)
- [Unused AWS EC2 Key Pairs — Trend Micro Conformity](https://www.trendmicro.com/cloudoneconformity/knowledge-base/aws/EC2/unused-key-pairs.html)

---

### Question 6: Rollout strategy for rotating keys across existing infrastructure

Given that 4Shark already uses Ansible, rotation is achievable without downtime. The key insight is that changing `authorized_keys` on running instances is non-destructive — the instance keeps running, services keep running, only SSH access is modified.

**Safe rotation sequence (Ansible-based):**

**Phase 1 — Inventory and audit (no changes)**
1. Use AWS CLI to list all key pairs across all regions: `aws ec2 describe-key-pairs --region <region>`
2. Use AWS CLI to identify which instances use which key pair: `aws ec2 describe-instances --query "Reservations[*].Instances[*].[InstanceId,KeyName]"`
3. Map current state: which key covers which instances in which region/environment
4. Store current `.pem` files in AWS Secrets Manager (if not already done)

**Phase 2 — Create standardized key pairs**
Using Ansible's `amazon.aws.ec2_key` module, create the new standardized key pairs in each region:
```yaml
- name: Create standardized key pairs
  amazon.aws.ec2_key:
    name: "4shark-{{ environment }}-{{ region }}-default"
    key_material: "{{ lookup('file', '~/.ssh/4shark_{{ environment }}.pub') }}"
    region: "{{ region }}"
    state: present
```
Loop through `[production, staging, development]` x `[us-east-1, sa-east-1]` = 6 key pairs.

**Phase 3 — Add new keys to running instances (additive, no removal yet)**
Using an Ansible playbook that connects via the existing (old) key, add the new public key to `~/.ssh/authorized_keys` on every instance. This step is safe — it only adds access, it does not remove anything.

**Phase 4 — Verify new key access**
Verify from a test machine that the new key provides SSH access to a sample of instances in each environment and region before proceeding.

**Phase 5 — Remove old keys from instances**
After verification, run another Ansible playbook to remove the old public key from `authorized_keys`. At this point, the old key pair name in the EC2 console is stale (cosmetic only) — it correctly no longer works.

**Phase 6 — Delete old key pairs from AWS**
Remove the orphaned key pair entries from the EC2 console using: `aws ec2 delete-key-pair --key-name <old-name> --region <region>`

**Multi-region handling:**
The `amazon.aws.ec2_key` module accepts a `region` parameter. A single playbook with a loop over regions handles the creation uniformly. Key material is the same public key content imported into each region — the private key is stored once in Secrets Manager.

**For importing the same key into multiple regions:**
```bash
# Extract public key from existing .pem
ssh-keygen -y -f existing-key.pem > existing-key.pub

# Import to each region
for region in us-east-1 sa-east-1; do
  aws ec2 import-key-pair \
    --key-name "4shark-production-${region}-default" \
    --public-key-material fileb://existing-key.pub \
    --region $region
done
```

**Critical safety rules during rollout:**
- Never remove the old key before verifying the new key works
- Keep at least one working access path to every instance throughout the process
- Run Phase 3 and Phase 5 during off-peak hours for production
- Test the full sequence in staging first

**Sources:**
- [amazon.aws.ec2_key module — Ansible Community Documentation](https://docs.ansible.com/projects/ansible/latest/collections/amazon/aws/ec2_key_module.html)
- [Using Ansible to organize your SSH keys in AWS — Fedora Magazine](https://fedoramagazine.org/ssh-key-aws-regions/)
- [How to use the same SSH key pair in all AWS regions — Fedora Magazine](https://fedoramagazine.org/ssh-key-aws-regions/)
- [GitHub: aws-key-rotation Ansible Playbook — sebinxavi](https://github.com/sebinxavi/aws-key-rotation)
- [Use one SSH key pair for Amazon EC2 in all Regions — AWS re:Post](https://repost.aws/knowledge-center/ec2-ssh-key-pair-regions)
- [Rotate Your AWS EC2 Key Pair Using the AWS SDK for Python — devopsetc](https://devopsetc.com/post/ec2-keypair-rotation/)

---

## Conclusions

### 1. Key pairs CAN be replaced on running instances without downtime

The mechanism is editing `~/.ssh/authorized_keys` directly. The EC2 console key pair association is cosmetic after launch. An Ansible playbook targeting all instances is the recommended approach for fleet-wide rotation. The AWSSupport-ResetAccess runbook is a last-resort recovery tool, not a rotation tool — it requires stopping the instance.

### 2. Organizational standard: per-environment minimum, per-user ideal

The community consensus is that keys should never be shared between users. The pragmatic floor for teams is one key pair per environment (prod/staging/dev). The ideal state is per-user keys added to instances via Ansible/IaC at provisioning time. For multi-region deployments, the same key material should be imported into each region under a region-encoded name.

### 3. Naming convention: structured and machine-readable

Pattern: `{company}-{environment}-{region}-{purpose}` (all lowercase, hyphen-separated).

For 4Shark specifically:
- `4shark-production-us-east-1-default`
- `4shark-production-sa-east-1-default`
- `4shark-staging-us-east-1-default`
- `4shark-staging-sa-east-1-default`
- `4shark-development-us-east-1-default`

### 4. The modern answer is SSM Session Manager — key pairs are legacy

In 2026, key pairs are a legacy mechanism. Session Manager (via IAM) is the AWS-recommended access method for production infrastructure. It eliminates long-lived credentials, reduces attack surface, provides a full audit trail, and works without inbound SSH ports. Ansible integrates natively with Session Manager via the `amazon.aws.aws_ssm` connection plugin (fully supported as of amazon.aws 10.0.0).

A full migration to Session Manager is the long-term target. Key pair standardization is a necessary intermediate step that can be executed immediately while the team evaluates and plans the SSM migration.

### 5. Shared keys are a measurable security risk

A single shared key covering all production instances is a single point of failure. Blast radius is maximum. Individual accountability is impossible. Revocation is disruptive. The AWS Well-Architected Framework's Security Pillar identifies the elimination of long-term static credentials as a core principle — shared key pairs are the clearest violation of this principle in a typical infrastructure.

### 6. Ansible-based rotation is safe and feasible without downtime

The additive-then-subtractive pattern (add new key first, verify, then remove old key) eliminates the risk of lockout. With 4Shark's existing Ansible infrastructure, this is achievable as a structured playbook targeting each environment sequentially. Production should be rotated last, after the process is validated in staging.

---

## Open Questions

The following questions were not resolvable through research alone and require an engineering decision:

1. **Will the team adopt Session Manager long-term, or maintain key pairs?** This changes the target architecture. If SSM is the goal, the investment in key pair standardization should be minimal — just enough to establish order while SSM migration is planned.

2. **What is the current inventory of instances per region and environment?** The Ansible rotation playbook needs a complete, accurate inventory to be safe. This data must come from the AWS console or CLI.

3. **Who holds the current `.pem` files?** If they are not in a shared secrets store (Secrets Manager or Vault), the rotation process must begin by centralizing those files before any rotation runs.

4. **Is there a formal offboarding process that revokes SSH access?** If not, this should be designed alongside key standardization.

---

## Next Steps

This investigation has produced two distinct workstreams. The engineer must decide the priority and sequencing:

**Workstream A — Immediate: Key pair standardization (tactical)**
This addresses the naming inconsistency and blast-radius risk now, using existing tools.
- Create standardized key pairs using the `4shark-{env}-{region}-default` pattern
- Write Ansible playbooks to rotate `authorized_keys` across all instances
- Store new `.pem` files in AWS Secrets Manager
- Delete old, inconsistently-named key pairs

**Workstream B — Strategic: Migration to Session Manager (modern)**
This eliminates key pairs entirely for human access, replacing them with IAM-based access.
- Attach `AmazonSSMManagedInstanceCore` to all instance profiles
- Verify SSM Agent status on all instances
- Configure session logging to CloudWatch or S3
- Update Ansible to use `amazon.aws.aws_ssm` connection plugin
- Remove port 22 from security groups
- Delete all SSH key pairs

**Decision (2026-02-27):** Skip Workstream A entirely. Go directly to Workstream B (Session Manager migration). Rationale: investing effort in key pair standardization is wasted work if the end goal is eliminating key pairs altogether. The team will go straight to the final state. See the [ssm-session-manager-adoption spike](../ssm-session-manager-adoption/SPIKE.md) for the detailed investigation and implementation path.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
