# SPIKE — Minimum AWS permissions for the break-glass identity

## Investigation question

Which AWS IAM actions does the break-glass identity (`arn:aws:iam::405749097490:user/ivo@4shark.com.br`) actually need in order to run `terraform plan` and `terraform apply` against the `identity/` and `audit/` stacks — so that an MFA-conditioned customer-managed policy can replace `AdministratorAccess` on that user without breaking the workflow that grants permissions back?

## Sources consulted

- `identity/` and `audit/` stack sources (`~/Projects/4Shark/terraform/`) — the declared resource and data-source inventory, which fixes the set of API actions the providers must be able to call.
- CloudTrail `LookupEvents`, 2026-05-28 → 2026-08-26, filtered to `userIdentity.type == "IAMUser"` — 7 782 events, the empirical record of what this identity actually called. Aggregate preserved as `break-glass-permissions_cloudtrail_1.txt`.
- https://docs.aws.amazon.com/IAM/latest/UserGuide/access-analyzer-policy-generation.html — IAM Access Analyzer policy generation, evaluated as an alternative method and rejected.
- https://developer.hashicorp.com/terraform/language/backend/s3 — the S3 backend's own permission requirements, including `use_lockfile` and KMS.
- `identity/providers.tf:31-36`, `audit/providers.tf` — the state backend configuration both stacks share.

## Findings

### Finding 1: CloudTrail conflates two different identities under one username

A `LookupEvents` query on `Username=ivo@4shark.com.br` returns 9 860 events across three identity types:

```
7782 IAMUser     arn:aws:iam::405749097490:user/ivo@4shark.com.br
2063 AssumedRole arn:aws:sts::405749097490:assumed-role/AWSReservedSSO_AdministratorAccess_c093ee78d82c07c2/ivo@4shark.com.br
  15 SAMLUser    none
```

**Source:** `aws cloudtrail lookup-events --lookup-attributes AttributeKey=Username,AttributeValue=ivo@4shark.com.br --start-time 2026-05-28`, aggregated by `.userIdentity.type` and `.userIdentity.arn`.

**Significance:** the `AssumedRole` events are the human browsing the console through the Identity Center `AdministratorAccess` permission set — they include `es`, `rds`, `ec2`, `billing`, `freetier`, `ConsoleLogin` and other services the stacks never touch. Any inventory built without this split is inflated by roughly a third with actions that belong to a different identity. The two identities share only an email address; the IAM user has no login profile at all (`GetLoginProfile` → `NoSuchEntity`), so the console path never runs through it.

### Finding 2: nearly every historical call was made with the long-term key, not an MFA session

Distribution of `sessionContext.attributes.mfaAuthenticated` across the 7 782 IAM-user events, by day:

```
 122 no-session  2026-05-29
 ...
 928 no-session  2026-08-21
  16 false       2026-08-25
 161 no-session  2026-08-25
  17 no-session  2026-08-26
 174 true        2026-08-26
```

**Source:** `break-glass-permissions_cloudtrail_1.txt` and the per-day aggregation of the same event set.

**Significance:** `mfaAuthenticated = true` appears on exactly one day — 2026-08-26, the day the break-glass MFA elevation was set up. Everything before it ran either with the long-term access key directly (`no-session`, no `sessionContext` at all) or with a session minted without MFA (`false`). An MFA-conditioned policy therefore does not merely describe the documented model — it *enforces* it, and it retires the long-term key for every purpose except minting a session. That is the stated intent (`IDENTITY-STACK.md`: the key "exists to be exchanged rather than used"), but it is a behavioural change, not a no-op.

### Finding 3: only `GetSessionToken` structurally cannot carry MFA

Today's non-MFA IAM-user calls, in full:

```
2026-08-26T19:17:11Z  sts  GetSessionToken
2026-08-26T18:51:09Z  sts  GetSessionToken
2026-08-26T17:55:17Z  sts  GetSessionToken
2026-08-26T15:43:59Z  sts  GetSessionToken
2026-08-26T15:26:24Z  iam  ListMFADevices
2026-08-26T14:21:51Z  iam  GetLoginProfile
2026-08-26T13:55:34Z  sso  DescribeInstance
...
```

**Source:** the same event set, filtered to `eventTime` starting `2026-08-26` and `mfaAuthenticated == "no-session"`.

**Significance:** the four `GetSessionToken` calls are the elevations themselves — they *establish* the MFA session and by definition cannot be inside one. Every other entry is an ad-hoc read run against the raw `ivo` profile during this session's audit work, not a step the stacks require. So an MFA condition costs nothing structural: the one action that cannot satisfy it is also the one action AWS does not let a policy govern at all.

### Finding 4: the empirical record cannot cover the state backend, and no CloudTrail-based method can

The IAM-user events include `s3:GetBucketLocation`, `GetBucketEncryption`, `GetBucketVersioning` and `ListBuckets`, plus `kms:Decrypt` (57) and `kms:GenerateDataKey` (31) — but no `GetObject` or `PutObject` on the state file.

**Source:** `break-glass-permissions_cloudtrail_1.txt`; and the IAM Access Analyzer documentation, verbatim: *"IAM Access Analyzer does not identify action-level activity for data events, such as Amazon S3 data events, in generated policies."*

**Significance:** S3 object operations are data events, which the trail does not record. The state backend's permissions are therefore invisible to the empirical method and must come from the backend's own documentation. This also settles the Access Analyzer question: it analyses *"a time period of up to 90 days"* of the same CloudTrail data, has the same data-event blind spot, additionally omits `iam:PassRole` (*"not tracked by CloudTrail and is not included in generated policies"*), and requires a service role to be created first. It would reproduce this inventory with the same holes and an extra setup step — no reason to take it.

### Finding 5: the state backend's requirements are fixed by configuration, not by history

Both stacks share one backend (`identity/providers.tf:31-36`, `audit/providers.tf`):

```hcl
  backend "s3" {
    bucket       = "4shark-terraform-state"
    key          = "identity/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
```

The bucket is encrypted with a customer-managed key:

```json
"SSEAlgorithm": "aws:kms",
"KMSMasterKeyID": "arn:aws:kms:us-east-1:405749097490:key/c14b0cdc-df2e-4085-8003-9c3d9bc480d4"
```

**Source:** `aws s3api get-bucket-encryption --bucket 4shark-terraform-state`; and the Terraform S3 backend documentation, which lists `s3:ListBucket` on the bucket plus `s3:GetObject` and `s3:PutObject` on the state key, adds `s3:GetObject`, `s3:PutObject` and `s3:DeleteObject` on `<key>.tflock` when `use_lockfile` is enabled, and states that with KMS encryption *"Terraform will need `kms:Encrypt`, `kms:Decrypt` and `kms:GenerateDataKey` permissions on this KMS key."*

**Significance:** this is the one part of the policy that can be tightly scoped by ARN — bucket, two state keys, two lock keys, one key ARN — and it is also the part whose omission fails first and most confusingly, because the failure happens before any resource is refreshed.

### Finding 6: the observed set is a subset of the required set, because destroy paths never ran

The 90-day window captured `CreatePolicy`, `CreatePolicyVersion`, `DeletePolicyVersion`, `CreateGroup`, `AddUserToGroup`, `RemoveUserFromGroup`, `AttachGroupPolicy`, `AttachUserPolicy`, `PutUserPolicy`, `DeleteUserPolicy`, `DeleteUser`, `TagUser`, `CreatePermissionSet`, `CreateAccountAssignment`, `ProvisionPermissionSet`, `identitystore:CreateUser`, `DeleteUser` and `DeleteGroupMembership` — but no `DeleteGroup`, no `DetachGroupPolicy`, no `DeletePolicy`, no `DeletePermissionSet`, no `DeleteAccountAssignment`, and nothing at all from `cloudtrail.amazonaws.com`.

**Source:** `break-glass-permissions_cloudtrail_1.txt` (the complete aggregate; absence of a row is the evidence).

**Significance:** an action is absent because nobody exercised that path in the window, not because the stack never needs it. The `audit/` stack in particular was not applied at all in these 90 days, so its entire permission surface is empirically unobserved. A policy built from the observed set alone would pass today and fail the first time somebody removes an engineer or touches the trail. The correct set is the **union** of what was observed and what the declared resources imply.

### Finding 7: the resulting policy is a blast-radius bound, not a privilege boundary

The stacks declare 40 AWS resource types, of which the load-bearing ones are `aws_iam_policy` (13), `aws_iam_group_policy_attachment` (11), `aws_iam_user`/`aws_iam_group`/their attachments, the four Identity Center resource families, and in `audit/` the CloudTrail trail with its S3 log bucket and KMS key.

**Source:** `grep -rhoE '^resource "[a-z0-9_]+"' identity/ audit/`, aggregated.

**Significance:** a policy that permits `iam:CreatePolicy`, `iam:CreatePolicyVersion` and `iam:AttachUserPolicy` permits the holder to write themselves `AdministratorAccess` — the escalation `IDENTITY-STACK.md` already names. Replacing the managed policy therefore does not make the identity technically unable to become an administrator; it makes the identity unable to touch EC2, RDS, ECS, S3 data, VPCs and everything else *without first performing a loud, CloudTrail-recorded escalation*. That is a real and worthwhile reduction, and describing it as containment would be false.

### Finding 8: the Identity Center admin path is console-only in practice, and its programmatic half cannot be removed separately

A permission set is reachable two ways: the console, which logs `Federate` under `sso.amazonaws.com`, and the CLI, which calls `GetRoleCredentials` on the portal API. Over the 90-day lookup window the account shows **15 `Federate` events into `AdministratorAccess`** (identity-store user `14b8d428…`, `aws_identitystore_user.admin`, browser user agent), **3 into `EngineerAccess`** (`f46884f8…`, `aws_identitystore_user.engineer["paulo"]`), and **zero `GetRoleCredentials`**.

**Source:** `aws cloudtrail lookup-events --lookup-attributes AttributeKey=EventName,AttributeValue=GetRoleCredentials|Federate --region us-east-1`; `GetRoleCredentials` is logged under `sso.amazonaws.com` per the Identity Center CloudTrail documentation, so the zero is absence of use rather than absence of logging.

**Significance:** AWS offers no per-permission-set control over access method — the documented settings are session duration and the assignment itself — and no IAM condition key expresses "this request came from the console", so a `Deny` has nothing to match. Removing the programmatic path therefore means removing the permission set, taking the console path with it. What makes that acceptable to leave in place is that the two halves are equally protected: AWS states *"All MFA types are supported for both browser-based console access as well as using the AWS CLI v2 with IAM Identity Center"*, and `aws sso login` completes through the same browser portal and the same MFA challenge. The lever that decides whether admin sits behind a hardware key is therefore the Identity Center MFA setting (Settings → Authentication → *Users can authenticate with these MFA types*, whose two options are "Security keys and built-in authenticators" and "Authenticator apps"), not the access method.

**Where the second factor actually comes from:** the instance's identity source is an **external identity provider over SAML 2.0**, read from the Identity Center console — so Identity Center manages no MFA of its own here and shows no MFA section on its Authentication tab. Authentication happens at Google Workspace, where `ivo@4shark.com.br` requires a FIDO2 security key, and `aws sso login` reaches the same provider through the browser. Both portal paths, console and CLI, are therefore behind the hardware key already.

The absence of `ExternalIds` on the identity-store user records is NOT evidence of an internal directory: Identity Center supports an external provider whose users are created manually rather than provisioned by SCIM, which is the shape this account runs.

## Derived action set

The union of the two methods, grouped as it should be written. Everything below is either observed in `break-glass-permissions_cloudtrail_1.txt` or implied by a declared resource type.

**IAM — users, groups, policies** (`identity/`)

`iam:CreateUser`, `GetUser`, `UpdateUser`, `DeleteUser`, `TagUser`, `UntagUser`, `ListUserTags`, `ListUsers`, `CreateLoginProfile`, `GetLoginProfile`, `UpdateLoginProfile`, `DeleteLoginProfile`, `CreateGroup`, `GetGroup`, `UpdateGroup`, `DeleteGroup`, `ListGroups`, `ListGroupsForUser`, `AddUserToGroup`, `RemoveUserFromGroup`, `CreatePolicy`, `DeletePolicy`, `GetPolicy`, `ListPolicies`, `CreatePolicyVersion`, `DeletePolicyVersion`, `GetPolicyVersion`, `ListPolicyVersions`, `AttachUserPolicy`, `DetachUserPolicy`, `ListAttachedUserPolicies`, `AttachGroupPolicy`, `DetachGroupPolicy`, `ListAttachedGroupPolicies`, `ListEntitiesForPolicy`, `TagPolicy`, `UntagPolicy`, `ListPolicyTags`

**Identity Center** (`identity/`)

`sso:ListInstances`, `DescribeInstance`, `CreatePermissionSet`, `DescribePermissionSet`, `UpdatePermissionSet`, `DeletePermissionSet`, `ListPermissionSets`, `ProvisionPermissionSet`, `DescribePermissionSetProvisioningStatus`, `AttachManagedPolicyToPermissionSet`, `DetachManagedPolicyFromPermissionSet`, `ListManagedPoliciesInPermissionSet`, `AttachCustomerManagedPolicyReferenceToPermissionSet`, `DetachCustomerManagedPolicyReferenceFromPermissionSet`, `ListCustomerManagedPolicyReferencesInPermissionSet`, `CreateAccountAssignment`, `DeleteAccountAssignment`, `ListAccountAssignments`, `DescribeAccountAssignmentCreationStatus`, `DescribeAccountAssignmentDeletionStatus`, `TagResource`, `UntagResource`, `ListTagsForResource`

`identitystore:CreateUser`, `DescribeUser`, `UpdateUser`, `DeleteUser`, `ListUsers`, `CreateGroup`, `DescribeGroup`, `UpdateGroup`, `DeleteGroup`, `ListGroups`, `CreateGroupMembership`, `DescribeGroupMembership`, `DeleteGroupMembership`, `ListGroupMemberships`

**CloudTrail, its bucket and its key** (`audit/`)

`cloudtrail:CreateTrail`, `DeleteTrail`, `UpdateTrail`, `GetTrail`, `GetTrailStatus`, `DescribeTrails`, `ListTrails`, `StartLogging`, `StopLogging`, `GetEventSelectors`, `PutEventSelectors`, `GetInsightSelectors`, `PutInsightSelectors`, `ListTags`, `AddTags`, `RemoveTags`

`kms:CreateKey`, `DescribeKey`, `GetKeyPolicy`, `PutKeyPolicy`, `GetKeyRotationStatus`, `EnableKeyRotation`, `ScheduleKeyDeletion`, `CreateAlias`, `DeleteAlias`, `ListAliases`, `ListResourceTags`, `TagResource`, `UntagResource`

S3 on the audit log bucket: `CreateBucket`, `DeleteBucket`, `ListBucket`, `GetBucketPolicy`, `PutBucketPolicy`, `DeleteBucketPolicy`, and the `Get`/`Put` pair for `BucketVersioning`, `EncryptionConfiguration`, `LifecycleConfiguration`, `BucketPublicAccessBlock`, `BucketOwnershipControls`, `BucketTagging`, plus `GetBucketLocation` and `GetBucketObjectLockConfiguration`.

**State backend** (both stacks — scoped to exact ARNs)

`s3:ListBucket` on `arn:aws:s3:::4shark-terraform-state`; `s3:GetObject` and `s3:PutObject` on `identity/terraform.tfstate` and `audit/terraform.tfstate`; `s3:GetObject`, `s3:PutObject`, `s3:DeleteObject` on the matching `.tflock` keys; `s3:GetBucketVersioning`, `GetBucketLocation`, `GetEncryptionConfiguration` on the bucket; `kms:Encrypt`, `kms:Decrypt`, `kms:GenerateDataKey` on `arn:aws:kms:us-east-1:405749097490:key/c14b0cdc-df2e-4085-8003-9c3d9bc480d4`.

**Identity self-check — needs no grant**

`sts:GetCallerIdentity` is called 1 046 times, by the three `aws_caller_identity` data sources and by `guard.tf`'s postcondition, and it belongs in no policy: AWS states *"No permissions are required to perform this operation"*, and that even an explicit deny does not stop it, *"because the same information is returned when access is denied"*. Naming it would be inert, exactly like `sts:GetSessionToken`.

**Out of scope for IAM entirely**

The `identity/` stack also manages GitHub, Cloudflare, MongoDB Atlas and Rollbar. Those providers authenticate with credentials read from the `Terraform ENV` 1Password item by the stack's `.envrc`; no AWS permission governs them, and nothing in this policy affects them.

## Trade-offs surfaced

| Approach | Pros | Cons |
|---|---|---|
| Observed actions only (CloudTrail) | Provably sufficient for what has actually run; smallest surface | Fails on the first unexercised path — no destroy actions, no `audit/` actions at all (Finding 6) |
| Derived actions only (resource types + docs) | Covers every declared path | Doc-derived lists over-grant and miss provider-specific reads the SDK makes (`ListTagsForResource`, `DescribeRegisteredRegions`) |
| Union of both, with `AdministratorAccess` kept until proven | Complete and empirically anchored; failures surface as `AccessDenied` while the fallback is still attached | Requires a deliberate proving run before the detach |
| IAM Access Analyzer generation | Purpose-built | Same 90-day window and same data-event blind spot as the direct query, omits `iam:PassRole`, needs a service role first (Finding 4) |

## What remains uncertain

- The `audit/` stack has no observed activity in the 90-day window, so its action list is entirely doc-derived. The CloudTrail history in `s3://4shark-cloudtrail` reaches back to 2023 and would settle it empirically, at the cost of reading gzipped objects by date prefix without Athena.
- Provider-internal reads are only visible once exercised. The AWS provider calls tagging and describe APIs that no resource declaration announces; `sso:ListTagsForResource` (270 calls) is the example already caught, and others may exist on paths not yet run.
- Whether `identity/`'s own `aws_iam_policy` resources will hit the IAM managed-policy size limit once this policy is expressed as one document is not yet checked; the action list above is long enough that splitting across two policies may be forced.

## Sequenced path

The order is dictated by Finding 2 and by the fact that a session inherits the user's permissions: removing the fallback before the replacement is proven leaves the identity unable to apply the stack that would grant it back.

1. Write the policy as `identity/policy_break_glass.tf`, conditioned on `aws:MultiFactorAuthPresent = true`, and attach it to `aws_iam_user.break_glass` **alongside** the existing `AdministratorAccess`. Both attached, nothing lost.
2. Prove it by exercising the real paths — `plan` on both stacks, then an `apply` that touches IAM, Identity Center and the trail. `AdministratorAccess` is still attached, so failures do not appear as denials; the proving signal has to come from CloudTrail rather than from errors.
3. Detach `AdministratorAccess` in its own PR, so the change is one line and the revert is one line.
4. Re-run `plan` on both stacks immediately. Any `AccessDenied` here names exactly one missing action, which is added reactively — the rule `IDENTITY-STACK.md` already applies to engineer permissions, applied to this identity.

The rollback at every step is re-attaching `AdministratorAccess`, which the engineer can do from the console under the Identity Center admin session — an identity that this change never touches (the console admin is `aws_identitystore_user.admin`, a different principal from the IAM user). That is what makes step 3 safe to attempt at all.

---

> **Authoring:** written in the main session as time-boxed research to reduce uncertainty ahead of replacing `AdministratorAccess` on the break-glass identity. Every claim cites the command that produced it or the document it is quoted from. The CloudTrail aggregate is preserved as `break-glass-permissions_cloudtrail_1.txt` so a later session can re-derive the inventory without re-querying a window that will have moved.
