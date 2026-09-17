# SPIKE — Keeping the Magnatech Tiny (Olist) API token alive as a daily managed job

## Investigation question

`PLAN.md` in this folder restores access with a one-time browser re-authorization and a
stopgap `tiny_token.sh refresh`. This spike answers the follow-up it defers:

1. What do other integrators actually do to keep a Tiny v3 OAuth2 (Authorization Code)
   token alive in an unattended daily process — cadence, refresh-token rotation handling,
   token storage, recovery when the chain lapses?
2. Webhooks vs polling on v3 — does Tiny recommend push for v3, what is the event catalog,
   and where webhooks don't cover, what does an incremental-poll fallback look like?
3. Is Authorization Code really the only usable flow, or does Tiny expose a
   `client_credentials` / service-account path for a registered app?
4. Where should the daily refresh job (and later the integration itself) run, given 4Shark
   has no general-purpose persistent EC2 and an established ECS-scheduled-task pattern for
   this exact job shape — with concrete options and their trade-offs, including alerting
   before the 24h cliff?
5. A final recommendation anchored in the evidence, with forks flagged for the engineer
   where community practice and 4Shark's own constraints do not obviously agree.

## Sources consulted

- `~/Projects/4Shark/dot-claude-plans/active/magnatech-tiny-token/PLAN.md` — the incident
  narrative and the two open follow-up axes (auth reliability, change delivery) this spike
  investigates.
- `~/Projects/4Shark/dot-claude-plans/active/magnatech-tiny-token/tiny_token.sh` — the
  stopgap script; its `save_tokens`/`cmd_refresh` shape is the baseline this spike evaluates
  against a managed-job alternative.
- `~/Projects/4Shark/terraform/modules/integrator/harvesters.tf` — the existing 4Shark
  pattern for a recurring, per-client ETL job (ECS Fargate + EventBridge Scheduler + SSM
  SecureString secrets + Rollbar).
- `~/Projects/4Shark/terraform/modules/ecs_scheduled_task/{main.tf,variables.tf,README.md}`
  — the generic, reusable scheduled-task module three different stacks instantiate.
- `~/Projects/4Shark/terraform/modules/app/scheduled_tasks.tf` — a second, independent
  consumer of the same module, with a concrete daily-cron alarm-window convention.
- `~/Projects/4Shark/terraform/modules/cloudwatch_app_monitoring/{alarms_scheduler.tf,alarms_cron.tf}`
  — the existing alarm shapes for "scheduler failed to invoke" and "cron produced no
  output" (i.e., is not running).
- `~/Projects/4Shark/terraform/monitoring/{sns.tf,chatbot.tf}` — the shared alert channel
  (SNS → AWS Chatbot → Slack `#dev_operations`) these alarms already publish to.
- `~/Projects/4Shark/terraform/monitoring/rollbar.tf` / `rollbar_notifications.tf` — confirms
  every harvester already carries a `ROLLBAR_ACCESS_TOKEN` secret and Slack-notified Rollbar
  project (app-level error reporting layer, distinct from the infra-level cron alarms).
- Direct fetch of `https://erp.tiny.com.br/public-api/v3/swagger/swagger.json` (the official
  v3 OpenAPI spec) — see auxiliary `tinytoken_data_1_swagger_summary.txt`.
- Direct fetch of `https://accounts.tiny.com.br/realms/tiny/.well-known/openid-configuration`
  (the Keycloak realm's OIDC discovery document) — see auxiliary `tinytoken_data_2_oidc_config.json`.
- Two diagnostic token-endpoint probes (no secret involved) — see auxiliary
  `tinytoken_log_1_client_credentials_probe.txt`.
- [automasoluct.com.br — Como gerar e renovar o token da API Tiny com N8N](https://automasoluct.com.br/2025/12/12/token-api-tiny-n8n/)
  — a community integrator's concrete refresh cadence and storage choice.
- [github.com/opastorello/olist-mcp-server](https://github.com/opastorello/olist-mcp-server)
  — a second, independent real-world Tiny v3 OAuth client, for corroboration on failure
  recovery.
- [ajuda.olist.com — Aplicativos API V3, Configurações e Utilização](https://ajuda.olist.com/hubs-e-plataformas-via-api/aplicativos-api-v3-configuracoes-e-utilizacao)
  — official v3 app-registration doc (thin; most of the fields tested returned "not
  documented").
- [tiny.com.br/api-docs/api2-limites-api](https://tiny.com.br/api-docs/api2-limites-api) —
  rate-limit numbers, explicitly scoped to API 2.0.
- [docs.aws.amazon.com — Rotation by Lambda function](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotate-secrets_lambda.html)
  and [Match AWS Secrets Manager events with Amazon EventBridge](https://docs.aws.amazon.com/secretsmanager/latest/userguide/monitoring-eventbridge.html)
  — the vendor-documented alternative hosting shape (Secrets Manager rotation Lambda).
- [aws.amazon.com/fargate/pricing](https://aws.amazon.com/fargate/pricing/) — Fargate
  per-second billing, grounding the "negligible cost" claim in Finding 6.

## Findings

### Finding 1: A real integrator's cadence is well inside the 24h window, and tokens are stored outside the workflow tool

**Evidence:** automasoluct.com.br's n8n-based Tiny integration guide states the token
lifetimes and its own chosen cadence:

> "The Access Token of Tiny expires in approximately 4 hours, while the Refresh Token
> remains valid for 24 hours."

> "the N8N executes the renewal every 3 hours or every 3h50min. This way, the token remains
> always valid and all integrations continue functioning without interruptions."

> "the flow stores the data in a Google Sheets spreadsheet. This way, you maintain control,
> history and ease to reuse the tokens in other flows."

**Source:** [automasoluct.com.br/2025/12/12/token-api-tiny-n8n](https://automasoluct.com.br/2025/12/12/token-api-tiny-n8n/)
(fetched and quote-verified 2026-09-16; re-fetch confirmed the three substrings above are
still present verbatim).

**Significance:** the community pattern for this exact problem is not "refresh right before
the access token dies" — it is refresh with a wide safety margin (3–3h50 against a 4h access
/ 24h refresh window), so a single missed run does not risk the 24h cliff. The storage choice
(a spreadsheet, external to the workflow engine) shows the underlying need — durable,
inspectable token storage outside the process that does the refreshing — even in a
lightweight hobbyist setup. Nothing in this source addresses refresh-token rotation or
what happens when the chain does lapse (see Finding 2 for a second source on that).

### Finding 2: A second, independent Tiny v3 client converges on the same "manual re-auth if it expires" recovery — but only ever tested at the token, never protocol, level

**Evidence:** `opastorello/olist-mcp-server`, an unrelated open-source MCP server wrapping
the Tiny v3 API, documents token persistence to a local file and states, on expiry:

> "Se expirar, abra `/auth` novamente" (if it expires, open `/auth` again)

**Source:** [github.com/opastorello/olist-mcp-server](https://github.com/opastorello/olist-mcp-server)
README, fetched and quote-verified 2026-09-16.

**Significance:** this is a second, independently-built integration reaching the identical
conclusion `PLAN.md` already documents from the Magnatech incident: once the refresh chain
is dead, the only path back is a fresh browser authorization. This corroborates that the
"reauthorize with the account owner" step is a property of Tiny's Authorization Code +
rotating-refresh-token design, not an artifact of how Emerson's `refresh.sh` was written.
Neither source documents the refresh-token *rotation* mechanism itself (whether each refresh
call invalidates the previous refresh_token) with a quotable statement — see "What remains
uncertain" below.

### Finding 3: The official v3 OpenAPI spec exposes zero webhook resources, across 129 endpoints and 30 resource groups

**Evidence:** the live `swagger.json` for `Olist ERP API v3` (fetched directly, not through
a rendered help page) lists 129 paths under 30 resource prefixes — `pedidos`, `produtos`,
`estoque`, `contas-pagar`, `contas-receber`, `notas`, `crm`, etc. — and:

```
grep -io "webhook[a-zA-Z]*" swagger.json | sort -u
# (no output — zero matches, case-insensitive, anywhere in a 1.15MB spec)
```

Full resource list and the two relevant query-parameter sets are preserved in
`tinytoken_data_1_swagger_summary.txt`.

**Source:** `https://erp.tiny.com.br/public-api/v3/swagger/swagger.json`, fetched and
grepped directly 2026-09-16 (title field confirms `"Olist ERP API v3"`, `openapi: "3.0.0"`).

**Significance:** every webhook-catalog page found by web search
([tiny.com.br/api-docs/api2-webhooks](https://tiny.com.br/api-docs/api2-webhooks),
[tiny.com.br/api-docs/api2-webhooks-tiny](https://tiny.com.br/api-docs/api2-webhooks-tiny),
[tiny.com.br/api-docs/api2-webhooks-atualizacao-estoque](https://tiny.com.br/api-docs/api2-webhooks-atualizacao-estoque))
is explicitly namespaced `api2-`, i.e. API 2.0. Combined with zero hits in the v3 OpenAPI
spec, no evidence was found of a v3 webhook resource or event catalog. This does not prove
v3 webhooks cannot exist in some other form — Tiny's v2 webhook configuration is a UI
setting under Menu → Configurações rather than a REST resource, so a v3 equivalent
configured outside the documented REST surface cannot be ruled out by this method alone —
but no such v3-specific documentation was found despite direct searches for it (see "What
remains uncertain").

### Finding 4: `/pedidos` and `/produtos` both expose an "updated since" filter; `/estoque` does not support bulk incremental listing

**Evidence:** from the same swagger spec, the query parameters on the two candidate
list endpoints:

```
/produtos GET -> ['nome', 'codigo', 'gtin', 'situacao', 'dataCriacao', 'dataAlteracao', 'idListaPreco', 'limit', 'offset']
/pedidos  GET -> ['numero', 'nomeCliente', 'codigoCliente', 'cpfCnpj', 'dataInicial', 'dataFinal', 'dataAtualizacao', 'situacao', ...]
/estoque/{idProduto} GET -> ['idProduto']   # per-product only, no list/date-filter form
```

**Source:** `https://erp.tiny.com.br/public-api/v3/swagger/swagger.json`, same fetch as
Finding 3; full parameter lists in `tinytoken_data_1_swagger_summary.txt`.

**Significance:** `dataAlteracao` on `/produtos` and `dataAtualizacao` on `/pedidos` are
exactly the mechanism `PLAN.md`'s follow-up section names as the polling fallback ("a
bounded incremental poll (by updated-at)"). This is directly usable for orders and products.
Stock (`/estoque`), however, only exposes a per-product GET with no bulk, date-filtered
listing endpoint in the current spec — an incremental stock poll would mean iterating every
known product ID rather than asking "what changed since T", which is a materially different
(and more expensive) shape than the orders/products case.

### Finding 5: The realm's OIDC discovery document advertises `client_credentials` as a supported grant type, but this cannot be attributed to the registered app without its secret

**Evidence:** the Keycloak realm's own discovery document:

```json
"grant_types_supported": ["authorization_code", "implicit", "refresh_token", "password",
  "client_credentials", "urn:ietf:params:oauth:grant-type:device_code", ...]
```

**Source:** `https://accounts.tiny.com.br/realms/tiny/.well-known/openid-configuration`,
fetched directly 2026-09-16; full document in `tinytoken_data_2_oidc_config.json`.

A follow-up diagnostic probe attempted to test whether the specific "4Shark Integrator"
`client_id` is permitted to use `client_credentials` (Keycloak's `serviceAccountsEnabled`
is a per-client toggle, independent of what the realm supports overall). Sending
`grant_type=client_credentials` with only the `client_id` (no secret) and sending
`grant_type=authorization_code` with the same `client_id` and a bogus code (no secret)
produced the byte-identical response in both cases:

```
{"error":"unauthorized_client","error_description":"Invalid client or Invalid client credentials"}
HTTP 401
```

Full transcript in `tinytoken_log_1_client_credentials_probe.txt`.

**Significance:** `grant_types_supported` at the realm level is a fact about the identity
provider's protocol capabilities, not about what the "4Shark Integrator" client is
configured to allow — Keycloak gates `client_credentials` per client via a separate
`serviceAccountsEnabled` flag, and the generic 401 returned with no secret cannot
distinguish "wrong/missing secret" from "this grant type is disabled for this client."
This question is **not settled** by this spike and requires the recovered `CLIENT_SECRET`
(PLAN.md prerequisite #1) to test directly: `curl` the token endpoint with
`grant_type=client_credentials` plus the real `client_id`/`client_secret` and read the
response — a single, side-effect-free HTTP call. No official Tiny/Olist documentation
found (searched directly) states that `client_credentials` is offered to third-party
marketplace apps; the observed flow in `tiny_token.sh` and in both community integrations
consulted (Findings 1–2) is Authorization Code only.

### Finding 6: 4Shark already has an established, multiply-instantiated pattern for exactly this job shape — ECS Fargate on an EventBridge schedule

**Evidence:** the `ecs_scheduled_task` module is not harvester-specific; it is consumed
independently by three different call sites:

```
modules/integrator/harvesters.tf:166   module "harvester_task" { source = "../ecs_scheduled_task" ... }
modules/integrator/deployments.tf      (staging deployment maintenance)
modules/app/scheduled_tasks.tf:56      module "scheduled_task" { source = "../ecs_scheduled_task" ... }
```

Its own README frames the use case directly:

> "Creates an EventBridge Scheduler that runs an ECS Fargate task on a cron or rate
> schedule. Used for maintenance jobs such as attachment expiration, daily report
> generation, and data cleanup tasks that run outside the main ECS services."

**Source:** `~/Projects/4Shark/terraform/modules/ecs_scheduled_task/README.md:3-5`;
call sites confirmed by `grep -rl "ecs_scheduled_task"` across the terraform repo
2026-09-16.

Secrets for a harvester follow the SSM SecureString pattern already in place — a
placeholder parameter created by Terraform, its real value populated out of band:

```hcl
# modules/integrator/harvesters.tf:51-68
resource "aws_ssm_parameter" "harvester_secrets" {
  for_each = local.harvester_secrets
  name  = "/${local.harvester_name[each.value]}/${split("/", each.key)[1]}"
  type  = "SecureString"
  value = "PLACEHOLDER"
  lifecycle { ignore_changes = [value] }
}
```

And a comment on the harvester task IAM role states the harvester itself never touches
SSM directly:

> "It reads no SSM itself — the configuration arrives as task-definition environment
> variables and secrets, which the execution role resolves — so it carries no inline
> policy." — `modules/integrator/harvesters.tf:89-91`

A repo-wide search for `ssm:PutParameter` / `secretsmanager:PutSecretValue` /
`secretsmanager:UpdateSecret` across every `.tf` file found matches only in
`identity/policy_engineer_write.tf` (the engineer's own elevated IAM policy) and
`modules/codedeploy/main.tf` (unrelated CodeDeploy hook permissions) — no ECS task
anywhere in this codebase is currently granted permission to write its own secret back.

**Significance:** hosting a daily refresh job on ECS Fargate + EventBridge Scheduler is not
a new pattern to invent — it is the same shape already running for every harvester and for
`app`'s own daily maintenance crons, with an established secrets-injection convention
(read-only, execution-role-resolved SSM SecureString). What is **not** already established
is a task that *writes* its own rotated credential back — every existing SSM secret in this
codebase is populated once, out of band, and read thereafter. A self-refreshing OAuth job
that persists its new `access_token`/`refresh_token` pair back to SSM on every run would be
the first instance of an ECS task holding write permission on its own secret in this
codebase — a deviation worth naming explicitly rather than treating as "just another
harvester."

### Finding 7: 4Shark's cron/scheduler alarms already cover both silent-death failure modes, but are not wired for the integrator/harvester side

**Evidence:** `cloudwatch_app_monitoring` defines four scheduled-task alarms:

```hcl
# alarms_scheduler.tf:1-21 — Alarm #9: EventBridge Scheduler → target invocation errors
metric_name = "TargetErrorCount"; namespace = "AWS/Scheduler"; threshold = 0

# alarms_scheduler.tf:23-43 — Alarm #9b: invocations dropped after retries exhausted
metric_name = "InvocationDroppedCount"; namespace = "AWS/Scheduler"; threshold = 0

# alarms_cron.tf:1-37 — Alarm #10: cron ran but logged ERROR/FATAL
pattern = "?ERROR ?FATAL"; namespace = "4Shark/Cron"

# alarms_cron.tf:39-66 — Alarm #11: cron produced no log events at all in its window
metric_name = "IncomingLogEvents"; namespace = "AWS/Logs"; treat_missing_data = "breaching"
comment: "The cron produced no log events for the family's cadence window, which means
it stopped running for any reason — failed to start (the env-var incident) or the schedule
stopped firing."
```

All four publish to a shared SNS topic (`alert_sns_topic_arn`) which
`modules/app/monitoring.tf:28` wires from `4shark-cloudwatch-alerts`, subscribed by AWS
Chatbot to Slack:

> "Routes CloudWatch alerts to the #dev_operations Slack channel." — `monitoring/chatbot.tf:1`

The module invoking `cloudwatch_app_monitoring` is only `modules/app/monitoring.tf` — a
repo-wide search confirms `cron_families` / `has_scheduled_tasks` / `sns_topic_arn` are not
referenced anywhere in `modules/integrator/` (where harvesters live). `app`'s own cadence
convention for the "not running" alarm window, taken directly from its scheduled-tasks
locals:

```hcl
# modules/app/scheduled_tasks.tf:36-51
# "One 'not running' alarm window per cron, derived from its schedule: hourly crons
# tolerate ~3h of silence, daily crons ~28h (cadence + buffer)."
```

**Source:** file:line citations above, all confirmed 2026-09-16.

**Significance:** the exact alarm shape needed to satisfy "alert on failure before the 24h
cliff" already exists and is proven in production for `app`'s own daily crons — it is not
wired for harvesters/integrator today. Standing this job up under `integrator` (alongside a
future Magnatech harvester) would mean either porting `cloudwatch_app_monitoring` to that
module, or reusing it as-is if the job instead lives under a stack that already wires
`app`'s monitoring module. Separately, harvesters already carry a `ROLLBAR_ACCESS_TOKEN`
secret and a Slack-notified Rollbar project (`monitoring/rollbar.tf:23,246-263`,
`rollbar_notifications.tf:709-747` for the two existing `simplex-harvester-*` projects) —
an application-level exception-reporting channel, complementary to but distinct from the
infra-level "did the task even run" alarms above: Rollbar only fires if the container starts
and the app's own code reports an error, while Alarm #11 fires even if the task fails to
launch at all.

### Finding 8: AWS's own documented pattern for exactly this problem (rotating a third-party OAuth credential on a schedule) is Secrets Manager + a custom rotation Lambda — not currently used anywhere in this codebase

**Evidence:**

> "For many types of secrets, Secrets Manager uses an AWS Lambda function to update the
> secret and the database or service." ... "To rotate a secret, Secrets Manager calls a
> Lambda function according to the rotation schedule you set up."

**Source:** [docs.aws.amazon.com/secretsmanager/.../rotate-secrets_lambda.html](https://docs.aws.amazon.com/secretsmanager/latest/userguide/rotate-secrets_lambda.html),
fetched and quote-verified 2026-09-16.

On the alerting side, Secrets Manager's rotation success is a native, default-on event —
but consuming it (or its failure counterpart) still requires the customer to build the
EventBridge rule themselves:

> "Secrets Manager moves the AWSCURRENT label to the new version whenever the active secret
> value changes, whether from a manual update or automatic rotation. This event is enabled
> by default for all secrets and routed to the default EventBridge event bus. To consume it,
> you add an event pattern that matches it..."

**Source:** [docs.aws.amazon.com/secretsmanager/.../monitoring-eventbridge.html](https://docs.aws.amazon.com/secretsmanager/latest/userguide/monitoring-eventbridge.html),
fetched and quote-verified 2026-09-16.

A repo-wide search for `aws_secretsmanager_secret_rotation` / `rotation_rules` across every
`.tf` file in `~/Projects/4Shark/terraform` returned zero matches — Secrets Manager itself
is used in only 7 files (`connection_pooler`, `app`, `auth`/Keycloak modules), all without
rotation configured, versus 31 files using the SSM Parameter Store pattern.

**Significance:** this is a real, vendor-documented alternative shape — a rotation Lambda
running on its own schedule, with atomic `AWSCURRENT`/`AWSPENDING` versioning (so a failed
rotation never destroys the last known-good token, unlike overwriting a single SSM
parameter in place). It solves the same problem as Finding 6/7's ECS-task approach, but
costs a Lambda deployment (`terraform/modules/lambda-ecs-autoscaling` and
`terraform/modules/codedeploy` are the only existing Lambda usages in this codebase — see
"What remains uncertain") and requires building the same EventBridge-rule-plus-SNS wiring
this spike already found is needed for the ECS approach (Finding 7). It is not a shortcut
that avoids building alerting; it changes the shape of the state store, not the alerting
effort.

### Finding 9: A scheduled Fargate token-refresh task costs a few minutes of billed compute per day, not a persistent process

**Evidence:**

> "Pricing is calculated per second with a 1-minute minimum. Duration is calculated from the
> time you start to download your container image (Docker pull) until the task terminates,
> rounded up to the nearest second."

**Source:** [aws.amazon.com/fargate/pricing](https://aws.amazon.com/fargate/pricing/),
fetched and quote-verified 2026-09-16.

**Significance:** at the 3-3h50min cadence the community source in Finding 1 uses (6-8
runs/day), each run billed at minimum one minute, the daily compute cost is on the order of
minutes of Fargate time — negligible next to an always-on task, and consistent with the
engineer's framing in the brief ("sobe 1x/dia"). This is a directional cost comparison, not
a region-specific dollar figure — no sa-east-1 Fargate price-per-second was looked up, since
the qualitative claim (trivial vs. persistent) does not turn on the exact rate.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| ECS Fargate scheduled task (EventBridge Scheduler), harvester-style | Established 4Shark pattern, 3 existing call sites; secrets via familiar SSM SecureString; natural home once a Magnatech integrator stack exists; cron alarms (#9-#11) proven in production for `app` | Self-writing the rotated token back to SSM (`ssm:PutParameter` on the task role) is a new permission shape in this codebase (Finding 6); cron alarms #9-#11 are not wired for `integrator`/harvester today — would need porting (Finding 7); no atomic "last known good" versioning on a plain SSM parameter overwrite | `modules/integrator/harvesters.tf`, `modules/ecs_scheduled_task/README.md`, `modules/cloudwatch_app_monitoring/alarms_{scheduler,cron}.tf` |
| AWS Secrets Manager + custom rotation Lambda | Vendor-documented pattern built specifically for rotating a third-party credential on a schedule; atomic AWSCURRENT/AWSPENDING versioning survives a failed rotation | Zero existing use of `aws_secretsmanager_secret_rotation` anywhere in this codebase — first-of-its-kind adoption; Lambda is only used today for two narrow internal purposes (autoscaling helper, CodeDeploy hooks), not a general pattern here; still requires building the EventBridge-rule-to-SNS wiring for alerting — not "free" | AWS docs (`rotate-secrets_lambda.html`, `monitoring-eventbridge.html`); repo-wide grep for `aws_secretsmanager_secret_rotation`, `aws_lambda_function` |
| Persistent EC2 (Emerson's original approach) | None identified relative to the alternatives above | This is the exact failure mode that caused the incident under investigation — 4Shark has no general-purpose persistent EC2, and the only EC2 instances that stay up (integrator MongoDB nodes) are reprovisioned periodically, silently wiping anything placed on them outside Terraform | `PLAN.md` background section; CLAUDE.md § AWS Policy / § Host Access (no SSH/general EC2 by default) |
| Webhooks (push) for change delivery | Recommended pattern per Tiny's own v2 docs (retry policy, avoids polling cost) | No v3 webhook resource found in the official OpenAPI spec (129 paths, 0 webhook hits) or in any v3-specific documentation located; every webhook doc found is explicitly namespaced API 2.0 | Findings 3-4; `tinytoken_data_1_swagger_summary.txt` |
| Incremental poll by `dataAlteracao`/`dataAtualizacao` | Directly supported today for `/produtos` and `/pedidos`; no dependency on an unconfirmed webhook capability | `/estoque` has no bulk date-filtered listing — a stock poll means iterating every product ID, not "what changed since T" | Finding 4; `tinytoken_data_1_swagger_summary.txt` |

## What remains uncertain

- **Refresh-token rotation, as a documented/quotable fact.** `PLAN.md` and `tiny_token.sh`
  assume each refresh call issues a new `refresh_token` that invalidates the previous one.
  No source fetched in this spike (Tiny/Olist docs, the two community integrations, Keycloak's
  own admin guide) yielded a quotable statement confirming this specifically for Tiny's
  realm. It is cheap to settle empirically the next time `tiny_token.sh refresh` runs —
  compare `TINY_REFRESH_TOKEN` in `~/.magnatech_tiny_tokens` before and after the call.
- **Whether the "4Shark Integrator" client is permitted `client_credentials`.** The realm
  advertises the grant type (Finding 5), but per-client eligibility (Keycloak's
  `serviceAccountsEnabled`) could not be tested without the real `CLIENT_SECRET`. Settling
  this is a single, side-effect-free `curl` once `PLAN.md` prerequisite #1 (recovering the
  secret) is done.
- **Whether a v3 webhook capability exists outside the documented REST surface** (e.g., a
  UI-configured subscription, as API 2.0's webhooks are, rather than a REST resource). Direct
  searches for v3-specific webhook documentation found none; this spike cannot rule out an
  undocumented or support-request-only feature (API 2.0's webhook page directs setup requests
  to `integracao@tiny.com.br`, and the same channel may apply to v3 — not confirmed either
  way).
- **Whether the whole daily-refresh job should live inside a future `integrator-magnatech`
  Terraform stack (once one exists) or stand alone until then.** No `integrator-magnatech`
  stack exists yet (confirmed — no matching directory in `~/Projects/4Shark/terraform`), so
  there is currently no natural home to attach an ECS-scheduled-task instantiation to without
  creating new infrastructure either way. This is a scope/sequencing question for the
  engineer, not something this spike's research resolves.

## Suggested options for main and the engineer

- **Option A — ECS Fargate scheduled task, harvester-style (Finding 6), with cron
  monitoring ported from `app` (Finding 7).** Follows the pattern already proven three times
  in this codebase. Requires: (1) deciding where the task's own `ssm:PutParameter` grant fits
  4Shark's existing "secrets are read-only from the app's perspective" convention — this is
  new territory, not a copy-paste of the harvester shape; (2) porting or reusing
  `cloudwatch_app_monitoring`'s scheduler/cron alarms for the `integrator` side; (3) deciding
  whether this stands alone now or waits for a `integrator-magnatech` stack.
- **Option B — AWS Secrets Manager with a custom rotation Lambda (Finding 8).** Matches the
  problem shape AWS itself designed this feature for, and gets atomic
  AWSCURRENT/AWSPENDING versioning for free. Costs adopting two things with no current
  precedent in this codebase at once (Secrets Manager rotation, and a general-purpose
  Lambda) versus Option A's single new piece (the write-back permission) on an otherwise
  familiar pattern.
- **Change-delivery axis (independent of A/B above) — poll by `dataAlteracao`/`dataAtualizacao`
  for orders and products (Finding 4); revisit webhooks only if a v3 capability is confirmed
  directly with Tiny (via `integracao@tiny.com.br` or equivalent), since no v3 webhook
  documentation was found (Finding 3).** Stock changes need a separate design decision, since
  `/estoque` has no bulk incremental-listing endpoint today.
- **client_credentials axis — test it directly once the `CLIENT_SECRET` is recovered
  (Finding 5), before designing the refresh job around the assumption that Authorization
  Code is the only option.** If it works, it removes the entire 24h-cliff/re-authorization
  problem class this spike and `PLAN.md` are otherwise built around; if it fails, the two
  options above stand as researched.
