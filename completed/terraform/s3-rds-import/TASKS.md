# Tasks — Import S3 Buckets and RDS Instances to Terraform

## S3 — COMPLETED

- [x] Create `modules/s3_bucket/` module (main.tf, variables.tf, outputs.tf)
- [x] Implement S3 import for beta-001 (4shark-staging)
- [x] Implement S3 import for demo-001 (4shark-poc)
- [x] Implement S3 import for shared-001 (4shark-shared)
- [x] Implement S3 import for atento-001 (4shark-atento-001)
- [x] Refactor IAM policies to use module outputs (4 environments)
- [x] Add ObjectWriter ownership controls to demo-001
- [x] Validate all 4 environments via AWS CLI
- [x] Validate `terraform plan` shows no changes (4 environments)
- [x] Remove import blocks from s3.tf files
- [x] Create PR #175 and merge

## RDS — COMPLETED

### Modules
- [x] Create `modules/rds_aurora_cluster/` module (main.tf, variables.tf, outputs.tf)
- [x] Create `modules/rds_instance/` module (main.tf, variables.tf, outputs.tf)

### Parameter Groups
- [x] Import RDS parameter groups into shared-resources

### Environments (order: lowest risk first)
- [x] beta-001: implement RDS standalone import (beta-db)
- [x] demo-001: implement RDS Aurora import (demo-prd, 1 instance)
- [x] setup: implement RDS standalone import (setup-prd-db)
- [x] atento-001: implement RDS Aurora import (atento-001-app-cluster-cluster, 2 instances)
- [x] shared-001: implement RDS Aurora import (production-app-2, 2 instances)

### Finalization
- [x] Validate `terraform plan` shows no changes (5 environments)
- [x] Remove import blocks from rds.tf files
- [x] Update CHANGELOG.md
- [x] Create PR #176 and merge
