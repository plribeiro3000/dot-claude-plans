# Import S3 Buckets and RDS Instances to Terraform

## Context

All 5 environments have S3 buckets and/or RDS instances created manually in AWS. The goal is to bring all these resources into Terraform management using `import` blocks with reusable modules.

## S3 — COMPLETED

### What was done
- Created reusable module `modules/s3_bucket/` (main.tf, variables.tf, outputs.tf)
- Imported 4 S3 buckets across all app environments
- Refactored IAM policies to use `module.s3_bucket.bucket_arn` instead of hardcoded ARNs
- Added ObjectWriter ownership controls to demo-001 (was missing, now consistent with other envs)
- All 4 environments validated via AWS CLI and `terraform plan` (zero changes)
- PR merged: #175

### S3 Resources managed per environment

| Environment | Bucket | CORS Origins | Resources |
|-------------|--------|-------------|-----------|
| shared-001 | `4shark-shared` | `*.app4shark.com.br`, `*.app4shark.com` | bucket, encryption, public access, CORS, ownership |
| demo-001 | `4shark-poc` | + `*.netlify.app` | same + ownership created (was missing) |
| beta-001 | `4shark-staging` | + `*.netlify.app` | bucket, encryption, public access, CORS, ownership |
| atento-001 | `4shark-atento-001` | + `*.atento.com` | bucket, encryption, public access, CORS, ownership |

---

## RDS — COMPLETED

### What was done
- Created reusable module `modules/rds_aurora_cluster/` (main.tf, variables.tf, outputs.tf)
- Created reusable module `modules/rds_instance/` (main.tf, variables.tf, outputs.tf)
- Imported RDS parameter groups into `shared-resources/` environment
- Imported 5 RDS resources across all environments (3 Aurora clusters + 2 standalone instances)
- All 5 environments validated via `terraform plan` (zero changes)
- PR merged: #176

### RDS Resources managed per environment

| Environment | Identifier | Type | Engine | Class | Instances |
|-------------|-----------|------|--------|-------|-----------|
| shared-001 | `production-app-2` | Aurora | PG 15.13 | db.t4g.large | 2 (writer+reader) |
| demo-001 | `demo-prd` | Aurora | PG 16.9 | db.t3.medium | 1 (writer) |
| beta-001 | `beta-db` | Standalone | PG 17.6 | db.t3.micro | 1 |
| atento-001 | `atento-001-app-cluster-cluster` | Aurora | PG 15.13 | db.t4g.large | 2 (writer+reader) |
| setup | `setup-prd-db` | Standalone | PG 16.9 | db.t3.micro | 1 |

### Parameter Groups (shared-resources)

Imported into `shared-resources/rds-parameter-groups.tf`:
- All custom parameter groups with tcp_keepalives params
- Now managed by Terraform instead of referenced by name only
