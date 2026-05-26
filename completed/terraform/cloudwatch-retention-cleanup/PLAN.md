# CloudWatch Log Groups — Retention & Cleanup

**Analysis executed on:** 2026-03-07
**Regions:** us-east-1 and sa-east-1
**Total groups analyzed:** 139 (129 + 10)

---

## Context

Complete audit of every CloudWatch log group revealed groups with no retention policy (indefinite cost growth), orphan groups (no events for months/years), and empty groups. Results saved in `/tmp/cw_analysis_report_*.txt` and `/tmp/cw_analysis_full_results.json`.

---

## ✅ Phase 1 — CLI deletions (us-east-1) — COMPLETED 2026-03-08

```
/aws/rds/cluster/production-app/postgresql           → deleted
/aws/rds/cluster/poc-app/postgresql                  → deleted
/aws/OpenSearchService/domains/elastic-index-2/audit-logs  → deleted
/aws/OpenSearchService/domains/elastic-index-2/index-logs  → deleted
/aws/OpenSearchService/domains/elastic-index-2/search-logs → deleted
/ecs/teste                                           → deleted
/ecs/TESTE                                           → deleted
/ecs/teste-puma                                      → deleted
```

## ✅ Phase 2 — CLI deletions (sa-east-1) — COMPLETED 2026-03-08

```
/ecs/keycloak       → deleted
/ecs/keycloak-task  → deleted
```

---

## ✅ Phase 3 — Additional orphans discovered and deleted — COMPLETED 2026-03-08

The original plan called for `put-retention-policy` on these groups, but verification confirmed the underlying resources no longer exist. All were deleted.

### RDS clusters (us-east-1) — clusters do not exist

```
/aws/rds/cluster/atento-001-app-cluster-cluster/postgresql → deleted
/aws/rds/cluster/demo-prd/postgresql                       → deleted
/aws/rds/cluster/atento-001-cluster/postgresql             → deleted
/aws/rds/cluster/demo-001-cluster/postgresql               → deleted
```

> `production-app-2` kept — already had `retention_in_days=30`, will be cleaned naturally.

### CodeDeploy hooks old format (us-east-1) — lambdas do not exist

```
/aws/lambda/codedeploy-hook-lambda-atento-001  → deleted
/aws/lambda/codedeploy-hook-lambda-beta-001    → deleted
/aws/lambda/codedeploy-hook-lambda-demo-001    → deleted
/aws/lambda/codedeploy-hook-lambda-shared-001  → deleted
/aws/lambda/codedeploy-hook-lambda-poc         → deleted
```

### OpenSearch (us-east-1) — domain does not exist

```
/aws/OpenSearchService/domains/elastic-index-2/application-logs → deleted
```

---

## 🔲 Phase 4 — Retention via Terraform (PENDING)

Feature branch required. Add `aws_cloudwatch_log_group` with `retention_in_days = 30` and run `terraform import` before applying.

### 4.1 — Active RDS clusters

Existing clusters: `app-atento-001-cluster`, `app-shared-001-cluster`, `app-demo-001-cluster`.

Add to each stack's `rds.tf`:

```hcl
resource "aws_cloudwatch_log_group" "rds_postgresql" {
  name              = "/aws/rds/cluster/${var.cluster_identifier}/postgresql"
  retention_in_days = 30
  tags              = var.tags
}
```

| File | Resource name | Import path |
|---|---|---|
| `app-atento-001/rds.tf` | `aws_cloudwatch_log_group.rds_app_atento_001` | `/aws/rds/cluster/app-atento-001-cluster/postgresql` |
| `app-shared-001/rds.tf` | `aws_cloudwatch_log_group.rds_shared_001` | `/aws/rds/cluster/shared-001-cluster/postgresql` |
| `app-shared-001/rds.tf` | `aws_cloudwatch_log_group.rds_app_shared_001` | `/aws/rds/cluster/app-shared-001-cluster/postgresql` |
| `app-demo-001/rds.tf` | `aws_cloudwatch_log_group.rds_app_demo_001` | `/aws/rds/cluster/app-demo-001-cluster/postgresql` |

```bash
cd terraform/app-atento-001
terraform import aws_cloudwatch_log_group.rds_app_atento_001 /aws/rds/cluster/app-atento-001-cluster/postgresql

cd ../app-shared-001
terraform import aws_cloudwatch_log_group.rds_shared_001     /aws/rds/cluster/shared-001-cluster/postgresql
terraform import aws_cloudwatch_log_group.rds_app_shared_001 /aws/rds/cluster/app-shared-001-cluster/postgresql

cd ../app-demo-001
terraform import aws_cloudwatch_log_group.rds_app_demo_001   /aws/rds/cluster/app-demo-001-cluster/postgresql
```

---

### 4.2 — CodeDeploy hook lambda — new format

Add to `modules/codedeploy/main.tf`:

```hcl
resource "aws_cloudwatch_log_group" "codedeploy_hook" {
  count = var.enable_hook_lambda ? 1 : 0

  name              = "/aws/lambda/${local.hook_lambda_name}"
  retention_in_days = var.cloudwatch_log_group_retention_in_days
  tags              = var.tags
}
```

Add variable in `modules/codedeploy/variables.tf`:

```hcl
variable "cloudwatch_log_group_retention_in_days" {
  description = "Retention in days for the CodeDeploy hook Lambda log group"
  type        = number
  default     = 30
}
```

Import per stack:

```bash
cd terraform/app-atento-001
terraform import 'module.codedeploy_web.aws_cloudwatch_log_group.codedeploy_hook[0]' /aws/lambda/Lambda-atento-001-codedeploy-hook

cd ../app-shared-001
terraform import 'module.codedeploy_web.aws_cloudwatch_log_group.codedeploy_hook[0]' /aws/lambda/Lambda-shared-001-codedeploy-hook

cd ../app-demo-001
terraform import 'module.codedeploy_web.aws_cloudwatch_log_group.codedeploy_hook[0]' /aws/lambda/Lambda-demo-001-codedeploy-hook

cd ../app-beta-001
terraform import 'module.codedeploy_web.aws_cloudwatch_log_group.codedeploy_hook[0]' /aws/lambda/Lambda-beta-001-codedeploy-hook

cd ../app-atento-001   # new VPC stack
terraform import 'module.codedeploy_web.aws_cloudwatch_log_group.codedeploy_hook[0]' /aws/lambda/Lambda-app-atento-001-codedeploy-hook

cd ../app-shared-001   # new VPC stack
terraform import 'module.codedeploy_web.aws_cloudwatch_log_group.codedeploy_hook[0]' /aws/lambda/Lambda-app-shared-001-codedeploy-hook
```

---

### 4.3 — EC2-start-integrator (sa-east-1)

Lambdas exist but are not in Terraform. Add to each `integrator-*` stack:

```hcl
resource "aws_cloudwatch_log_group" "ec2_start_lambda" {
  name              = "/aws/lambda/EC2-start-integrator-${var.client_name}"
  retention_in_days = 30
}
```

Import per stack:

```bash
cd terraform/integrator-almaviva
terraform import aws_cloudwatch_log_group.ec2_start_lambda /aws/lambda/EC2-start-integrator-almaviva

cd ../integrator-redebrasil
terraform import aws_cloudwatch_log_group.ec2_start_lambda /aws/lambda/EC2-start-integrator-redebrasil

cd ../integrator-maqnelson
terraform import aws_cloudwatch_log_group.ec2_start_lambda /aws/lambda/EC2-start-integrator-maqnelson

cd ../integrator-commcenter
terraform import aws_cloudwatch_log_group.ec2_start_lambda /aws/lambda/EC2-start-integrator-commcenter

cd ../integrator-aster-maquinas
terraform import aws_cloudwatch_log_group.ec2_start_lambda /aws/lambda/EC2-start-integrator-aster-maquinas

cd ../integrator-atento-br
terraform import aws_cloudwatch_log_group.ec2_start_lambda /aws/lambda/EC2-start-integrator-atento-br
```

---

## Notes

- `RDSOSMetrics` in sa-east-1 is orphan (390 days) but has 30d retention — will be cleaned naturally by CloudWatch.
- `production-app-2/postgresql` kept with retention=30 already configured — no action needed.
