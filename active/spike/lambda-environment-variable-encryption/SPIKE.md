# SPIKE — Lambda environment variable ownership and encryption

## Investigation question

Two questions, taken in order:

1. Are the Lambda functions' environment variables managed by Terraform, or were they set by hand outside version control?
2. The values are believed to be unencrypted and readable by anyone. How are they protected today, what is actually exposed, and what would make them safer?

## Sources consulted

- `terraform/modules/app/lambda.tf:111-125` — the map that assembles every autoscaling function's environment, including the two credential-bearing entries
- `terraform/modules/app/lambda.tf:131-139` — the SSM SecureString lookups the credentials are read from
- `terraform/modules/app/lambda_scaling_lock.tf:26-28,47-49` — the deploy-pipeline lock functions, which receive the same Redis credential
- `terraform/modules/lambda-ecs-autoscaling/main.tf:31-63` — the `aws_lambda_function` resource; no `kms_key_arn` argument is declared on it
- `terraform/modules/lambda-ecs-autoscaling/variables.tf:93-99` — the `environment_variables` variable and its stated exposure assumption
- `terraform/modules/app/kms.tf:25-230` — the per-stack customer managed key and its `ViaService`-scoped policy statements
- `terraform/identity/policies_baseline.tf:85-94` — the unelevated engineer baseline's Lambda read actions
- `terraform/identity/policy_engineer_terraform_services.tf:1-75` — the MFA-gated elevated read statement carrying `lambda:GetFunctionConfiguration`
- `/tmp/lambda_kms_check_20260827.json`, `/tmp/lambda_kms_check_saeast1_20260827.json` — live `aws lambda list-functions` output, both regions, showing the key binding of all 28 functions
- https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html — AWS's own statement of the default encryption behaviour, the customer-managed-key behaviour, and the permission set each requires

## Findings

### Finding 1: Every Lambda environment variable is declared in Terraform — none is hand-set

The `app` module builds the environment for each autoscaling function as a Terraform map comprehension. Nothing is typed into the console.

**Evidence:**

```hcl
  lambda_environment_variables = {
    for name, config in local.declared_lambdas : name => {
      AUTO_SCALING_GROUP_NAME = "${var.environment}-worker-${name}-asg"
      ECS_CLUSTER_NAME        = local.lambda_cluster_name
      ECS_SERVICE_NAME        = "${var.environment}-worker-${name}-service"
      JOBS_PER_PROCESS        = tostring(config.jobs_per_process)
      METRICS_ENDPOINT        = "https://${local.lambda_metrics_host}/hirefire/${data.aws_ssm_parameter.hirefire_token.value}/info"
      PROCESS_NAME            = "worker_${replace(name, "-", "_")}"
      REDIS_URL               = data.aws_ssm_parameter.redis_lock_url.value
    }
  }
```

**Source:** `terraform/modules/app/lambda.tf:111-125`

**Significance:** The premise behind question 1 does not hold. The map is passed to the shared module at `lambda.tf:206` (`environment_variables = local.lambda_environment_variables[each.key]`), and the two lock functions receive their own map at `lambda_scaling_lock.tf:26-28` and `:47-49`. A hand-edit in the console would be reverted by the next apply of the stack.

**Verification:** File read at the cited lines; the quoted block is the literal file content.

### Finding 2: The two credential-bearing values are sourced from SSM SecureString, not from a literal or a variable

Neither credential is written in the repository. Both are read at plan time from an encrypted parameter.

**Evidence:**

```hcl
data "aws_ssm_parameter" "redis_lock_url" {
  name            = "/${var.environment}/REDIS_LOCK_URL"
  with_decryption = true
}

data "aws_ssm_parameter" "hirefire_token" {
  name            = "/${var.environment}/HIREFIRE_TOKEN"
  with_decryption = true
}
```

**Source:** `terraform/modules/app/lambda.tf:131-139`

**Significance:** Two of the seven environment entries carry a credential — `REDIS_URL` is a connection string including its password, and `METRICS_ENDPOINT` embeds the HireFire token inside the URL path. The remaining five are derived names and numbers with no secret content. The parameters they come from are encrypted under the stack's own customer managed key (`terraform/modules/app/ssm_secrets.tf:37`, `key_id = local.kms_key_arn`), so the *storage of record* is already protected; what this spike is about is the copy that lands on the function.

**Verification:** File read at the cited lines; the quoted block is the literal file content.

### Finding 3: All 28 functions run on the AWS-managed key — no customer managed key is bound to any of them

The shared module declares no `kms_key_arn` on the function resource, and the live account confirms the consequence.

**Evidence:** `aws_lambda_function.this` (`terraform/modules/lambda-ecs-autoscaling/main.tf:31-63`) declares `function_name`, `role`, `runtime`, `handler`, `timeout`, `memory_size`, the S3 package arguments, `layers`, `vpc_config`, a dynamic `environment` block and `tags`. There is no `kms_key_arn` argument. Live confirmation, every function in both regions:

```
us-east-1  — 26 functions, "KmsKeyArn": null on every one
sa-east-1  —  2 functions, "KmsKeyArn": null on both
```

**Source:** `terraform/modules/lambda-ecs-autoscaling/main.tf:31-63`; `/tmp/lambda_kms_check_20260827.json`; `/tmp/lambda_kms_check_saeast1_20260827.json`

**Significance:** The values are not stored in the clear — AWS encrypts them regardless — but they are encrypted under a key nobody here controls, which means the key policy cannot be used as a second authorization lock. This is the substantive half of question 2.

**Verification:** File read at the cited lines; both JSON files were produced by `aws lambda list-functions` in this session and read back in full.

### Finding 4: AWS always encrypts at rest, and a customer managed key is what converts that into an access control

The default is not "unencrypted" — it is "encrypted under a key with no policy of yours attached".

**Evidence:** Verbatim: *"Lambda always provides server-side encryption at rest with an AWS KMS key. By default, Lambda uses an AWS managed key."* And on what changes with your own key: *"When you use a customer managed key, only users in your account with access to the KMS key can view or manage environment variables on the function."*

**Source:** https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html

**Significance:** Encryption at rest is not the axis that decides who can read the value — the API permission is. A customer managed key adds a second, independent lock, because reading the value then requires `kms:Decrypt` on that key in addition to the Lambda read permission.

**Verification:** URL fetched / Verbatim quotes checked / Both substrings confirmed under the "Security at rest" heading.

### Finding 5: The values are already gated behind MFA — the unelevated baseline cannot read them

The two API actions that return environment variables are deliberately absent from the permission set an engineer holds by default.

**Evidence:** The unelevated baseline grants three Lambda read actions:

```hcl
        Sid    = "LambdaReadOnly"
        Effect = "Allow"
        Action = [
          "lambda:GetFunctionCodeSigningConfig",
          "lambda:GetFunctionConcurrency",
          "lambda:ListFunctions",
        ]
```

`lambda:GetFunction` and `lambda:GetFunctionConfiguration` appear only in `EngineerTerraformServices`, under the statement `TerraformServicesElevatedRead`, whose condition block carries `"aws:MultiFactorAuthPresent" = "true"`.

**Source:** `terraform/identity/policies_baseline.tf:85-94`; `terraform/identity/policy_engineer_terraform_services.tf:9,33-34,71`

**Significance:** "Readable by everyone" overstates the current exposure. Reading a value requires an MFA-elevated session, which is the same bar as any other elevated read in this account. The module's own variable description already records this as the intended control (`terraform/modules/lambda-ecs-autoscaling/variables.tf:95`: *"Values may include credentials (e.g., REDIS_URL); engineer baseline IAM gates read access via MFA"*). What is missing is the second lock, not the first.

**Verification:** Files read at the cited lines; the quoted block is the literal file content and the MFA condition was confirmed by reading the statement it belongs to.

### Finding 6: The stack's own key already exists and is wired to every other service — Lambda is the one consumer left out

Each app stack owns a customer managed key, and its policy grants cryptographic use per service through a `ViaService` condition.

**Evidence:** `local.kms_key_arn` is consumed by SSM parameters (`ssm_secrets.tf:37`), CloudWatch log groups (`main.tf:93`, `lambda.tf:210`, `lambda_scaling_lock.tf:32,53`), Secrets Manager (`connection_pooler_secrets.tf:26,44`), ECR (`ecr.tf:34`), OpenSearch (`opensearch.tf:71`) and the capacity module (`capacity.tf:47`). The key policy carries one `ViaService`-scoped statement per service — SSM, CloudWatch Logs, Secrets Manager, S3, ECR — and **no** statement for `lambda.<region>.amazonaws.com`.

**Source:** `terraform/modules/app/kms.tf:31-230`; the consumer list from `grep -rn 'kms_key_arn' terraform/modules/app/*.tf`

**Significance:** Binding the functions to this key follows a pattern the module already repeats six times; it is an added statement plus an added argument, not a new mechanism. The functions' *log groups* are already encrypted under it (`lambda.tf:210`) — only the environment block is not.

**Verification:** File read at the cited lines; the consumer list is the literal grep output from this session.

### Finding 7: A customer managed key at rest costs the execution role nothing; client-side helpers are a different, heavier option

The two encryption options in AWS's page require different permissions and different amounts of work.

**Evidence:** For server-side encryption with your own key, verbatim: *"grant permissions to any users or roles that you want to be able to view or manage environment variables on the function"*, needing `kms:CreateGrant`, `kms:Encrypt` to configure and `kms:Decrypt` to view. For client-side: *"If you're enabling client-side encryption for security in transit, your function needs permission to call the `kms:Decrypt` API operation"* and *"Add code to your function that decrypts the environment variables."*

**Source:** https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html

**Significance:** The server-side option changes no Ruby in the `lambda` repository — the function still receives a plain string. The client-side option stores ciphertext in the environment block, so `GetFunctionConfiguration` returns an unusable value even to an MFA-elevated reader, at the cost of decryption code in each function and a KMS call per cold start.

**Verification:** URL fetched / Verbatim quotes checked / Substrings confirmed under "Managing permissions to your server-side encryption KMS key" and step 5 of the configuration procedure.

### Finding 8: AWS's own recommendation is to not put the credential in an environment variable at all

The page opens with a note that outranks both encryption options.

**Evidence:** Verbatim: *"To increase database security, we recommend that you use AWS Secrets Manager instead of environment variables to store database credentials."*

**Source:** https://docs.aws.amazon.com/lambda/latest/dg/configuration-envvars-encryption.html

**Significance:** The credential of record already lives in an SSM SecureString (Finding 2). The environment variable is a *copy* of it made at apply time. Reading the parameter at runtime instead would remove the copy entirely — and would also mean a credential rotation takes effect without a Terraform apply, which it does not today.

**Verification:** URL fetched / Verbatim quote checked / Substring confirmed in the note block under the page's opening paragraph.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| Leave as is | No work; the MFA gate already blocks the unelevated baseline | The key policy adds no second lock; the value sits in Terraform state and is returned in the clear to any elevated reader | Findings 3, 5 |
| Bind the stack's existing customer managed key (`kms_key_arn`) | Follows the module's existing per-service pattern; adds a second independent lock (`kms:Decrypt` on top of the Lambda permission); no application code changes; the key already rotates and audits per stack | Adds a `ViaService = lambda` statement to the key policy; an elevated reader who also holds the key tag can still see the value; KMS key charges already incurred | Findings 4, 6, 7 |
| Client-side encryption helpers | `GetFunctionConfiguration` returns ciphertext, so the value is unreadable through the API regardless of Lambda permissions | Decryption code in every function in the `lambda` repository; a KMS call per cold start; the ciphertext must be produced somewhere at apply time, which Terraform has no native step for | Finding 7 |
| Read from SSM at runtime, drop the env var | No copy of the credential outside the parameter of record; rotation takes effect without a Terraform apply; matches AWS's stated recommendation | Code change in every function; an SSM call and `kms:Decrypt` on the execution role per cold start; the functions run every minute, so the added latency is paid continuously | Findings 2, 8 |

## What remains uncertain

- Whether the Terraform state copy is considered in scope. The value is in state in the clear (`sensitive = true` at `terraform/modules/lambda-ecs-autoscaling/variables.tf:98` redacts CLI output, not state), and none of the four approaches above removes it except the runtime-read one — and only for the environment block, since the `data` source would go away with it.
- Which principals currently carry the `KeyAccess = all` tag that the key's direct-crypto statement requires (`terraform/modules/app/kms.tf:65-72`). That set is what "who gains a second lock" resolves to, and it was not enumerated in this spike.
- Whether the same treatment is wanted for the `codedeploy-hook` functions, which are declared elsewhere (`terraform/modules/codedeploy/main.tf`) and were not examined here.

## Suggested options for main and the engineer

- Option A: Leave the current arrangement and record the MFA gate as the accepted control.
- Option B: Bind the stack's existing customer managed key to the functions, adding the `ViaService = lambda` statement to the key policy.
- Option C: Option B, plus moving the two credential-bearing values to a runtime SSM read so no copy exists on the function at all.
- Option D: Client-side encryption helpers for the two credential-bearing values.
