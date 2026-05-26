# PLAN — Identity & SSO Stack

**Status:** COMPLETED (2026-03-10)
**PRs merged:** #227 (identity-stack), #228 (identity-permission-model), #230 (atlas-identity)

---

## What Was Done

### AWS IAM Identity Center (SSO)
- Google Workspace configured as sole authentication gateway for AWS console access
- Admin identity (`ivo@4shark.com.br`) provisioned with full access and 1-hour session limit
- Engineers provisioned with read-only baseline access and 8-hour sessions
- `engineers` IAM group with baseline permissions: CloudWatch Logs, EC2 start/stop, ECR, CodeDeploy, OpenSearch, ElastiCache, Lambda
- `engineers-elevated` IAM role with MFA requirement for destructive operations
- Engineers can self-manage own credentials (MFA, access keys, password change)
- OpenSearch configuration management added to elevated role

### MongoDB Atlas SSO (SAML via Google Workspace)
- Google Workspace SAML app created and linked to Atlas federation
- IdP activated and verified for domain `4shark.com.br`
- Team-based access model: engineers auto-receive read + data access on all projects
- `engineers-elevated` Atlas team created for sensitive cluster operations
- MongoDB organization ownership consolidated to admin identity
- Terraform resources imported: `mongodbatlas_federated_settings_identity_provider`, `mongodbatlas_federated_settings_org_config`
- MongoDB domain TXT verification record removed post-verification (security recommendation)

### DNS
- Decentralized DNS definition across app environments (PR #226)
