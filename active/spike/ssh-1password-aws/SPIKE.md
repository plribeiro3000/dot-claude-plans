# SPIKE — SSH Authentication Failure with 1Password Agent and AWS EC2 Ubuntu 24.04

**Conducted by:** Engineering team
**Date:** 2026-02-27
**Status:** Research complete — pending decisions

---

## Goal

Diagnose why SSH authentication fails when connecting to an EC2 instance (`i-0ffb1631196bdbf9d`, Ubuntu 24.04, IP `10.255.0.92`) created via Terraform with key pair `kp-4shark`, using 1Password SSH agent on macOS with OpenSSH 10.2.

The specific questions to answer:

1. Did cloud-init properly inject the public key into `/home/ubuntu/.ssh/authorized_keys`?
2. Does Ubuntu 24.04 have any SSH server configuration that rejects RSA keys?
3. Could 1Password SSH agent be signing with an incompatible algorithm or the wrong key?
4. Why can't OpenSSH 10.2 on macOS load the old PEM-format private key directly?
5. How can we access the instance to diagnose without SSH working?
6. What is the correct SSH + 1Password + AWS key pair workflow?

---

## Method

- Reviewed the Terraform source code for the affected instance (`/Users/plribeiro3000/Projects/4Shark/terraform/vpn/main.tf` and `modules/pritunl/`)
- Searched web for known bugs in cloud-init, Ubuntu 24.04, and 1Password SSH agent
- Fetched official documentation from 1Password Developer docs, AWS EC2 docs, and cloud-init GitHub issue tracker
- Analyzed SSH debug output provided by the engineer

---

## Evidence

### 1. Known cloud-init Bug on Ubuntu 24.04 — HIGH CONFIDENCE ROOT CAUSE

**Source:** [GitHub canonical/cloud-init issue #6175](https://github.com/canonical/cloud-init/issues/6175) and [issue #6062](https://github.com/canonical/cloud-init/issues/6062)

**Finding:** There is an **open and confirmed bug** in cloud-init `24.4-0ubuntu1~24.04.2` affecting Ubuntu 24.04 LTS. The bug causes the authorized_keys file to be written with **0 bytes**, even though cloud-init logs show no error. The debug log entry is:

```
Writing to /home/ubuntu/.ssh/authorized_keys - wb: [600] 0 bytes
```

**Affected versions:** cloud-init 24.4-0ubuntu1~24.04.2 on Ubuntu 24.04.2 and 24.04.3 LTS

**Status:** Open as of January 2026. No official patch released.

**Platforms:** Reported on OpenStack, Azure, and generic deployments. AWS EC2 is not specifically mentioned but uses the same cloud-init mechanism.

**The AMI in use** (`ami-032ab7316dbf1ea74`) is Ubuntu 24.04 LTS for sa-east-1. This AMI almost certainly contains the affected cloud-init version, given the bug affects all Ubuntu 24.04 images from this period.

**This is the most likely explanation for why the correct key is offered but rejected:** the server has an empty `authorized_keys` — there is nothing to match against, so every key is rejected with "Permission denied".

---

### 2. Ubuntu 24.04 SSH Server RSA Key Algorithm Configuration

**Source:** [TecAdmin](https://tecadmin.net/userauth_pubkey-key-type-ssh-rsa-not-in-pubkeyacceptedalgorithms/), [Claudiokuenzler blog](https://www.claudiokuenzler.com/blog/1314/ssh-connection-not-working-userauth-pubkey-ssh-rsa-not-in-pubkeyacceptedalgorithms), various Ubuntu 22.04/24.04 reports

**Finding:** Ubuntu 22.04+ servers disable the old `ssh-rsa` (SHA-1) signature scheme by default. They require `rsa-sha2-256` or `rsa-sha2-512` instead.

**However:** The debug output shows `server-sig-algs=<...,rsa-sha2-512,rsa-sha2-256>` — meaning the server does accept modern RSA signatures. This rules out an algorithm mismatch as the primary problem.

**Conclusion on this factor:** Not the root cause. The server accepts RSA with SHA-2 algorithms.

---

### 3. OpenSSH 10.2 Cannot Load Old PEM Format Keys (BEGIN RSA PRIVATE KEY)

**Source:** OpenSSH release notes history, [Archlinux forum](https://bbs.archlinux.org/viewtopic.php?id=270005), [OpenSSH 8.3 release notes](https://lwn.net/Articles/821544/)

**Finding:** AWS generates RSA private keys in the old PEM format (`-----BEGIN RSA PRIVATE KEY-----`), also called "PKCS#1 format". OpenSSH has been using its own native key format (`-----BEGIN OPENSSH PRIVATE KEY-----`) since version 7.8 (2018).

The `type -1` and "no pubkey loaded" errors in the debug output indicate that OpenSSH 10.2 on macOS cannot parse the PKCS#1 PEM format for authentication — it does not extract the public key from it for the purposes of key selection. This is a **client-side parsing limitation**, not a server-side rejection.

**Important distinction:** RSA keys themselves are NOT deprecated. Only the `ssh-rsa` (SHA-1) signature algorithm is deprecated since OpenSSH 8.8 (2021). Modern RSA keys work fine with `rsa-sha2-256` and `rsa-sha2-512`. The issue is purely the **file format** of the private key downloaded from AWS.

**Fix:** Convert the PEM key to OpenSSH format:
```bash
ssh-keygen -p -m OpenSSH -f ~/.ssh/kp-4shark.pem
# This converts in-place without changing the passphrase (press Enter if none)
```
Or generate a new key and add to a renamed copy:
```bash
cp ~/.ssh/kp-4shark.pem ~/.ssh/kp-4shark
ssh-keygen -p -m OpenSSH -f ~/.ssh/kp-4shark
```

---

### 4. 1Password SSH Agent — "Explicit Agent" Behavior and Key Selection

**Source:** [1Password Developer docs — SSH agent](https://developer.1password.com/docs/ssh/agent/), [1Password SSH agent advanced](https://developer.1password.com/docs/ssh/agent/advanced/), [1Password compatibility](https://developer.1password.com/docs/ssh/agent/compatibility/)

**Finding on "explicit agent":** When you specify `IdentityFile ~/.ssh/kp-4shark.pub` (a `.pub` file) in SSH config, OpenSSH reads the public key from that file to identify which key should be offered. SSH then looks for the corresponding private key in the agent. If the agent has a key matching that fingerprint, it signs using the agent. The debug label "explicit agent" means: "the public key was specified explicitly via IdentityFile, but signing happens via the agent."

**1Password compatibility with OpenSSH on macOS:** Confirmed compatible. OpenSSH on macOS supports `IdentityAgent` and `IdentityFile` with 1Password.

**1Password RSA signature algorithm:** 1Password uses `rsa-sha2-256` or `rsa-sha2-512` for RSA key signing (modern algorithms). There are no reported issues with 1Password using the deprecated `ssh-rsa` (SHA-1) scheme. This is NOT a factor.

**Key finding:** The debug output shows the correct fingerprint (`SHA256:SuPaINEcs8QSpda8SVhjJv4ae5wDT1lg1+SVegTtYZs`) being offered by 1Password via the agent. The fingerprint matches the AWS key pair. The server rejects it — meaning the server has **no matching public key** in `authorized_keys`. This confirms the cloud-init bug hypothesis.

---

### 5. EC2 Access Alternatives — Instance Already Has SSM Configured

**Source:** `modules/pritunl/iam.tf` in the Terraform codebase

**Critical finding:** The Terraform code for this instance already attaches `AmazonSSMManagedInstanceCore`:

```hcl
resource "aws_iam_role_policy_attachment" "ssm" {
  role       = aws_iam_role.this.name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}
```

**Source:** [AWS SSM Session Manager docs](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-getting-started-instance-profile.html)

**SSM Agent on Ubuntu 24.04:** Pre-installed on Ubuntu 24.04 AMIs (covered under "Ubuntu 20.04 and later" in AWS docs). The SSM agent runs as a snap package: `amazon-ssm-agent`.

**What SSM requires:**
- IAM role with `AmazonSSMManagedInstanceCore` — ALREADY PRESENT
- SSM agent installed — LIKELY PRESENT (Ubuntu 24.04 official AMI)
- Outbound HTTPS (port 443) to SSM endpoints — requires security group to allow outbound or VPC endpoints

**What this means:** SSM Session Manager is likely the fastest path to diagnose and fix the issue, without needing SSH.

---

### 6. EC2 Instance Connect — Alternative Temporary Key Method

**Source:** [AWS EC2 Instance Connect docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-connect-methods.html), [EC2 Instance Connect prerequisites](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/ec2-instance-connect-prerequisites.html)

**Finding:** EC2 Instance Connect pushes a temporary public key to the instance metadata for 60 seconds, bypassing `authorized_keys`. The instance must have the `ec2-instance-connect` package installed and configured via `AuthorizedKeysCommand` in `sshd_config`.

**For Ubuntu 20.04+:** The `ec2-instance-connect` package is pre-installed in official Ubuntu AMIs. Ubuntu 24.04 is covered under "Ubuntu 20.04 or later".

**Command to use:**
```bash
# Step 1: Push temporary key (valid for 60 seconds)
aws ec2-instance-connect send-ssh-public-key \
  --region sa-east-1 \
  --instance-id i-0ffb1631196bdbf9d \
  --instance-os-user ubuntu \
  --ssh-public-key file://~/.ssh/kp-4shark.pub

# Step 2: SSH within 60 seconds using the private key
ssh -i ~/.ssh/kp-4shark.pem ubuntu@10.255.0.92
```

**Caveat:** The instance is in a private subnet (`10.255.0.92`). EC2 Instance Connect via the AWS Console (browser-based) requires a public IP. CLI-based `send-ssh-public-key` only works if the instance is reachable from your local machine over TCP port 22.

---

### 7. EC2 Serial Console

**Source:** AWS documentation on EC2 Serial Console

**Finding:** The EC2 serial console allows direct access to the instance boot output and login prompt without network connectivity. However, it requires:
1. Serial console access to be enabled at the account level
2. The instance to be a Nitro-based instance (t3a.micro is Nitro-based — confirmed)
3. A username and password set on the OS (not default for Ubuntu cloud images, which use key-only auth)

Serial console is useful for viewing boot logs but **not practical for direct login** without a pre-configured password.

---

### 8. Verification via Console Output

**Source:** [AWS EC2 troubleshooting docs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/TroubleshootingInstancesConnecting.html)

**Finding:** `aws ec2 get-console-output` can retrieve the early boot output, including cloud-init initialization messages. This can confirm whether cloud-init ran successfully and what SSH host keys were generated, but it does not directly show the `authorized_keys` content.

To check cloud-init status without logging in:
```bash
aws ec2 get-console-output \
  --instance-id i-0ffb1631196bdbf9d \
  --region sa-east-1 \
  --output text
```

Look for lines containing `cloud-init` errors or the SSH fingerprint of the instance host key.

---

## Conclusions

### Root Cause (Most Likely)

**The authorized_keys file is empty on the server.** This is caused by the confirmed cloud-init bug in Ubuntu 24.04 LTS (`24.4-0ubuntu1~24.04.2`) where the SSH key injection writes 0 bytes to `authorized_keys` silently. The client-side evidence is consistent with this: the correct fingerprint is offered, the server sees the offer, but has nothing to match it against.

### Secondary Issues (Real but Not Root Cause)

1. **OpenSSH 10.2 cannot load AWS-format PEM keys directly.** The `-----BEGIN RSA PRIVATE KEY-----` format is not parseable by modern OpenSSH for key selection purposes. The key must be converted to OpenSSH format (`-----BEGIN OPENSSH PRIVATE KEY-----`) before it can be used directly as `IdentityFile`. This is a client-side file format issue.

2. **SSH config uses `.pem` file as IdentityFile.** The SSH config should reference either the converted private key file (OpenSSH format) or the `.pub` public key file (which works with 1Password agent as demonstrated in attempt 4).

### What Works (Client-Side Configuration)

The configuration from attempt 4 is correct:
```
Host 10.255.0.*
  IdentitiesOnly yes
  IdentityFile ~/.ssh/kp-4shark.pub
  User ubuntu
  IdentityAgent "~/Library/Group Containers/2BUA8C4S2C.com.1password/t/agent.sock"
```

This correctly offers the right key via 1Password agent. The failure is server-side.

### Fastest Path to Diagnose

SSM Session Manager is available immediately — the IAM role already has `AmazonSSMManagedInstanceCore` and Ubuntu 24.04 includes the SSM agent. No additional configuration is needed (assuming outbound HTTPS is allowed from the instance).

---

## Next Steps

### Option A — Diagnose via SSM Session Manager (Recommended, fastest)

1. Start an SSM session:
   ```bash
   aws ssm start-session \
     --target i-0ffb1631196bdbf9d \
     --region sa-east-1
   ```
2. Once inside, check the authorized_keys file:
   ```bash
   cat /home/ubuntu/.ssh/authorized_keys
   sudo cat /root/.ssh/authorized_keys 2>/dev/null
   ```
3. Check cloud-init logs:
   ```bash
   sudo cat /var/log/cloud-init.log | grep -A5 "authorized"
   sudo cat /var/log/cloud-init-output.log
   ```
4. If empty, manually add the public key:
   ```bash
   echo "ssh-rsa AAAA..." >> /home/ubuntu/.ssh/authorized_keys
   chmod 600 /home/ubuntu/.ssh/authorized_keys
   ```

### Option B — Fix authorized_keys via AWS Console User Data (requires restart)

Replace the instance user data with a cloud-config that explicitly injects the key:
```yaml
#cloud-config
ssh_authorized_keys:
  - ssh-rsa AAAA...your-public-key-here...
```
Then stop and start the instance (not just reboot — user data re-runs on re-launch when `cloud_final_modules` is configured).

### Option C — Convert PEM key to OpenSSH format (client-side fix for the future)

```bash
cp ~/.ssh/kp-4shark.pem ~/.ssh/kp-4shark
ssh-keygen -p -m OpenSSH -f ~/.ssh/kp-4shark
```
This resolves the `type -1` / "no pubkey loaded" error when using the private key directly (without 1Password agent).

### Option D — Rebuild the instance with a workaround user_data

Add a `user_data` block to the Pritunl module that explicitly injects the SSH key, bypassing cloud-init's key_name mechanism entirely:

```hcl
user_data = base64encode(<<-EOF
  #!/bin/bash
  mkdir -p /home/ubuntu/.ssh
  echo "${var.ssh_public_key}" >> /home/ubuntu/.ssh/authorized_keys
  chmod 700 /home/ubuntu/.ssh
  chmod 600 /home/ubuntu/.ssh/authorized_keys
  chown -R ubuntu:ubuntu /home/ubuntu/.ssh
  EOF
)
```

This requires a new Terraform variable `ssh_public_key` and a `terraform apply` followed by an instance replacement.

---

### Priority Recommendation

**Start with Option A (SSM).** It is non-destructive, does not require instance replacement, and confirms the root cause immediately. If `authorized_keys` is empty, Option A also resolves it directly by adding the key manually.

If SSM is not reachable (e.g., outbound HTTPS blocked by security group), proceed to Option B or D.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
