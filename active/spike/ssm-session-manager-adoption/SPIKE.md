# SPIKE — AWS Systems Manager Session Manager as Full SSH Replacement

**Conducted by:** Engineering Team
**Date:** 2026-02-27
**Status:** Research complete — decision made (see below)

---

## Goal

Evaluate whether AWS Systems Manager Session Manager is mature and reliable enough to fully replace SSH key pairs on EC2 instances. Specifically:

1. Is Session Manager battle-tested and widely adopted in 2026?
2. Can EC2 instances be launched without a key pair entirely?
3. Does Ansible work reliably over Session Manager (via `amazon.aws.aws_ssm`)?
4. What are the infrastructure prerequisites?
5. What capabilities are lost by dropping key pairs entirely?
6. What are the cost implications?
7. Can port 22 be closed completely?

This spike was triggered by Open Question #1 from the [aws-key-pair-standardization spike](../aws-key-pair-standardization/SPIKE.md): "Will the team adopt Session Manager long-term, or maintain key pairs?"

---

## Method

- Deep web research across AWS official documentation, community blogs, GitHub issues, and technical articles
- Reviewed Ansible documentation and GitHub issue trackers for the `amazon.aws.aws_ssm` connection plugin
- Analyzed cost models for VPC Interface Endpoints
- Cross-referenced multiple independent sources for each finding

---

## Evidence

### 1. Maturity and Adoption

**Session Manager is a mature, battle-tested service.** It was launched in **September 2018** (announced on the [AWS Blog](https://aws.amazon.com/blogs/aws/new-session-manager/)) and has been generally available for over 7 years. The Session Manager CLI plugin has continuous releases, with the most recent versions in 2025.

**Community adoption signals:**
- AWS includes Session Manager in its [Security Maturity Model](https://maturitymodel.security.aws.dev/en/2.-foundational/fleet-manager/) as a **Foundational** security practice — meaning it is expected of any organization past the initial security phase
- [cloudonaut](https://cloudonaut.io/goodbye-ssh-use-aws-session-manager-instead/) (a respected AWS community voice) published "Goodbye SSH, use AWS Session Manager instead" — recommending it as the default access method
- [QloudX](https://www.qloudx.com/still-using-ec2-key-pairs-switch-to-session-manager-now/) published "Still Using EC2 Key Pairs? Switch to Session Manager Now!" — framing key pairs as legacy
- Multiple Medium articles from 2024-2025 describe bastion hosts as an [obsolete pattern](https://medium.com/@ismailkovvuru/aws-bastion-hosts-obsolete-2025-secure-access-guide-with-ssm-session-manager-tailscale-07fd37592500), replaced by Session Manager
- The [cyberpunk.tools blog](https://www.cyberpunk.tools/jekyll/update/2025/01/07/aws-systems-manager-session-manager.html) (January 2025) documents a complete SSH-to-SSM migration
- A [February 2026 article](https://oneuptime.com/blog/post/2026-02-12-session-manager-ec2-access-without-ssh/view) from OneUptime describes SSM as the standard approach for EC2 access without SSH

**Verdict:** Session Manager is not experimental. It is a 7+ year old GA service recommended by AWS's own security team and widely adopted by the community. It is safe to treat it as production-ready.

---

### 2. Launching EC2 Instances Without a Key Pair

**Yes, you can launch EC2 instances without assigning a key pair.** This is officially supported by AWS.

When launching an instance through the AWS Console, there is a "Proceed without a key pair" option. In the AWS CLI and SDKs, you simply omit the `--key-name` parameter. In Terraform, you omit the `key_name` attribute from `aws_instance` or `aws_launch_template`.

The AWS documentation on [EC2 key pairs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html) explicitly states:

> "As an alternative to key pairs, you can use AWS Systems Manager Session Manager to connect to your instance with an interactive one-click browser-based shell or the AWS Command Line Interface (AWS CLI)."

**Important clarification:** The "Proceed without a key pair" warning about "anyone can potentially access your instance" is misleading — it refers to the scenario where you launch without a key pair AND without Session Manager configured. If Session Manager is properly configured (SSM Agent + IAM role), the instance is fully accessible and secure.

**Terraform example (no key pair):**
```hcl
resource "aws_instance" "example" {
  ami                  = "ami-xxxxxxxxx"
  instance_type        = "t3.micro"
  iam_instance_profile = aws_iam_instance_profile.ssm.name
  # key_name deliberately omitted — access via Session Manager only

  vpc_security_group_ids = [aws_security_group.no_ssh.id]
}
```

There are multiple [Terraform modules](https://registry.terraform.io/modules/terraform-aws-modules/ec2-instance/aws/latest/examples/session-manager) and [AWS sample repositories](https://github.com/aws-samples/enable-session-manager-terraform) demonstrating this exact pattern.

**Verdict:** Launching without a key pair is officially supported, widely documented, and the recommended approach when using Session Manager.

**Sources:**
- [Amazon EC2 key pairs — AWS Documentation](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-key-pairs.html)
- [Using 'Proceed without key pair' — Saturn Cloud](https://saturncloud.io/blog/using-proceed-without-key-pair-in-ec2-instance-creation-a-comprehensive-guide/)
- [How to Connect to EC2 Without SSH Using SSM — David Hyppolite](https://davidhyppolite.com/blog/secure-ec2-access-no-ssh)
- [Terraform EC2 Session Manager example — Terraform Registry](https://registry.terraform.io/modules/terraform-aws-modules/ec2-instance/aws/latest/examples/session-manager)

---

### 3. Ansible Integration with Session Manager

This is the most critical section for 4Shark given the heavy reliance on Ansible. There are **two approaches**, each with distinct trade-offs.

#### Approach A: Native `amazon.aws.aws_ssm` Connection Plugin

The `aws_ssm` connection plugin was originally in the `community.aws` collection and has been **promoted to `amazon.aws`** (the Red Hat-maintained collection), indicating increased maturity and official support. As of `amazon.aws` 10.0.0, it is a fully supported connection plugin.

**How it works:**
- Ansible opens an SSM session to the target instance
- Module code (`.py` files) is uploaded to an **S3 bucket** (required)
- The target instance downloads the module from S3 via presigned URLs, executes it, and uploads results back to S3
- Ansible retrieves results from S3

**Requirements:**
- S3 bucket for file transfer (controller must have `s3:PutObject`, `s3:GetObject`, `s3:DeleteObject`, `s3:GetBucketLocation`)
- Session Manager CLI plugin installed on the Ansible controller
- SSM Agent running on target instances
- IAM permissions for SSM on both controller and target

**Supported features:**
- File transfers (via S3)
- `become` / privilege escalation (use `become_user`, not `remote_user` or `ansible_user`)
- Windows and Linux targets
- PowerShell shell type
- KMS-encrypted S3 buckets (with proper IAM permissions)
- Custom SSM documents

**Known limitations and issues:**

1. **Performance is significantly slower than SSH.** Users report playbooks taking [approximately 2x longer](https://github.com/ansible-collections/amazon.aws/issues/2636) (e.g., 24 minutes vs 12 minutes for SSH). Each task incurs ~3 seconds of overhead for session setup. The root cause is architectural: SSM opens/closes multiple sessions per task (3-6 sessions for a single command), and file transfers go through S3 with multiple HTTP round-trips. SSH has `ControlMaster` for persistent connections; SSM has no equivalent.

2. **Multiple sessions per task can overwhelm SSM Agent.** A [documented issue](https://github.com/ansible-collections/community.aws/issues/1148) reports that the plugin opens 3-6 SSM sessions for a single Ansible task. On Windows hosts especially, this can cause the SSM Agent to become unresponsive after sustained use. AWS's own documentation notes that Session Manager is designed for interactive shell use, not high-frequency automation.

3. **S3 bucket is mandatory** — even for simple `shell` or `command` modules, because Ansible transfers module `.py` files via S3. This adds:
   - An S3 bucket to manage (lifecycle, permissions, cleanup)
   - Security consideration: if the play terminates ungracefully, files may remain in S3. If bucket versioning is enabled, files remain in version history indefinitely.
   - **Security warning from Ansible docs:** "Passwords will be included in plaintext in those files in S3 indefinitely, visible to anyone with access to that bucket"

4. **`remote_user` / `ansible_user` not supported.** Only `become_user` works for user switching.

5. **Fact gathering has had issues.** A [GitHub issue](https://github.com/ansible-collections/community.aws/issues/113) reported failures during fact gathering, though this has been addressed in newer versions.

**Sources:**
- [amazon.aws.aws_ssm connection plugin — Ansible Documentation](https://docs.ansible.com/projects/ansible/latest/collections/amazon/aws/aws_ssm_connection.html)
- [Speed issue with SSM vs SSH — GitHub Issue #2636](https://github.com/ansible-collections/amazon.aws/issues/2636)
- [Multiple sessions per task — GitHub Issue #1148](https://github.com/ansible-collections/community.aws/issues/1148)
- [File transfer via port forwarding — GitHub Issue #2638](https://github.com/ansible-collections/amazon.aws/issues/2638)
- [S3 bucket garbage collection — GitHub Issue #222](https://github.com/ansible-collections/community.aws/issues/222)

#### Approach B: SSH Tunneled Through SSM (ProxyCommand)

This hybrid approach uses SSM as a **transport layer** while keeping Ansible's native SSH connection. The SSH connection is tunneled through an SSM session via a `ProxyCommand`.

**How it works:**
1. Ansible initiates an SSH connection as usual
2. The SSH `ProxyCommand` starts an SSM session to the target instance, forwarding port 22
3. SSH traffic flows through the encrypted SSM tunnel
4. Ansible uses its native SSH connection plugin with all its optimizations (ControlMaster, multiplexing)

**Configuration (SSH config or `ansible.cfg`):**
```
Host i-* mi-*
  ProxyCommand sh -c "aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p'"
```

**Ansible variable:**
```yaml
ansible_ssh_common_args: >-
  -o StrictHostKeyChecking=no
  -o UserKnownHostsFile=/dev/null
  -o ProxyCommand="aws ssm start-session --target %h --document-name AWS-StartSSHSession --parameters 'portNumber=%p'"
```

**Advantages over native plugin:**
- Full SSH performance (ControlMaster, persistent connections)
- No S3 bucket needed
- All Ansible SSH features work (rsync, scp, `remote_user`, etc.)
- File transfers use SSH directly, not S3

**Disadvantages:**
- **Still requires SSH keys or EC2 Instance Connect** on the target — SSM is only the transport, SSH authentication still happens. This means you cannot fully eliminate key pairs with this approach unless you combine it with EC2 Instance Connect (which pushes ephemeral keys).
- More complex SSH configuration
- Requires the Session Manager CLI plugin on every machine running Ansible

**Sources:**
- [Provisioning with Ansible via SSM — soudegesu](https://www.soudegesu.com/en/post/aws/provisioning-with-ansible-via-ssm/)
- [Ansible Playbook via Session Manager SSH Port — Medium](https://medium.com/@kay.renfa/ansible-playbook-using-ec2-plugin-via-session-manager-from-ssh-port-e68d5a962d2b)
- [Multi-account EC2 management with SSM and Ansible — Digihunch](https://www.digihunch.com/2024/05/managing-ec2-instances-across-aws-accounts-ssm/)
- [Configure SSH Client for SSM — QloudX](https://www.qloudx.com/configure-your-ssh-client-to-connect-to-your-ec2-instances-via-aws-systems-manager-session-manager/)

#### Recommendation for Ansible

| Criteria | Native `aws_ssm` plugin | SSH over SSM tunnel |
|----------|------------------------|---------------------|
| **Performance** | ~2x slower than SSH | Same as SSH |
| **Eliminates key pairs** | Yes | No (still needs SSH auth) |
| **S3 dependency** | Yes (mandatory) | No |
| **Ansible feature support** | Partial (`become_user` only) | Full |
| **Complexity** | Medium (S3 bucket, IAM) | Medium (ProxyCommand config) |
| **File transfer** | Via S3 | Via SSH (scp/rsync) |
| **Best for** | Small-medium playbooks, security-first | Large playbooks, performance-critical |

**For 4Shark:** If the goal is to **completely eliminate key pairs**, the native `aws_ssm` plugin is the only option that achieves this. The performance penalty is real but may be acceptable depending on playbook size and frequency. For large, performance-sensitive playbooks, the SSH-over-SSM tunnel approach is better but requires keeping some form of SSH authentication.

---

### 4. Prerequisites for Session Manager

**SSM Agent:**
- **Pre-installed** on: Amazon Linux 2, Amazon Linux 2023 (requires manual start on AL2023 per some reports), Ubuntu 16.04+, and most AWS-provided AMIs
- **Not pre-installed** on: Custom AMIs, older AMIs, some marketplace AMIs
- The agent must be version 2.3.12+ for Session Manager support
- Agent communicates outbound over HTTPS (port 443) to AWS endpoints

**IAM Role:**
- Instance must have an IAM instance profile with the `AmazonSSMManagedInstanceCore` managed policy (or equivalent custom policy)
- **Do NOT use** the deprecated `AmazonEC2RoleforSSM` policy — it grants excessive S3 and other permissions
- For the Ansible `aws_ssm` plugin, additional S3 permissions are needed on the controller

**Network — instances with internet access:**
- Outbound HTTPS (port 443) to:
  - `ssm.<region>.amazonaws.com`
  - `ssmmessages.<region>.amazonaws.com`
  - `ec2messages.<region>.amazonaws.com`
- No inbound ports required

**Network — instances in private subnets (no internet access):**
- Three **VPC Interface Endpoints** are required:
  - `com.amazonaws.<region>.ssm`
  - `com.amazonaws.<region>.ssmmessages`
  - `com.amazonaws.<region>.ec2messages`
- If using the Ansible `aws_ssm` plugin, also need an **S3 endpoint** (Gateway type — free)
- If using KMS encryption for sessions, also need a KMS endpoint
- If logging sessions to CloudWatch, also need a CloudWatch Logs endpoint
- Security groups on VPC endpoints must allow inbound HTTPS (port 443) from the VPC CIDR

**Session Manager CLI Plugin:**
- Required on any workstation that needs to start sessions via AWS CLI
- Available for Linux, macOS, and Windows
- [Installation guide](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)

**Sources:**
- [Session Manager prerequisites — AWS Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-prerequisites.html)
- [Instance permissions for Session Manager — AWS Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-instance-profile.html)
- [Automated Session Manager setup without internet gateway — AWS Blog](https://aws.amazon.com/blogs/mt/automated-configuration-of-session-manager-without-an-internet-gateway/)
- [VPC Endpoints for SSM — DEV Community](https://dev.to/aws-builders/securely-access-your-ec2-instances-with-aws-systems-manager-ssm-and-vpc-endpoints-1bli)
- [Securing EC2 Access with SSM — The Hidden Port](https://thehiddenport.dev/posts/aws-securing-ec2-access-with-ssm/)

---

### 5. What You Lose by Dropping Key Pairs Entirely

**Scenarios where SSH may still be needed:**

1. **SSM Agent failure.** If the SSM Agent crashes, becomes unresponsive, or fails to start, you lose all remote access to the instance. With SSH keys, you could still connect directly. Without them, your only options are:
   - Stop the instance, detach the root volume, attach to another instance, fix the problem, reattach
   - Use the [EC2 Serial Console](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-serial-console.html) (if enabled — not available in all regions/instance types)
   - Use the [AWSSupport-TroubleshootSessionManager](https://docs.aws.amazon.com/systems-manager-automation-runbooks/latest/userguide/automation-awssupport-troubleshoot-session-manager.html) runbook

2. **Network connectivity to AWS endpoints.** If the instance loses HTTPS connectivity to SSM endpoints (VPC endpoint misconfiguration, security group change, route table issue), Session Manager stops working. SSH, being direct, would still work if port 22 is reachable.

3. **IAM or STS outages.** Session Manager depends on IAM authentication. During (rare) IAM regional outages, Session Manager would be affected. SSH with key pairs operates independently of IAM.

4. **Third-party tools that only support SSH.** Some legacy tools, monitoring agents, or CI/CD pipelines may only support SSH connections. These would need to be updated or replaced.

5. **SCP/rsync without S3.** Direct file transfer via SCP or rsync requires SSH. Without SSH, file transfers go through S3 (native plugin) or require [port forwarding](https://dev.to/cwprogram/rsync-and-ssm-agent-port-forwarding-for-file-transfers-without-private-key-1b5p) via SSM. The [aws-ssm-tools](https://github.com/mludvig/aws-ssm-tools) project provides `ec2-ssh` and rsync integration via SSM tunnels.

6. **Boot-time debugging.** If an instance fails during boot (before the SSM Agent starts), there is no way to connect via Session Manager. SSH is also unavailable at this point, so this is a wash — EC2 Serial Console is the tool for this scenario.

**Community-reported gotchas:**

- The `AmazonEC2RoleforSSM` managed policy is overly permissive — always use `AmazonSSMManagedInstanceCore` or a custom policy
- Session Manager sessions have a default idle timeout (20 minutes) and maximum duration (configurable) — long-running operations may be interrupted
- If bucket versioning is enabled on the Ansible S3 bucket, transferred files (including potentially sensitive data) persist in version history even after deletion

**Risk mitigation for emergency access:**

The recommended mitigation is **not** to keep key pairs "just in case" — this defeats the purpose. Instead:
- Enable [EC2 Serial Console](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-serial-console.html) for true emergency access
- Use [EC2 Instance Connect Endpoint](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/connect-using-eice.html) as a backup access method — it pushes ephemeral SSH keys via IAM, no long-lived keys needed
- Monitor SSM Agent health via CloudWatch metrics
- Set up CloudWatch alarms for SSM Agent connectivity loss

**Sources:**
- [Troubleshooting Session Manager — AWS Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-troubleshooting.html)
- [Troubleshooting SSM Agent — AWS Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/troubleshooting-ssm-agent.html)
- [Troubleshoot offline SSM Agent — AWS re:Post](https://repost.aws/knowledge-center/systems-manager-ec2-instance-not-appear)
- [rsync via SSM port forwarding — DEV Community](https://dev.to/cwprogram/rsync-and-ssm-agent-port-forwarding-for-file-transfers-without-private-key-1b5p)
- [aws-ssm-tools — GitHub](https://github.com/mludvig/aws-ssm-tools)

---

### 6. Cost Implications

**Session Manager itself: FREE.**

AWS Systems Manager Session Manager is included at no extra charge. There is no per-session cost, no per-hour cost, and no data transfer cost for Session Manager itself.

**What costs money:**

| Component | Required? | Cost |
|-----------|-----------|------|
| Session Manager sessions | Core | Free |
| SSM Agent | Core | Free (included in AMIs) |
| S3 bucket (for Ansible `aws_ssm` plugin) | Only for Ansible native plugin | S3 storage + request pricing (minimal) |
| CloudWatch Logs (session logging) | Recommended | CloudWatch Logs pricing (~$0.50/GB ingested) |
| S3 session logs | Alternative to CloudWatch | S3 storage pricing (minimal) |
| VPC Interface Endpoints (private subnets) | Only for private subnets | **$0.01/hour/AZ per endpoint** |

**VPC Endpoint cost breakdown (the main hidden cost):**

For instances in **private subnets without internet access**, you need at minimum 3 VPC Interface Endpoints (`ssm`, `ssmmessages`, `ec2messages`). If you also need S3 access for Ansible, add a Gateway Endpoint (free).

Per a [detailed cost analysis by William Khoo](https://blog.wkhoo.com/posts/centralised-ssm-endpoints):

**Distributed model (endpoints in each VPC):**
- 3 endpoints x $0.01/hour/AZ = $0.03/hour/AZ
- In 2 AZs = $0.06/hour per VPC
- Monthly: ~$43.80 per VPC (just for SSM endpoints)
- With additional endpoints (KMS, CloudWatch, S3 interface): up to ~$168/month per VPC

**Centralized model (endpoints in a hub VPC, accessed via Transit Gateway):**
- Significantly cheaper at scale (2+ VPCs)
- ~$72.59/month per VPC when sharing via Transit Gateway across 10 VPCs
- Saves ~$960/month compared to distributed in a 10-VPC environment

**For instances with internet access (NAT Gateway or public subnet):**
- VPC endpoints are NOT required — SSM traffic goes through the internet
- Cost is zero beyond existing NAT Gateway costs

**Important note:** As of April 2022, cross-AZ data transfer through VPC Interface Endpoints is free within the same region.

**Bottom line:** If your instances have internet access (via NAT Gateway), the migration to Session Manager has essentially zero incremental cost. If instances are in fully private subnets, VPC endpoints add ~$44-168/month per VPC depending on how many endpoint types are needed.

**Sources:**
- [AWS Systems Manager Pricing](https://aws.amazon.com/systems-manager/pricing/)
- [AWS PrivateLink Pricing](https://aws.amazon.com/privatelink/pricing/)
- [Centralized SSM VPC Endpoints Cost-Benefit Analysis — William Khoo](https://blog.wkhoo.com/posts/centralised-ssm-endpoints)
- [SSM Endpoints per VPC — AWS Security Architect](https://awssecurityarchitect.com/aws-ec2-patching/ssm-endpoints-per-vpc/)

---

### 7. Closing Port 22

**Yes, port 22 can be completely closed.**

Session Manager does not use SSH or port 22. It uses an outbound WebSocket connection over HTTPS (port 443) initiated by the SSM Agent on the instance. Because security group rules are stateful, the return traffic is automatically allowed.

From the [AWS documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html):

> "Session Manager provides secure node management without the need to open inbound ports."

The [security group configuration](https://thehiddenport.dev/posts/aws-securing-ec2-access-with-ssm/) for a Session Manager-only instance:
- **Inbound rules:** None required (or only application-specific ports like 80/443)
- **Outbound rules:** HTTPS (port 443) to AWS endpoints (or VPC endpoint security groups)

**Verification:** Multiple sources confirm that removing all inbound rules from a security group does NOT affect Session Manager connectivity, because the SSM Agent initiates the connection outbound.

**Caveat:** If you use the SSH-over-SSM-tunnel approach (Approach B from the Ansible section), SSH still runs on the instance on port 22 — but it is accessed through the SSM tunnel, not directly. In this case, port 22 does NOT need to be open in the security group either, because the SSM tunnel handles the transport.

**Sources:**
- [Session Manager — AWS Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager.html)
- [Securing EC2 Access with SSM — The Hidden Port](https://thehiddenport.dev/posts/aws-securing-ec2-access-with-ssm/)
- [Secure EC2 Access Without Opening Port 22 — Necko Technologies](https://www.necko.tech/en/blog/ssh-over-ssm)
- [Session Manager without internet gateway — AWS Blog](https://aws.amazon.com/blogs/mt/automated-configuration-of-session-manager-without-an-internet-gateway/)

---

### Bonus: Audit and Compliance Benefits

Session Manager provides audit capabilities that SSH with key pairs cannot match:

- **CloudTrail integration:** Every `StartSession` API call is logged in CloudTrail with the IAM identity that initiated it — full individual accountability
- **Session logging:** Full command-by-command logging to CloudWatch Logs or S3, with optional KMS encryption
- **IAM-based access control:** Access is granted/revoked instantly via IAM policies — no need to touch instances
- **MFA support:** Session Manager integrates with IAM MFA — you can require MFA before allowing session access
- **Centralized management:** Session preferences (idle timeout, max duration, logging, encryption) can be [managed organization-wide](https://aws.amazon.com/blogs/security/how-to-automate-session-manager-preferences-across-your-organization/) via AWS Organizations

**Sources:**
- [Logging session activity — AWS Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-auditing.html)
- [Session logging to CloudWatch — AWS Documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-logging-cloudwatch-logs.html)
- [Automate Session Manager preferences across organization — AWS Security Blog](https://aws.amazon.com/blogs/security/how-to-automate-session-manager-preferences-across-your-organization/)

---

## Conclusions

### Session Manager is ready for full production adoption

The service is 7+ years old, recommended by AWS's own Security Maturity Model as a foundational practice, and widely adopted. This is not bleeding edge — it is mainstream.

### EC2 instances can launch without key pairs

This is officially supported and documented by AWS. Terraform, CloudFormation, and the AWS Console all support it. No workaround needed.

### Ansible integration works but has real trade-offs

The native `amazon.aws.aws_ssm` plugin is functional and officially supported (promoted from `community.aws` to `amazon.aws`). However:
- **Performance is ~2x slower than SSH** due to the S3-based file transfer architecture
- An S3 bucket is mandatory, with security implications
- The `remote_user` feature does not work — only `become_user`

For teams where playbook performance is critical, the SSH-over-SSM-tunnel approach is better but does not eliminate key pairs. For teams prioritizing security over speed, the native plugin is the right choice.

### The main risk is SSM Agent dependency

Without key pairs, the SSM Agent becomes the single point of access. If the agent fails, emergency access requires stopping the instance or using EC2 Serial Console. This is manageable with monitoring and backup access methods (EC2 Instance Connect Endpoint, Serial Console).

### Cost is negligible for most architectures

Session Manager is free. The only significant cost is VPC Interface Endpoints for private subnets (~$44-168/month per VPC). Instances with internet access incur zero incremental cost.

### Port 22 can be completely closed

Session Manager uses outbound HTTPS only. No inbound ports are required. This is a clear security improvement — it eliminates an entire attack vector.

### The audit trail is superior to SSH

Session Manager provides individual accountability (IAM identity per session), full command logging, MFA support, and centralized policy management. SSH with shared key pairs provides none of these.

---

## Decision Matrix

| Factor | Confidence | Verdict |
|--------|-----------|---------|
| Service maturity | High | Ready for production |
| Launch without key pair | High | Fully supported |
| Ansible native plugin | Medium | Works, but 2x slower — acceptable for most workloads |
| Ansible SSH-over-SSM | High | Works, full performance — but keeps SSH auth |
| Prerequisites | High | Well-documented, straightforward |
| Emergency access without SSH | Medium | Requires planning (Serial Console, EICE) |
| Cost (internet access) | High | Free |
| Cost (private subnets) | High | ~$44-168/month per VPC |
| Close port 22 | High | Yes, completely |
| Audit/compliance | High | Superior to SSH |

---

## Next Steps

**Decision (2026-02-27):** The team chose **Path C (Phased)** — go directly to Session Manager, skipping the intermediate key pair standardization (Workstream A from the [aws-key-pair-standardization spike](../aws-key-pair-standardization/SPIKE.md)). Rationale: standardizing key pairs is wasted effort if the end goal is eliminating them entirely. Go straight to the final state.

The Ansible approach (native plugin vs SSH-over-SSM) will be decided in Phase 4 after testing with real playbooks.

**Next action:** Create a PLAN.md to formalize the phased rollout.

---

Based on the findings, there are three possible paths (Path C was chosen):

### Path A — Full Session Manager (no key pairs)
- Eliminate key pairs entirely on new instances
- Migrate existing instances to Session Manager
- Use the native `amazon.aws.aws_ssm` Ansible plugin
- Accept the ~2x performance penalty on playbooks
- Close port 22 everywhere
- **Best for:** Security-first teams, compliance-driven environments

### Path B — Hybrid (SSM transport, SSH authentication)
- Use SSH-over-SSM-tunnel for Ansible (full performance)
- Use Session Manager for interactive access
- Still need some form of SSH authentication (EC2 Instance Connect for ephemeral keys)
- Close port 22 in security groups (SSM tunnel handles it)
- **Best for:** Teams with large, performance-sensitive Ansible playbooks

### Path C — Phased (recommended for 4Shark)
1. **Phase 1:** Enable Session Manager on all instances (add IAM role, verify SSM Agent)
2. **Phase 2:** Use Session Manager for all interactive/manual access — stop using SSH for human access
3. **Phase 3:** Close port 22 for human access (allow only from Ansible controller if using SSH-over-SSM)
4. **Phase 4:** Test the native `aws_ssm` Ansible plugin on a non-critical environment — measure the performance impact on 4Shark's actual playbooks
5. **Phase 5:** Based on Phase 4 results, decide between native plugin (Path A) or SSH-over-SSM (Path B) for Ansible
6. **Phase 6:** For new instances, stop assigning key pairs
7. **Phase 7:** Gradually remove key pairs from existing instances

**This spike feeds into [Workstream B of the aws-key-pair-standardization spike](../aws-key-pair-standardization/SPIKE.md).** A PLAN.md should be created to formalize the implementation strategy.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
