# CloudWatch Log Groups — Retention & Cleanup

**Análise executada em:** 2026-03-07
**Regiões:** us-east-1 e sa-east-1
**Total de grupos analisados:** 139 (129 + 10)

---

## Contexto

Auditoria completa de todos os log groups do CloudWatch revelou grupos sem política de retenção (custo crescente indefinido), grupos órfãos (sem eventos há meses/anos) e grupos vazios. Resultados salvos em `/tmp/cw_analysis_report_*.txt` e `/tmp/cw_analysis_full_results.json`.

---

## ✅ Fase 1 — Deleções via CLI (us-east-1) — CONCLUÍDA 2026-03-08

```
/aws/rds/cluster/production-app/postgresql           → deletado
/aws/rds/cluster/poc-app/postgresql                  → deletado
/aws/OpenSearchService/domains/elastic-index-2/audit-logs  → deletado
/aws/OpenSearchService/domains/elastic-index-2/index-logs  → deletado
/aws/OpenSearchService/domains/elastic-index-2/search-logs → deletado
/ecs/teste                                           → deletado
/ecs/TESTE                                           → deletado
/ecs/teste-puma                                      → deletado
```

## ✅ Fase 2 — Deleções via CLI (sa-east-1) — CONCLUÍDA 2026-03-08

```
/ecs/keycloak       → deletado
/ecs/keycloak-task  → deletado
```

---

## ✅ Fase 3 — Órfãos adicionais descobertos e deletados — CONCLUÍDA 2026-03-08

O plano original previa `put-retention-policy` para estes grupos, mas verificação confirmou que os recursos subjacentes não existem mais. Todos foram deletados.

### RDS clusters (us-east-1) — clusters não existem

```
/aws/rds/cluster/atento-001-app-cluster-cluster/postgresql → deletado
/aws/rds/cluster/demo-prd/postgresql                       → deletado
/aws/rds/cluster/atento-001-cluster/postgresql             → deletado
/aws/rds/cluster/demo-001-cluster/postgresql               → deletado
```

> `production-app-2` mantido — já tinha `retention_in_days=30`, será limpo naturalmente.

### CodeDeploy hooks formato antigo (us-east-1) — lambdas não existem

```
/aws/lambda/codedeploy-hook-lambda-atento-001  → deletado
/aws/lambda/codedeploy-hook-lambda-beta-001    → deletado
/aws/lambda/codedeploy-hook-lambda-demo-001    → deletado
/aws/lambda/codedeploy-hook-lambda-shared-001  → deletado
/aws/lambda/codedeploy-hook-lambda-poc         → deletado
```

### OpenSearch (us-east-1) — domínio não existe

```
/aws/OpenSearchService/domains/elastic-index-2/application-logs → deletado
```

---

## 🔲 Fase 4 — Retenção via Terraform (PENDENTE)

Feature branch necessária. Adicionar `aws_cloudwatch_log_group` com `retention_in_days = 30` e fazer `terraform import` antes do apply.

### 4.1 — RDS clusters ativos

Clusters existentes: `app-atento-001-cluster`, `app-shared-001-cluster`, `app-demo-001-cluster`.

Adicionar em cada `rds.tf` da stack correspondente:

```hcl
resource "aws_cloudwatch_log_group" "rds_postgresql" {
  name              = "/aws/rds/cluster/${var.cluster_identifier}/postgresql"
  retention_in_days = 30
  tags              = var.tags
}
```

| Arquivo | Resource name | Import path |
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

### 4.2 — CodeDeploy hook lambda — formato novo

Adicionar em `modules/codedeploy/main.tf`:

```hcl
resource "aws_cloudwatch_log_group" "codedeploy_hook" {
  count = var.enable_hook_lambda ? 1 : 0

  name              = "/aws/lambda/${local.hook_lambda_name}"
  retention_in_days = var.cloudwatch_log_group_retention_in_days
  tags              = var.tags
}
```

Adicionar variável em `modules/codedeploy/variables.tf`:

```hcl
variable "cloudwatch_log_group_retention_in_days" {
  description = "Retention in days for the CodeDeploy hook Lambda log group"
  type        = number
  default     = 30
}
```

Import por stack:

```bash
cd terraform/app-atento-001
terraform import 'module.codedeploy_web.aws_cloudwatch_log_group.codedeploy_hook[0]' /aws/lambda/Lambda-atento-001-codedeploy-hook

cd ../app-shared-001
terraform import 'module.codedeploy_web.aws_cloudwatch_log_group.codedeploy_hook[0]' /aws/lambda/Lambda-shared-001-codedeploy-hook

cd ../app-demo-001
terraform import 'module.codedeploy_web.aws_cloudwatch_log_group.codedeploy_hook[0]' /aws/lambda/Lambda-demo-001-codedeploy-hook

cd ../app-beta-001
terraform import 'module.codedeploy_web.aws_cloudwatch_log_group.codedeploy_hook[0]' /aws/lambda/Lambda-beta-001-codedeploy-hook

cd ../app-atento-001   # novo stack VPC
terraform import 'module.codedeploy_web.aws_cloudwatch_log_group.codedeploy_hook[0]' /aws/lambda/Lambda-app-atento-001-codedeploy-hook

cd ../app-shared-001   # novo stack VPC
terraform import 'module.codedeploy_web.aws_cloudwatch_log_group.codedeploy_hook[0]' /aws/lambda/Lambda-app-shared-001-codedeploy-hook
```

---

### 4.3 — EC2-start-integrator (sa-east-1)

Lambdas existem mas não estão no Terraform. Adicionar em cada stack `integrator-*`:

```hcl
resource "aws_cloudwatch_log_group" "ec2_start_lambda" {
  name              = "/aws/lambda/EC2-start-integrator-${var.client_name}"
  retention_in_days = 30
}
```

Import por stack:

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

## Notas

- `RDSOSMetrics` em sa-east-1 está órfão (390 dias) mas tem retenção de 30d — será limpo naturalmente pelo CloudWatch.
- `production-app-2/postgresql` mantido com retenção=30 já configurada — sem ação necessária.
