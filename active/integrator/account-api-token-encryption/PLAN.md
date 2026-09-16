# PLAN — Account api_token encryption at rest (integrator)

## Objective

Store the integrator's `Account` API token encrypted at rest instead of plaintext, and convert every existing deployment's stored token to the encrypted form as part of the 9.0.0 rollout — without the token value ever leaving the database.

## The change (merged to develop, PR 4shark/integrator#2422)

`Account` stores the token through the `symmetric-encryption` field macro, the same pattern the authentication secrets already use:

- `app/models/account.rb`: the persisted field is `field :encrypted_api_token, type: String, encrypted: true`; the gem generates the `api_token` / `api_token=` accessors (getter decrypts, setter encrypts). A `def api_token=(value); super if value.present?; end` guard mirrors `authentication.rb` so a blank write never clears the stored value. The presence validation is on `encrypted_api_token`. `api_headers` reads the `api_token` accessor unchanged.
- One column, already encrypted — the same shape as `encrypted_password` / `encrypted_client_secret` / `encrypted_security_token` on `Authentication`. There is no plaintext column alongside the encrypted one.

The change lives on `develop` only. `master` still declares `field :api_token, type: String` (plaintext), so production integrators do not encrypt the token until 9.0.0 ships this to `master`.

## Why a data migration is NOT used

The conversion of existing tokens is done by hand on each deployment's console, not by a `db:migrate` data migration. This is a deliberate decision: the rollout is controlled per environment, and the token value stays inside the database and the console session — it is never routed through an automatic migration nor captured to a file.

The conversion is safe because the plaintext survives the deploy: renaming the field to `encrypted_api_token` does not delete the old `api_token` key from existing Mongo documents (Mongoid leaves undeclared keys in place), the new code only writes `encrypted_api_token`, and `db:migrate` carries no migration for this change. So after the code is live, each Account document still carries its plaintext under the old `api_token` key, and the re-encryption reads exactly that.

## The encryption keys were the wrong size in SSM — the blocker found during rollout

The first re-encryption attempt on staging failed with `ArgumentError: key must be 32 bytes`. The cause is a secrets provisioning gap, not a code defect:

- `symmetric-encryption` uses the configured key **raw** (`config/symmetric-encryption.yml` sets `key: <%= ENV['SYMMETRIC_ENCRYPTION_KEY'] %>` with `cipher_name: aes-256-cbc` and no decode directive; the dev/test keys are 32-character strings). So `SYMMETRIC_ENCRYPTION_KEY` must be a 32-byte string and `SYMMETRIC_ENCRYPTION_IV` a 16-byte string. That the key is used raw is proven by the failure itself: an 11-character placeholder produced an 11-byte cipher-key error, not a base64/hex decode error.
- Terraform creates each secret parameter with `value = "PLACEHOLDER"` and `lifecycle { ignore_changes = [value] }` (`modules/integrator/deployments.tf:80-100`). The real value is set out-of-band, and **`terraform apply` never touches it** — so applying Terraform does not fix a wrong key.
- The staging parameters were still at `"PLACEHOLDER"` (11 bytes). The production parameters held a 64-character value (also not 32 bytes). Either way the key is not 32 bytes, so any encrypt/decrypt throws — which also means encryption never worked on any integrator, so **no encrypted data existed anywhere** and replacing the key orphans nothing.

## The fix — set valid keys in SSM (not Terraform), then deploy, then re-encrypt

Set a valid `SYMMETRIC_ENCRYPTION_KEY` (32 chars) and `SYMMETRIC_ENCRYPTION_IV` (16 chars) per deployment, generating the value inside the command so it is never printed:

```bash
aws ssm put-parameter --name /integrator-<slug>/SYMMETRIC_ENCRYPTION_KEY --type SecureString --overwrite --value "$(openssl rand -hex 16)" --region sa-east-1 --profile engineer-elevated
aws ssm put-parameter --name /integrator-<slug>/SYMMETRIC_ENCRYPTION_IV --type SecureString --overwrite --value "$(openssl rand -hex 8)" --region sa-east-1 --profile engineer-elevated
```

`openssl rand -hex 16` is 32 characters (32 bytes used raw); `-hex 8` is 16 characters. The parameter path is `/integrator-<slug>/…` where `<slug>` is the deployment key (e.g. `commcenter`, `commcenter-staging`). Setting the value is a plain SSM write — do NOT route it through Terraform (the value is `ignore_changes`).

A running task reads the SSM secrets at start, so after setting the key the deployment must be redeployed to pick it up.

## Rollout procedure (per deployment)

Run for every integrator deployment, one at a time. The window between the deploy and the re-encryption is the only moment the token reads empty; keep them together.

1. **Ensure a valid key/IV in SSM** (32/16 bytes) for the deployment — see the fix above. Skip if already valid.
2. **Deploy the deployment** (`gh workflow run deploy.yaml -R 4shark/integrator -f integrator=<slug>` — `--ref master` for productive slugs, `--ref develop` for `-staging`). The build that binds the code to `:latest` is triggered by the merge to the release branch; confirm that build succeeded before deploying.
3. **Pre-flight** — `bin/ecs run` on the deployment, read-only, confirms the plaintext is present before touching anything:

   ```ruby
   total = Account.collection.count_documents({})
   plaintext = Account.collection.count_documents('api_token' => { '$exists' => true })
   cifrados = Account.collection.count_documents('encrypted_api_token' => { '$exists' => true })
   puts "accounts=#{total} plaintext_api_token=#{plaintext} encrypted_api_token=#{cifrados}"
   ```

   Expect `plaintext_api_token` greater than zero. If it is already zero and `encrypted_api_token` matches the account count, this deployment is already converted — skip the mutation.
4. **Mutation + verification** — `bin/ecs run` on the same deployment. Reads the raw plaintext left under the old key, rewrites it through the encrypted accessor, then removes the old key. The value is never printed:

   ```ruby
   Account.collection.find('api_token' => { '$exists' => true }).each do |document|
     raw = document['api_token']
     next if raw.blank?
     account = Account.find(document['_id'])
     account.api_token = raw
     account.save!
     Account.collection.update_one({ '_id' => document['_id'] }, '$unset' => { 'api_token' => '' })
     puts "re-encrypted #{document['_id']}"
   end
   restantes = Account.collection.count_documents('api_token' => { '$exists' => true })
   cifrados = Account.collection.count_documents('encrypted_api_token' => { '$exists' => true })
   puts "verificacao: plaintext_restante=#{restantes} cifrados=#{cifrados}"
   ```

   Done when `plaintext_restante=0` and `cifrados` equals the account count (typically 1 per deployment). Auth then reads the encrypted token.

The `$unset` runs only after the encrypted copy is written, so the plaintext is never removed before its ciphered replacement exists. A halt between records leaves a clean partial state that re-running completes (the `$exists` selector no longer matches a converted document).

## State as of 2026-09-15

Every integrator now holds a valid 32-byte `SYMMETRIC_ENCRYPTION_KEY` and 16-byte IV in SSM (all were invalid before — staging at `PLACEHOLDER`, production at 64 chars).

The four staging deployments — `atento-cl-staging`, `atento-co-staging`, `atento-mx-staging`, `commcenter-staging` — have valid keys, were redeployed on the develop image, and had their `api_token` re-encrypted (`plaintext_restante=0`, `cifrados=1` on each). Staging is complete and is the rehearsal of the productive rollout.

The seven production deployments — `almaviva`, `atento-br`, `atento-cl`, `atento-co`, `atento-mx`, `commcenter`, `maqnelson` — have valid keys set in SSM but were **not** redeployed, on purpose: `master` does not use encryption yet, so the key is unused until 9.0.0 and a redeploy now would only restart them to load an unused value.

## For the 9.0.0 production release

The api_token encryption (the PR #2422 model change) ships to `master` at 9.0.0. Because the production keys are already valid in SSM, no key work remains at release — for each production deployment, deploy the 9.0.0 image, then run the pre-flight and mutation above to convert its still-plaintext `api_token`, then confirm `plaintext_restante=0`. The conversion is the same one already rehearsed on staging.
