# Auxiliary: SSM Seeding Procedure (per environment)

This file is referenced from PLAN-SPIKE.md. It describes the out-of-band seeding
steps needed after Terraform creates new SSM PLACEHOLDER resources.

Layer-0 constraint: connection-string values contain passwords. They are NEVER
printed to the terminal or chat. All seeding goes through local temp files and
`--value file://` so the value never appears in the shell history or session output.

## Pre-conditions

- `4shark-mfa` profile is active (`/elevate-aws-access`)
- Existing SSM appsettings param for the env is still live (value not yet destroyed)
- New Terraform resources exist in SSM with PLACEHOLDER value (first TF apply already done)

## Step 1 — Download existing appsettings value

```bash
aws ssm get-parameter --name "/integrator-atento-harvester-<env>/appsettings" --with-decryption --query "Parameter.Value" --output text --profile 4shark-mfa > /tmp/appsettings_<env>.json
```

Verify: `wc -c /tmp/appsettings_<env>.json` should be non-trivial (not just "PLACEHOLDER").

## Step 2 — Extract and seed the `companies` value

Extract only the COMPANIES subtree:

```bash
jq '{COMPANIES: .COMPANIES}' /tmp/appsettings_<env>.json > /tmp/companies_<env>.json
```

Seed into the new `/companies` param:

```bash
aws ssm put-parameter --name "/integrator-atento-harvester-<env>/companies" --value "$(cat /tmp/companies_<env>.json)" --type SecureString --overwrite --profile 4shark-mfa
```

Verify the param is populated (value length only, no echo):

```bash
aws ssm get-parameter --name "/integrator-atento-harvester-<env>/companies" --with-decryption --query "length(Parameter.Value)" --profile 4shark-mfa
```

## Step 3 — Extract and seed connection-string secrets

Extract to temp files (never echoed to terminal):

```bash
jq -r '.ConnectionString_Simplex' /tmp/appsettings_<env>.json > /tmp/cs_simplex_<env>.txt
jq -r '.ConnectionString_4Shark' /tmp/appsettings_<env>.json > /tmp/cs_4shark_<env>.txt
```

Seed via `file://` path to avoid terminal exposure:

```bash
aws ssm put-parameter --name "/integrator-atento-harvester-<env>/ConnectionString_Simplex" --value "file:///tmp/cs_simplex_<env>.txt" --type SecureString --overwrite --profile 4shark-mfa
aws ssm put-parameter --name "/integrator-atento-harvester-<env>/ConnectionString_4Shark" --value "file:///tmp/cs_4shark_<env>.txt" --type SecureString --overwrite --profile 4shark-mfa
```

Verify (length only):

```bash
aws ssm get-parameter --name "/integrator-atento-harvester-<env>/ConnectionString_Simplex" --with-decryption --query "length(Parameter.Value)" --profile 4shark-mfa
aws ssm get-parameter --name "/integrator-atento-harvester-<env>/ConnectionString_4Shark" --with-decryption --query "length(Parameter.Value)" --profile 4shark-mfa
```

## Step 4 — Extract 7 plain scalar values

These do NOT need SSM — they will be hardcoded in the Terraform `environment_variables`
locals. Extract them for reference when writing the TF locals:

```bash
jq '{UserRegisterType,SubsidiaryRegisterType,State,DefaultCity,ExternalIdSource,EmailDomain,EmailSource}' /tmp/appsettings_<env>.json
```

EmailDomain and EmailSource are optional in the code (`string.IsNullOrWhiteSpace` check
in `_4SharkService.cs:324` and `_4SharkService.cs:330`). If either is absent or empty,
the code uses its default (`"atento.com"` for EmailDomain, `null` for EmailSource).

## Step 5 — Clean up local temp files

```bash
rm /tmp/appsettings_<env>.json /tmp/companies_<env>.json /tmp/cs_simplex_<env>.txt /tmp/cs_4shark_<env>.txt
```

## Environments to repeat

Run steps 1–5 for each of the four environments in order:
1. mx-staging
2. co-staging
3. mx (prod)
4. co (prod)

Staging first so Step 4 values can be validated with a test run before hardcoding
in the Terraform locals for prod.
