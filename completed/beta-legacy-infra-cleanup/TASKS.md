# TASKS — Beta Legacy Infrastructure Cleanup

**Created:** 2026-02-11
**Reference:** PLAN.md (same directory)
**AWS Profile:** `4shark`
**AWS Region:** `us-east-1`

## Execution Protocol

**Claude does NOT execute any commands.** All commands are executed by the engineer.

**Flow:**
1. Engineer says "próximo" (next)
2. Claude presents the next command (ready for copy-paste), explains what it does, and states the expected result
3. Engineer copies the command, executes in their terminal, and pastes the output back
4. Claude validates the output against expected result
5. If OK → engineer says "próximo" for the next command
6. If NOT OK → Claude analyzes and recommends action before proceeding

**Safety rules:**
- Never skip a CHECK command — always validate before destructive actions
- If any CHECK result is unexpected, STOP and analyze before proceeding
- BACKUP commands are mandatory before EC2 termination
- Each phase has a dependency order — respect the sequence

**Setup — Run once in your terminal:**
```bash
export AWS="--profile 4shark --region us-east-1"
```

All commands below use `$AWS` as shorthand for `--profile 4shark --region us-east-1`.

---

## Phase 1 — DNS Verification ✅ DONE

No tasks remaining.

---

## Phase 2 — Terraform: Remove Old Worker ASGs

> Phase 2 involves editing Terraform files (done by Claude in a separate session) and then running terraform commands (done by engineer).
> Tasks 2.1 is done by Claude. Tasks 2.2+ are executed by the engineer.

### Task 2.1 — Create branch and edit Terraform files (Claude)

This task is performed by Claude when the engineer requests it. Claude will edit:
- `terraform/main.tf` — Remove `local.beta` (lines 18-24) + 7 module blocks (lines 558-759)
- `terraform/variables.tf` — Remove `ami_beta` (lines 12-15) + 21 `beta_*` vars (lines 190-271)
- `terraform/terraform.tfvars` — Remove `ami_beta` (line 2) + 21 `beta_*` values (lines 99-132)

### Task 2.2 — Validate Terraform plan

```bash
cd ~/Projects/4Shark/terraform && AWS_PROFILE=4shark terraform plan
```

**Expected:** 14 resources to destroy (7 ASGs + 7 Launch Templates). 0 to add or change.

**Abort if:** Plan shows additions, changes, or resources outside `worker-beta-*`.

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
aws autoscaling describe-auto-scaling-groups $AWS --query 'AutoScalingGroups[?contains(AutoScalingGroupName, `worker-beta`)].AutoScalingGroupName' --output json
```

**Expected:** `[]`

---

## Phase 3 — Manual: Remove Old Internal ALB

> ALB confirmed NOT in Terraform (grep returned no matches).

### Task 3.1 — Check ALB exists

```bash
aws elbv2 describe-load-balancers $AWS --load-balancer-arns "arn:aws:elasticloadbalancing:us-east-1:405749097490:loadbalancer/app/4Shark-Beta-dev-APP-LB/736bc61b2c4ac8b9" --query 'LoadBalancers[*].{Name:LoadBalancerName,Scheme:Scheme,State:State.Code,VPC:VpcId}'
```

**Expected:** Name=4Shark-Beta-dev-APP-LB, Scheme=internal, State=active

### Task 3.2 — Check target group "beta" has no targets

```bash
aws elbv2 describe-target-health $AWS --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:405749097490:targetgroup/beta/eaa23e9aa11cde1f"
```

**Expected:** `{"TargetHealthDescriptions": []}`

### Task 3.3 — Check target group "no-other" has no targets

```bash
aws elbv2 describe-target-health $AWS --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:405749097490:targetgroup/no-other/e9ab6e73c8b92490"
```

**Expected:** `{"TargetHealthDescriptions": []}`

**Abort if:** Any target group has healthy targets.

### Task 3.4 — Delete listener

```bash
aws elbv2 delete-listener $AWS --listener-arn "arn:aws:elasticloadbalancing:us-east-1:405749097490:listener/app/4Shark-Beta-dev-APP-LB/736bc61b2c4ac8b9/fded74c5a25c99dd"
```

**Expected:** No output (success).

### Task 3.5 — Delete load balancer

```bash
aws elbv2 delete-load-balancer $AWS --load-balancer-arn "arn:aws:elasticloadbalancing:us-east-1:405749097490:loadbalancer/app/4Shark-Beta-dev-APP-LB/736bc61b2c4ac8b9"
```

**Expected:** No output (success).

### Task 3.6 — Wait for ALB deletion to complete (~1-2 min)

```bash
aws elbv2 wait load-balancers-deleted $AWS --load-balancer-arns "arn:aws:elasticloadbalancing:us-east-1:405749097490:loadbalancer/app/4Shark-Beta-dev-APP-LB/736bc61b2c4ac8b9"
```

**Expected:** No output (waiter completed).

### Task 3.7 — Delete target group "beta"

```bash
aws elbv2 delete-target-group $AWS --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:405749097490:targetgroup/beta/eaa23e9aa11cde1f"
```

**Expected:** No output (success).

### Task 3.8 — Delete target group "no-other"

```bash
aws elbv2 delete-target-group $AWS --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:405749097490:targetgroup/no-other/e9ab6e73c8b92490"
```

**Expected:** No output (success).

### Task 3.9 — Verify ALB deleted

```bash
aws elbv2 describe-load-balancers $AWS --names "4Shark-Beta-dev-APP-LB" 2>&1
```

**Expected:** Error "LoadBalancerNotFound"

### Task 3.10 — Verify target group "beta" deleted

```bash
aws elbv2 describe-target-groups $AWS --names "beta" 2>&1
```

**Expected:** Error "TargetGroupNotFound"

### Task 3.11 — Verify target group "no-other" deleted

```bash
aws elbv2 describe-target-groups $AWS --names "no-other" 2>&1
```

**Expected:** Error "TargetGroupNotFound"

---

## Phase 4 — Manual: Terminate Legacy EC2 Instances

### Task 4.1 — Check instances current state

```bash
aws ec2 describe-instances $AWS --instance-ids i-057a9e566ed594686 i-0f161420d6c52d262 i-0aa46ae5eb981de1a --query 'Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name}' --output table
```

**Expected:** beta-app001=stopped, worker-image-beta=running, beta-puma-backup=running

### Task 4.2 — Check termination protection: beta-app001

```bash
aws ec2 describe-instance-attribute $AWS --instance-id i-057a9e566ed594686 --attribute disableApiTermination --query 'DisableApiTermination.Value'
```

**Expected:** `false`

### Task 4.3 — Check termination protection: worker-image-beta

```bash
aws ec2 describe-instance-attribute $AWS --instance-id i-0f161420d6c52d262 --attribute disableApiTermination --query 'DisableApiTermination.Value'
```

**Expected:** `false`

### Task 4.4 — Check termination protection: beta-puma-backup

```bash
aws ec2 describe-instance-attribute $AWS --instance-id i-0aa46ae5eb981de1a --attribute disableApiTermination --query 'DisableApiTermination.Value'
```

**Expected:** `false`

**If any returns `true`:** Run `aws ec2 modify-instance-attribute $AWS --instance-id <ID> --no-disable-api-termination` to disable it.

### Task 4.5 — Check EBS volumes

```bash
aws ec2 describe-volumes $AWS --filters "Name=attachment.instance-id,Values=i-057a9e566ed594686,i-0f161420d6c52d262,i-0aa46ae5eb981de1a" --query 'Volumes[*].{ID:VolumeId,Size:Size,InstanceId:Attachments[0].InstanceId,DeleteOnTermination:Attachments[0].DeleteOnTermination}' --output table
```

**Expected:** 3 volumes, all DeleteOnTermination=true

**If DeleteOnTermination=false:** Volumes won't auto-delete on termination. You'll need to manually delete them after termination with `aws ec2 delete-volume $AWS --volume-id <ID>`.

### Task 4.6 — Backup: snapshot beta-app001 volume

```bash
aws ec2 create-snapshot $AWS --volume-id vol-0a7de407c0ae9699f --description "Backup before cleanup: beta-app001" --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=backup-beta-app001-cleanup},{Key=DeleteAfter,Value=2026-02-25}]'
```

**Expected:** SnapshotId returned, State=pending

### Task 4.7 — Backup: snapshot worker-image-beta volume

```bash
aws ec2 create-snapshot $AWS --volume-id vol-09773f8dc8b6ae2f2 --description "Backup before cleanup: worker-image-beta" --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=backup-worker-image-beta-cleanup},{Key=DeleteAfter,Value=2026-02-25}]'
```

**Expected:** SnapshotId returned, State=pending

### Task 4.8 — Backup: snapshot beta-puma-backup volume

```bash
aws ec2 create-snapshot $AWS --volume-id vol-00fee9001c50148e6 --description "Backup before cleanup: beta-puma-backup" --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=backup-beta-puma-backup-cleanup},{Key=DeleteAfter,Value=2026-02-25}]'
```

**Expected:** SnapshotId returned, State=pending

### Task 4.9 — Verify all 3 snapshots completed

```bash
aws ec2 describe-snapshots $AWS --filters "Name=tag:Name,Values=backup-*-cleanup" --query 'Snapshots[*].{ID:SnapshotId,Name:Tags[?Key==`Name`].Value|[0],State:State,VolumeId:VolumeId}' --output table
```

**Expected:** 3 snapshots, all State=completed. If State=pending, wait 2-3 minutes and re-run.

### Task 4.10 — Stop worker-image-beta

```bash
aws ec2 stop-instances $AWS --instance-ids i-0f161420d6c52d262
```

**Expected:** StoppingInstances with CurrentState=stopping

### Task 4.11 — Stop beta-puma-backup

```bash
aws ec2 stop-instances $AWS --instance-ids i-0aa46ae5eb981de1a
```

**Expected:** StoppingInstances with CurrentState=stopping

### Task 4.12 — Wait for both instances to stop

```bash
aws ec2 wait instance-stopped $AWS --instance-ids i-0f161420d6c52d262 i-0aa46ae5eb981de1a
```

**Expected:** No output (waiter completed). **Now wait 5-10 minutes before proceeding to health check.**

### Task 4.13 — Health check: ECS services still healthy

```bash
aws ecs describe-services $AWS --cluster beta-001 --services beta-001-web-service beta-001-worker-commission-service beta-001-worker-system-service beta-001-worker-user-service --query 'services[*].{Name:serviceName,Running:runningCount,Desired:desiredCount,Status:status}' --output table
```

**Expected:** All Status=ACTIVE, Running matches Desired.

**Abort if:** Any service shows Running < Desired or Status != ACTIVE. DO NOT TERMINATE — investigate the dependency first.

### Task 4.14 — Terminate all 3 instances

```bash
aws ec2 terminate-instances $AWS --instance-ids i-057a9e566ed594686 i-0f161420d6c52d262 i-0aa46ae5eb981de1a
```

**Expected:** TerminatingInstances with CurrentState=shutting-down

**Possible problem:** "DisableApiTermination" error → go back to Tasks 4.2-4.4 and disable termination protection.

### Task 4.15 — Wait for termination to complete

```bash
aws ec2 wait instance-terminated $AWS --instance-ids i-057a9e566ed594686 i-0f161420d6c52d262 i-0aa46ae5eb981de1a
```

**Expected:** No output (waiter completed).

### Task 4.16 — Verify instances terminated

```bash
aws ec2 describe-instances $AWS --instance-ids i-057a9e566ed594686 i-0f161420d6c52d262 i-0aa46ae5eb981de1a --query 'Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name}' --output table
```

**Expected:** All State=terminated

### Task 4.17 — Verify EBS volumes auto-deleted

```bash
aws ec2 describe-volumes $AWS --volume-ids vol-0a7de407c0ae9699f vol-09773f8dc8b6ae2f2 vol-00fee9001c50148e6 2>&1
```

**Expected:** Error "InvalidVolume.NotFound"

**If volumes still exist:** DeleteOnTermination was false. Delete manually with `aws ec2 delete-volume $AWS --volume-id <ID>` for each.

---

## Phase 5 — Manual: Deregister AMIs

### Task 5.1 — Check AMIs exist

```bash
aws ec2 describe-images $AWS --image-ids ami-0c14bfdf210f61e06 ami-0bb13eede2776c00a --query 'Images[*].{ID:ImageId,Name:Name,State:State}' --output table
```

**Expected:** 2 AMIs, both State=available

### Task 5.2 — Check no launch templates with "beta" still exist

```bash
aws ec2 describe-launch-templates $AWS --query 'LaunchTemplates[?contains(LaunchTemplateName, `beta`)].{Name:LaunchTemplateName,ID:LaunchTemplateId}' --output table
```

**Expected:** Only `beta-001-*` launch templates (new ECS). No `worker-beta-*` templates (removed by Phase 2).

**Abort if:** Any `worker-beta-*` launch template still exists — Phase 2 was incomplete.

### Task 5.3 — Check no ASGs use these AMIs via launch configs

```bash
aws autoscaling describe-launch-configurations $AWS --query 'LaunchConfigurations[?ImageId==`ami-0c14bfdf210f61e06` || ImageId==`ami-0bb13eede2776c00a`].LaunchConfigurationName' --output json
```

**Expected:** `[]`

**Abort if:** Any launch config still references these AMIs.

### Task 5.4 — Deregister AMI ami-0c14bfdf210f61e06

```bash
aws ec2 deregister-image $AWS --image-id ami-0c14bfdf210f61e06
```

**Expected:** No output (success).

### Task 5.5 — Deregister AMI ami-0bb13eede2776c00a

```bash
aws ec2 deregister-image $AWS --image-id ami-0bb13eede2776c00a
```

**Expected:** No output (success).

### Task 5.6 — Verify AMIs deregistered

```bash
aws ec2 describe-images $AWS --image-ids ami-0c14bfdf210f61e06 ami-0bb13eede2776c00a 2>&1
```

**Expected:** Error "InvalidAMIID.NotFound"

### Task 5.7 — Verify AMI snapshots still exist (safety net)

```bash
aws ec2 describe-snapshots $AWS --snapshot-ids snap-01f20812128da69ee snap-07b4ddf449348e59d --query 'Snapshots[*].{ID:SnapshotId,State:State,Description:Description}' --output table
```

**Expected:** 2 snapshots, both State=completed. Keep for 1 week as safety net.

### Task 5.8 — (After 2026-02-18) Delete snapshot snap-01f20812128da69ee

```bash
aws ec2 delete-snapshot $AWS --snapshot-id snap-01f20812128da69ee
```

**Expected:** No output (success).

### Task 5.9 — (After 2026-02-18) Delete snapshot snap-07b4ddf449348e59d

```bash
aws ec2 delete-snapshot $AWS --snapshot-id snap-07b4ddf449348e59d
```

**Expected:** No output (success).

### Task 5.10 — (After 2026-02-18) Verify snapshots deleted

```bash
aws ec2 describe-snapshots $AWS --snapshot-ids snap-01f20812128da69ee snap-07b4ddf449348e59d 2>&1
```

**Expected:** Error "InvalidSnapshot.NotFound"

---

## Phase 6 — Manual: Release Elastic IP

### Task 6.1 — Check EIP status

```bash
aws ec2 describe-addresses $AWS --allocation-ids eipalloc-03151ca7a0d965374 --query 'Addresses[*].{AllocationId:AllocationId,PublicIp:PublicIp,AssociationId:AssociationId,InstanceId:InstanceId}' --output table
```

**Expected:** EIP exists. AssociationId should be empty/null (auto-disassociated after Phase 4 termination).

**If AssociationId is NOT empty:** Run Task 6.2 first. If empty, skip Task 6.2.

### Task 6.2 — (Conditional) Disassociate EIP if still attached

```bash
aws ec2 disassociate-address $AWS --association-id eipassoc-0bd4cc4f03afc3ea3
```

**Expected:** No output (success). Only needed if Task 6.1 shows AssociationId is not empty.

### Task 6.3 — Release EIP

```bash
aws ec2 release-address $AWS --allocation-id eipalloc-03151ca7a0d965374
```

**Expected:** No output (success).

### Task 6.4 — Verify EIP released

```bash
aws ec2 describe-addresses $AWS --allocation-ids eipalloc-03151ca7a0d965374 2>&1
```

**Expected:** Error "InvalidAddressID.NotFound"

---

## Phase 7 — Manual: Delete Security Groups

### Task 7.1 — Check SG ecs-instance-beta-app001 has no ENIs

```bash
aws ec2 describe-network-interfaces $AWS --filters "Name=group-id,Values=sg-0e6d5e9b26c16d232" --query 'NetworkInterfaces[*].{ID:NetworkInterfaceId,Status:Status,InstanceId:Attachment.InstanceId}' --output json
```

**Expected:** `[]`

**Abort if:** ENIs still attached.

### Task 7.2 — Check no other SGs reference ecs-instance-beta-app001

```bash
aws ec2 describe-security-groups $AWS --filters "Name=ip-permission.group-id,Values=sg-0e6d5e9b26c16d232" --query 'SecurityGroups[*].{ID:GroupId,Name:GroupName}' --output json
```

**Expected:** `[]`

**If not empty:** Another SG has an ingress rule referencing this SG. You need to revoke that rule first with `aws ec2 revoke-security-group-ingress`.

### Task 7.3 — Delete SG ecs-instance-beta-app001

```bash
aws ec2 delete-security-group $AWS --group-id sg-0e6d5e9b26c16d232
```

**Expected:** No output (success).

**Possible problem:** "DependencyViolation" → another SG references this one (Task 7.2 should have caught it) or an ENI is still attached.

### Task 7.4 — Verify SG ecs-instance-beta-app001 deleted

```bash
aws ec2 describe-security-groups $AWS --group-ids sg-0e6d5e9b26c16d232 2>&1
```

**Expected:** Error "InvalidGroup.NotFound"

### Task 7.5 — Check SG 4Shark-Beta-Worker has no ENIs

> Must run AFTER Phase 4 (EC2 termination releases the ENI).

```bash
aws ec2 describe-network-interfaces $AWS --filters "Name=group-id,Values=sg-021c3388b2d932b8e" --query 'NetworkInterfaces[*].{ID:NetworkInterfaceId,Status:Status,InstanceId:Attachment.InstanceId}' --output json
```

**Expected:** `[]`

**Abort if:** ENIs still attached. Wait for EC2 termination to complete.

### Task 7.6 — Check no other SGs reference 4Shark-Beta-Worker

```bash
aws ec2 describe-security-groups $AWS --filters "Name=ip-permission.group-id,Values=sg-021c3388b2d932b8e" --query 'SecurityGroups[*].{ID:GroupId,Name:GroupName}' --output json
```

**Expected:** `[]`

**If not empty:** Another SG has an ingress rule referencing this SG. Revoke that rule first.

### Task 7.7 — Delete SG 4Shark-Beta-Worker

```bash
aws ec2 delete-security-group $AWS --group-id sg-021c3388b2d932b8e
```

**Expected:** No output (success).

### Task 7.8 — Verify SG 4Shark-Beta-Worker deleted

```bash
aws ec2 describe-security-groups $AWS --group-ids sg-021c3388b2d932b8e 2>&1
```

**Expected:** Error "InvalidGroup.NotFound"

### Task 7.9 — Check SG 4Shark-Beta-Web has no ENIs

```bash
aws ec2 describe-network-interfaces $AWS --filters "Name=group-id,Values=sg-065474bf0caf77666" --query 'NetworkInterfaces[*].{ID:NetworkInterfaceId,Status:Status,InstanceId:Attachment.InstanceId}' --output json
```

**Expected:** `[]`

### Task 7.10 — Delete SG 4Shark-Beta-Web

```bash
aws ec2 delete-security-group $AWS --group-id sg-065474bf0caf77666
```

**Expected:** No output (success).

### Task 7.11 — Verify SG 4Shark-Beta-Web deleted

```bash
aws ec2 describe-security-groups $AWS --group-ids sg-065474bf0caf77666 2>&1
```

**Expected:** Error "InvalidGroup.NotFound"

### Task 7.12 — Check SG 4Shark-Beta-APP has no ENIs

> Must run AFTER Phase 4 (EC2 termination releases the ENI from beta-app001).

```bash
aws ec2 describe-network-interfaces $AWS --filters "Name=group-id,Values=sg-098ca9bc747d1b2bd" --query 'NetworkInterfaces[*].{ID:NetworkInterfaceId,Status:Status,InstanceId:Attachment.InstanceId}' --output json
```

**Expected:** `[]`

**Abort if:** ENIs still attached. Wait for EC2 termination to complete.

### Task 7.13 — Revoke cross-reference from ecs-l8w0dg87 to 4Shark-Beta-APP

> SG `ecs-l8w0dg87` (sg-0feeef9d431815ddc) has an ingress rule referencing `4Shark-Beta-APP` (sg-098ca9bc747d1b2bd) on port 22 (SSH, "bastion host"). This must be revoked before deleting Beta-APP.

```bash
aws ec2 revoke-security-group-ingress $AWS --group-id sg-0feeef9d431815ddc --protocol tcp --port 22 --source-group sg-098ca9bc747d1b2bd
```

**Expected:** `{"Return": true}`

### Task 7.14 — Delete SG 4Shark-Beta-APP

```bash
aws ec2 delete-security-group $AWS --group-id sg-098ca9bc747d1b2bd
```

**Expected:** No output (success).

**Possible problem:** "DependencyViolation" → The cross-reference from `ecs-l8w0dg87` was not revoked (Task 7.13) or another reference exists. Run `aws ec2 describe-security-groups $AWS --filters "Name=ip-permission.group-id,Values=sg-098ca9bc747d1b2bd"` to find all referencing SGs.

### Task 7.15 — Verify SG 4Shark-Beta-APP deleted

```bash
aws ec2 describe-security-groups $AWS --group-ids sg-098ca9bc747d1b2bd 2>&1
```

**Expected:** Error "InvalidGroup.NotFound"

---

## Phase 8 — Manual: Delete Legacy EventBridge Rule + Lambda Functions

> The rule `Lambda-beta-worker-auto-scaling-rule` is DISABLED but still exists with 3 targets.
> Targets must be removed before deleting the rule. Rule must be deleted before deleting Lambdas.

### Task 8.1 — Check EventBridge rule exists and is DISABLED

```bash
aws events describe-rule $AWS --name "Lambda-beta-worker-auto-scaling-rule" --query '{Name:Name,State:State,Schedule:ScheduleExpression}' --output json
```

**Expected:** State=DISABLED, ScheduleExpression=rate(1 minute)

### Task 8.2 — List targets of the rule

```bash
aws events list-targets-by-rule $AWS --rule "Lambda-beta-worker-auto-scaling-rule" --query 'Targets[*].{Id:Id,Arn:Arn}' --output table
```

**Expected:** 3 targets:
- `Lambda-beta-worker-auto-scaling-user` (Id: Id43222ff1-cc38-4281-b50e-6b2e18abc20d)
- `Lambda-beta-worker-auto-scaling-system` (Id: pdno85hyohwe2ufv47mq)
- `Lambda-beta-worker-auto-scaling-minor` (Id: z0vi9riaodvza05h4mq4)

### Task 8.3 — Remove all targets from the rule

```bash
aws events remove-targets $AWS --rule "Lambda-beta-worker-auto-scaling-rule" --ids "Id43222ff1-cc38-4281-b50e-6b2e18abc20d" "pdno85hyohwe2ufv47mq" "z0vi9riaodvza05h4mq4"
```

**Expected:** `{"FailedEntryCount": 0, "FailedEntries": []}`

**If FailedEntryCount > 0:** Check the FailedEntries for error details. Fix and retry.

### Task 8.4 — Verify targets removed

```bash
aws events list-targets-by-rule $AWS --rule "Lambda-beta-worker-auto-scaling-rule" --query 'Targets' --output json
```

**Expected:** `[]`

### Task 8.5 — Delete the EventBridge rule

```bash
aws events delete-rule $AWS --name "Lambda-beta-worker-auto-scaling-rule"
```

**Expected:** No output (success).

**Possible problem:** "This rule has targets. Remove the targets before deleting the rule." → Task 8.3 did not succeed. Re-run Task 8.2 to check remaining targets.

### Task 8.6 — Verify rule deleted

```bash
aws events describe-rule $AWS --name "Lambda-beta-worker-auto-scaling-rule" 2>&1
```

**Expected:** Error "ResourceNotFoundException"

### Task 8.7 — Verify no legacy EventBridge Scheduler schedules

```bash
aws scheduler list-schedules $AWS --query 'Schedules[?contains(Name, `beta`)].{Name:Name,State:State}' --output table
```

**Expected:** Only `beta-001-*` schedules (new ECS). No legacy ones.

### Task 8.8 — Check Lambda minor has no event source mappings

```bash
aws lambda list-event-source-mappings $AWS --function-name Lambda-beta-worker-auto-scaling-minor --query 'EventSourceMappings[*].{Source:EventSourceArn,State:State}' --output json
```

**Expected:** `[]`

### Task 8.9 — Check Lambda system has no event source mappings

```bash
aws lambda list-event-source-mappings $AWS --function-name Lambda-beta-worker-auto-scaling-system --query 'EventSourceMappings[*].{Source:EventSourceArn,State:State}' --output json
```

**Expected:** `[]`

### Task 8.10 — Check Lambda user has no event source mappings

```bash
aws lambda list-event-source-mappings $AWS --function-name Lambda-beta-worker-auto-scaling-user --query 'EventSourceMappings[*].{Source:EventSourceArn,State:State}' --output json
```

**Expected:** `[]`

### Task 8.11 — Check Lambda major has no event source mappings

```bash
aws lambda list-event-source-mappings $AWS --function-name Lambda-beta-worker-auto-scaling-major --query 'EventSourceMappings[*].{Source:EventSourceArn,State:State}' --output json
```

**Expected:** `[]`

**Abort if:** Any Lambda has event source mappings. Remove triggers first.

### Task 8.12 — Delete Lambda minor

```bash
aws lambda delete-function $AWS --function-name Lambda-beta-worker-auto-scaling-minor
```

**Expected:** No output (success).

### Task 8.13 — Delete Lambda system

```bash
aws lambda delete-function $AWS --function-name Lambda-beta-worker-auto-scaling-system
```

**Expected:** No output (success).

### Task 8.14 — Delete Lambda user

```bash
aws lambda delete-function $AWS --function-name Lambda-beta-worker-auto-scaling-user
```

**Expected:** No output (success).

### Task 8.15 — Delete Lambda major

```bash
aws lambda delete-function $AWS --function-name Lambda-beta-worker-auto-scaling-major
```

**Expected:** No output (success).

### Task 8.16 — Verify no legacy Lambda functions remaining

```bash
aws lambda list-functions $AWS --query 'Functions[?contains(FunctionName, `beta`)].FunctionName' --output json
```

**Expected:** Only `beta-001-*` functions (if any). No `Lambda-beta-worker-*` functions.

---

## Phase 9 — Manual: Delete Legacy IAM Roles and Policies

### Task 9.1 — Check last used: Eventbridge-beta-invoke-minor-role

```bash
aws iam get-role $AWS --role-name Eventbridge-beta-invoke-minor-role --query 'Role.{Name:RoleName,LastUsed:RoleLastUsed.LastUsedDate,Region:RoleLastUsed.Region}' --output json
```

**Expected:** LastUsed is old (September 2025 or null). Safe to delete.

**Abort if:** LastUsed is within the last 24h.

### Task 9.2 — Check last used: Eventbridge-beta-invoke-system-role

```bash
aws iam get-role $AWS --role-name Eventbridge-beta-invoke-system-role --query 'Role.{Name:RoleName,LastUsed:RoleLastUsed.LastUsedDate,Region:RoleLastUsed.Region}' --output json
```

**Expected:** LastUsed is old or null.

### Task 9.3 — Check last used: Eventbridge-beta-invoke-user-role

```bash
aws iam get-role $AWS --role-name Eventbridge-beta-invoke-user-role --query 'Role.{Name:RoleName,LastUsed:RoleLastUsed.LastUsedDate,Region:RoleLastUsed.Region}' --output json
```

**Expected:** LastUsed is old or null.

### Task 9.4 — Check last used: Lambda-beta-worker-auto-scaling-minor-role

```bash
aws iam get-role $AWS --role-name Lambda-beta-worker-auto-scaling-minor-role --query 'Role.{Name:RoleName,LastUsed:RoleLastUsed.LastUsedDate,Region:RoleLastUsed.Region}' --output json
```

**Expected:** LastUsed is old or null.

### Task 9.5 — List all attached policies on all 4 roles

```bash
aws iam list-attached-role-policies $AWS --role-name Eventbridge-beta-invoke-minor-role --query 'AttachedPolicies[*].{Name:PolicyName,Arn:PolicyArn}' --output table
```

**Expected:** Exactly 1 policy: `Eventbridge-beta-invoke-minor-policy`

**If more than 1:** You need to detach each extra policy before deleting the role. Note the extra policy ARNs.

### Task 9.6 — Check for inline policies on all 4 roles

```bash
aws iam list-role-policies $AWS --role-name Eventbridge-beta-invoke-minor-role --query 'PolicyNames' --output json
```

**Expected:** `[]` (no inline policies)

**If not empty:** Delete each inline policy with `aws iam delete-role-policy $AWS --role-name <ROLE> --policy-name <POLICY>` before deleting the role.

> Repeat Tasks 9.5-9.6 for the other 3 roles if you want to be thorough.
> For brevity, check one — if it's clean, the others likely are too (all created the same way).

### Task 9.7 — Detach policy from Eventbridge-beta-invoke-minor-role

```bash
aws iam detach-role-policy $AWS --role-name Eventbridge-beta-invoke-minor-role --policy-arn "arn:aws:iam::405749097490:policy/Eventbridge-beta-invoke-minor-policy"
```

**Expected:** No output (success).

### Task 9.8 — Delete Eventbridge-beta-invoke-minor-role

```bash
aws iam delete-role $AWS --role-name Eventbridge-beta-invoke-minor-role
```

**Expected:** No output (success).

**Possible problem:** "Cannot delete entity, must detach all policies first" → extra policies exist. Run `aws iam list-attached-role-policies $AWS --role-name Eventbridge-beta-invoke-minor-role` and detach each one.

**Possible problem:** "Cannot delete entity, must delete all inline policies first" → Run `aws iam list-role-policies $AWS --role-name Eventbridge-beta-invoke-minor-role` and delete each.

### Task 9.9 — Delete Eventbridge-beta-invoke-minor-policy

```bash
aws iam delete-policy $AWS --policy-arn "arn:aws:iam::405749097490:policy/Eventbridge-beta-invoke-minor-policy"
```

**Expected:** No output (success).

**Possible problem:** "Cannot delete policy with non-default versions" → Run `aws iam list-policy-versions $AWS --policy-arn <ARN>` and delete non-default versions first.

### Task 9.10 — Detach policy from Eventbridge-beta-invoke-system-role

```bash
aws iam detach-role-policy $AWS --role-name Eventbridge-beta-invoke-system-role --policy-arn "arn:aws:iam::405749097490:policy/Eventbridge-beta-invoke-system-policy"
```

**Expected:** No output (success).

### Task 9.11 — Delete Eventbridge-beta-invoke-system-role

```bash
aws iam delete-role $AWS --role-name Eventbridge-beta-invoke-system-role
```

**Expected:** No output (success).

### Task 9.12 — Delete Eventbridge-beta-invoke-system-policy

```bash
aws iam delete-policy $AWS --policy-arn "arn:aws:iam::405749097490:policy/Eventbridge-beta-invoke-system-policy"
```

**Expected:** No output (success).

### Task 9.13 — Detach policy from Eventbridge-beta-invoke-user-role

```bash
aws iam detach-role-policy $AWS --role-name Eventbridge-beta-invoke-user-role --policy-arn "arn:aws:iam::405749097490:policy/Eventbridge-beta-invoke-user-policy"
```

**Expected:** No output (success).

### Task 9.14 — Delete Eventbridge-beta-invoke-user-role

```bash
aws iam delete-role $AWS --role-name Eventbridge-beta-invoke-user-role
```

**Expected:** No output (success).

### Task 9.15 — Delete Eventbridge-beta-invoke-user-policy

```bash
aws iam delete-policy $AWS --policy-arn "arn:aws:iam::405749097490:policy/Eventbridge-beta-invoke-user-policy"
```

**Expected:** No output (success).

### Task 9.16 — Detach policy from Lambda-beta-worker-auto-scaling-minor-role

```bash
aws iam detach-role-policy $AWS --role-name Lambda-beta-worker-auto-scaling-minor-role --policy-arn "arn:aws:iam::405749097490:policy/Lambda-beta-worker-auto-scaling-minor-policy"
```

**Expected:** No output (success).

### Task 9.17 — Delete Lambda-beta-worker-auto-scaling-minor-role

```bash
aws iam delete-role $AWS --role-name Lambda-beta-worker-auto-scaling-minor-role
```

**Expected:** No output (success).

### Task 9.18 — Delete Lambda-beta-worker-auto-scaling-minor-policy

```bash
aws iam delete-policy $AWS --policy-arn "arn:aws:iam::405749097490:policy/Lambda-beta-worker-auto-scaling-minor-policy"
```

**Expected:** No output (success).

### Task 9.19 — Verify no legacy beta IAM roles remaining

```bash
aws iam list-roles $AWS --query 'Roles[?contains(RoleName, `beta`)].RoleName' --output json
```

**Expected:** Only `beta-001-*` roles (if any). No `Eventbridge-beta-invoke-*` or `Lambda-beta-worker-*` roles.

### Task 9.20 — Verify no legacy beta IAM policies remaining

```bash
aws iam list-policies $AWS --scope Local --query 'Policies[?contains(PolicyName, `beta`)].PolicyName' --output json
```

**Expected:** Only `beta-001-*` policies (if any). No `Eventbridge-beta-invoke-*` or `Lambda-beta-worker-*` policies.

---

## Phase 10 — Manual: Delete Legacy CloudWatch Log Groups

### Task 10.1 — Check ALL log groups containing "beta"

```bash
aws logs describe-log-groups $AWS --query 'logGroups[?contains(logGroupName, `beta`)].{Name:logGroupName,StoredBytes:storedBytes,Retention:retentionInDays}' --output table
```

**Expected:** Shows ALL log groups containing "beta" (legacy + new). Legacy ones to delete: `/ecs/beta-app001-task`, `/ecs/beta-task`, `/ecs/beta-worker-user`, `/ecs/beta-worker_user`, `/ecs/beta.app0001`, `/ecs/betaapp001`, `/ecs/beta_001_worker_cleansing`, `/aws/lambda/codedeploy-hook-lambda-beta`, `/aws/lambda/Lambda-beta-worker-auto-scaling-major`, `/aws/lambda/Lambda-beta-worker-auto-scaling-minor`, `/aws/lambda/Lambda-beta-worker-auto-scaling-system`, `/aws/lambda/Lambda-beta-worker-auto-scaling-user`. New ones to KEEP: `/ecs/beta-001-*`, `/aws/lambda/codedeploy-hook-lambda-beta-001`.

### Task 10.2 — Delete /ecs/beta-app001-task

```bash
aws logs delete-log-group $AWS --log-group-name "/ecs/beta-app001-task"
```

**Expected:** No output (success).

### Task 10.3 — Delete /ecs/beta-task

```bash
aws logs delete-log-group $AWS --log-group-name "/ecs/beta-task"
```

**Expected:** No output (success).

### Task 10.4 — Delete /ecs/beta-worker-user

```bash
aws logs delete-log-group $AWS --log-group-name "/ecs/beta-worker-user"
```

**Expected:** No output (success).

### Task 10.5 — Delete /ecs/beta-worker_user

```bash
aws logs delete-log-group $AWS --log-group-name "/ecs/beta-worker_user"
```

**Expected:** No output (success).

### Task 10.6 — Delete /ecs/beta.app0001

```bash
aws logs delete-log-group $AWS --log-group-name "/ecs/beta.app0001"
```

**Expected:** No output (success).

### Task 10.7 — Delete /ecs/betaapp001

```bash
aws logs delete-log-group $AWS --log-group-name "/ecs/betaapp001"
```

**Expected:** No output (success).

### Task 10.8 — Delete /ecs/beta_001_worker_cleansing

```bash
aws logs delete-log-group $AWS --log-group-name "/ecs/beta_001_worker_cleansing"
```

**Expected:** No output (success).

### Task 10.9 — Delete /aws/lambda/codedeploy-hook-lambda-beta (orphaned)

```bash
aws logs delete-log-group $AWS --log-group-name "/aws/lambda/codedeploy-hook-lambda-beta"
```

**Expected:** No output (success). This is an orphaned log group — the Lambda function `codedeploy-hook-lambda-beta` no longer exists. The active function is `codedeploy-hook-lambda-beta-001`.

### Task 10.10 — Check legacy /aws/lambda/ log groups

```bash
aws logs describe-log-groups $AWS --log-group-name-prefix "/aws/lambda/Lambda-beta-worker" --query 'logGroups[*].{Name:logGroupName,StoredBytes:storedBytes}' --output table
```

**Expected:** 4 log groups (minor, system, user, major).

### Task 10.11 — Delete /aws/lambda/Lambda-beta-worker-auto-scaling-major

```bash
aws logs delete-log-group $AWS --log-group-name "/aws/lambda/Lambda-beta-worker-auto-scaling-major"
```

**Expected:** No output (success).

### Task 10.12 — Delete /aws/lambda/Lambda-beta-worker-auto-scaling-minor

```bash
aws logs delete-log-group $AWS --log-group-name "/aws/lambda/Lambda-beta-worker-auto-scaling-minor"
```

**Expected:** No output (success).

### Task 10.13 — Delete /aws/lambda/Lambda-beta-worker-auto-scaling-system

```bash
aws logs delete-log-group $AWS --log-group-name "/aws/lambda/Lambda-beta-worker-auto-scaling-system"
```

**Expected:** No output (success).

### Task 10.14 — Delete /aws/lambda/Lambda-beta-worker-auto-scaling-user

```bash
aws logs delete-log-group $AWS --log-group-name "/aws/lambda/Lambda-beta-worker-auto-scaling-user"
```

**Expected:** No output (success).

### Task 10.15 — Verify /ecs/ legacy log groups deleted

```bash
aws logs describe-log-groups $AWS --query 'logGroups[?contains(logGroupName, `beta`)].logGroupName' --output json
```

**Expected:** Only `/ecs/beta-001-*` and `/aws/lambda/codedeploy-hook-lambda-beta-001` log groups (new ECS). No legacy groups like `/ecs/beta-app001-task`, `/ecs/beta-task`, `/aws/lambda/Lambda-beta-worker-*`, or `/aws/lambda/codedeploy-hook-lambda-beta` (without -001).

### Task 10.16 — Verify /aws/lambda/ legacy log groups deleted

```bash
aws logs describe-log-groups $AWS --log-group-name-prefix "/aws/lambda/Lambda-beta-worker" --query 'logGroups[*].logGroupName' --output json
```

**Expected:** `[]`

---

## Phase 11 — Validation

### Task 11.1 — Terraform state validation

```bash
cd ~/Projects/4Shark/terraform && AWS_PROFILE=4shark terraform plan
```

**Expected:** "No changes. Your infrastructure matches the configuration."

### Task 11.2 — ECS services health check

```bash
aws ecs describe-services $AWS --cluster beta-001 --services beta-001-web-service beta-001-worker-commission-service beta-001-worker-system-service beta-001-worker-user-service --query 'services[*].{Name:serviceName,Status:status,Running:runningCount,Desired:desiredCount}' --output table
```

**Expected:** All Status=ACTIVE, Running matches Desired.

### Task 11.3 — Public ALB target group health check

```bash
aws elbv2 describe-target-health $AWS --target-group-arn "$(aws elbv2 describe-target-groups $AWS --names beta-001-pub-tg --query 'TargetGroups[0].TargetGroupArn' --output text)" --query 'TargetHealthDescriptions[*].{Target:Target.Id,Health:TargetHealth.State}' --output table
```

**Expected:** All targets healthy.

### Task 11.4 — PGBouncer NLB target group health check

```bash
aws elbv2 describe-target-health $AWS --target-group-arn "$(aws elbv2 describe-target-groups $AWS --names nlbatg1-beta --query 'TargetGroups[0].TargetGroupArn' --output text)" --query 'TargetHealthDescriptions[*].{Target:Target.Id,Health:TargetHealth.State}' --output table
```

**Expected:** All targets healthy.

### Task 11.5 — Scan for orphaned legacy SGs in VPC

```bash
aws ec2 describe-security-groups $AWS --filters "Name=vpc-id,Values=vpc-0968cc73edd5596b0" --query 'SecurityGroups[*].{ID:GroupId,Name:GroupName}' --output table
```

**Expected:** No SGs with names containing "beta" or "worker" (except beta-001-* and pgbouncer-*).

### Task 11.6 — Scan for orphaned legacy EC2 instances in VPC

```bash
aws ec2 describe-instances $AWS --filters "Name=vpc-id,Values=vpc-0968cc73edd5596b0" "Name=instance-state-name,Values=running,stopped" --query 'Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name}' --output table
```

**Expected:** Only beta-001-web, pgbouncer-beta-*, pritunl-beta-* instances.

### Task 11.7 — Scan for orphaned legacy Lambda functions

```bash
aws lambda list-functions $AWS --query 'Functions[?contains(FunctionName, `beta`)].FunctionName' --output json
```

**Expected:** Only `beta-001-*` functions (if any). No `Lambda-beta-worker-*`.

### Task 11.8 — Scan for orphaned legacy EventBridge rules

```bash
aws events list-rules $AWS --query 'Rules[?contains(Name, `beta`)].{Name:Name,State:State}' --output table
```

**Expected:** No `Lambda-beta-*` rules. Only `beta-001-*` rules (if any).

### Task 11.9 — Scan for orphaned legacy IAM roles

```bash
aws iam list-roles $AWS --query 'Roles[?contains(RoleName, `beta`)].RoleName' --output json
```

**Expected:** Only `beta-001-*` roles (if any). No `Eventbridge-beta-*` or `Lambda-beta-*` roles.

### Task 11.10 — (After 24-48h) Cost validation

```bash
aws ce get-cost-and-usage $AWS --time-period Start=2026-02-11,End=2026-02-12 --granularity DAILY --metrics "UnblendedCost" --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute","Elastic Load Balancing"]}}' --query 'ResultsByTime[*].Total.UnblendedCost'
```

**Expected:** Reduced EC2 and ELB costs compared to previous days.

---

## Cleanup Backups (run after 2026-02-25)

### Task B.1 — List EBS backup snapshots

```bash
aws ec2 describe-snapshots $AWS --filters "Name=tag:DeleteAfter,Values=2026-02-25" --query 'Snapshots[*].{ID:SnapshotId,Name:Tags[?Key==`Name`].Value|[0]}' --output table
```

**Expected:** 3 backup snapshots (beta-app001, worker-image-beta, beta-puma-backup).

> Note the SnapshotIds from the output — use them in Tasks B.2-B.4 below.

### Task B.2 — Delete backup snapshot 1 (beta-app001)

```bash
aws ec2 delete-snapshot $AWS --snapshot-id <SNAPSHOT-ID-FROM-B.1>
```

**Expected:** No output (success). Replace `<SNAPSHOT-ID-FROM-B.1>` with the actual ID.

### Task B.3 — Delete backup snapshot 2 (worker-image-beta)

```bash
aws ec2 delete-snapshot $AWS --snapshot-id <SNAPSHOT-ID-FROM-B.1>
```

**Expected:** No output (success). Replace `<SNAPSHOT-ID-FROM-B.1>` with the actual ID.

### Task B.4 — Delete backup snapshot 3 (beta-puma-backup)

```bash
aws ec2 delete-snapshot $AWS --snapshot-id <SNAPSHOT-ID-FROM-B.1>
```

**Expected:** No output (success). Replace `<SNAPSHOT-ID-FROM-B.1>` with the actual ID.

### Task B.5 — Verify all backup snapshots deleted

```bash
aws ec2 describe-snapshots $AWS --filters "Name=tag:DeleteAfter,Values=2026-02-25" --query 'Snapshots[*].SnapshotId' --output json
```

**Expected:** `[]`

---

## Execution Order Summary

```
Phase 2  → Terraform PR (ASGs)           [blocking: must go first]
Phase 3  → ALB delete (manual)           [independent after Phase 2]
Phase 4  → EC2 terminate (manual)        [blocking: Phase 6, 7 depend on this]
Phase 5  → AMI deregister (manual)       [depends on Phase 2]
Phase 6  → EIP release (manual)          [depends on Phase 4 for auto-disassociate]
Phase 7  → SG delete (manual)            [7.1-7.4: independent, 7.5-7.8+7.12-7.15: depend on Phase 4, 7.9-7.11: independent]
Phase 8  → EventBridge + Lambda delete    [EventBridge first, then Lambdas]
Phase 9  → IAM delete (manual)           [depends on Phase 8]
Phase 10 → CloudWatch delete (manual)    [depends on Phase 8 for Lambda log groups]
Phase 11 → Validation                    [depends on all above]
```

**Recommended sequential order (safest):**
```
Phase 2 → Phase 4 → Phase 3 → Phase 5 → Phase 6 → Phase 7 → Phase 8 → Phase 9 → Phase 10 → Phase 11
```

**Why this order:**
- Phase 2 first: Terraform removes ASGs/LTs (prerequisite for Phase 5 AMI check)
- Phase 4 second: EC2 termination unblocks Phases 6 (EIP) and 7 (SGs)
- Phase 3 after 4: ALB is independent but grouped after EC2 for clarity
- Phases 5-7: Cleanup dependent on Phases 2+4
- Phase 8: EventBridge rule cleanup first (remove targets, delete rule), then Lambda deletion before IAM/CloudWatch cleanup
- Phase 11 last: Full validation sweep

**Parallel execution possible (if comfortable):**
- After Phase 2: Phases 3, 4, 5, 8 can run in parallel
- After Phase 4: Phases 6, 7 can run
- After Phase 8: Phases 9, 10 can run
- Phase 11 runs last

## Troubleshooting Reference

| Error | Cause | Solution |
|-------|-------|----------|
| `Error acquiring the state lock` | Someone else running terraform | Wait for them to finish, or use `terraform force-unlock <LOCK_ID>` with caution |
| `DisableApiTermination` on terminate | Termination protection enabled | Run `aws ec2 modify-instance-attribute $AWS --instance-id <ID> --no-disable-api-termination` |
| `DependencyViolation` on SG delete | Another SG references this one, or ENI attached | Check cross-references (Task 7.2/7.6) and revoke rules, or wait for EC2 termination |
| `must detach all policies first` on role delete | Role has extra managed or inline policies | List and detach all policies with `list-attached-role-policies` and `list-role-policies` |
| `must delete all inline policies` on role delete | Role has inline policies | Delete with `delete-role-policy` for each inline policy |
| `policy with non-default versions` on policy delete | Policy has multiple versions | Delete non-default versions with `delete-policy-version` first |
| `This rule has targets` on EventBridge rule delete | Rule still has targets attached | Run `list-targets-by-rule` and `remove-targets` first (Tasks 8.2-8.4) |
| `ResourceInUseException` on Lambda delete | Lambda has active invocations | Wait and retry after a minute |
| `TargetGroupAssociationLimit` on TG delete | Listener still referencing TG | Delete the listener first (Task 3.4) |
| `$AWS: command not found` | Forgot to set env variable | Run `export AWS="--profile 4shark --region us-east-1"` |
| `InvalidParameterValue` on volume snapshot | Instance is in wrong state | Stop instance before snapshotting if needed |
| `ResourceNotFoundException` on log group delete | Log group already deleted | Harmless — skip and continue |
