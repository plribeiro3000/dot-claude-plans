# PLAN — KMS Key Standardization

## Background

During the VPC redesign (feature/vpc-app-beta-001), all new RDS clusters were created with the
`4shark-master` KMS key. However, two loose ends remain:

1. The `4shark-master` key was created via CLI and is **not yet imported into Terraform state**
2. Old RDS instances (pre-migration) were created with the old KMS key (`64b7af79-...`) and have **not yet been migrated**

## Key Details

| Attribute | Value |
|---|---|
| Key name | `4shark-master` |
| Type | Multi-Region |
| Key ID | `mrk-fa0cda243274491784fc7b39bead5a03` |
| Alias | `alias/4shark-master` |
| Primary region | us-east-1 |
| Replica region | sa-east-1 |
| Key policy | allows `rds.{region}.amazonaws.com` + `secretsmanager.{region}.amazonaws.com` |

## Tasks

### Task 1 — Import `4shark-master` KMS key into Terraform

The key exists in AWS but has no Terraform resource managing it. Import it into `shared-resources/`.

1. Create `shared-resources/kms.tf` with `aws_kms_key` + `aws_kms_alias` resources matching current config
2. Run `terraform import` for both resources
3. Verify `terraform plan` shows no changes

### Task 2 — Migrate old RDS instances to `4shark-master` KMS key

Old instances still use the legacy KMS key. Migration requires a snapshot + restore procedure (AWS
does not support in-place KMS key change on RDS).

Identify which instances are affected before starting.

```bash
aws rds describe-db-instances \
  --query 'DBInstances[*].[DBInstanceIdentifier,KmsKeyId]' \
  --output table --region us-east-1
aws rds describe-db-clusters \
  --query 'DBClusters[*].[DBClusterIdentifier,KmsKeyId]' \
  --output table --region us-east-1
```

**Migration procedure per instance/cluster:**
1. Create manual snapshot
2. Copy snapshot with new KMS key (`aws rds copy-db-snapshot --kms-key-id alias/4shark-master`)
3. Restore from copied snapshot
4. Update Terraform to point to new instance
5. Delete old instance

**Note**: This requires a maintenance window per instance. Gradual — do one environment at a time.
