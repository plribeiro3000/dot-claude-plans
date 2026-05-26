# TASKS — Atento Legacy Infrastructure Cleanup

**Created:** 2026-02-13
**Reference:** PLAN.md (same directory)
**AWS Profile:** `4shark`
**AWS Region:** `us-east-1`
**Last Updated:** 2026-02-13

## Progress Summary

| Phase | Description | Status |
|-------|-------------|--------|
| 1 — ALB Traffic Verification | CloudWatch metrics check | DONE |
| 2 — ASGs + Launch Templates | Delete 7 ASGs + 7 LTs (manual) | DONE |
| 3A — EC2 Terminate (4 of 5) | Terminate app002/003/004 + worker-image | DONE |
| 3B — EC2 Terminate app001 | Terminate when cron jobs migrated | PENDING |
| 4 — ALB + Target Group | Delete legacy ALB | DONE |
| 5 — AMIs | Deregister 3 AMIs + delete 3 snapshots | DONE |
| 6 — Security Groups | Delete unused SGs | DONE (3 of 4) — APP SG kept with app001 |
| 7 — EventBridge Rule | Delete rule + 3 targets | DONE |
| 8 — Lambda Functions | Delete 4 legacy functions | DONE |
| 9 — IAM Roles + Policies | Delete 4 roles + 4 policies | DONE |
| 10 — CloudWatch Log Groups | Delete 4 legacy log groups | DONE |
| 11 — Validation | Final health check | PENDING |

**Remaining:**
- `atento-app001` (i-01fe7b0f0dc0cd5e2) — cron jobs still running, terminate after migration
- SG `4Shark-Atento-prd-APP` (sg-028ac379bbf238e21) — kept until app001 is terminated
- Extra SG `atento-prd-elasticsearch` (sg-0b022486f83571ab7) — discovered and deleted 2026-02-13 (orphaned, not used by OpenSearch domain)
- Final validation sweep

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
- **NEVER touch PGBouncer instances** (i-0cf3bfce8a0724fe4 puma, i-0f1b80edb0ea79746 sidekiq)
- **NEVER touch Integrator resources** (EC2-start-integrator-atento-br role + associated policies)
- **NEVER delete shared cross-env IAM roles** (Lambda-worker-auto-scaling-standard-role, Lambda-worker-auto-scaling-major-role)

**Setup — Run once in your terminal:**
```bash
export AWS="--profile 4shark --region us-east-1"
```

All commands below use `$AWS` as shorthand for `--profile 4shark --region us-east-1`.

---

## Phase 1 — ALB Traffic Verification DONE (2026-02-13)

> The legacy ALB `4Shark-Atento-prd-APP-LB` is still active with 4 healthy targets.
> DNS was switched to `atento-001-pub-lb` via CloudFlare. MUST verify zero traffic before deletion.

### Task 1.1 — Verify DNS resolves to new ALB

```bash
dig atento.app4shark.com +short
```

**Expected:** Should resolve to the new `atento-001-pub-lb` ALB (CNAME), NOT to the legacy ALB.

### Task 1.2 — Check CloudWatch RequestCount on legacy ALB (last 24h)

```bash
aws cloudwatch get-metric-statistics $AWS --namespace AWS/ApplicationELB --metric-name RequestCount --dimensions Name=LoadBalancer,Value=app/4Shark-Atento-prd-APP-LB/07ad022dfd0bb760 --start-time $(date -u -v-24H +%Y-%m-%dT%H:%M:%S) --end-time $(date -u +%Y-%m-%dT%H:%M:%S) --period 3600 --statistics Sum --query 'Datapoints[*].{Time:Timestamp,Count:Sum}' --output table
```

**Expected:** All datapoints should show Count=0 (or very close to zero). If significant traffic exists, DNS has not fully propagated — DO NOT proceed with ALB deletion until traffic is zero.

---

## Phase 2 — Manual: Delete Old Worker ASGs + Launch Templates DONE (2026-02-13)

> All 7 ASGs are at desired=0 with no running instances. Safe to delete manually.
> Old Terraform folders will be dropped entirely — no PR needed.

### Task 2.1 — Check all legacy ASGs exist and are at desired=0

```bash
aws autoscaling describe-auto-scaling-groups $AWS --auto-scaling-group-names worker-atento-cleansing-asg worker-atento-commission-asg worker-atento-commission_tiger_shark-asg worker-atento-commission_white_shark-asg worker-atento-migration-asg worker-atento-system-asg worker-atento-user-asg --query 'AutoScalingGroups[*].{Name:AutoScalingGroupName,Desired:DesiredCapacity,Min:MinSize,Max:MaxSize,Instances:Instances|length(@)}' --output table
```

**Expected:** 7 ASGs, all Desired=0, Min=0, Instances=0.

**Abort if:** Any ASG has Desired > 0 or running instances.

### Task 2.2 — Delete worker-atento-cleansing-asg

```bash
aws autoscaling delete-auto-scaling-group $AWS --auto-scaling-group-name worker-atento-cleansing-asg --force-delete
```

**Expected:** No output (success).

### Task 2.3 — Delete worker-atento-commission-asg

```bash
aws autoscaling delete-auto-scaling-group $AWS --auto-scaling-group-name worker-atento-commission-asg --force-delete
```

**Expected:** No output (success).

### Task 2.4 — Delete worker-atento-commission_tiger_shark-asg

```bash
aws autoscaling delete-auto-scaling-group $AWS --auto-scaling-group-name worker-atento-commission_tiger_shark-asg --force-delete
```

**Expected:** No output (success).

### Task 2.5 — Delete worker-atento-commission_white_shark-asg

```bash
aws autoscaling delete-auto-scaling-group $AWS --auto-scaling-group-name worker-atento-commission_white_shark-asg --force-delete
```

**Expected:** No output (success).

### Task 2.6 — Delete worker-atento-migration-asg

```bash
aws autoscaling delete-auto-scaling-group $AWS --auto-scaling-group-name worker-atento-migration-asg --force-delete
```

**Expected:** No output (success).

### Task 2.7 — Delete worker-atento-system-asg

```bash
aws autoscaling delete-auto-scaling-group $AWS --auto-scaling-group-name worker-atento-system-asg --force-delete
```

**Expected:** No output (success).

### Task 2.8 — Delete worker-atento-user-asg

```bash
aws autoscaling delete-auto-scaling-group $AWS --auto-scaling-group-name worker-atento-user-asg --force-delete
```

**Expected:** No output (success).

### Task 2.9 — Verify all legacy ASGs deleted

```bash
aws autoscaling describe-auto-scaling-groups $AWS --query 'AutoScalingGroups[?contains(AutoScalingGroupName, `worker-atento`)].AutoScalingGroupName' --output json
```

**Expected:** `[]`

### Task 2.10 — Delete Launch Template lt-0537348ebf6da0a5c (cleansing)

```bash
aws ec2 delete-launch-template $AWS --launch-template-id lt-0537348ebf6da0a5c
```

**Expected:** LaunchTemplate deletion confirmed.

### Task 2.11 — Delete Launch Template lt-0e7667f78bb17f02c (commission)

```bash
aws ec2 delete-launch-template $AWS --launch-template-id lt-0e7667f78bb17f02c
```

**Expected:** LaunchTemplate deletion confirmed.

### Task 2.12 — Delete Launch Template lt-0ed6f684d295dfaac (commission_tiger_shark)

```bash
aws ec2 delete-launch-template $AWS --launch-template-id lt-0ed6f684d295dfaac
```

**Expected:** LaunchTemplate deletion confirmed.

### Task 2.13 — Delete Launch Template lt-0521ad31c16342651 (commission_white_shark)

```bash
aws ec2 delete-launch-template $AWS --launch-template-id lt-0521ad31c16342651
```

**Expected:** LaunchTemplate deletion confirmed.

### Task 2.14 — Delete Launch Template lt-006c9241f392a6103 (migration)

```bash
aws ec2 delete-launch-template $AWS --launch-template-id lt-006c9241f392a6103
```

**Expected:** LaunchTemplate deletion confirmed.

### Task 2.15 — Delete Launch Template lt-0758a22033e6522d2 (system)

```bash
aws ec2 delete-launch-template $AWS --launch-template-id lt-0758a22033e6522d2
```

**Expected:** LaunchTemplate deletion confirmed.

### Task 2.16 — Delete Launch Template lt-02090ca3900afebe1 (user)

```bash
aws ec2 delete-launch-template $AWS --launch-template-id lt-02090ca3900afebe1
```

**Expected:** LaunchTemplate deletion confirmed.

### Task 2.17 — Verify all legacy Launch Templates deleted

```bash
aws ec2 describe-launch-templates $AWS --query 'LaunchTemplates[?contains(LaunchTemplateName, `worker-atento`)].{Name:LaunchTemplateName,ID:LaunchTemplateId}' --output json
```

**Expected:** `[]`

---

## Phase 3 — Manual: Terminate Legacy EC2 Instances — PARTIAL (3A DONE, 3B PENDING)

>> 5 legacy instances. `atento-app001` has cron jobs running — terminate LAST (Phase 3B).
> Phase 3A terminates worker-image + app002/003/004. Phase 3B terminates app001 when cron is migrated.

### Task 3.1 — Check all instances current state

```bash
aws ec2 describe-instances $AWS --instance-ids i-01fe7b0f0dc0cd5e2 i-0bfd054b31f4a8a11 i-0d8a1ba8c4c2ca0a3 i-00fd0644f9591b7c4 i-0ea8a28a4f735d5f6 --query 'Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name,Type:InstanceType}' --output table
```

**Expected:** All 5 instances running: atento-app001 through atento-app004 (t2.medium), worker-image-atento (t3a.small).

### Task 3.2 — Check termination protection: atento-app001

```bash
aws ec2 describe-instance-attribute $AWS --instance-id i-01fe7b0f0dc0cd5e2 --attribute disableApiTermination --query 'DisableApiTermination.Value'
```

**Expected:** `false`

### Task 3.3 — Check termination protection: atento-app002

```bash
aws ec2 describe-instance-attribute $AWS --instance-id i-0bfd054b31f4a8a11 --attribute disableApiTermination --query 'DisableApiTermination.Value'
```

**Expected:** `false`

### Task 3.4 — Check termination protection: atento-app003

```bash
aws ec2 describe-instance-attribute $AWS --instance-id i-0d8a1ba8c4c2ca0a3 --attribute disableApiTermination --query 'DisableApiTermination.Value'
```

**Expected:** `false`

### Task 3.5 — Check termination protection: atento-app004

```bash
aws ec2 describe-instance-attribute $AWS --instance-id i-00fd0644f9591b7c4 --attribute disableApiTermination --query 'DisableApiTermination.Value'
```

**Expected:** `false`

### Task 3.6 — Check termination protection: worker-image-atento

```bash
aws ec2 describe-instance-attribute $AWS --instance-id i-0ea8a28a4f735d5f6 --attribute disableApiTermination --query 'DisableApiTermination.Value'
```

**Expected:** `false`

**If any returns `true`:** Run `aws ec2 modify-instance-attribute $AWS --instance-id <ID> --no-disable-api-termination` to disable it.

### Task 3.7 — Check EBS volumes (DeleteOnTermination)

```bash
aws ec2 describe-volumes $AWS --filters "Name=attachment.instance-id,Values=i-01fe7b0f0dc0cd5e2,i-0bfd054b31f4a8a11,i-0d8a1ba8c4c2ca0a3,i-00fd0644f9591b7c4,i-0ea8a28a4f735d5f6" --query 'Volumes[*].{ID:VolumeId,Size:Size,InstanceId:Attachments[0].InstanceId,DeleteOnTermination:Attachments[0].DeleteOnTermination}' --output table
```

**Expected:** 5 volumes, all DeleteOnTermination=true.

**If DeleteOnTermination=false:** Volumes won't auto-delete on termination. You'll need to manually delete them after termination with `aws ec2 delete-volume $AWS --volume-id <ID>`.

### Task 3.8 — Backup: snapshot atento-app001 volume

```bash
aws ec2 create-snapshot $AWS --volume-id vol-03968ef618fa256ff --description "Backup before cleanup: atento-app001" --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=backup-atento-app001-cleanup},{Key=DeleteAfter,Value=2026-02-27}]'
```

**Expected:** SnapshotId returned, State=pending

### Task 3.9 — Backup: snapshot atento-app002 volume

```bash
aws ec2 create-snapshot $AWS --volume-id vol-0b887935c13c3aed3 --description "Backup before cleanup: atento-app002" --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=backup-atento-app002-cleanup},{Key=DeleteAfter,Value=2026-02-27}]'
```

**Expected:** SnapshotId returned, State=pending

### Task 3.10 — Backup: snapshot atento-app003 volume

```bash
aws ec2 create-snapshot $AWS --volume-id vol-0fd67bd9a15b90572 --description "Backup before cleanup: atento-app003" --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=backup-atento-app003-cleanup},{Key=DeleteAfter,Value=2026-02-27}]'
```

**Expected:** SnapshotId returned, State=pending

### Task 3.11 — Backup: snapshot atento-app004 volume

```bash
aws ec2 create-snapshot $AWS --volume-id vol-0b08cb14589149a63 --description "Backup before cleanup: atento-app004" --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=backup-atento-app004-cleanup},{Key=DeleteAfter,Value=2026-02-27}]'
```

**Expected:** SnapshotId returned, State=pending

### Task 3.12 — Backup: snapshot worker-image-atento volume

```bash
aws ec2 create-snapshot $AWS --volume-id vol-05f4fbdb59cda5d9a --description "Backup before cleanup: worker-image-atento" --tag-specifications 'ResourceType=snapshot,Tags=[{Key=Name,Value=backup-worker-image-atento-cleanup},{Key=DeleteAfter,Value=2026-02-27}]'
```

**Expected:** SnapshotId returned, State=pending

### Task 3.13 — Verify all 5 snapshots completed

```bash
aws ec2 describe-snapshots $AWS --filters "Name=tag:Name,Values=backup-atento-*-cleanup,backup-worker-image-atento-cleanup" --query 'Snapshots[*].{ID:SnapshotId,Name:Tags[?Key==`Name`].Value|[0],State:State,VolumeId:VolumeId}' --output table
```

**Expected:** 5 snapshots, all State=completed. If State=pending, wait 2-3 minutes and re-run.

### Phase 3A — Terminate worker-image + app002/003/004

### Task 3.14 — Stop worker-image-atento

```bash
aws ec2 stop-instances $AWS --instance-ids i-0ea8a28a4f735d5f6
```

**Expected:** StoppingInstances with CurrentState=stopping

### Task 3.15 — Stop atento-app002, atento-app003, atento-app004

```bash
aws ec2 stop-instances $AWS --instance-ids i-0bfd054b31f4a8a11 i-0d8a1ba8c4c2ca0a3 i-00fd0644f9591b7c4
```

**Expected:** StoppingInstances with CurrentState=stopping for all 3.

### Task 3.16 — Wait for 4 instances to stop

```bash
aws ec2 wait instance-stopped $AWS --instance-ids i-0ea8a28a4f735d5f6 i-0bfd054b31f4a8a11 i-0d8a1ba8c4c2ca0a3 i-00fd0644f9591b7c4
```

**Expected:** No output (waiter completed). **Now wait 5-10 minutes before proceeding to health check.**

### Task 3.17 — Health check: ECS services still healthy

```bash
aws ecs describe-services $AWS --cluster atento-001-cluster --services atento-001-web-service atento-001-worker-commission-service atento-001-worker-system-service atento-001-worker-user-service --query 'services[*].{Name:serviceName,Running:runningCount,Desired:desiredCount,Status:status}' --output table
```

**Expected:** All Status=ACTIVE, Running matches Desired.

**Abort if:** Any service shows Running < Desired or Status != ACTIVE. DO NOT TERMINATE — investigate the dependency first.

### Task 3.18 — Health check: PGBouncer instances still running

```bash
aws ec2 describe-instances $AWS --instance-ids i-0cf3bfce8a0724fe4 i-0f1b80edb0ea79746 --query 'Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name}' --output table
```

**Expected:** pgbouncer-atento-puma=running, pgbouncer-atento-sidekiq=running

**Abort if:** Either PGBouncer instance is not running. DO NOT PROCEED — PGBouncers are critical.

### Task 3.19 — Terminate 4 instances (not app001)

```bash
aws ec2 terminate-instances $AWS --instance-ids i-0ea8a28a4f735d5f6 i-0bfd054b31f4a8a11 i-0d8a1ba8c4c2ca0a3 i-00fd0644f9591b7c4
```

**Expected:** TerminatingInstances with CurrentState=shutting-down

**Possible problem:** "DisableApiTermination" error → go back to Tasks 3.3-3.6 and disable termination protection.

### Task 3.20 — Wait for termination to complete

```bash
aws ec2 wait instance-terminated $AWS --instance-ids i-0ea8a28a4f735d5f6 i-0bfd054b31f4a8a11 i-0d8a1ba8c4c2ca0a3 i-00fd0644f9591b7c4
```

**Expected:** No output (waiter completed).

### Task 3.21 — Verify 4 instances terminated

```bash
aws ec2 describe-instances $AWS --instance-ids i-0ea8a28a4f735d5f6 i-0bfd054b31f4a8a11 i-0d8a1ba8c4c2ca0a3 i-00fd0644f9591b7c4 --query 'Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name}' --output table
```

**Expected:** All State=terminated

### Task 3.22 — Verify EBS volumes auto-deleted (4 volumes)

```bash
aws ec2 describe-volumes $AWS --volume-ids vol-0b887935c13c3aed3 vol-0fd67bd9a15b90572 vol-0b08cb14589149a63 vol-05f4fbdb59cda5d9a 2>&1
```

**Expected:** Error "InvalidVolume.NotFound"

**If volumes still exist:** DeleteOnTermination was false. Delete manually with `aws ec2 delete-volume $AWS --volume-id <ID>` for each.

### Phase 3B — Terminate atento-app001 (when Chrome is no longer needed)

> **SKIP this sub-phase until cron jobs are migrated off app001.**
> Engineer must explicitly confirm before proceeding.

### Task 3.23 — Confirm cron jobs are migrated off atento-app001

> This is a manual confirmation step. The engineer must verify that all cron jobs running on atento-app001 have been migrated to the new infrastructure or are no longer necessary.

### Task 3.24 — Stop atento-app001

```bash
aws ec2 stop-instances $AWS --instance-ids i-01fe7b0f0dc0cd5e2
```

**Expected:** StoppingInstances with CurrentState=stopping

### Task 3.25 — Wait for app001 to stop

```bash
aws ec2 wait instance-stopped $AWS --instance-ids i-01fe7b0f0dc0cd5e2
```

**Expected:** No output (waiter completed). **Wait 5 minutes, then re-run Task 3.17 and 3.18 health checks.**

### Task 3.26 — Terminate atento-app001

```bash
aws ec2 terminate-instances $AWS --instance-ids i-01fe7b0f0dc0cd5e2
```

**Expected:** TerminatingInstances with CurrentState=shutting-down

### Task 3.27 — Wait for app001 termination

```bash
aws ec2 wait instance-terminated $AWS --instance-ids i-01fe7b0f0dc0cd5e2
```

**Expected:** No output (waiter completed).

### Task 3.28 — Verify app001 terminated

```bash
aws ec2 describe-instances $AWS --instance-ids i-01fe7b0f0dc0cd5e2 --query 'Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name}' --output table
```

**Expected:** State=terminated

### Task 3.29 — Verify app001 EBS volume auto-deleted

```bash
aws ec2 describe-volumes $AWS --volume-ids vol-03968ef618fa256ff 2>&1
```

**Expected:** Error "InvalidVolume.NotFound"

---

## Phase 4 — Manual: Delete Legacy ALB + Target Group DONE (2026-02-13)

> Must run AFTER Phase 1 confirms zero traffic on legacy ALB.

### Task 4.1 — Check ALB exists

```bash
aws elbv2 describe-load-balancers $AWS --load-balancer-arns "arn:aws:elasticloadbalancing:us-east-1:405749097490:loadbalancer/app/4Shark-Atento-prd-APP-LB/07ad022dfd0bb760" --query 'LoadBalancers[*].{Name:LoadBalancerName,Scheme:Scheme,State:State.Code,VPC:VpcId}' --output table
```

**Expected:** Name=4Shark-Atento-prd-APP-LB, Scheme=internet-facing, State=active

### Task 4.2 — List listeners on legacy ALB

```bash
aws elbv2 describe-listeners $AWS --load-balancer-arn "arn:aws:elasticloadbalancing:us-east-1:405749097490:loadbalancer/app/4Shark-Atento-prd-APP-LB/07ad022dfd0bb760" --query 'Listeners[*].{ARN:ListenerArn,Port:Port,Protocol:Protocol}' --output table
```

**Expected:** 1 or 2 listeners (likely :80 redirect + :443 with forwarding rule). Note the ListenerArns for deletion.

### Task 4.3 — Delete all listeners (use ARNs from Task 4.2)

> Run one delete command per listener ARN returned by Task 4.2.

```bash
aws elbv2 delete-listener $AWS --listener-arn "<LISTENER-ARN-FROM-4.2>"
```

**Expected:** No output (success). Repeat for each listener.

### Task 4.4 — Delete the load balancer

```bash
aws elbv2 delete-load-balancer $AWS --load-balancer-arn "arn:aws:elasticloadbalancing:us-east-1:405749097490:loadbalancer/app/4Shark-Atento-prd-APP-LB/07ad022dfd0bb760"
```

**Expected:** No output (success).

### Task 4.5 — Wait for ALB deletion to complete (~1-2 min)

```bash
aws elbv2 wait load-balancers-deleted $AWS --load-balancer-arns "arn:aws:elasticloadbalancing:us-east-1:405749097490:loadbalancer/app/4Shark-Atento-prd-APP-LB/07ad022dfd0bb760"
```

**Expected:** No output (waiter completed).

### Task 4.6 — Delete target group

```bash
aws elbv2 delete-target-group $AWS --target-group-arn "arn:aws:elasticloadbalancing:us-east-1:405749097490:targetgroup/4Shark-Atento-prd-APP-TG-ssl/6d457f715a3b3dc0"
```

**Expected:** No output (success).

### Task 4.7 — Verify ALB deleted

```bash
aws elbv2 describe-load-balancers $AWS --names "4Shark-Atento-prd-APP-LB" 2>&1
```

**Expected:** Error "LoadBalancerNotFound"

### Task 4.8 — Verify target group deleted

```bash
aws elbv2 describe-target-groups $AWS --target-group-arns "arn:aws:elasticloadbalancing:us-east-1:405749097490:targetgroup/4Shark-Atento-prd-APP-TG-ssl/6d457f715a3b3dc0" 2>&1
```

**Expected:** Error "TargetGroupNotFound"

---

## Phase 5 — Manual: Deregister AMIs DONE (2026-02-13)

> 3 AMIs: 2 worker images + 1 app snapshot (atento-app002).

### Task 5.1 — Check AMIs exist

```bash
aws ec2 describe-images $AWS --image-ids ami-0a6c783ead9d0a096 ami-04df9ddd81789caf9 ami-039789a85d5826a42 --query 'Images[*].{ID:ImageId,Name:Name,State:State}' --output table
```

**Expected:** 3 AMIs, all State=available:
- `worker-image-atento-v3.8.0` (ami-0a6c783ead9d0a096)
- `worker-image-atento-v3.7.0` (ami-04df9ddd81789caf9)
- `atento-app002` (ami-039789a85d5826a42 — app snapshot)

### Task 5.2 — Check no launch templates reference these AMIs

```bash
aws ec2 describe-launch-templates $AWS --query 'LaunchTemplates[?contains(LaunchTemplateName, `atento`)].{Name:LaunchTemplateName,ID:LaunchTemplateId}' --output json
```

**Expected:** Only `atento-001-*` launch templates (new ECS). No `worker-atento-*` templates (removed by Phase 2).

**Abort if:** Any `worker-atento-*` launch template still exists — Phase 2 was incomplete.

### Task 5.3 — Deregister AMI ami-0a6c783ead9d0a096 (worker v3.8.0)

```bash
aws ec2 deregister-image $AWS --image-id ami-0a6c783ead9d0a096
```

**Expected:** No output (success).

### Task 5.4 — Deregister AMI ami-04df9ddd81789caf9 (worker v3.7.0)

```bash
aws ec2 deregister-image $AWS --image-id ami-04df9ddd81789caf9
```

**Expected:** No output (success).

### Task 5.5 — Deregister AMI ami-039789a85d5826a42 (atento-app002 snapshot)

> This is an app instance snapshot, not a worker image. Verify it's not needed before deregistering.

```bash
aws ec2 deregister-image $AWS --image-id ami-039789a85d5826a42
```

**Expected:** No output (success).

### Task 5.6 — Verify AMIs deregistered

```bash
aws ec2 describe-images $AWS --image-ids ami-0a6c783ead9d0a096 ami-04df9ddd81789caf9 ami-039789a85d5826a42 2>&1
```

**Expected:** Error "InvalidAMIID.NotFound"

### Task 5.7 — Verify AMI snapshots still exist (safety net)

```bash
aws ec2 describe-snapshots $AWS --snapshot-ids snap-0737287c1c0458737 snap-049c163974e95ec94 snap-06ffc7764a7ce581a --query 'Snapshots[*].{ID:SnapshotId,State:State,Description:Description}' --output table
```

**Expected:** 3 snapshots, all State=completed. Keep for 1 week as safety net.

### Task 5.8 — (After 2026-02-20) Delete snapshot snap-0737287c1c0458737 (worker v3.8.0)

```bash
aws ec2 delete-snapshot $AWS --snapshot-id snap-0737287c1c0458737
```

**Expected:** No output (success).

### Task 5.9 — (After 2026-02-20) Delete snapshot snap-049c163974e95ec94 (worker v3.7.0)

```bash
aws ec2 delete-snapshot $AWS --snapshot-id snap-049c163974e95ec94
```

**Expected:** No output (success).

### Task 5.10 — (After 2026-02-20) Delete snapshot snap-06ffc7764a7ce581a (atento-app002)

```bash
aws ec2 delete-snapshot $AWS --snapshot-id snap-06ffc7764a7ce581a
```

**Expected:** No output (success).

### Task 5.11 — (After 2026-02-20) Verify snapshots deleted

```bash
aws ec2 describe-snapshots $AWS --snapshot-ids snap-0737287c1c0458737 snap-049c163974e95ec94 snap-06ffc7764a7ce581a 2>&1
```

**Expected:** Error "InvalidSnapshot.NotFound"

---

## Phase 6 — Manual: Delete Security Groups — PARTIAL 3 of 4 DONE (2026-02-13)

> Must run AFTER Phase 3 (EC2 termination releases ENIs) and Phase 4 (ALB deletion releases ENIs).
> Note: SG 4Shark-Atento-prd-APP (sg-028ac379bbf238e21) depends on app001 termination (Phase 3B).

### Task 6.1 — Check SG 4Shark-Atento-prd-APP-LB has no ENIs

> Must run AFTER Phase 4 (ALB deletion releases the ENIs).

```bash
aws ec2 describe-network-interfaces $AWS --filters "Name=group-id,Values=sg-0c3c89b3855f2c011" --query 'NetworkInterfaces[*].{ID:NetworkInterfaceId,Status:Status,InstanceId:Attachment.InstanceId}' --output json
```

**Expected:** `[]`

**Abort if:** ENIs still attached. Wait for ALB deletion to complete.

### Task 6.2 — Check no other SGs reference 4Shark-Atento-prd-APP-LB

```bash
aws ec2 describe-security-groups $AWS --filters "Name=ip-permission.group-id,Values=sg-0c3c89b3855f2c011" --query 'SecurityGroups[*].{ID:GroupId,Name:GroupName}' --output json
```

**Expected:** `[]`

**If not empty:** Another SG has an ingress rule referencing this SG. You need to revoke that rule first with `aws ec2 revoke-security-group-ingress`.

### Task 6.3 — Delete SG 4Shark-Atento-prd-APP-LB

```bash
aws ec2 delete-security-group $AWS --group-id sg-0c3c89b3855f2c011
```

**Expected:** No output (success).

**Possible problem:** "DependencyViolation" → another SG references this one (Task 6.2 should have caught it) or an ENI is still attached.

### Task 6.4 — Verify SG 4Shark-Atento-prd-APP-LB deleted

```bash
aws ec2 describe-security-groups $AWS --group-ids sg-0c3c89b3855f2c011 2>&1
```

**Expected:** Error "InvalidGroup.NotFound"

### Task 6.5 — Check SG 4Shark-Atento-Worker has no ENIs

> Must run AFTER Phase 3A (worker-image-atento termination releases the ENI).

```bash
aws ec2 describe-network-interfaces $AWS --filters "Name=group-id,Values=sg-017f04587a743355e" --query 'NetworkInterfaces[*].{ID:NetworkInterfaceId,Status:Status,InstanceId:Attachment.InstanceId}' --output json
```

**Expected:** `[]`

**Abort if:** ENIs still attached. Wait for EC2 termination to complete.

### Task 6.6 — Check no other SGs reference 4Shark-Atento-Worker

```bash
aws ec2 describe-security-groups $AWS --filters "Name=ip-permission.group-id,Values=sg-017f04587a743355e" --query 'SecurityGroups[*].{ID:GroupId,Name:GroupName}' --output json
```

**Expected:** `[]`

**If not empty:** Another SG has an ingress rule referencing this SG. Revoke that rule first.

### Task 6.7 — Delete SG 4Shark-Atento-Worker

```bash
aws ec2 delete-security-group $AWS --group-id sg-017f04587a743355e
```

**Expected:** No output (success).

### Task 6.8 — Verify SG 4Shark-Atento-Worker deleted

```bash
aws ec2 describe-security-groups $AWS --group-ids sg-017f04587a743355e 2>&1
```

**Expected:** Error "InvalidGroup.NotFound"

### Task 6.9 — Check SG 4Shark-Atento-prd-APP has no ENIs

> Must run AFTER Phase 3B (atento-app001 termination). If app001 is still running, SKIP Tasks 6.9-6.12 and come back later.

```bash
aws ec2 describe-network-interfaces $AWS --filters "Name=group-id,Values=sg-028ac379bbf238e21" --query 'NetworkInterfaces[*].{ID:NetworkInterfaceId,Status:Status,InstanceId:Attachment.InstanceId}' --output json
```

**Expected:** `[]`

**Abort if:** ENIs still attached. app001 must be terminated first (Phase 3B).

### Task 6.10 — Check no other SGs reference 4Shark-Atento-prd-APP

```bash
aws ec2 describe-security-groups $AWS --filters "Name=ip-permission.group-id,Values=sg-028ac379bbf238e21" --query 'SecurityGroups[*].{ID:GroupId,Name:GroupName}' --output json
```

**Expected:** `[]`

**If not empty:** Another SG has an ingress rule referencing this SG. Revoke that rule first with `aws ec2 revoke-security-group-ingress`.

### Task 6.11 — Delete SG 4Shark-Atento-prd-APP

```bash
aws ec2 delete-security-group $AWS --group-id sg-028ac379bbf238e21
```

**Expected:** No output (success).

### Task 6.12 — Verify SG 4Shark-Atento-prd-APP deleted

```bash
aws ec2 describe-security-groups $AWS --group-ids sg-028ac379bbf238e21 2>&1
```

**Expected:** Error "InvalidGroup.NotFound"

---

## Phase 7 — Manual: Delete Legacy EventBridge Rule DONE (2026-02-13)

> The rule `Lambda-atento-worker-auto-scaling-rule` is DISABLED but still exists with 3 targets.
> Targets must be removed before deleting the rule. Rule must be deleted before deleting Lambdas.

### Task 7.1 — Check EventBridge rule exists and is DISABLED

```bash
aws events describe-rule $AWS --name "Lambda-atento-worker-auto-scaling-rule" --query '{Name:Name,State:State,Schedule:ScheduleExpression}' --output json
```

**Expected:** State=DISABLED, ScheduleExpression=rate(1 minute)

### Task 7.2 — List targets of the rule

```bash
aws events list-targets-by-rule $AWS --rule "Lambda-atento-worker-auto-scaling-rule" --query 'Targets[*].{Id:Id,Arn:Arn}' --output table
```

**Expected:** 3 targets:
- `Lambda-atento-worker-auto-scaling-system` (Id: Id9f1cbf64-a25e-43df-8982-174ff7759514)
- `Lambda-atento-worker-auto-scaling-user` (Id: Idcbadd28a-799f-467e-964a-a82a6df0d33e)
- `Lambda-atento-worker-auto-scaling-minor` (Id: Idf57dc9db-2de4-421d-b618-482aa1ecb9bd)

### Task 7.3 — Remove all targets from the rule

```bash
aws events remove-targets $AWS --rule "Lambda-atento-worker-auto-scaling-rule" --ids "Id9f1cbf64-a25e-43df-8982-174ff7759514" "Idcbadd28a-799f-467e-964a-a82a6df0d33e" "Idf57dc9db-2de4-421d-b618-482aa1ecb9bd"
```

**Expected:** `{"FailedEntryCount": 0, "FailedEntries": []}`

**If FailedEntryCount > 0:** Check the FailedEntries for error details. Fix and retry.

### Task 7.4 — Verify targets removed

```bash
aws events list-targets-by-rule $AWS --rule "Lambda-atento-worker-auto-scaling-rule" --query 'Targets' --output json
```

**Expected:** `[]`

### Task 7.5 — Delete the EventBridge rule

```bash
aws events delete-rule $AWS --name "Lambda-atento-worker-auto-scaling-rule"
```

**Expected:** No output (success).

**Possible problem:** "This rule has targets. Remove the targets before deleting the rule." → Task 7.3 did not succeed. Re-run Task 7.2 to check remaining targets.

### Task 7.6 — Verify rule deleted

```bash
aws events describe-rule $AWS --name "Lambda-atento-worker-auto-scaling-rule" 2>&1
```

**Expected:** Error "ResourceNotFoundException"

### Task 7.7 — Verify no legacy EventBridge Scheduler schedules

```bash
aws scheduler list-schedules $AWS --query 'Schedules[?contains(Name, `atento`)].{Name:Name,State:State}' --output table
```

**Expected:** Only `Lambda-atento-001-*` schedules (new ECS). No legacy ones.

---

## Phase 8 — Manual: Delete Legacy Lambda Functions DONE (2026-02-13)

### Task 8.1 — Check Lambda minor has no event source mappings

```bash
aws lambda list-event-source-mappings $AWS --function-name Lambda-atento-worker-auto-scaling-minor --query 'EventSourceMappings[*].{Source:EventSourceArn,State:State}' --output json
```

**Expected:** `[]`

### Task 8.2 — Check Lambda system has no event source mappings

```bash
aws lambda list-event-source-mappings $AWS --function-name Lambda-atento-worker-auto-scaling-system --query 'EventSourceMappings[*].{Source:EventSourceArn,State:State}' --output json
```

**Expected:** `[]`

### Task 8.3 — Check Lambda user has no event source mappings

```bash
aws lambda list-event-source-mappings $AWS --function-name Lambda-atento-worker-auto-scaling-user --query 'EventSourceMappings[*].{Source:EventSourceArn,State:State}' --output json
```

**Expected:** `[]`

### Task 8.4 — Check Lambda major has no event source mappings

```bash
aws lambda list-event-source-mappings $AWS --function-name Lambda-atento-worker-auto-scaling-major --query 'EventSourceMappings[*].{Source:EventSourceArn,State:State}' --output json
```

**Expected:** `[]`

**Abort if:** Any Lambda has event source mappings. Remove triggers first.

### Task 8.5 — Delete Lambda minor

```bash
aws lambda delete-function $AWS --function-name Lambda-atento-worker-auto-scaling-minor
```

**Expected:** No output (success).

### Task 8.6 — Delete Lambda system

```bash
aws lambda delete-function $AWS --function-name Lambda-atento-worker-auto-scaling-system
```

**Expected:** No output (success).

### Task 8.7 — Delete Lambda user

```bash
aws lambda delete-function $AWS --function-name Lambda-atento-worker-auto-scaling-user
```

**Expected:** No output (success).

### Task 8.8 — Delete Lambda major

```bash
aws lambda delete-function $AWS --function-name Lambda-atento-worker-auto-scaling-major
```

**Expected:** No output (success).

### Task 8.9 — Verify no legacy Lambda functions remaining

```bash
aws lambda list-functions $AWS --query 'Functions[?contains(FunctionName, `atento`)].FunctionName' --output json
```

**Expected:** Only `Lambda-atento-001-*` and `codedeploy-hook-lambda-atento-001` functions. No `Lambda-atento-worker-*` functions.

---

## Phase 9 — Manual: Delete Legacy IAM Roles and Policies DONE (2026-02-13)

> **CRITICAL:** EventBridge invoke policies for atento are in the `service-role/` path.
> Use full ARN with `service-role/` prefix when detaching.
> **DO NOT delete** shared cross-env roles: `Lambda-worker-auto-scaling-standard-role`, `Lambda-worker-auto-scaling-major-role`.

### Task 9.1 — Check last used: Eventbridge-atento-invoke-minor-role

```bash
aws iam get-role $AWS --role-name Eventbridge-atento-invoke-minor-role --query 'Role.{Name:RoleName,Path:Path,LastUsed:RoleLastUsed.LastUsedDate,Region:RoleLastUsed.Region}' --output json
```

**Expected:** LastUsed is old (September 2025 or null). Note the Path value — if it contains `/service-role/`, the associated policy is also under that path. Safe to delete.

**Abort if:** LastUsed is within the last 24h.

### Task 9.2 — Check last used: Eventbridge-atento-invoke-system-role

```bash
aws iam get-role $AWS --role-name Eventbridge-atento-invoke-system-role --query 'Role.{Name:RoleName,Path:Path,LastUsed:RoleLastUsed.LastUsedDate,Region:RoleLastUsed.Region}' --output json
```

**Expected:** LastUsed is old or null.

### Task 9.3 — Check last used: Eventbridge-atento-invoke-user-role

```bash
aws iam get-role $AWS --role-name Eventbridge-atento-invoke-user-role --query 'Role.{Name:RoleName,Path:Path,LastUsed:RoleLastUsed.LastUsedDate,Region:RoleLastUsed.Region}' --output json
```

**Expected:** LastUsed is old or null.

### Task 9.4 — Check last used: Lambda-atento-worker-auto-scaling-minor-role

```bash
aws iam get-role $AWS --role-name Lambda-atento-worker-auto-scaling-minor-role --query 'Role.{Name:RoleName,Path:Path,LastUsed:RoleLastUsed.LastUsedDate,Region:RoleLastUsed.Region}' --output json
```

**Expected:** LastUsed is old or null.

### Task 9.5 — List attached policies on Eventbridge-atento-invoke-minor-role

```bash
aws iam list-attached-role-policies $AWS --role-name Eventbridge-atento-invoke-minor-role --query 'AttachedPolicies[*].{Name:PolicyName,Arn:PolicyArn}' --output table
```

**Expected:** Exactly 1 policy: `Eventbridge-atento-invoke-minor-policy`. **Note the full ARN** — it may contain `/service-role/` in the path. Use this exact ARN in Task 9.7.

**If more than 1:** You need to detach each extra policy before deleting the role. Note the extra policy ARNs.

### Task 9.6 — Check for inline policies on Eventbridge-atento-invoke-minor-role

```bash
aws iam list-role-policies $AWS --role-name Eventbridge-atento-invoke-minor-role --query 'PolicyNames' --output json
```

**Expected:** `[]` (no inline policies)

**If not empty:** Delete each inline policy with `aws iam delete-role-policy $AWS --role-name <ROLE> --policy-name <POLICY>` before deleting the role.

> Repeat Tasks 9.5-9.6 for the other 3 roles if you want to be thorough.
> For brevity, check one — if it's clean, the others likely are too (all created the same way).

### Task 9.7 — Detach policy from Eventbridge-atento-invoke-minor-role

> **Use the exact ARN from Task 9.5.** If the path is `/service-role/`, the ARN will be:
> `arn:aws:iam::405749097490:policy/service-role/Eventbridge-atento-invoke-minor-policy`
> If NOT in service-role, use: `arn:aws:iam::405749097490:policy/Eventbridge-atento-invoke-minor-policy`

```bash
aws iam detach-role-policy $AWS --role-name Eventbridge-atento-invoke-minor-role --policy-arn "<ARN-FROM-TASK-9.5>"
```

**Expected:** No output (success).

### Task 9.8 — Delete Eventbridge-atento-invoke-minor-role

```bash
aws iam delete-role $AWS --role-name Eventbridge-atento-invoke-minor-role
```

**Expected:** No output (success).

**Possible problem:** "Cannot delete entity, must detach all policies first" → extra policies exist. Run `aws iam list-attached-role-policies $AWS --role-name Eventbridge-atento-invoke-minor-role` and detach each one.

**Possible problem:** "Cannot delete entity, must delete all inline policies first" → Run `aws iam list-role-policies $AWS --role-name Eventbridge-atento-invoke-minor-role` and delete each.

### Task 9.9 — Delete Eventbridge-atento-invoke-minor-policy

> Use the same ARN from Task 9.5.

```bash
aws iam delete-policy $AWS --policy-arn "<ARN-FROM-TASK-9.5>"
```

**Expected:** No output (success).

**Possible problem:** "Cannot delete policy with non-default versions" → Run `aws iam list-policy-versions $AWS --policy-arn <ARN>` and delete non-default versions first.

### Task 9.10 — Detach policy from Eventbridge-atento-invoke-system-role

> Discover the full ARN first:

```bash
aws iam list-attached-role-policies $AWS --role-name Eventbridge-atento-invoke-system-role --query 'AttachedPolicies[*].{Name:PolicyName,Arn:PolicyArn}' --output table
```

Then detach using the discovered ARN:

```bash
aws iam detach-role-policy $AWS --role-name Eventbridge-atento-invoke-system-role --policy-arn "<ARN-FROM-ABOVE>"
```

**Expected:** No output (success).

### Task 9.11 — Delete Eventbridge-atento-invoke-system-role

```bash
aws iam delete-role $AWS --role-name Eventbridge-atento-invoke-system-role
```

**Expected:** No output (success).

### Task 9.12 — Delete Eventbridge-atento-invoke-system-policy

> Use the ARN discovered in Task 9.10.

```bash
aws iam delete-policy $AWS --policy-arn "<ARN-FROM-TASK-9.10>"
```

**Expected:** No output (success).

### Task 9.13 — Detach policy from Eventbridge-atento-invoke-user-role

> Discover the full ARN first:

```bash
aws iam list-attached-role-policies $AWS --role-name Eventbridge-atento-invoke-user-role --query 'AttachedPolicies[*].{Name:PolicyName,Arn:PolicyArn}' --output table
```

Then detach using the discovered ARN:

```bash
aws iam detach-role-policy $AWS --role-name Eventbridge-atento-invoke-user-role --policy-arn "<ARN-FROM-ABOVE>"
```

**Expected:** No output (success).

### Task 9.14 — Delete Eventbridge-atento-invoke-user-role

```bash
aws iam delete-role $AWS --role-name Eventbridge-atento-invoke-user-role
```

**Expected:** No output (success).

### Task 9.15 — Delete Eventbridge-atento-invoke-user-policy

> Use the ARN discovered in Task 9.13.

```bash
aws iam delete-policy $AWS --policy-arn "<ARN-FROM-TASK-9.13>"
```

**Expected:** No output (success).

### Task 9.16 — Detach policy from Lambda-atento-worker-auto-scaling-minor-role

```bash
aws iam list-attached-role-policies $AWS --role-name Lambda-atento-worker-auto-scaling-minor-role --query 'AttachedPolicies[*].{Name:PolicyName,Arn:PolicyArn}' --output table
```

Then detach:

```bash
aws iam detach-role-policy $AWS --role-name Lambda-atento-worker-auto-scaling-minor-role --policy-arn "<ARN-FROM-ABOVE>"
```

**Expected:** No output (success).

### Task 9.17 — Delete Lambda-atento-worker-auto-scaling-minor-role

```bash
aws iam delete-role $AWS --role-name Lambda-atento-worker-auto-scaling-minor-role
```

**Expected:** No output (success).

### Task 9.18 — Delete Lambda-atento-worker-auto-scaling-minor-policy

> Use the ARN discovered in Task 9.16.

```bash
aws iam delete-policy $AWS --policy-arn "<ARN-FROM-TASK-9.16>"
```

**Expected:** No output (success).

### Task 9.19 — Verify no legacy atento IAM roles remaining

```bash
aws iam list-roles $AWS --query 'Roles[?contains(RoleName, `atento`)].RoleName' --output json
```

**Expected:** Only `atento-001-*`, `codedeploy-hook-lambda-role-atento-001`, `EventBridge-atento-001-*`, `Lambda-atento-001-*`, and `EC2-start-integrator-atento-br` roles. No `Eventbridge-atento-invoke-*` or `Lambda-atento-worker-*` roles.

### Task 9.20 — Verify no legacy atento IAM policies remaining

```bash
aws iam list-policies $AWS --scope Local --query 'Policies[?contains(PolicyName, `atento`)].PolicyName' --output json
```

**Expected:** Only `atento-001-*`, `codedeploy-hook-lambda-policy-atento-001`, `EventBridge-atento-001-*`, `Lambda-atento-001-*`, `ECS-atento-001-*`, `CloudWatch-atento-001-*`, `AutoScaling-atento-001-*`, `app-poc-deploy-atento-001`, and Integrator policies (`EC2-machine-atento-br`, `Lambda-start-integrator-atento-br`, `CloudWatch-Lambda-EC2-start-integrator-atento-br`, `S3-bucket-4shark-integrator-atento-br`). No `Eventbridge-atento-invoke-*` or `Lambda-atento-worker-*` policies.

---

## Phase 10 — Manual: Delete Legacy CloudWatch Log Groups DONE (2026-02-13)

### Task 10.1 — Check all legacy log groups

```bash
aws logs describe-log-groups $AWS --log-group-name-prefix "/aws/lambda/Lambda-atento-worker" --query 'logGroups[*].{Name:logGroupName,StoredBytes:storedBytes,Retention:retentionInDays}' --output table
```

**Expected:** 4 legacy log groups:
- `/aws/lambda/Lambda-atento-worker-auto-scaling-major` (0 bytes)
- `/aws/lambda/Lambda-atento-worker-auto-scaling-minor` (8.2 MB)
- `/aws/lambda/Lambda-atento-worker-auto-scaling-system` (5.8 MB)
- `/aws/lambda/Lambda-atento-worker-auto-scaling-user` (5.8 MB)

### Task 10.2 — Delete /aws/lambda/Lambda-atento-worker-auto-scaling-major

```bash
aws logs delete-log-group $AWS --log-group-name "/aws/lambda/Lambda-atento-worker-auto-scaling-major"
```

**Expected:** No output (success).

### Task 10.3 — Delete /aws/lambda/Lambda-atento-worker-auto-scaling-minor

```bash
aws logs delete-log-group $AWS --log-group-name "/aws/lambda/Lambda-atento-worker-auto-scaling-minor"
```

**Expected:** No output (success).

### Task 10.4 — Delete /aws/lambda/Lambda-atento-worker-auto-scaling-system

```bash
aws logs delete-log-group $AWS --log-group-name "/aws/lambda/Lambda-atento-worker-auto-scaling-system"
```

**Expected:** No output (success).

### Task 10.5 — Delete /aws/lambda/Lambda-atento-worker-auto-scaling-user

```bash
aws logs delete-log-group $AWS --log-group-name "/aws/lambda/Lambda-atento-worker-auto-scaling-user"
```

**Expected:** No output (success).

### Task 10.6 — Verify all legacy log groups deleted

```bash
aws logs describe-log-groups $AWS --query 'logGroups[?contains(logGroupName, `atento`)].logGroupName' --output json
```

**Expected:** Only new groups: `/ecs/atento-001-*`, `/aws/lambda/Lambda-atento-001-*`, `/aws/lambda/codedeploy-hook-lambda-atento-001`. No `Lambda-atento-worker-*` groups.

---

## Phase 11 — Validation

### Task 11.1 — ECS services health check

```bash
aws ecs describe-services $AWS --cluster atento-001-cluster --services atento-001-web-service atento-001-worker-commission-service atento-001-worker-system-service atento-001-worker-user-service atento-001-worker-cleansing-service atento-001-worker-migration-service atento-001-worker-commission-tiger-shark-service atento-001-worker-commission-white-shark-service --query 'services[*].{Name:serviceName,Status:status,Running:runningCount,Desired:desiredCount}' --output table
```

**Expected:** All Status=ACTIVE, Running matches Desired.

### Task 11.2 — Public ALB target group health check

```bash
aws elbv2 describe-target-health $AWS --target-group-arn "$(aws elbv2 describe-target-groups $AWS --names atento-001-pub-tg --query 'TargetGroups[0].TargetGroupArn' --output text)" --query 'TargetHealthDescriptions[*].{Target:Target.Id,Health:TargetHealth.State}' --output table
```

**Expected:** All targets healthy.

### Task 11.3 — PGBouncer instances health check

```bash
aws ec2 describe-instances $AWS --instance-ids i-0cf3bfce8a0724fe4 i-0f1b80edb0ea79746 --query 'Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name}' --output table
```

**Expected:** pgbouncer-atento-puma=running, pgbouncer-atento-sidekiq=running

### Task 11.4 — Scan for orphaned legacy SGs in VPC

```bash
aws ec2 describe-security-groups $AWS --filters "Name=vpc-id,Values=vpc-0204a1f8b5de51941" --query 'SecurityGroups[*].{ID:GroupId,Name:GroupName}' --output table
```

**Expected:** No SGs with names containing "Atento-prd-APP" or "Atento-Worker". PGBouncer, terraform-*, atento-001-*, and other environment SGs should remain.

### Task 11.5 — Scan for orphaned legacy EC2 instances in VPC

```bash
aws ec2 describe-instances $AWS --filters "Name=vpc-id,Values=vpc-0204a1f8b5de51941" "Name=instance-state-name,Values=running,stopped" --query 'Reservations[*].Instances[*].{ID:InstanceId,Name:Tags[?Key==`Name`].Value|[0],State:State.Name}' --output table
```

**Expected:** Only atento-001-* (ECS), pgbouncer-atento-puma, pgbouncer-atento-sidekiq, and instances from other environments (shared, demo). No atento-app* or worker-image-atento.

### Task 11.6 — Scan for orphaned legacy Lambda functions

```bash
aws lambda list-functions $AWS --query 'Functions[?contains(FunctionName, `atento`)].FunctionName' --output json
```

**Expected:** Only `Lambda-atento-001-*` and `codedeploy-hook-lambda-atento-001`. No `Lambda-atento-worker-*`.

### Task 11.7 — Scan for orphaned legacy EventBridge rules

```bash
aws events list-rules $AWS --query 'Rules[?contains(Name, `atento`)].{Name:Name,State:State}' --output json
```

**Expected:** `[]`. No legacy rules remaining.

### Task 11.8 — Scan for orphaned legacy IAM roles

```bash
aws iam list-roles $AWS --query 'Roles[?contains(RoleName, `atento`)].RoleName' --output json
```

**Expected:** Only `atento-001-*`, `codedeploy-hook-lambda-role-atento-001`, `EventBridge-atento-001-*`, `Lambda-atento-001-*`, and `EC2-start-integrator-atento-br` roles. No `Eventbridge-atento-invoke-*` or `Lambda-atento-worker-*` roles.

### Task 11.9 — Verify Integrator resources untouched

```bash
aws iam get-role $AWS --role-name EC2-start-integrator-atento-br --query 'Role.{Name:RoleName,CreateDate:CreateDate}' --output json
```

**Expected:** Role exists and is intact.

### Task 11.10 — (After 24-48h) Cost validation

```bash
aws ce get-cost-and-usage $AWS --time-period Start=2026-02-13,End=2026-02-14 --granularity DAILY --metrics "UnblendedCost" --filter '{"Dimensions":{"Key":"SERVICE","Values":["Amazon Elastic Compute Cloud - Compute","Elastic Load Balancing"]}}' --query 'ResultsByTime[*].Total.UnblendedCost'
```

**Expected:** Reduced EC2 and ELB costs compared to previous days.

---

## Cleanup Backups (run after 2026-02-27)

### Task B.1 — List EBS backup snapshots

```bash
aws ec2 describe-snapshots $AWS --filters "Name=tag:Name,Values=backup-atento-*-cleanup,backup-worker-image-atento-cleanup" --query 'Snapshots[*].{ID:SnapshotId,Name:Tags[?Key==`Name`].Value|[0]}' --output table
```

**Expected:** 5 backup snapshots (atento-app001 through app004, worker-image-atento).

> Note the SnapshotIds from the output — use them in Tasks B.2-B.6 below.

### Task B.2 — Delete backup snapshot 1 (atento-app001)

```bash
aws ec2 delete-snapshot $AWS --snapshot-id <SNAPSHOT-ID-FROM-B.1>
```

**Expected:** No output (success). Replace `<SNAPSHOT-ID-FROM-B.1>` with the actual ID.

### Task B.3 — Delete backup snapshot 2 (atento-app002)

```bash
aws ec2 delete-snapshot $AWS --snapshot-id <SNAPSHOT-ID-FROM-B.1>
```

**Expected:** No output (success).

### Task B.4 — Delete backup snapshot 3 (atento-app003)

```bash
aws ec2 delete-snapshot $AWS --snapshot-id <SNAPSHOT-ID-FROM-B.1>
```

**Expected:** No output (success).

### Task B.5 — Delete backup snapshot 4 (atento-app004)

```bash
aws ec2 delete-snapshot $AWS --snapshot-id <SNAPSHOT-ID-FROM-B.1>
```

**Expected:** No output (success).

### Task B.6 — Delete backup snapshot 5 (worker-image-atento)

```bash
aws ec2 delete-snapshot $AWS --snapshot-id <SNAPSHOT-ID-FROM-B.1>
```

**Expected:** No output (success).

### Task B.7 — Verify all backup snapshots deleted

```bash
aws ec2 describe-snapshots $AWS --filters "Name=tag:DeleteAfter,Values=2026-02-27" --query 'Snapshots[*].SnapshotId' --output json
```

**Expected:** `[]`

---

## Execution Order Summary

```
Phase 1  → ALB Traffic Verification         [blocking: must go first for Phase 4]
Phase 2  → ASGs + Launch Templates (manual)  [independent]
Phase 3A → EC2 terminate (4 of 5)            [blocking: Phase 4, 6 depend on this]
Phase 3B → EC2 terminate app001              [deferred: when cron jobs are migrated]
Phase 4  → ALB + TG delete                   [depends on Phase 1 + Phase 3A]
Phase 5  → AMI deregister                    [depends on Phase 2]
Phase 6  → SG delete (6.1-6.8)              [depends on Phase 3A + Phase 4]
Phase 6  → SG delete (6.9-6.12)             [depends on Phase 3B]
Phase 7  → EventBridge rule delete           [must run BEFORE Phase 8]
Phase 8  → Lambda delete                     [depends on Phase 7]
Phase 9  → IAM delete                        [depends on Phase 8]
Phase 10 → CloudWatch delete                 [depends on Phase 8]
Phase 11 → Validation                        [depends on all above]
```

**Recommended sequential order (safest):**
```
Phase 1 → Phase 2 → Phase 3A → Phase 4 → Phase 5 → Phase 6 (partial) → Phase 7 → Phase 8 → Phase 9 → Phase 10 → Phase 3B → Phase 6 (6.9-6.12) → Phase 11
```

**Why this order:**
- Phase 1 first: ALB traffic verification before any ALB-related destructive action
- Phase 2 second: ASGs/LTs are independent, safe (all desired=0)
- Phase 3A third: EC2 termination (4 of 5) unblocks Phases 4 (ALB) and 6 (SGs)
- Phase 4 after 3A: ALB deletion after traffic verified and EC2 terminated
- Phase 5 after 2: AMI deregister after LTs confirmed removed
- Phase 6 partial: Delete APP-LB and Worker SGs (after ALB + EC2)
- Phases 7-10: Supporting resources cleanup (EventBridge → Lambda → IAM → CloudWatch)
- Phase 3B: Deferred until cron jobs are migrated off app001
- Phase 6 completion: Delete APP SG after app001 terminated
- Phase 11 last: Full validation sweep

**Parallel execution possible (if comfortable):**
- After Phase 1: Phases 2, 7 can start immediately
- After Phase 2: Phase 5 can run
- After Phase 3A: Phases 4, 6 (partial) can run
- After Phase 7: Phases 8 can run, then 9+10 after 8
- Phase 11 runs last (after 3B + 6 completion)

## Troubleshooting Reference

| Error | Cause | Solution |
|-------|-------|----------|
| `DisableApiTermination` on terminate | Termination protection enabled | Run `aws ec2 modify-instance-attribute $AWS --instance-id <ID> --no-disable-api-termination` |
| `DependencyViolation` on SG delete | Another SG references this one, or ENI attached | Check cross-references and revoke rules, or wait for EC2/ALB termination |
| `must detach all policies first` on role delete | Role has extra managed or inline policies | List and detach all policies with `list-attached-role-policies` and `list-role-policies` |
| `must delete all inline policies` on role delete | Role has inline policies | Delete with `delete-role-policy` for each inline policy |
| `policy with non-default versions` on policy delete | Policy has multiple versions | Delete non-default versions with `delete-policy-version` first |
| `This rule has targets` on EventBridge rule delete | Targets not removed | Run `remove-targets` first (Task 7.3) |
| `ResourceInUseException` on Lambda delete | Lambda has active invocations | Wait and retry after a minute |
| `TargetGroupAssociationLimit` on TG delete | Listener still referencing TG | Delete the listener first (Task 4.3) |
| `$AWS: command not found` | Forgot to set env variable | Run `export AWS="--profile 4shark --region us-east-1"` |
| `InvalidParameterValue` on volume snapshot | Instance is in wrong state | Stop instance before snapshotting if needed |
| `ResourceNotFoundException` on log group delete | Log group already deleted | Harmless — skip and continue |
| `NoSuchEntity` on IAM role/policy | Already deleted | Harmless — skip and continue |
