# TASKS — Demo Legacy Infrastructure Cleanup

**Created:** 2026-02-11
**Reference:** PLAN.md (same directory)
**AWS Profile:** `4shark`
**AWS Region:** `us-east-1`

## Execution Protocol

**Claude does NOT execute any commands.** All commands are executed by the engineer.

**Flow:**
1. Engineer says "proximo" (next)
2. Claude presents the next command (ready for copy-paste), explains what it does, and states the expected result
3. Engineer copies the command, executes in their terminal, and pastes the output back
4. Claude validates the output against expected result
5. If OK → engineer says "proximo" for the next command
6. If NOT OK → Claude analyzes and recommends action before proceeding

**Safety rules:**
- Never skip a CHECK command — always validate before destructive actions
- If any CHECK result is unexpected, STOP and analyze before proceeding
- BACKUP commands are mandatory before EC2 termination
- Each phase has a dependency order — respect the sequence
- **NEVER touch PGBouncer instances** (i-0d94ee11d885895be, i-04af861d35a147a24)

**Setup — Run once in your terminal:**
```bash
export AWS="--profile 4shark --region us-east-1"
```

All commands below use `$AWS` as shorthand for `--profile 4shark --region us-east-1`.

---

## Phase 1 — DNS Verification

### Task 1.1 — Check Cloudflare DNS for A records pointing to EIP

> This must be done manually in Cloudflare dashboard or via API.
> Search for any A records pointing to `54.162.171.130`.
> Also verify what `demo.app4shark.com` and `demo001.app4shark.com` resolve to.

```bash
dig demo.app4shark.com +short
```

**Expected:** Should resolve to the new demo-001-pub-lb ALB (CNAME), NOT to 54.162.171.130.

```bash
dig demo001.app4shark.com +short
```

**Expected:** Should resolve to demo-001-pub-lb ALB DNS name.

### Task 1.2 — Verify no other DNS records point to EIP

> Check Cloudflare for ALL A records with value 54.162.171.130.

**Expected:** No A records pointing to this IP. If any exist, they must be updated before Phase 5 (EIP release).

---

## Phase 2 — Terraform: Remove Old Worker ASGs

> Phase 2 involves editing Terraform files (done by Claude in a separate session) and then running terraform commands (done by engineer).
> Task 2.1 is done by Claude. Tasks 2.2+ are executed by the engineer.

### Task 2.1 — Create branch and edit Terraform files (Claude)

This task is performed by Claude when the engineer requests it. Claude will edit:
- `terraform/main.tf` — Remove `local.demo` (lines 26-32) + 7 module blocks (lines 761-963)
- `terraform/variables.tf` — Remove `ami_demo` (lines 17-20) + 21 `demo_*` vars (lines 274-356)
- `terraform/terraform.tfvars` — Remove `ami_demo` (line 3) + 21 `demo_*` values + section header (lines 135-171)

### Task 2.2 — Validate Terraform plan

```bash
cd ~/Projects/4Shark/terraform && AWS_PROFILE=4shark terraform plan
```

**Expected:** 14 resources to destroy (7 ASGs + 7 Launch Templates). 0 to add or change.

**Abort if:** Plan shows additions, changes, or resources outside `worker-demo-*`.

**Possible problem:** "Error acquiring the state lock" → someone else is running terraform. Wait or ask them to finish.

### Task 2.3 — Apply Terraform (after PR merge)

```bash
cd ~/Projects/4Shark/terraform && AWS_PROFILE=4shark terraform apply
```

**Expected:** "Apply complete! Resources: 0 added, 0 changed, 14 destroyed."

**Possible problem:** "ResourceInUse" on an ASG → some instance is still running in that ASG. Check with `aws autoscaling describe-auto-scaling-groups` and terminate the instance first.

### Task 2.4 — Verify ASGs removed

```bash
cd ~/Projects/4Shark/terraform && AWS_PROFILE=4shark terraform plan
```

**Expected:** "No changes. Your infrastructure matches the configuration."

### Task 2.5 — Verify ASGs no longer exist in AWS

```bash
aws autoscaling describe-auto-scaling-groups $AWS --query 'AutoScalingGroups[?contains(AutoScalingGroupName, `worker-demo`)].AutoScalingGroupName' --output json
```

**Expected:** `[]`

---

## Phase 3 — Manual: Terminate Legacy EC2 Instances

### Task 3.1 — Check instances current state

```bash
aws ec2 describe-instances $AWS --instance-ids i-0b74f0731fb052055 i-0fae0ac07b261301b --query 'Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name}' --output table
```

**Expected:** demo-app001=running, worker-image-demo=running

### Task 3.2 — Check termination protection: demo-app001

```bash
aws ec2 describe-instance-attribute $AWS --instance-id i-0b74f0731fb052055 --attribute disableApiTermination --query 'DisableApiTermination.Value'
```

**Expected:** `false`

### Task 3.3 — Check termination protection: worker-image-demo

```bash
aws ec2 describe-instance-attribute $AWS --instance-id i-0fae0ac07b261301b --attribute disableApiTermination --query 'DisableApiTermination.Value'
```

**Expected:** `false`

**If any returns `true`:** Run `aws ec2 modify-instance-attribute $AWS --instance-id <ID> --no-disable-api-termination` to disable it.

### Task 3.4 — Check EBS volumes

```bash
aws ec2 describe-volumes $AWS --filters "Name=attachment.instance-id,Values=i-0b74f0731fb052055,i-0fae0ac07b261301b" --query 'Volumes[*].{ID:VolumeId,Size:Size,InstanceId:Attachments[0].InstanceId,DeleteOnTermination:Attachments[0].DeleteOnTermination}' --output table
```

**Expected:** 2 volumes, all DeleteOnTermination=true

**If DeleteOnTermination=false:** Volumes won't auto-delete on termination. You'll need to manually delete them after termination with `aws ec2 delete-volume $AWS --volume-id <ID>`.

### Task 3.5 — Backup: snapshot demo-app001 volume

```bash
aws ec2 create-snapshot $AWS --volume-id vol-0a9631f76e0bb971b --description "Backup before cleanup: demo-app001" --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=backup-demo-app001-cleanup},{Key=DeleteAfter,Value=2026-02-25}]'
```

**Expected:** SnapshotId returned, State=pending

### Task 3.6 — Backup: snapshot worker-image-demo volume

```bash
aws ec2 create-snapshot $AWS --volume-id vol-015e5d29736ecf659 --description "Backup before cleanup: worker-image-demo" --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=backup-worker-image-demo-cleanup},{Key=DeleteAfter,Value=2026-02-25}]'
```

**Expected:** SnapshotId returned, State=pending

### Task 3.7 — Verify both snapshots completed

```bash
aws ec2 describe-snapshots $AWS --filters "Name=tag:Name,Values=backup-demo-*-cleanup" --query 'Snapshots[*].{ID:SnapshotId,Name:Tags[?Key==`Name`].Value|[0],State:State,VolumeId:VolumeId}' --output table
```

**Expected:** 2 snapshots, all State=completed. If State=pending, wait 2-3 minutes and re-run.

### Task 3.8 — Stop demo-app001

```bash
aws ec2 stop-instances $AWS --instance-ids i-0b74f0731fb052055
```

**Expected:** StoppingInstances with CurrentState=stopping

### Task 3.9 — Stop worker-image-demo

```bash
aws ec2 stop-instances $AWS --instance-ids i-0fae0ac07b261301b
```

**Expected:** StoppingInstances with CurrentState=stopping

### Task 3.10 — Wait for both instances to stop

```bash
aws ec2 wait instance-stopped $AWS --instance-ids i-0b74f0731fb052055 i-0fae0ac07b261301b
```

**Expected:** No output (waiter completed). **Now wait 5-10 minutes before proceeding to health check.**

### Task 3.11 — Health check: ECS services still healthy

```bash
aws ecs describe-services $AWS --cluster demo-001-cluster --services demo-001-web-service demo-001-worker-commission-service demo-001-worker-system-service demo-001-worker-user-service --query 'services[*].{Name:serviceName,Running:runningCount,Desired:desiredCount,Status:status}' --output table
```

**Expected:** All Status=ACTIVE, Running matches Desired.

**Abort if:** Any service shows Running < Desired or Status != ACTIVE. DO NOT TERMINATE — investigate the dependency first.

### Task 3.12 — Health check: PGBouncer instances still running

```bash
aws ec2 describe-instances $AWS --instance-ids i-0d94ee11d885895be i-04af861d35a147a24 --query 'Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name}' --output table
```

**Expected:** pgbouncer-demo-puma=running, pgbouncer-demo-sidekiq=running

**Abort if:** Either PGBouncer instance is not running. DO NOT PROCEED — PGBouncers are critical.

### Task 3.13 — Terminate both legacy instances

```bash
aws ec2 terminate-instances $AWS --instance-ids i-0b74f0731fb052055 i-0fae0ac07b261301b
```

**Expected:** TerminatingInstances with CurrentState=shutting-down

**Possible problem:** "DisableApiTermination" error → go back to Tasks 3.2-3.3 and disable termination protection.

### Task 3.14 — Wait for termination to complete

```bash
aws ec2 wait instance-terminated $AWS --instance-ids i-0b74f0731fb052055 i-0fae0ac07b261301b
```

**Expected:** No output (waiter completed).

### Task 3.15 — Verify instances terminated

```bash
aws ec2 describe-instances $AWS --instance-ids i-0b74f0731fb052055 i-0fae0ac07b261301b --query 'Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name}' --output table
```

**Expected:** All State=terminated

### Task 3.16 — Verify EBS volumes auto-deleted

```bash
aws ec2 describe-volumes $AWS --volume-ids vol-0a9631f76e0bb971b vol-015e5d29736ecf659 2>&1
```

**Expected:** Error "InvalidVolume.NotFound"

**If volumes still exist:** DeleteOnTermination was false. Delete manually with `aws ec2 delete-volume $AWS --volume-id <ID>` for each.

---

## Phase 4 — Manual: Deregister AMIs

### Task 4.1 — Check AMIs exist

```bash
aws ec2 describe-images $AWS --image-ids ami-09c4ce9b7b05d250d ami-042585670b08ee535 --query 'Images[*].{ID:ImageId,Name:Name,State:State}' --output table
```

**Expected:** 2 AMIs, both State=available

### Task 4.2 — Check no launch templates with "worker-demo" still exist

```bash
aws ec2 describe-launch-templates $AWS --query 'LaunchTemplates[?contains(LaunchTemplateName, `worker-demo`)].{Name:LaunchTemplateName,ID:LaunchTemplateId}' --output table
```

**Expected:** No `worker-demo-*` templates (removed by Phase 2).

**Abort if:** Any `worker-demo-*` launch template still exists — Phase 2 was incomplete.

### Task 4.3 — Check no ASGs use these AMIs via launch configs

```bash
aws autoscaling describe-launch-configurations $AWS --query 'LaunchConfigurations[?ImageId==`ami-09c4ce9b7b05d250d` || ImageId==`ami-042585670b08ee535`].LaunchConfigurationName' --output json
```

**Expected:** `[]`

**Abort if:** Any launch config still references these AMIs.

### Task 4.4 — Deregister AMI ami-042585670b08ee535

```bash
aws ec2 deregister-image $AWS --image-id ami-042585670b08ee535
```

**Expected:** No output (success).

### Task 4.5 — Deregister AMI ami-09c4ce9b7b05d250d

```bash
aws ec2 deregister-image $AWS --image-id ami-09c4ce9b7b05d250d
```

**Expected:** No output (success).

### Task 4.6 — Verify AMIs deregistered

```bash
aws ec2 describe-images $AWS --image-ids ami-09c4ce9b7b05d250d ami-042585670b08ee535 2>&1
```

**Expected:** Error "InvalidAMIID.NotFound"

### Task 4.7 — Verify AMI snapshots still exist (safety net)

```bash
aws ec2 describe-snapshots $AWS --snapshot-ids snap-06932330fa854a492 snap-08f978c8fa3bae57c --query 'Snapshots[*].{ID:SnapshotId,State:State,Description:Description}' --output table
```

**Expected:** 2 snapshots, both State=completed. Keep for 1 week as safety net.

### Task 4.8 — (After 2026-02-18) Delete snapshot snap-06932330fa854a492

```bash
aws ec2 delete-snapshot $AWS --snapshot-id snap-06932330fa854a492
```

**Expected:** No output (success).

### Task 4.9 — (After 2026-02-18) Delete snapshot snap-08f978c8fa3bae57c

```bash
aws ec2 delete-snapshot $AWS --snapshot-id snap-08f978c8fa3bae57c
```

**Expected:** No output (success).

### Task 4.10 — (After 2026-02-18) Verify snapshots deleted

```bash
aws ec2 describe-snapshots $AWS --snapshot-ids snap-06932330fa854a492 snap-08f978c8fa3bae57c 2>&1
```

**Expected:** Error "InvalidSnapshot.NotFound"

---

## Phase 5 — Manual: Release Elastic IP

### Task 5.1 — Check EIP status

```bash
aws ec2 describe-addresses $AWS --allocation-ids eipalloc-07ef3164971760037 --query 'Addresses[*].{AllocationId:AllocationId,PublicIp:PublicIp,AssociationId:AssociationId,InstanceId:InstanceId}' --output table
```

**Expected:** EIP exists. AssociationId should be empty/null (auto-disassociated after Phase 3 termination).

**If AssociationId is NOT empty:** Run Task 5.2 first. If empty, skip Task 5.2.

### Task 5.2 — (Conditional) Disassociate EIP if still attached

```bash
aws ec2 disassociate-address $AWS --association-id eipassoc-0f212e49c4dc9aa97
```

**Expected:** No output (success). Only needed if Task 5.1 shows AssociationId is not empty.

### Task 5.3 — Release EIP

```bash
aws ec2 release-address $AWS --allocation-id eipalloc-07ef3164971760037
```

**Expected:** No output (success).

### Task 5.4 — Verify EIP released

```bash
aws ec2 describe-addresses $AWS --allocation-ids eipalloc-07ef3164971760037 2>&1
```

**Expected:** Error "InvalidAddressID.NotFound"

---

## Phase 6 — Manual: Delete Security Groups

### Task 6.1 — Check SG 4Shark-Demo-prd-APP has no ENIs

```bash
aws ec2 describe-network-interfaces $AWS --filters "Name=group-id,Values=sg-0345d56db03e50853" --query 'NetworkInterfaces[*].{ID:NetworkInterfaceId,Status:Status,InstanceId:Attachment.InstanceId}' --output json
```

**Expected:** `[]`

**Abort if:** ENIs still attached.

### Task 6.2 — Check no other SGs reference 4Shark-Demo-prd-APP

```bash
aws ec2 describe-security-groups $AWS --filters "Name=ip-permission.group-id,Values=sg-0345d56db03e50853" --query 'SecurityGroups[*].{ID:GroupId,Name:GroupName}' --output json
```

**Expected:** `[]`

**If not empty:** Another SG has an ingress rule referencing this SG. You need to revoke that rule first with `aws ec2 revoke-security-group-ingress`.

### Task 6.3 — Delete SG 4Shark-Demo-prd-APP

```bash
aws ec2 delete-security-group $AWS --group-id sg-0345d56db03e50853
```

**Expected:** No output (success).

**Possible problem:** "DependencyViolation" → another SG references this one (Task 6.2 should have caught it) or an ENI is still attached.

### Task 6.4 — Verify SG 4Shark-Demo-prd-APP deleted

```bash
aws ec2 describe-security-groups $AWS --group-ids sg-0345d56db03e50853 2>&1
```

**Expected:** Error "InvalidGroup.NotFound"

### Task 6.5 — Check SG 4Shark-Demo-Worker has no ENIs

> Must run AFTER Phase 3 (EC2 termination releases the ENI).

```bash
aws ec2 describe-network-interfaces $AWS --filters "Name=group-id,Values=sg-092d04453a53ffdf1" --query 'NetworkInterfaces[*].{ID:NetworkInterfaceId,Status:Status,InstanceId:Attachment.InstanceId}' --output json
```

**Expected:** `[]`

**Abort if:** ENIs still attached. Wait for EC2 termination to complete.

### Task 6.6 — Check no other SGs reference 4Shark-Demo-Worker

```bash
aws ec2 describe-security-groups $AWS --filters "Name=ip-permission.group-id,Values=sg-092d04453a53ffdf1" --query 'SecurityGroups[*].{ID:GroupId,Name:GroupName}' --output json
```

**Expected:** `[]`

**If not empty:** Another SG has an ingress rule referencing this SG. Revoke that rule first.

### Task 6.7 — Delete SG 4Shark-Demo-Worker

```bash
aws ec2 delete-security-group $AWS --group-id sg-092d04453a53ffdf1
```

**Expected:** No output (success).

### Task 6.8 — Verify SG 4Shark-Demo-Worker deleted

```bash
aws ec2 describe-security-groups $AWS --group-ids sg-092d04453a53ffdf1 2>&1
```

**Expected:** Error "InvalidGroup.NotFound"

---

## Phase 7 — Manual: Delete Legacy EventBridge Rule

> The rule `Lambda-demo-worker-auto-scaling-rule` is DISABLED but still exists with 3 targets.
> Targets must be removed before deleting the rule. Rule must be deleted before deleting Lambdas.

### Task 7.1 — Check EventBridge rule exists and is DISABLED

```bash
aws events describe-rule $AWS --name "Lambda-demo-worker-auto-scaling-rule" --query '{Name:Name,State:State,Schedule:ScheduleExpression}' --output json
```

**Expected:** State=DISABLED, ScheduleExpression=rate(1 minute)

### Task 7.2 — List targets of the rule

```bash
aws events list-targets-by-rule $AWS --rule "Lambda-demo-worker-auto-scaling-rule" --query 'Targets[*].{Id:Id,Arn:Arn}' --output table
```

**Expected:** 3 targets:
- `Lambda-demo-worker-auto-scaling-system` (Id: Id50d1134b-0a09-42bb-9255-f09ae9b7b251)
- `Lambda-demo-worker-auto-scaling-minor` (Id: pyusv7mfu65iucew997l)
- `Lambda-demo-worker-auto-scaling-user` (Id: zyba9htag8z5v0s0k8wt)

### Task 7.3 — Remove all targets from the rule

```bash
aws events remove-targets $AWS --rule "Lambda-demo-worker-auto-scaling-rule" --ids "Id50d1134b-0a09-42bb-9255-f09ae9b7b251" "pyusv7mfu65iucew997l" "zyba9htag8z5v0s0k8wt"
```

**Expected:** `{"FailedEntryCount": 0, "FailedEntries": []}`

**If FailedEntryCount > 0:** Check the FailedEntries for error details. Fix and retry.

### Task 7.4 — Verify targets removed

```bash
aws events list-targets-by-rule $AWS --rule "Lambda-demo-worker-auto-scaling-rule" --query 'Targets' --output json
```

**Expected:** `[]`

### Task 7.5 — Delete the EventBridge rule

```bash
aws events delete-rule $AWS --name "Lambda-demo-worker-auto-scaling-rule"
```

**Expected:** No output (success).

**Possible problem:** "This rule has targets. Remove the targets before deleting the rule." → Task 7.3 did not succeed. Re-run Task 7.2 to check remaining targets.

### Task 7.6 — Verify rule deleted

```bash
aws events describe-rule $AWS --name "Lambda-demo-worker-auto-scaling-rule" 2>&1
```

**Expected:** Error "ResourceNotFoundException"

### Task 7.7 — Verify no legacy EventBridge Scheduler schedules

```bash
aws scheduler list-schedules $AWS --query 'Schedules[?contains(Name, `demo`)].{Name:Name,State:State}' --output table
```

**Expected:** Only `Lambda-demo-001-*` schedules (new ECS). No legacy ones.

---

## Phase 8 — Manual: Delete Legacy Lambda Functions

### Task 8.1 — Check Lambda minor has no event source mappings

```bash
aws lambda list-event-source-mappings $AWS --function-name Lambda-demo-worker-auto-scaling-minor --query 'EventSourceMappings[*].{Source:EventSourceArn,State:State}' --output json
```

**Expected:** `[]`

### Task 8.2 — Check Lambda system has no event source mappings

```bash
aws lambda list-event-source-mappings $AWS --function-name Lambda-demo-worker-auto-scaling-system --query 'EventSourceMappings[*].{Source:EventSourceArn,State:State}' --output json
```

**Expected:** `[]`

### Task 8.3 — Check Lambda user has no event source mappings

```bash
aws lambda list-event-source-mappings $AWS --function-name Lambda-demo-worker-auto-scaling-user --query 'EventSourceMappings[*].{Source:EventSourceArn,State:State}' --output json
```

**Expected:** `[]`

### Task 8.4 — Check Lambda major has no event source mappings

```bash
aws lambda list-event-source-mappings $AWS --function-name Lambda-demo-worker-auto-scaling-major --query 'EventSourceMappings[*].{Source:EventSourceArn,State:State}' --output json
```

**Expected:** `[]`

**Abort if:** Any Lambda has event source mappings. Remove triggers first.

### Task 8.5 — Delete Lambda minor

```bash
aws lambda delete-function $AWS --function-name Lambda-demo-worker-auto-scaling-minor
```

**Expected:** No output (success).

### Task 8.6 — Delete Lambda system

```bash
aws lambda delete-function $AWS --function-name Lambda-demo-worker-auto-scaling-system
```

**Expected:** No output (success).

### Task 8.7 — Delete Lambda user

```bash
aws lambda delete-function $AWS --function-name Lambda-demo-worker-auto-scaling-user
```

**Expected:** No output (success).

### Task 8.8 — Delete Lambda major

```bash
aws lambda delete-function $AWS --function-name Lambda-demo-worker-auto-scaling-major
```

**Expected:** No output (success).

### Task 8.9 — Verify no legacy Lambda functions remaining

```bash
aws lambda list-functions $AWS --query 'Functions[?contains(FunctionName, `demo`)].FunctionName' --output json
```

**Expected:** Only `Lambda-demo-001-*` and `codedeploy-hook-lambda-demo-001` functions. No `Lambda-demo-worker-*` functions.

---

## Phase 9 — Manual: Delete Legacy IAM Roles and Policies

### Task 9.1 — Check last used: Eventbridge-demo-invoke-minor-role

```bash
aws iam get-role $AWS --role-name Eventbridge-demo-invoke-minor-role --query 'Role.{Name:RoleName,LastUsed:RoleLastUsed.LastUsedDate,Region:RoleLastUsed.Region}' --output json
```

**Expected:** LastUsed is old (September 2025 or null). Safe to delete.

**Abort if:** LastUsed is within the last 24h.

### Task 9.2 — Check last used: Eventbridge-demo-invoke-system-role

```bash
aws iam get-role $AWS --role-name Eventbridge-demo-invoke-system-role --query 'Role.{Name:RoleName,LastUsed:RoleLastUsed.LastUsedDate,Region:RoleLastUsed.Region}' --output json
```

**Expected:** LastUsed is old or null.

### Task 9.3 — Check last used: Eventbridge-demo-invoke-user-role

```bash
aws iam get-role $AWS --role-name Eventbridge-demo-invoke-user-role --query 'Role.{Name:RoleName,LastUsed:RoleLastUsed.LastUsedDate,Region:RoleLastUsed.Region}' --output json
```

**Expected:** LastUsed is old or null.

### Task 9.4 — Check last used: Lambda-demo-worker-auto-scaling-minor-role

```bash
aws iam get-role $AWS --role-name Lambda-demo-worker-auto-scaling-minor-role --query 'Role.{Name:RoleName,LastUsed:RoleLastUsed.LastUsedDate,Region:RoleLastUsed.Region}' --output json
```

**Expected:** LastUsed is old or null.

### Task 9.5 — List all attached policies on Eventbridge-demo-invoke-minor-role

```bash
aws iam list-attached-role-policies $AWS --role-name Eventbridge-demo-invoke-minor-role --query 'AttachedPolicies[*].{Name:PolicyName,Arn:PolicyArn}' --output table
```

**Expected:** Exactly 1 policy: `Eventbridge-demo-invoke-minor-policy`

**If more than 1:** You need to detach each extra policy before deleting the role. Note the extra policy ARNs.

### Task 9.6 — Check for inline policies on Eventbridge-demo-invoke-minor-role

```bash
aws iam list-role-policies $AWS --role-name Eventbridge-demo-invoke-minor-role --query 'PolicyNames' --output json
```

**Expected:** `[]` (no inline policies)

**If not empty:** Delete each inline policy with `aws iam delete-role-policy $AWS --role-name <ROLE> --policy-name <POLICY>` before deleting the role.

> Repeat Tasks 9.5-9.6 for the other 3 roles if you want to be thorough.
> For brevity, check one — if it's clean, the others likely are too (all created the same way).

### Task 9.7 — Detach policy from Eventbridge-demo-invoke-minor-role

```bash
aws iam detach-role-policy $AWS --role-name Eventbridge-demo-invoke-minor-role --policy-arn "arn:aws:iam::405749097490:policy/Eventbridge-demo-invoke-minor-policy"
```

**Expected:** No output (success).

### Task 9.8 — Delete Eventbridge-demo-invoke-minor-role

```bash
aws iam delete-role $AWS --role-name Eventbridge-demo-invoke-minor-role
```

**Expected:** No output (success).

**Possible problem:** "Cannot delete entity, must detach all policies first" → extra policies exist. Run `aws iam list-attached-role-policies $AWS --role-name Eventbridge-demo-invoke-minor-role` and detach each one.

**Possible problem:** "Cannot delete entity, must delete all inline policies first" → Run `aws iam list-role-policies $AWS --role-name Eventbridge-demo-invoke-minor-role` and delete each.

### Task 9.9 — Delete Eventbridge-demo-invoke-minor-policy

```bash
aws iam delete-policy $AWS --policy-arn "arn:aws:iam::405749097490:policy/Eventbridge-demo-invoke-minor-policy"
```

**Expected:** No output (success).

**Possible problem:** "Cannot delete policy with non-default versions" → Run `aws iam list-policy-versions $AWS --policy-arn <ARN>` and delete non-default versions first.

### Task 9.10 — Detach policy from Eventbridge-demo-invoke-system-role

```bash
aws iam detach-role-policy $AWS --role-name Eventbridge-demo-invoke-system-role --policy-arn "arn:aws:iam::405749097490:policy/Eventbridge-demo-invoke-system-policy"
```

**Expected:** No output (success).

### Task 9.11 — Delete Eventbridge-demo-invoke-system-role

```bash
aws iam delete-role $AWS --role-name Eventbridge-demo-invoke-system-role
```

**Expected:** No output (success).

### Task 9.12 — Delete Eventbridge-demo-invoke-system-policy

```bash
aws iam delete-policy $AWS --policy-arn "arn:aws:iam::405749097490:policy/Eventbridge-demo-invoke-system-policy"
```

**Expected:** No output (success).

### Task 9.13 — Detach policy from Eventbridge-demo-invoke-user-role

```bash
aws iam detach-role-policy $AWS --role-name Eventbridge-demo-invoke-user-role --policy-arn "arn:aws:iam::405749097490:policy/Eventbridge-demo-invoke-user-policy"
```

**Expected:** No output (success).

### Task 9.14 — Delete Eventbridge-demo-invoke-user-role

```bash
aws iam delete-role $AWS --role-name Eventbridge-demo-invoke-user-role
```

**Expected:** No output (success).

### Task 9.15 — Delete Eventbridge-demo-invoke-user-policy

```bash
aws iam delete-policy $AWS --policy-arn "arn:aws:iam::405749097490:policy/Eventbridge-demo-invoke-user-policy"
```

**Expected:** No output (success).

### Task 9.16 — Detach policy from Lambda-demo-worker-auto-scaling-minor-role

```bash
aws iam detach-role-policy $AWS --role-name Lambda-demo-worker-auto-scaling-minor-role --policy-arn "arn:aws:iam::405749097490:policy/Lambda-demo-worker-auto-scaling-minor-policy"
```

**Expected:** No output (success).

### Task 9.17 — Delete Lambda-demo-worker-auto-scaling-minor-role

```bash
aws iam delete-role $AWS --role-name Lambda-demo-worker-auto-scaling-minor-role
```

**Expected:** No output (success).

### Task 9.18 — Delete Lambda-demo-worker-auto-scaling-minor-policy

```bash
aws iam delete-policy $AWS --policy-arn "arn:aws:iam::405749097490:policy/Lambda-demo-worker-auto-scaling-minor-policy"
```

**Expected:** No output (success).

### Task 9.19 — Verify no legacy demo IAM roles remaining

```bash
aws iam list-roles $AWS --query 'Roles[?contains(RoleName, `demo`)].RoleName' --output json
```

**Expected:** Only `demo-001-*`, `codedeploy-hook-lambda-role-demo-001`, `EventBridge-demo-001-*`, and `Lambda-demo-001-*` roles. No `Eventbridge-demo-invoke-*` or `Lambda-demo-worker-*` roles.

### Task 9.20 — Verify no legacy demo IAM policies remaining

```bash
aws iam list-policies $AWS --scope Local --query 'Policies[?contains(PolicyName, `demo`)].PolicyName' --output json
```

**Expected:** Only `demo-001-*`, `codedeploy-hook-lambda-policy-demo-001`, `EventBridge-demo-001-*`, `Lambda-demo-001-*`, `ECS-demo-001-*`, `CloudWatch-demo-001-*`, `AutoScaling-demo-001-*`, and `app-poc-deploy-demo-001` policies. No `Eventbridge-demo-invoke-*` or `Lambda-demo-worker-*` policies.

---

## Phase 10 — Manual: Delete Legacy CloudWatch Log Groups

### Task 10.1 — Check all legacy log groups

```bash
aws logs describe-log-groups $AWS --query 'logGroups[?contains(logGroupName, `demo`)].{Name:logGroupName,StoredBytes:storedBytes,Retention:retentionInDays}' --output table
```

**Expected:** Mix of legacy and new. Legacy to delete:
- `/aws/lambda/Lambda-demo-worker-auto-scaling-*` (4 groups)
- `/aws/lambda/codedeploy-hook-lambda-demo` (orphaned — function deleted)
- `/ecs/task-demo-app001` (empty, 1-day retention)

New to KEEP: `/aws/lambda/Lambda-demo-001-*`, `/aws/lambda/codedeploy-hook-lambda-demo-001`, `/aws/rds/cluster/demo-prd/*`.

### Task 10.2 — Delete /aws/lambda/Lambda-demo-worker-auto-scaling-major

```bash
aws logs delete-log-group $AWS --log-group-name "/aws/lambda/Lambda-demo-worker-auto-scaling-major"
```

**Expected:** No output (success).

### Task 10.3 — Delete /aws/lambda/Lambda-demo-worker-auto-scaling-minor

```bash
aws logs delete-log-group $AWS --log-group-name "/aws/lambda/Lambda-demo-worker-auto-scaling-minor"
```

**Expected:** No output (success).

### Task 10.4 — Delete /aws/lambda/Lambda-demo-worker-auto-scaling-system

```bash
aws logs delete-log-group $AWS --log-group-name "/aws/lambda/Lambda-demo-worker-auto-scaling-system"
```

**Expected:** No output (success).

### Task 10.5 — Delete /aws/lambda/Lambda-demo-worker-auto-scaling-user

```bash
aws logs delete-log-group $AWS --log-group-name "/aws/lambda/Lambda-demo-worker-auto-scaling-user"
```

**Expected:** No output (success).

### Task 10.6 — Delete /aws/lambda/codedeploy-hook-lambda-demo (orphaned)

```bash
aws logs delete-log-group $AWS --log-group-name "/aws/lambda/codedeploy-hook-lambda-demo"
```

**Expected:** No output (success). This is an orphaned log group — the Lambda function `codedeploy-hook-lambda-demo` no longer exists.

### Task 10.7 — Delete /ecs/task-demo-app001

```bash
aws logs delete-log-group $AWS --log-group-name "/ecs/task-demo-app001"
```

**Expected:** No output (success). Legacy ECS task naming, empty, 1-day retention.

### Task 10.8 — Verify all legacy log groups deleted

```bash
aws logs describe-log-groups $AWS --query 'logGroups[?contains(logGroupName, `demo`)].logGroupName' --output json
```

**Expected:** Only new groups: `/aws/lambda/Lambda-demo-001-*`, `/aws/lambda/codedeploy-hook-lambda-demo-001`, `/aws/rds/cluster/demo-prd/postgresql`. No `Lambda-demo-worker-*`, no `codedeploy-hook-lambda-demo` (without -001), no `/ecs/task-demo-app001`.

---

## Phase 11 — Validation

### Task 11.1 — Terraform state validation

```bash
cd ~/Projects/4Shark/terraform && AWS_PROFILE=4shark terraform plan
```

**Expected:** "No changes. Your infrastructure matches the configuration."

### Task 11.2 — ECS services health check

```bash
aws ecs describe-services $AWS --cluster demo-001-cluster --services demo-001-web-service demo-001-worker-commission-service demo-001-worker-system-service demo-001-worker-user-service demo-001-worker-cleansing-service demo-001-worker-migration-service demo-001-worker-commission-tiger-shark-service demo-001-worker-commission-white-shark-service --query 'services[*].{Name:serviceName,Status:status,Running:runningCount,Desired:desiredCount}' --output table
```

**Expected:** All Status=ACTIVE, Running matches Desired.

### Task 11.3 — Public ALB target group health check

```bash
aws elbv2 describe-target-health $AWS --target-group-arn "$(aws elbv2 describe-target-groups $AWS --names demo-001-pub-tg --query 'TargetGroups[0].TargetGroupArn' --output text)" --query 'TargetHealthDescriptions[*].{Target:Target.Id,Health:TargetHealth.State}' --output table
```

**Expected:** All targets healthy.

### Task 11.4 — PGBouncer instances health check

```bash
aws ec2 describe-instances $AWS --instance-ids i-0d94ee11d885895be i-04af861d35a147a24 --query 'Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name}' --output table
```

**Expected:** pgbouncer-demo-puma=running, pgbouncer-demo-sidekiq=running

### Task 11.5 — Scan for orphaned legacy SGs in VPC

```bash
aws ec2 describe-security-groups $AWS --filters "Name=vpc-id,Values=vpc-0204a1f8b5de51941" --query 'SecurityGroups[*].{ID:GroupId,Name:GroupName}' --output table
```

**Expected:** No SGs with names containing "Demo-prd-APP" or "Demo-Worker". PGBouncer-sg, 4Shark-demo-prd-db, and demo-001-* SGs should remain.

### Task 11.6 — Scan for orphaned legacy EC2 instances in VPC

```bash
aws ec2 describe-instances $AWS --filters "Name=vpc-id,Values=vpc-0204a1f8b5de51941" "Name=instance-state-name,Values=running,stopped" --query 'Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name}' --output table
```

**Expected:** Only demo-001-web, pgbouncer-demo-puma, pgbouncer-demo-sidekiq instances (and any other non-demo instances in the shared VPC).

### Task 11.7 — Scan for orphaned legacy Lambda functions

```bash
aws lambda list-functions $AWS --query 'Functions[?contains(FunctionName, `demo`)].FunctionName' --output json
```

**Expected:** Only `Lambda-demo-001-*` and `codedeploy-hook-lambda-demo-001`. No `Lambda-demo-worker-*`.

### Task 11.8 — Scan for orphaned legacy EventBridge rules

```bash
aws events list-rules $AWS --query 'Rules[?contains(Name, `demo`)].{Name:Name,State:State}' --output json
```

**Expected:** `[]`. No legacy rules remaining.

### Task 11.9 — Scan for orphaned legacy IAM roles

```bash
aws iam list-roles $AWS --query 'Roles[?contains(RoleName, `demo`)].RoleName' --output json
```

**Expected:** Only `demo-001-*`, `codedeploy-hook-lambda-role-demo-001`, `EventBridge-demo-001-*`, and `Lambda-demo-001-*` roles. No `Eventbridge-demo-*` (lowercase 'b') or `Lambda-demo-worker-*` roles.

### Task 11.10 — (After 24-48h) Cost validation

```bash
aws ce get-cost-and-usage $AWS --time-period Start=2026-02-12,End=2026-02-13 --granularity DAILY --metrics "UnblendedCost" --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute","Elastic Load Balancing"]}}' --query 'ResultsByTime[*].Total.UnblendedCost'
```

**Expected:** Reduced EC2 costs compared to previous days.

---

## Cleanup Backups (run after 2026-02-25)

### Task B.1 — List EBS backup snapshots

```bash
aws ec2 describe-snapshots $AWS --filters "Name=tag:DeleteAfter,Values=2026-02-25" --query 'Snapshots[*].{ID:SnapshotId,Name:Tags[?Key==`Name`].Value|[0]}' --output table
```

**Expected:** 2 backup snapshots (demo-app001, worker-image-demo).

> Note the SnapshotIds from the output — use them in Tasks B.2-B.3 below.

### Task B.2 — Delete backup snapshot 1 (demo-app001)

```bash
aws ec2 delete-snapshot $AWS --snapshot-id <SNAPSHOT-ID-FROM-B.1>
```

**Expected:** No output (success). Replace `<SNAPSHOT-ID-FROM-B.1>` with the actual ID.

### Task B.3 — Delete backup snapshot 2 (worker-image-demo)

```bash
aws ec2 delete-snapshot $AWS --snapshot-id <SNAPSHOT-ID-FROM-B.1>
```

**Expected:** No output (success). Replace `<SNAPSHOT-ID-FROM-B.1>` with the actual ID.

### Task B.4 — Verify all backup snapshots deleted

```bash
aws ec2 describe-snapshots $AWS --filters "Name=tag:DeleteAfter,Values=2026-02-25" --query 'Snapshots[*].SnapshotId' --output json
```

**Expected:** `[]`

---

## Execution Order Summary

```
Phase 1  → DNS Verification                 [blocking: must go first for Phase 5]
Phase 2  → Terraform PR (ASGs)              [blocking: must complete before Phase 4]
Phase 3  → EC2 terminate (manual)           [blocking: Phase 5, 6 depend on this]
Phase 4  → AMI deregister (manual)          [depends on Phase 2]
Phase 5  → EIP release (manual)             [depends on Phase 1 + Phase 3]
Phase 6  → SG delete (manual)               [depends on Phase 3]
Phase 7  → EventBridge rule delete (manual)  [must run BEFORE Phase 8]
Phase 8  → Lambda delete (manual)           [depends on Phase 7]
Phase 9  → IAM delete (manual)              [depends on Phase 8]
Phase 10 → CloudWatch delete (manual)       [depends on Phase 8]
Phase 11 → Validation                       [depends on all above]
```

**Recommended sequential order (safest):**
```
Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5 → Phase 6 → Phase 7 → Phase 8 → Phase 9 → Phase 10 → Phase 11
```

**Why this order:**
- Phase 1 first: DNS verification before any destructive action
- Phase 2 second: Terraform removes ASGs/LTs (prerequisite for Phase 4 AMI check)
- Phase 3 third: EC2 termination unblocks Phases 5 (EIP) and 6 (SGs)
- Phase 4 after 3: AMI deregister after LTs confirmed removed
- Phases 5-6: Cleanup dependent on Phase 3
- Phase 7 before 8: EventBridge rule targets removed before Lambda deletion
- Phase 8 before 9-10: Lambda deletion before IAM/CloudWatch cleanup
- Phase 11 last: Full validation sweep

**Parallel execution possible (if comfortable):**
- After Phase 2: Phases 3, 4, 7 can run in parallel
- After Phase 3: Phases 5, 6 can run
- After Phase 7+8: Phases 9, 10 can run
- Phase 11 runs last

## Troubleshooting Reference

| Error | Cause | Solution |
|-------|-------|----------|
| `Error acquiring the state lock` | Someone else running terraform | Wait for them to finish, or use `terraform force-unlock <LOCK_ID>` with caution |
| `DisableApiTermination` on terminate | Termination protection enabled | Run `aws ec2 modify-instance-attribute $AWS --instance-id <ID> --no-disable-api-termination` |
| `DependencyViolation` on SG delete | Another SG references this one, or ENI attached | Check cross-references (Task 6.2/6.6) and revoke rules, or wait for EC2 termination |
| `must detach all policies first` on role delete | Role has extra managed or inline policies | List and detach all policies with `list-attached-role-policies` and `list-role-policies` |
| `must delete all inline policies` on role delete | Role has inline policies | Delete with `delete-role-policy` for each inline policy |
| `policy with non-default versions` on policy delete | Policy has multiple versions | Delete non-default versions with `delete-policy-version` first |
| `This rule has targets` on EventBridge rule delete | Targets not removed | Run `remove-targets` first (Task 7.3) |
| `ResourceInUseException` on Lambda delete | Lambda has active invocations | Wait and retry after a minute |
| `$AWS: command not found` | Forgot to set env variable | Run `export AWS="--profile 4shark --region us-east-1"` |
| `InvalidParameterValue` on volume snapshot | Instance is in wrong state | Stop instance before snapshotting if needed |
| `ResourceNotFoundException` on log group delete | Log group already deleted | Harmless — skip and continue |
