# SPIKE — Per-Environment Machine Access to 4Shark's EC2 MongoDB Hosts

## Investigation question

4Shark is executing a "one KMS key per environment" migration (`kms-key-per-environment/PLAN.md`)
whose stated driver is per-integrator/per-environment **access delegation**: an engineer granted
access to one environment should reach that environment's decrypt key and nothing else. The
engineer wants to know whether the same per-environment access-delegation goal should extend to
**machine access** — SSH/shell access to 4Shark's only EC2 instances, the MongoDB hosts (five
integrator replica sets plus the VPN's Mongo host), which today all share a single EC2 key pair
(`kp-4shark`).

Four sub-questions, answered in order below:

1. Does a dedicated EC2 key pair per environment make sense, mirroring the per-environment KMS key?
2. How does the community/AWS express a two-tier access model — Tier 1 (see infrastructure,
   read/decrypt data, no shell) vs Tier 2 (shell into the machines)?
3. Is an SSH key pair the right mechanism for this at all, or does AWS recommend Session Manager
   (IAM-gated, tag-scoped, audited) instead?
4. Should machine-access-per-environment be folded into the in-flight KMS-key-per-environment work,
   or is it a structurally separate mechanism?

## Sources consulted

- `~/Projects/4Shark/dot-claude-plans/active/spike/ssm-session-manager-adoption/SPIKE.md` — prior
  4Shark research concluding Session Manager is production-ready and the team should skip key-pair
  standardization and migrate to Session Manager. Scoped to the general SSH-vs-SSM question, not to
  a tiered/per-environment access model.
- `~/Projects/4Shark/dot-claude-plans/active/spike/aws-key-pair-standardization/SPIKE.md` — prior
  4Shark research on key-pair organization/naming; documents the 2026-02-27 decision to skip
  standardization workstream and go straight to Session Manager.
- `~/Projects/4Shark/dot-claude-plans/active/spike/aws-engineer-staging-tier/SPIKE.md` — the
  restricted-engineer-tier effort this investigation feeds; established that this AWS account is
  the Organization's management account (SCPs do not apply) and that AWS's stated best practice for
  human access is IAM Identity Center / temporary credentials over long-lived IAM-user keys.
- `~/Projects/4Shark/dot-claude-plans/active/terraform/kms-key-per-environment/PLAN.md` — the
  in-flight KMS migration; read in full for any mention of SSH, key pairs, or machine access
  (grep confirmed: none — see Finding 3).
- `~/Projects/4Shark/terraform/modules/vpn/mongodb.tf:92` and every
  `~/Projects/4Shark/terraform/integrator-*/mongodb.tf` — the live Terraform for every Mongo EC2
  instance in scope.
- `aws iam get-instance-profile` / `list-attached-role-policies` / `list-role-policies` for
  `mongo-cwagent` (default read-only profile, 2026-07-21) — see auxiliary:
  `ec2-ssh-access-per-environment_data_1.json`
- https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-restrict-access-quickstart.html
  — AWS official sample IAM policies for Session Manager (tag-scoped `StartSession`). See auxiliary:
  `ec2-ssh-access-per-environment_doc_1.txt`
- https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-restrict-access-examples.html
  — AWS official tag-based restriction examples. See auxiliary: `ec2-ssh-access-per-environment_doc_2.txt`
- https://aws.amazon.com/blogs/mt/how-to-grant-least-privilege-access-to-third-parties-on-your-private-ec2-instances-with-aws-systems-manager/
  — AWS Cloud Operations Blog, tag-based (ABAC) least-privilege access per external party via
  Session Manager, no key pairs. See auxiliary: `ec2-ssh-access-per-environment_doc_2.txt`
- https://xebia.com/blog/ssm-startsession-tags/ — practitioner blog, a second (deny-based, per-user)
  tag-scoping technique for `ssm:StartSession`. See auxiliary: `ec2-ssh-access-per-environment_doc_2.txt`

## Findings

### Finding 1: Today, both the SSH key AND the IAM role are shared across every Mongo host — 16 instances, one key, one role

**Evidence:**
```
modules/vpn/mongodb.tf:92:   key_name      = "kp-4shark"
integrator-almaviva/mongodb.tf:39,82,125:   iam_instance_profile = "mongo-cwagent"
integrator-atento/mongodb.tf:43,86,129:     iam_instance_profile = "mongo-cwagent"
integrator-commcenter/mongodb.tf:39,82,125: iam_instance_profile = "mongo-cwagent"
integrator-maqnelson/mongodb.tf:41,84,127:  iam_instance_profile = "mongo-cwagent"
integrator-redebrasil/mongodb.tf:31,76,121: iam_instance_profile = "mongo-cwagent"
```
`grep -rn "key_name" ~/Projects/4Shark/terraform/{modules/vpn,integrator-*}/mongodb.tf` returns
`"kp-4shark"` for every one of the 16 `aws_instance` resources (3 nodes × 5 integrators + 1 VPN
Mongo host); `grep -rn "iam_instance_profile"` returns the identical string `"mongo-cwagent"` for
every one of them.

**Source:** `~/Projects/4Shark/terraform/modules/vpn/mongodb.tf:92`;
`~/Projects/4Shark/terraform/integrator-atento/mongodb.tf:43,86,129` (representative of all five
integrators, each verified individually)

**Significance:** the SSH key pair is not the only shared credential in play. The instance's own
IAM role is shared too. Whether this matters for a chosen mechanism differs — see Finding 6.

### Finding 2: Every Mongo instance already carries a per-client/per-environment tag

**Evidence:**
```
integrator-atento/mongodb.tf:55:       Client     = "atento"
integrator-almaviva/mongodb.tf:51:     Client     = "almaviva"
integrator-commcenter/mongodb.tf:51:   Client     = "commcenter"
integrator-maqnelson/mongodb.tf:53:    Client     = "maqnelson"
integrator-redebrasil/mongodb.tf:43:   Client     = "redebrasil"
modules/vpn/mongodb.tf:79:             Environment = "management"
```
Every integrator's three Mongo nodes carry a consistent `Client = "<slug>"` tag; the VPN's Mongo
host carries `Environment = "management"` and `Role = "database"`.

**Source:** `~/Projects/4Shark/terraform/integrator-atento/mongodb.tf:55`,
`~/Projects/4Shark/terraform/integrator-almaviva/mongodb.tf:51`,
`~/Projects/4Shark/terraform/integrator-commcenter/mongodb.tf:51`,
`~/Projects/4Shark/terraform/integrator-maqnelson/mongodb.tf:53`,
`~/Projects/4Shark/terraform/integrator-redebrasil/mongodb.tf:43`,
`~/Projects/4Shark/terraform/modules/vpn/mongodb.tf:79`

**Significance:** the tag precondition that AWS's own tag-scoped `ssm:StartSession` examples rely
on (Finding 5) already exists on every Mongo host in scope, at no additional Terraform cost. A
per-environment scoping mechanism built on `ssm:resourceTag/Client` conditions would not require
adding tags first — it would only require writing the IAM policy.

### Finding 3: The in-flight KMS-key-per-environment plan does not address machine access at all

**Evidence:** `grep -n -i "ssh\|key_name\|key pair\|session manager\|ssm.*session\|machine access"`
against the full 765-line `kms-key-per-environment/PLAN.md` returns exactly one match, and it is
unrelated — a reference to "`ssm-read`" (an SSM *parameter*-read IAM policy name for ECS tasks, not
Session Manager). The plan's own stated scope: *"Scope — this design covers the six stacks on
`4shark-master`, and only those"* and, later, *"The five integrators (sa-east-1, customer-managed
key per integrator)"* — both populations are ECS task roles and SSM SecureString/RDS/OpenSearch
encryption. No EC2 instance, key pair, or Session Manager mechanism appears anywhere in the document.

**Source:** `~/Projects/4Shark/dot-claude-plans/active/terraform/kms-key-per-environment/PLAN.md`
(full-text grep, zero relevant matches)

**Significance:** the KMS-per-environment work and machine access to the Mongo hosts are, as
currently scoped, two disjoint bodies of work touching different resource types (ECS task
roles/KMS keys for the former; EC2 instances/SSH or IAM session access for the latter). Folding
them together would be a scope decision made now, not something the existing plan already
anticipates or partially covers.

### Finding 4: `mongo-cwagent`, the instance role every Mongo host shares, lacks the IAM policy Session Manager needs

**Evidence:**
```json
"AttachedPolicies": [
  { "PolicyName": "CloudWatchAgentServerPolicy",
    "PolicyArn": "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy" }
]
```
`aws iam list-role-policies --role-name mongo-cwagent` returns `"PolicyNames": []` (zero inline
policies). `AmazonSSMManagedInstanceCore` — the managed policy the ssm-session-manager-adoption
spike identifies as required (*"Instance must have an IAM role with the `AmazonSSMManagedInstanceCore`
managed policy (or equivalent custom policy)"*, `ssm-session-manager-adoption/SPIKE.md:204`) — is
absent.

**Source:** `ec2-ssh-access-per-environment_data_1.json` (raw `aws iam` output, 2026-07-21,
default read-only profile)

**Significance:** Session Manager is not functional against any of these 16 hosts today,
independent of which access-tiering mechanism is eventually chosen. This is a prerequisite
regardless of the answer to Q3/Q4 below — adopting Session Manager for these hosts requires this
policy attachment as a first step, distinct from any per-environment scoping design.

### Finding 5: AWS's own sample IAM policies document tag-scoped `ssm:StartSession` — the mechanism that expresses "per-environment" without a key pair

**Evidence:**
```json
{
  "Effect": "Allow",
  "Action": ["ssm:StartSession"],
  "Resource": ["arn:aws:ec2:*:{{111122223333}}:instance/*"],
  "Condition": {
    "StringLike": { "ssm:resourceTag/Finance": ["WebServers"] }
  }
}
```
The page's own prose: *"You can restrict access to managed nodes based on specific tags. In the
following example, the user is allowed to start and resume sessions... on any managed node...
with the condition that the node is a Finance WebServer... If the user sends a command to a
managed node that isn't tagged or that has any tag other than Finance: WebServer, the command
result will include `AccessDenied`."*

**Source:** https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-restrict-access-examples.html
(fetched 2026-07-21; full quote and JSON preserved in `ec2-ssh-access-per-environment_doc_2.txt`)

**Significance:** substituting `ssm:resourceTag/Client` for `ssm:resourceTag/Finance` against the
`Client` tag already on every Mongo instance (Finding 2) reproduces, in IAM, the same shape of
isolation the KMS-per-environment plan builds with a key policy naming a role — an engineer's IAM
identity can be scoped to `Client=atento` and denied `Client=almaviva`, with **no key pair
involved at all**.

### Finding 6: A two-tier model (describe/list vs connect) is documented by AWS and demonstrated for exactly the per-tenant case

**Evidence:** AWS Cloud Operations Blog, on granting third-parties least-privilege EC2 access:
*"AWS Systems Manager Session Manager provides a more secure way to manage your Amazon Elastic
Compute Cloud (EC2) instances without the need to open inbound ports, maintain bastion hosts, or
manage SSH keys."* And, on the tag-scoping mechanism: *"Using ABAC, it's only possible to start a
session on the EC2 instances that have the tag value associated to the right third-party."* Both
quotes independently re-confirmed present in the source on a second fetch (2026-07-21).

**Source:** https://aws.amazon.com/blogs/mt/how-to-grant-least-privilege-access-to-third-parties-on-your-private-ec2-instances-with-aws-systems-manager/
(full text preserved in `ec2-ssh-access-per-environment_doc_2.txt`)

**Significance:** the article's design separates `ec2:DescribeInstances` (see which instances
exist — Tier 1: visibility, no shell) from `ssm:StartSession` gated by the resource-tag condition
(Tier 2: connect). This is a directly analogous case to the engineer's Tier 1/Tier 2 requirement —
except the article's Tier 1 is "list infrastructure," not "read/decrypt data." 4Shark's Tier 1
requirement (per `aws-engineer-staging-tier/SPIKE.md`) additionally needs `ssm:GetParameter` +
scoped `kms:Decrypt` on the environment's SecureString key — a different AWS service (Systems
Manager Parameter Store + KMS) from the one gating Tier 2 (Systems Manager Session Manager). AWS's
own sample policies keep these as **separate IAM statements** even within one document (Finding 7).

### Finding 7: AWS's own Session Manager sample policies use a KMS statement too — but for a different key, and kept in a separate statement

**Evidence:**
```json
{
  "Effect": "Allow",
  "Action": ["kms:GenerateDataKey"],
  "Resource": "arn:aws:kms:{{us-east-1}}:{{111122223333}}:key/{{key-name}}"
}
```
The page's explanatory note: *"The `kms:GenerateDataKey` permission enables the creation of a data
encryption key that will be used to encrypt session data... If you won't use KMS key encryption for
your session data, remove the following content from the policy."*

**Source:** https://docs.aws.amazon.com/systems-manager/latest/userguide/getting-started-restrict-access-quickstart.html
(full text preserved in `ec2-ssh-access-per-environment_doc_1.txt`)

**Significance:** this KMS action encrypts the Session Manager shell transcript/traffic (an
optional session preference) — a structurally different KMS use case from the environment's
SecureString-decrypt key the `kms-key-per-environment` plan builds. Even in AWS's own sample, this
KMS statement is a standalone block, not merged with the `StartSession` statement or with any data
KMS grant. Not found: any AWS documentation or community source describing a single combined IAM
grant that bundles environment KMS-decrypt (data plane) with SSM Session-connect (control plane)
under one "environment access" unit — the two stay separate statements in every source consulted.

### Finding 8: an SSH key pair is structurally single-tier — it cannot express "read but no shell" on its own

**Evidence:** a key pair's only function, per AWS's own EC2 documentation quoted in the
`aws-key-pair-standardization` spike, is authenticating an SSH session — *"the `~/.ssh/authorized_keys`
file on the instance is the authoritative source"* for who may log in (`aws-key-pair-standardization/SPIKE.md:37`).
There is no AWS or community mechanism found in this investigation, nor in the two prior 4Shark
spikes, for an SSH key to grant a "see but don't shell" capability — possession of a working key
IS shell access; there is no intermediate state.

**Source:** `~/Projects/4Shark/dot-claude-plans/active/spike/aws-key-pair-standardization/SPIKE.md:37`
(internal citation, itself citing https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/replacing-key-pair.html)

**Significance:** the engineer's Tier 1/Tier 2 split is native to IAM (a policy either does or does
not carry an `ssm:StartSession` statement; `ec2:Describe*`/`ssm:GetParameter` can exist without it)
but is not expressible with an SSH key pair at all, per-environment or otherwise. A key-pair-based
design would need a wholly separate mechanism bolted on for Tier 1 (e.g., IAM read access to
`describe-instances` + SSM parameters), so the two-tier requirement is not something a per-environment
key pair solves even partially — it solves only (a version of) Tier 2.

**Correction (2026-07-21, engineer).** The claim above holds ONLY for the trivial case — the SSH private
key sitting on the operator's own disk, where possessing the file IS shell access. It does NOT hold for
4Shark's actual design, which stores the SSH private key IN an SSM SecureString encrypted by the
environment's dedicated KMS key. There, "obtaining the key" is an IAM-gated read (`ssm:GetParameter` +
`kms:Decrypt`), not a raw SSH capability — and an IAM read IS gradable into "cannot read the key
parameter" (Tier 1) vs "can" (Tier 2). So the two-tier split IS expressible with an SSH key, when the key
is a KMS-encrypted SSM parameter rather than a file on disk. See Finding 10; this reframes Option A.

### Finding 9: 4Shark's own prior research already concluded, generically, that key pairs are the legacy path and Session Manager is the modern one — but did not evaluate the tiered/per-environment case

**Evidence:** *"In 2026, key pairs are a legacy mechanism. Session Manager (via IAM) is the
AWS-recommended access method for production infrastructure."* And the recorded decision:
*"Decision (2026-02-27): Skip Workstream A entirely. Go directly to Workstream B (Session Manager
migration). Rationale: investing effort in key pair standardization is wasted work if the end goal
is eliminating key pairs altogether."*

**Source:** `~/Projects/4Shark/dot-claude-plans/active/spike/aws-key-pair-standardization/SPIKE.md:310-312,360`

**Significance:** this decision was made about key pairs and Session Manager generically, across
4Shark's whole EC2 estate, and predates both the KMS-key-per-environment initiative and the
`aws-engineer-staging-tier` restricted-tier effort. It did not evaluate a tag-scoped, two-tier,
per-environment access model specifically — that composition (Findings 5, 6) is new material this
spike adds, not a re-derivation of the earlier decision. The earlier decision is a data point
supporting Option B below, not a settled answer to this spike's Q2/Q3.

### Finding 10: Storing the SSH private key in an SSM SecureString, read gated by IAM, is a documented community pattern — and it is what makes 4Shark's two-tier split expressible with a key, without Session Manager

**4Shark's design (engineer, 2026-07-21):** do NOT distribute the SSH private key through 1Password to
everyone. Store it IN the infrastructure as an SSM SecureString, encrypted by the environment's dedicated
KMS key (the same key the `kms-key-per-environment` plan mints). To SSH, a principal must first READ that
parameter — which requires `ssm:GetParameter` on the key's path AND `kms:Decrypt` on the environment's
key — then use the fetched key to connect. "Obtaining the key" thus becomes an IAM-gated read, not a raw
SSH capability, which is exactly what makes the Tier 1/Tier 2 split expressible (dissolving Finding 8's
objection for this design):
- **Tier 1** — IAM reads the environment's general parameters + `kms:Decrypt` on the env key, but has NO
  `ssm:GetParameter` on the SSH-key path. Sees infra and data; cannot obtain the key; cannot SSH.
- **Tier 2** — the same PLUS read of the SSH-key parameter. Fetches the key → `ssh-agent` → SSH.

**Evidence the pattern is established:** Eric Hammond (Alestic, a long-running AWS blog) documents storing
an SSH private key in SSM Parameter Store and fetching it only when needed — *"Upload the SSH private key
to SSM Parameter Store:"* (with `--type SecureString`); *"The SSH private key is only kept in memory and
only during the execution of the `git` command."*; *"We don't even want to store it on disk when it is
used, no matter how temporarily."*; *"with access controlled by AWS IAM, and only retrieve it briefly when
it is needed to be used."*

**Source:** https://alestic.com/2018/12/aws-ssm-parameter-store-git-key/ (fetched 2026-07-21; four quotes
above verified verbatim on the page). Corroborating, as separate findings not merged into this one:
https://kskilling.com/2019/10/14/retrieving-the-private-key-of-an-ssh-key-pair-from-aws-ssm/ (retrieving
an SSH key pair's private key from SSM) and the AWS re:Post confirmation that reading a SecureString
requires both `ssm:GetParameter` and `kms:Decrypt`
(https://repost.aws/questions/QUFySsI0MDRsGEJ1C3dq0-hw/).

**Significance:** this is a THIRD mechanism the original spike missed, and it is the one that matches
4Shark's stated intent. It reframes Option A entirely: a "dedicated key per environment" is not a bare
key pair on disk (single-tier, Finding 8) — it is the environment's SSH key living as a SecureString
under that environment's dedicated KMS key, where the tier boundary is an IAM read on the key parameter.
It rides the `kms-key-per-environment` machinery verbatim: "access to beta" = beta's `kms:Decrypt` grant +
(for Tier 2) `ssm:GetParameter` on beta's SSH-key path. Trade-off vs Option B (Session Manager): CloudTrail
audits the KEY FETCH (`GetParameter`), not the SSH session command-by-command the way Session Manager does,
and once fetched the key is a live credential in the operator's agent until it rotates. Benefits over
Option B: it works today (no `AmazonSSMManagedInstanceCore` prerequisite, no SSM VPC-endpoint readiness
question — Findings 4 and the Uncertain section), and it reuses the KMS-per-environment work with no new
AWS service to adopt.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| **A — Bare EC2 key pair per environment** (the key distributed as a file to the operator) | Simple mental model — matches the KMS-key-per-environment naming; no new AWS mechanism to learn | Cannot express Tier 1 (Finding 8) — a key pair on disk is single-tier by construction; no individual accountability or CloudTrail session log per engineer (`ssm-session-manager-adoption/SPIKE.md:361-364`); a leaked key still exposes every host that shares it unless keys are ALSO rotated per-node (today all 16 hosts share one key — Finding 1); 4Shark's own prior research already concluded key pairs are the legacy path for the whole estate (Finding 9) | Findings 1, 8, 9 |
| **D — SSH key per environment stored in an SSM SecureString under the env's dedicated KMS key, read gated by IAM (4Shark's stated design)** | Expresses Tier 1/Tier 2 natively — the tier boundary is `ssm:GetParameter` on the SSH-key path + `kms:Decrypt` on the env key (Finding 10); rides the kms-key-per-environment machinery verbatim (the SSH key is just another SecureString under the env key — no new AWS service to adopt); works today (no `AmazonSSMManagedInstanceCore` attach, no SSM VPC-endpoint readiness question — Finding 4 / Uncertain); a documented community pattern (Finding 10, Alestic) | CloudTrail audits the key FETCH (`GetParameter`), not the SSH session command-by-command the way Session Manager (Option B) does; once fetched, the key is a live credential in the operator's agent until it rotates; the shared `kp-4shark` (Finding 1) would need replacing with per-environment key pairs materialized into SSM, and a rotation story defined | Finding 10 |
| **B — SSM Session Manager + `ssm:resourceTag`-scoped IAM, two separate statements for Tier 1 (SSM/KMS read) and Tier 2 (StartSession)** | Native two-tier expression (Finding 8); the `Client`/`Environment` tag precondition already exists on every host (Finding 2); AWS publishes this exact tag-scoped-StartSession shape as a sample policy (Finding 5) and as a named third-party/tenant least-privilege pattern (Finding 6); individual accountability + CloudTrail audit per session (`ssm-session-manager-adoption/SPIKE.md:357-370`); no port 22 exposure | `AmazonSSMManagedInstanceCore` is not yet attached to `mongo-cwagent` (Finding 4) — a prerequisite regardless of tiering design; VPC networking/endpoint readiness for the sa-east-1 integrator VPCs was not confirmed in this spike (see Uncertain, below) — the general cost/prerequisite mechanics are already documented in `ssm-session-manager-adoption/SPIKE.md` §§4,6 | Findings 2, 4, 5, 6, 9 |
| **C — Hybrid: keep `kp-4shark` as an emergency/break-glass credential, adopt B for day-to-day tiered access** | Preserves a recovery path if SSM Agent fails (`ssm-session-manager-adoption/SPIKE.md:243-256` lists SSM-Agent-failure as a real gap) | Does not solve per-environment isolation for the emergency path — the shared key remains shared; the prior 4Shark decision explicitly rejected "keep keys just in case" as defeating the purpose (`ssm-session-manager-adoption/SPIKE.md:264-266`) | Finding 9; `ssm-session-manager-adoption/SPIKE.md:243-269` |

## What remains uncertain

- Whether the sa-east-1 integrator VPCs (almaviva, atento, commcenter, maqnelson, redebrasil) have
  the outbound network path SSM Agent needs — the `networking/ssm.tf` file publishes no
  `nat_gateway_eips` parameter for these VPCs (unlike the `app-*`/`onboarding`/`setup` VPCs, which
  each publish one), and their private-subnet route table points toward a shared `egress-sa-east-1`
  Transit Gateway VPC rather than a per-VPC NAT. Whether that shared egress path already reaches the
  SSM/SSMMessages/EC2Messages endpoints, or whether VPC Interface Endpoints are additionally needed,
  was not confirmed — this is a readiness question for whichever Option is chosen, not something
  that changes the mechanism comparison above. (`ssm-session-manager-adoption/SPIKE.md` §4 documents
  the general VPC-endpoint cost/requirement mechanics for private subnets.)
- Whether 4Shark wants per-environment isolation to reach the level of "Santiago can shell into
  Atento's Mongo hosts but not Almaviva's" (mirroring the `atento-access-delegation` driver named in
  `kms-key-per-environment/PLAN.md`) as a concrete, near-term need, or whether the two-tier
  requirement is currently about a single engineer needing Tier 1 only (as in
  `aws-engineer-staging-tier/SPIKE.md`'s frontend-engineer driver) — the trade-off table above holds
  either way, but the urgency and the exact tag values to scope on depend on which driver is live.
- Whether the shared `mongo-cwagent` role also needs splitting per environment/client (mirroring the
  KMS plan's `ecsTaskExecutionRole` split) — this spike's Finding 6 argues it is not a *blocking*
  prerequisite for Option B, because SSM Session Manager's caller-side authorization is scoped by
  the caller's own IAM policy + the target's tags, not by the target's own attached role. Whether a
  per-client instance role is independently desirable for other reasons (e.g., scoping what the
  MongoDB process itself can do via IMDS-obtained credentials) was not investigated here.

## Suggested options for main and the engineer

- **Option A**: dedicated EC2 key pair per environment (Finding 1's shared-key problem addressed
  literally, mirroring the KMS-key-per-environment naming) — but Finding 8 shows this does not
  reach the Tier 1/Tier 2 requirement at all; it would need a separate, IAM-based mechanism bolted
  on for Tier 1, at which point most of the SSM/IAM machinery in Option B is being built anyway.
- **Option B**: adopt SSM Session Manager for the Mongo hosts, express Tier 1 as
  `ssm:GetParameter` + scoped `kms:Decrypt` + `ec2:Describe*` (no `ssm:StartSession` statement), and
  Tier 2 as the same plus `ssm:StartSession` conditioned on `ssm:resourceTag/Client` (or
  `Environment`) — directly grounded in Findings 2, 4, 5, 6, and consistent with 4Shark's own prior
  decision (Finding 9) to treat key pairs as the legacy path for the whole estate, not only for a
  newly-created resource.
- **Option C**: Option B for day-to-day access, `kp-4shark` retained only as a documented
  break-glass path for SSM-Agent-failure recovery — accepting that the break-glass path itself
  remains unscoped by environment (Finding 9's own prior rejection of "keep keys just in case"
  applies here too, so this option carries that named trade-off explicitly rather than silently).
- **Option D (4Shark's stated design)**: store each environment's SSH private key as an SSM SecureString
  encrypted by that environment's dedicated KMS key; Tier 1 = read the env's general parameters +
  `kms:Decrypt` (no `ssm:GetParameter` on the SSH-key path); Tier 2 = the same plus read of the SSH-key
  parameter → `ssh-agent` → SSH. Grounded in Finding 10 (documented community pattern, Alestic) and it is
  the option that reuses the kms-key-per-environment work verbatim while keeping SSH. Its trade-off vs
  Option B is audit granularity (the key fetch is logged, not the session) and a fetched key being a live
  credential until rotation. This is the option to weigh against B; Option A (bare key on disk) is
  superseded by it.
- **On folding vs separating (Q4)**: Finding 3 shows the two are currently disjoint in scope
  (different AWS resource types — ECS task roles/KMS keys vs EC2 instances/Session Manager IAM).
  Whether to run them as one combined initiative or two sequenced ones is a scheduling/scope
  decision for the engineer, not something resolved by the mechanism findings above — either
  sequencing is compatible with Option B.
