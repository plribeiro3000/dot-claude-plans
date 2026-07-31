# Auxiliary file 3 — rollout evidence: queues, terraform, GraphQL contract, permissions

Referenced from `PLAN-SPIKE.md` § "Rollout / zero-downtime".

Every claim below was read at the line cited, on `develop` for `app` / `app-webclient` and on the
working tree for `terraform`.

---

## 1. Which applications are affected — verified, not assumed

`grep -rln "IncentiveVariable\|PlanVariable\|aggregated_modifier\|Commissioning\|incentive_variables"`
over `~/Projects/4Shark/onboarding`, `setup`, `integrator` and `lambda` returned **no matches**. None
of those four repositories references the models this feature touches.

The SDK repositories were checked by name only (`app-sdk-advpl`, `app-sdk-dotnet`) — see the
Not-researched note at the end of this file.

The affected set is therefore `app` (backend) and `app-webclient` (frontend).

**`app-webclient` is not one deploy — it is one Netlify site per client.** `ls src/environments`
returns **40 entries**, of which two are the shared `environment.ts` / `environment.prod.ts` and the
rest are per-client environment folders (`4shark`, `atento`, `atento-mx`, `almaviva`, `goodyear`, …).
`DEPLOY-REFERENCE.md:138` states the shipping model verbatim:

> **Netlify** — build+deploy combined at Netlify (publishes `dist/browser`), one Netlify site **per client** (whitelabel). NOT GitHub Actions.

and `DEPLOY-REFERENCE.md:143`:

> When the engineer says "deploy the frontend", the answer is **Netlify**, not `gh workflow run` — there is no GitHub Actions deploy workflow for `app-webclient`.

`netlify.toml` carries only `[build] publish = "dist/browser"`, the SPA redirect and the security
headers — **no `[context.*]` branch blocks**, so the branch→site binding lives in each Netlify site's
own settings, not in the repository.

---

## 2. Sidekiq queues — where a queue name is declared, and where it is NOT

### 2.1 The queue a worker enqueues into is `base_queue_name` + a per-company suffix

`app/app/models/tenant_worker/queue.rb:31`:

```ruby
      "#{@worker.base_queue_name}#{queue_suffix}"
```

`app/app/models/tenant_worker/queue.rb:52-58`:

```ruby
    def queue_suffix
      if @worker.base_queue_name == :payroll
        @company.payroll_queue_suffix
      else
        @company.commission_queue_suffix
      end
    end
```

So one `base_queue_name :indicator_incentive_calculation` becomes `indicator_incentive_calculation`,
`indicator_incentive_calculation_tiger_shark`, `indicator_incentive_calculation_white_shark`, … one
per company suffix.

### 2.2 The queue list lives in the sidekiq YAML files — five of them for commission

`ls config | grep sidekiq` returns eleven files; the commission family is five:
`sidekiq_commission.yml`, `sidekiq_commission_tiger_shark.yml`, `sidekiq_commission_white_shark.yml`,
`sidekiq_commission_without_deal_indexation.yml`, plus `sidekiq_payroll_tiger_shark.yml`.

`config/sidekiq_commission.yml:4-28` — the base list, priority-ordered:

```yaml
:queues:
  - [commission_setup, 1]
  - [deal_indexation, 10]
  - [deal_metrification, 20]
  - [deal_accumulation, 30]
  - [indicator_cleansing, 40]
  - [indicator_aggregation, 50]
  - [indicator_options_calculation, 60]
  - [deal_incentive_calculation, 70]
```

`config/sidekiq_commission_tiger_shark.yml:5-10` is the same list with the suffix applied:

```yaml
  - [commission_setup_tiger_shark, 1]
  - [deal_indexation_tiger_shark, 10]
  - [deal_metrification_tiger_shark, 20]
  - [deal_accumulation_tiger_shark, 30]
  - [indicator_cleansing_tiger_shark, 40]
  - [indicator_aggregation_tiger_shark, 50]
```

A queue absent from the YAML is never polled by that fleet — jobs enqueued into it sit forever.

### 2.3 Autoscaling reads a SEPARATE queue list, in the HireFire initializer

`config/initializers/hire_fire.rb:36-58` — the `worker_commission` dyno:

```ruby
  config.dyno(:worker_commission) do
    HireFire::Macro::Sidekiq.queue(
      :commission_setup,
      :deal_indexation,
      :deal_metrification,
      :deal_accumulation,
      :indicator_cleansing,
      :indicator_aggregation,
      :indicator_options_calculation,
      :deal_incentive_calculation,
```

There are **five commission dyno blocks** — `:worker_commission` (36), `:worker_commission_white_shark`
(61), `:worker_commission_tiger_shark` (86), `:worker_commission_without_deal_indexation` (111), plus
`:worker_payroll_tiger_shark` (139).

**This list is the autoscaling metric.** The Lambda reads it over HTTP —
`terraform/app-shared-001/lambda.tf:54`:

```hcl
      METRICS_ENDPOINT        = "https://${local.lambda_metrics_host}/hirefire/${data.aws_ssm_parameter.hirefire_token.value}/info"
```

A queue present in the YAML but absent from HireFire is polled by the workers but **invisible to
autoscaling** — depth grows with no capacity added, silently.

**That drift already exists in the repository.** `sidekiq_commission.yml` lists
`user_payment_type_ranking_caching` (19), `commission_ranking_caching` (20),
`user_payment_type_redemption_caching` (26) and `commission_redemption_caching` (27); the
`:worker_commission` HireFire block lists none of the four. So the failure mode is not hypothetical
— it is the current state for those queues.

---

## 3. Terraform — what it actually declares, and what it does not

### 3.1 A worker service is defined by its CONFIG FILE PATH, never by a queue list

`terraform/app-shared-001/terraform.tfvars:106-125`:

```hcl
  "shared-001-worker-commission-service" = {
    task_family                  = "shared-001-worker-commission"
    container_name               = "shared-001-worker-commission"
    image                        = "405749097490.dkr.ecr.us-east-1.amazonaws.com/shared-001-app:latest"
    command                      = ["bundle", "exec", "sidekiq", "-C", "config/sidekiq_commission_without_deal_indexation.yml"]
    task_cpu                     = 2048
    task_memory                  = 2048
```

and the two variants at `:131` and `:152`:

```hcl
    command                      = ["bundle", "exec", "sidekiq", "-C", "config/sidekiq_commission_tiger_shark.yml"]
```

```hcl
    command                      = ["bundle", "exec", "sidekiq", "-C", "config/sidekiq_commission_white_shark.yml"]
```

`grep -rn "sidekiq_commission" terraform` returns **twelve** hits, all of this shape, across
`app-beta-001`, `app-demo-001`, `app-shared-001`, `app-atento-001`. **No terraform file anywhere
enumerates a Sidekiq queue name.**

### 3.2 Autoscaling is per PROCESS, not per queue

`terraform/app-shared-001/lambda.tf:16-20`:

```hcl
  base_lambdas = {
    "commission" = { package = "worker-commission-autoscaling", schedule = true, schedule_suffix = null }
    "user"       = { package = "worker-autoscaling", schedule = true, schedule_suffix = null }
    "system"     = { package = "worker-autoscaling", schedule = true, schedule_suffix = null }
  }
```

`terraform/app-shared-001/lambda.tf:48-58` — the whole env-var set the Lambda receives:

```hcl
  lambda_env_vars = {
    for key, config in local.lambdas : key => {
      AUTO_SCALING_GROUP_NAME = local.lambda_asg_names[key]
      ECS_CLUSTER_NAME        = local.lambda_cluster_name
      ECS_SERVICE_NAME        = "${var.environment}-worker-${key}-service"
      JOBS_PER_PROCESS        = tostring(var.lambda_jobs_per_process)
      METRICS_ENDPOINT        = "https://${local.lambda_metrics_host}/hirefire/${data.aws_ssm_parameter.hirefire_token.value}/info"
      PROCESS_NAME            = "worker_${replace(key, "-", "_")}"
      REDIS_URL               = data.aws_ssm_parameter.redis_lock_url.value
    }
  }
```

`PROCESS_NAME` is `worker_commission` — the HireFire dyno name, not a queue. The commission-balancing
service map (`terraform/app-shared-001/config.yml`) is `services: {}` (line 16) with the shape
documented in its own header comment (lines 8-14) — process name → ECS service + ASG. Again, no
queues.

**Conclusion**: a new `base_queue_name` needs the app-side YAML (×5) and HireFire (×5) changes and
**no terraform change**. Reusing an existing `base_queue_name` needs neither.

---

## 4. Migrations relative to the deploy — the expand/contract test

### 4.1 The migration runs on the NEW image while the OLD image still serves

`app/.github/workflows/deploy-shared-001.yaml` job order:

- `:371` `prepare-and-migrate:`
- `:384` `- name: Build/Push image and register task definition`
- `:396` `image-tag: latest`
- `:403` `- name: Run database migrations`
- `:458` `"command": ["bin/rails", "db:migrate"],`
- `:616` `# DEPLOY WEB - Create CodeDeploy deployment (image already built by prepare-and-migrate)`
- `:621` `needs: [sidekiq-quiet-mode, prepare-and-migrate]`

So `db:migrate` runs from the new image at `:403-458`, and the web deployment that activates the new
code is a later job depending on it. **Between those two points the schema is new and every serving
container is old.** That window is the expand/contract test.

`DEPLOYMENT-STRATEGY.md:65` states the same as an invariant:

> Migrations run as a **separate one-shot ECS task** (`aws ecs run-task` → `bin/rails db:migrate` → `aws ecs wait tasks-stopped` → check exit code), gated *before* the new web/worker code is activated

A migration failure sets a permanent lock and aborts — `deploy-shared-001.yaml:504-516`:

```
      - name: Lock permanently on migration failure
        if: failure() && steps.run-migrations.outcome == 'failure'
```

### 4.2 `strong_migrations` is active, with default checks

`Gemfile:78`: `gem 'strong_migrations'`.

`config/initializers/strong_migrations.rb` is two lines:

```ruby
StrongMigrations.auto_analyze = true
```

No `start_after`, no disabled checks — so the gem's default check set applies. Two evidenced
consequences in the repository's own recent migrations:

`db/migrate/20260722215726_add_plan_id_to_plan_statement_portable_batches.rb:5` — `add_reference`
must be wrapped:

```ruby
    safety_assured { add_reference :plan_statement_portable_batches, :plan, foreign_key: true, index: true, null: true }
```

`db/migrate/20260729113429_add_unique_index_to_user_update_document_enrollments.rb:2-11` — a
concurrent index needs the transaction disabled:

```ruby
  disable_ddl_transaction!

  def up
    add_index :user_update_document_enrollments,
              %i[user_id user_update_document_id],
              unique: true,
              algorithm: :concurrently,
              if_not_exists: true
```

### 4.3 A new permission is created by a DATA migration

`db/migrate/20260729113439_user_update_document_actions.rb` in full:

```ruby
class UserUpdateDocumentActions < ActiveRecord::Migration[8.1]
  def up
    Action.create!(key: 'user_update_document_listing', level: 'module', resource: 'user_update_document')
    Action.create!(key: 'user_update_document_creation', level: 'module', resource: 'user_update_document')
    Action.create!(key: 'user_update_document_destruction', level: 'resource', resource: 'user_update_document')
    Action.create!(key: 'user_update_document_download', level: 'resource', resource: 'user_update_document')
  end

  def down
    Action.get(key: 'user_update_document_listing').destroy
```

`grep -rn "Action.create"` over `db/` returns this pattern going back to 2022 — it is the established
mechanism, not a one-off.

The key must also be added to the hardcoded list in `app/workers/company/admin/processor.rb`
(`MODULE_KEYS`, lines 16-52; `incentive_clone` is on line 31), which the processor iterates at
`:77-83`:

```ruby
        ACTION_KEYS.each do |action_key|
          action = Action.with_uncached_connection { Action.get(key: action_key) }

          Permission.with_uncached_connection do
            admin.permissions.find_or_create_by(action_id: action.id)
          end
        end
```

`Action.get` resolves through `ApplicationRecord.get_id` (`app/models/application_record.rb:134-140`),
which ends in `find_by!` — so a key listed in `MODULE_KEYS` with no `Action` row raises
`ActiveRecord::RecordNotFound` and the processor dies. **The `Action.create!` migration must land
before any code path reads the key.**

---

## 5. `Computation` in flight — the exact mechanics

### 5.1 The key is derived from the plan and does not change

`app/models/plan.rb:166-168`:

```ruby
  def computation
    @computation ||= Computation.new("plan_#{id}")
  end
```

`app/models/computation.rb:48-54`:

```ruby
    def queue
      @queue ||= Counter.new("queue:#{@key}")
    end

    def executions
      @executions ||= Counter.new("executions:#{@key}")
    end
```

So the Redis keys are `queue:plan_<id>` and `executions:plan_<id>`. Nothing in this feature changes
the derivation, which is the first of the three phasing triggers in `DEPLOYMENT-STRATEGY.md:145`:

> 1. **The `Computation` key derivation changes.** In-flight counters live under the old key; the new code computes a new key → the old counters are orphaned and the chain stalls (`queue` never closes).

### 5.2 The counters carry a 12-hour TTL, refreshed on every increment

`app/models/counter.rb:4`:

```ruby
  DEFAULT_EXPIRATION_TIME = 12.hours.to_i
```

`app/models/counter.rb:12-22`:

```ruby
    def increment(by: 1)
      value, _result =
        redis_pool.with do |connection|
          connection.multi do |pipeline|
            pipeline.incrby(@key, by)
            pipeline.expire(@key, DEFAULT_EXPIRATION_TIME)
          end
        end

      value
    end
```

`app/models/counter.rb:48-52`:

```ruby
    def value
      redis_pool.with do |connection|
        connection.get(@key)
      end.to_i
    end
```

`.to_i` on a `nil` returns `0`, so **after both keys expire, `done?` evaluates `0 == 0` and returns
true.** For a deploy this is not reachable (the window is minutes), but it is the reason a chain
stalled for more than 12 hours cannot simply be resumed — the counters are gone and `done?` lies.

### 5.3 The counters are reset once, at the head of the chain

`app/workers/commission/producer.rb:17-18`:

```ruby
      commission.computation.reset_queue
      commission.computation.reset_executions
```

### 5.4 The successor is resolved at execution time, not carried in the job arguments

Every enqueue names the next class inline — e.g. `app/workers/indicator_incentive/finalizer.rb:22`:

```ruby
      Ranking::Producer.with_company_id(commission.company_id).dynamic_perform_async(commission_id, partial)
```

and the job payload carries only class, args and queue (`app/workers/tenant_worker.rb:51-62`):

```ruby
    def dynamic_perform_async(*args)
      result =
        Sidekiq::Client.push(
          'class' => self,
          'args' => args,
          'queue' => queue.name,
          **queue.metadata
        )
```

So a job already sitting in Redis when the new image starts serving runs the **new** body of its own
class and enqueues the **new** successor. It does not carry a stale successor.

---

## 6. GraphQL contract — what the current frontend actually sends

### 6.1 The frontend sends inline query strings with explicit variable declarations

`app-webclient/src/app/indicator-incentives/create/indicator-incentive-create.component.ts:171-191`:

```ts
        `mutation CreateIncentive(
          $commissionType: String
          $description: String
          $groupId: ID
          $name: String
          $reference: String
          $rules: [RuleInputGraphql!]
          $type: String
        ) {
          createIncentive(
            commissionType: $commissionType
            description: $description
            groupId: $groupId
            name: $name
            reference: $reference
            rules: $rules
            type: $type
          ) {
            id
          }
        }`,
```

The rule payload is built field by field at `:153-165`:

```ts
      variables.rules = this.form.value.rules.map((rule: { value: string; description: string }) => {
        const ruleInput: Record<string, any> = { type: 'IndicatorRule' };

        if (rule.value) {
          ruleInput.value = rule.value;
        }

        if (rule.description) {
          ruleInput.description = rule.description;
        }

        return ruleInput;
      });
```

Two consequences: the mutation selects only `{ id }`, so a new output field on `RuleGraphqlType` is
invisible to it; and the input type is referenced **by name** (`RuleInputGraphql`), so the type name
must not change.

### 6.2 `errorPolicy: 'none'` makes any GraphQL error fatal to the whole result

`app-webclient/src/app/indicator-incentives/create/indicator-incentive-create.service.ts:15-28`:

```ts
      defaultOptions: {
        watchQuery: {
          fetchPolicy: 'no-cache',
          errorPolicy: 'none',
        },
        query: {
          fetchPolicy: 'no-cache',
          errorPolicy: 'none',
        },
        mutate: {
          fetchPolicy: 'no-cache',
          errorPolicy: 'none',
        },
      },
```

The same block appears verbatim in `indicator-incentive-permissions.service.ts:16-29`. Under
`errorPolicy: 'none'` a partial result is discarded and the subscriber's error branch fires — so a
**query selecting a field the server does not have** fails the whole screen, not just that field.
This is the constraint that makes step (2) of the engineer's sequence non-trivial.

### 6.3 The server-side field and argument lists

| File | Line(s) | Current |
|---|---|---|
| `app/graphql_types/rule_graphql_type.rb` | 3-14 | `commissionings`, `created_at`, `description`, `document_line`, `id`, `incentive`, `incentive_id`, `type`, `updated_at`, `value` |
| `app/graphql_types/rule_input_graphql_type.rb` | 4-8 | `argument :_destroy, Boolean, required: false` … `:description`, `:id`, `:type`, `:value` — every one `required: false` |
| `app/graphql_types/incentive_variable_graphql_type.rb` | 4-7 | `id`, `incentive`, `incentive_id`, `variable`, `variable_id` |
| `app/graphql_types/variable_graphql_type.rb` | 33 | `field :type, String, null: false` |
| `app/graphql_resolvers/variable_graphql_resolver.rb` | 21 | `option(:type, type: String) { \|scope, type\| scope.for_type(type) }` |
| `app/graphql_mutations/create_incentive_graphql_mutation.rb` | 43-47 | `rules: %i[ description type value ]` |
| `app/graphql_mutations/update_incentive_graphql_mutation.rb` | 43-49 | `rules: %i[ _destroy description id type value ]` |

Note that `RuleInputGraphqlType` has **no required argument at all** today — every one is
`required: false`. Adding one that is `required: true` would break every existing client sending that
input type.

---

## 7. An incentive already used by a plan cannot be updated

`app/policies/incentive_policy.rb:12-19`:

```ruby
  def update?
    return false if user.company_id != record.company_id
    return false if record.disabled?
    return false if record.plans.any?
    return true if role.permission?('incentive_update')

    record.owner_id == user.id && user.permission?('incentive_update')
  end
```

`return false if record.plans.any?` — an incentive attached to any plan is not updatable through the
mutation. So an output binding can only ever be set on an incentive that is **not yet in a plan**,
which bounds the backwards-compatibility surface sharply: no existing productive incentive can
acquire a binding by accident, and no existing plan's arithmetic can change without a new incentive
being authored and added.

---

## Not researched

- **The SDK repositories** (`app-sdk-advpl`, `app-sdk-dotnet`) were not opened. They were excluded
  from the grep in §1, which covered only `onboarding`, `setup`, `integrator` and `lambda`. Whether
  either SDK models `Incentive` / `Rule` / `Variable` is unverified.
- **`app-mobileclient`** was not examined. `DEPLOY-REFERENCE.md:140` records that it has *"No CI/CD in the repo — store delivery mechanism is not evidenced here."*
- **The autoscaling Lambda source** (`worker-commission-autoscaling` package) was not read — only its
  Terraform-supplied environment. Whether it does anything per-queue beyond consuming the HireFire
  endpoint is unverified.
- **`app/docs/architecture/PARALLEL_PROCESSING.md` does not exist.** `DEPLOYMENT-STRATEGY.md` cites it
  four times with line numbers (`:39-42`, `:76-79`, `:88-89`), and `app/CLAUDE.md` links the
  `dot-claude` `DATA-PROCESSING.md` in its place. `ls docs/architecture` returns eight files and that
  is not among them, so those four citations could not be verified against the repository. The
  `Computation` facts in §5 above were read from the code instead.
