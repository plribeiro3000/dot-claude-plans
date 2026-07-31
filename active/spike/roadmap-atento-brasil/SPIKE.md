# SPIKE — Atento Brasil Roadmap: PR-Sized Task Breakdown

## Investigation question

Break the six improvement requests raised in the 2026-07-22 meeting ("Pedidos de Melhorias
4Shark", Gustavo Bonilha / Jonathas Lins / Lucas Dala Rosa, Atento Brasil) into PR-sized
engineering tasks, each with: dependencies (and the reason for each), a day estimate with the
reasoning behind the size, ordered steps, the files it touches (`file:line`), and checkable
acceptance criteria. Estimates must be grounded in the actual code state of `app` and
`app-webclient` at `develop` HEAD (2026-07-30) — not the meeting notes alone. Item 1 (group
removal invalidation) is explicitly gated on a legal opinion (Danilo + Atento's legal) and
therefore carries a duration only, no start date. Items 4 (expanded declaration + signature
lock) and 5 (infinite scroll) were reported as already in progress/delivered and had to be
verified against the current code, not assumed. Item 6 (rule simulation) has no committed
date and needs to be sized so it can be placed or deliberately deferred. A cross-check against
the Barigui client's overlapping ask (collapse/expand + signature lock, opposite default per
profile) was also required.

## Sources consulted

- `~/Projects/4Shark/app` @ `611d5a5c8` (develop HEAD, 2026-07-30 12:05:38 -0300) — Rails backend, release `3.60.0` (2026-07-30) already in `CHANGELOG.md:22`, confirming the engineer's warning that `app/models/rule.rb` and neighbours shifted with this release; all line numbers below were read directly from these files on 2026-07-30, not carried over from memory.
- `~/Projects/4Shark/app-webclient` @ `f1920fb6b` (develop HEAD, 2026-07-30 12:49:23 -0300) — Angular front-end.
- `app/app/models/plan_statement.rb` — the declaration record and its `pending`/`accepted`/`canceled` state machine.
- `app/app/models/groupification.rb`, `app/app/models/group.rb`, `app/app/models/groupification_history.rb` — the group-membership model and its current removal-gating validation.
- `app/app/graphql_mutations/finish_groupification_graphql_mutation.rb`, `app/app/controllers/api/v3/groups/groupifications_controller.rb`, `app/app/policies/groupification_policy.rb` — the two removal entry points (GraphQL for the admin UI, REST for the integrator) and their authorization.
- `app/app/workers/groupification/processor.rb`, `app/app/workers/plan_statement/consumer.rb`, `app/app/workers/plan_statement/producer.rb`, `app/app/workers/plan/canceler.rb` — the background workers that regenerate or bulk-cancel `PlanStatement` rows; `Plan::Canceler` is the closest existing precedent for a bulk-invalidation worker.
- `app/app/models/plan_statement_dataset.rb` — the MongoDB (dashboard) mirror of `PlanStatement`'s status enum; any new status must be added symmetrically here.
- `app/app/models/plan_acceptment.rb`, `app/app/models/acceptment_reason.rb` — the existing "reason" pattern (a forced-acceptance justification) used as the closest precedent for the new invalidation-reason concept.
- `app/db/schema.rb:1408-1420` (`plan_acceptments`), `:1600-1615` (`plan_statements`), `:1626-1660` (`plans`, including `policy_document`) — current column shapes.
- `app/config/locales/pt-BR/models/groupification.yml` — confirms the exact wording of today's removal-blocking validation message (`date_after_or_equal_to`).
- `app/app/models/attachment.rb`, `app/app/models/banner_attachment.rb`, `app/app/models/signature.rb` — the two existing file-hosting patterns (polymorphic `Attachment` STI vs a dedicated base64-upload model); `Signature` is the closest precedent for item 2.
- `app/app/graphql_mutations/create_plan_graphql_mutation.rb`, `update_plan_graphql_mutation.rb`, `app/app/graphql_types/plan_graphql_type.rb`, `app/app/workers/plan_document/producer.rb`, `consumer.rb` — every current usage of the `policy_document` string/URL field.
- `app-webclient/src/app/plan/create/plan-create.component.html:356-359`, `plan/update/plan-update.component.html:339-342`, `plan/create/plan-create-form-builder.service.ts:67`, `plan/update/plan-update-form-builder.service.ts:63`, `plan/show/plan-show.component.html:85-89` — every front-end surface of `policyDocument` today.
- `app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.ts` and `.html` — the rule-declaration rendering/signing flow. Full copy preserved as auxiliary [`roadmap-atento-brasil_excerpt_1_plan-statement-show.component.ts`](./roadmap-atento-brasil_excerpt_1_plan-statement-show.component.ts).
- `app-webclient/src/app/statement/statement-show/statement-show.component.ts` — the result-declaration rendering/signing flow. Relevant excerpt preserved as auxiliary [`roadmap-atento-brasil_excerpt_2_statement-show-pagination.txt`](./roadmap-atento-brasil_excerpt_2_statement-show-pagination.txt).
- `app-webclient/CHANGELOG.md:17-134` — release history for the last two months, used to date what is already merged (1.281.0, 1.275.0) versus what is still `[Unreleased]`.
- `git -C app-webclient log --oneline -- .../plan-statement-show.component.ts` and `git show --stat` on commits `a174849a0` and `f2631bcc4` — the two commits that delivered item 4, used both as evidence and as a same-scale precedent for estimating item 3.
- `git -C app log --oneline -- app/models/rule.rb` and `Read app/app/models/rule.rb` — confirms the existing `Dentaku`-based formula engine (`Rule#calculate!`) as the reusable core for item 6.
- `app/app/models/rankifier_variable.rb`, `app/app/models/rankifier.rb` — the "tier" data (goal/cap/weight rows) referenced by item 3.
- `WebSearch`/community grounding was not needed for this spike — every claim below resolves against the two repositories' own code and git history.

## Findings

### Finding 1: the removal-blocking validation is a date constraint, not an outright block

**Evidence:**
```ruby
# app/app/models/groupification.rb:106-123
def finishing_date
  return if ends_at.nil?
  return if group.nil?

  today = Time.zone.today.beginning_of_day
  plan_ids = group.plans.joins(calendar: :periods).where(periods: { ends_at: ...today }).uniq
  user_plan_ids = user.plan_statements.where(plan_id: plan_ids).pluck(:plan_id).uniq
  period_ids = Plan.where(id: user_plan_ids).joins(calendar: :periods).pluck('periods.id')
  closed_period_ids = Period.where(id: period_ids).where(ends_at: ...today).uniq

  return if closed_period_ids.none?

  latest_period_ends_at = Period.where(id: closed_period_ids).maximum(:ends_at)

  return if ends_at >= latest_period_ends_at

  errors.add(:ends_at, :date_after_or_equal_to, date: I18n.l(latest_period_ends_at))
end
```
and the i18n message it raises:
```yaml
# app/config/locales/pt-BR/models/groupification.yml:22-27
ends_at:
  after: deve ser após a data de entrada
  blank: não pode ficar em branco
  date_after: "deve ser após %{count}"
  date_after_or_equal_to: "deve ser após ou igual a %{count}"
```

**Significance:** the current backend behavior is: if the user already has a `PlanStatement`
(declaration) tied to a *closed* period of any plan the group runs, `Groupification#finish`
(the "remove from group" action, reached from `FinishGroupificationGraphqlMutation` and from
`Api::V3::Groups::GroupificationsController#destroy`) rejects an `ends_at` earlier than that
closed period's end date — this is the "blocked for legal reasons" behavior the demand
describes. It is enforced as a validation error on `ends_at`, not as a hard "cannot remove at
all" rule, and it only fires when a *closed*-period declaration exists. There is no equivalent
check in the front-end (`app-webclient/src/app/group/finish/group-finish.component.ts:150-158`
only relays whatever server-side error key comes back generically), so the whole behavior — and
the whole redesign — lives in this one backend method and the model around it.

### Finding 2: no existing "invalidated" status, no existing reason/log association on `PlanStatement`

**Evidence:**
```ruby
# app/app/models/plan_statement.rb:27-34
enumerize :status,
          in: {
            pending: 0,
            accepted: 1,
            canceled: 2
          },
          default: :pending,
          scope: true
```
```
# app/db/schema.rb:1600-1615
create_table "plan_statements", id: :serial, force: :cascade do |t|
  t.bigint "company_id"
  t.datetime "created_at", null: false
  t.integer "owner_id"
  t.integer "plan_id"
  t.bigint "plan_statement_portable_batch_id"
  t.integer "status"
  t.datetime "updated_at", null: false
  t.integer "user_id"
  ...
```

**Significance:** the table has no reason/justification column and no free-text field of any
kind — a migration is required regardless of how the "reason" is modeled. The closest existing
precedent for a status-change reason is `AcceptmentReason` (`app/app/models/acceptment_reason.rb`),
a dedicated model with `name`/`description`/`key`, required by `PlanAcceptment` (`validates
:acceptment_reason, presence: true` at `app/app/models/plan_acceptment.rb:12`) whenever a
manager force-accepts a declaration on an employee's behalf. The same shape (a small,
company-scoped, named reason record, `belongs_to`'d from the record being changed) is the
natural analog for an "invalidation reason" on `PlanStatement`.

### Finding 3: the MongoDB dashboard mirror carries the identical status enum and must be updated symmetrically

**Evidence:**
```ruby
# app/app/models/plan_statement_dataset.rb:24-31 (Mongoid)
enumerize :status,
          in: {
            pending: 0,
            accepted: 1,
            canceled: 2
          },
          default: :pending,
          scope: true
```
and the worker that keeps both stores synchronized when a plan is bulk-canceled:
```ruby
# app/app/workers/plan/canceler.rb:7-15
def perform(plan_id)
  plan = Plan.with_uncached_connection { Plan.find(plan_id) }
  commission_ids = Commission.with_uncached_connection { plan.commission_ids }
  plan_statement_ids = PlanStatement.with_uncached_connection { plan.statements.pluck(:id) }

  PlanStatement.with_uncached_connection { PlanStatement.where(id: plan_statement_ids).update_all(status: 2) }
  PlanStatementDataset.in(plan_statement_id: plan_statement_ids).update_all(status: 2)
  StatementDataset.in(commission_id: commission_ids).update_all(status: 2)
end
```

**Significance:** `Plan::Canceler` is the direct precedent for "sweep every plan and mark
statements", but it is scoped to ONE plan (`plan_id`) and updates ONE status value in three
places (PostgreSQL `plan_statements`, Mongo `PlanStatementDataset`, Mongo `StatementDataset`).
The new item-1 worker is a step more complex: it starts from a *user leaving a group*, must
resolve every currently-active plan run by that group (not one plan_id passed in), and only the
declarations affected by the specific removal — the same three-store fan-out pattern applies,
so a new status value ripples through all three enums, not just `PlanStatement`'s.

### Finding 4: `PlanStatement::Consumer` uses `find_or_initialize_by` — a real resurrection risk for an "invalidated" statement

**Evidence:**
```ruby
# app/app/workers/plan_statement/consumer.rb:14-21
plan_statement =
  PlanStatement.with_uncached_connection do
    plan.statements.find_or_initialize_by(user_id: user_id)
  end

plan_statement.company_id = company.id
plan_statement.owner_id = owner_id
PlanStatement.with_uncached_connection { plan_statement.save! }
```

**Significance:** whenever `PlanStatement::Producer`/`Consumer` re-runs for a plan (triggered by
plan approval — see `app/app/workers/plan_statement/producer.rb:11` `return unless
plan.approved? && company.operator_legal_module?`), it looks up the statement by `user_id` alone
and re-saves it. If a statement was invalidated by the new item-1 flow, this existing worker
would find that same row and silently persist over it unless the new code explicitly guards
against re-activating an invalidated record. This is not a hypothetical edge case — the
happy-path plan-approval flow already calls this method for every user in the plan's group, so
it will run again for a user who was removed and later re-added, or whose invalidated
declaration predates a plan re-approval. This is a concrete technical risk to resolve during
task 1.2, not an incidental detail.

### Finding 5: `plan.policy_document` is a plain 8000-char string column, rendered as a raw hyperlink, with zero URL validation anywhere in the stack

**Evidence:**
```
# app/db/schema.rb:1626-1647 (plans table)
t.string "policy_document", limit: 8000
```
```ruby
# app/app/graphql_types/plan_graphql_type.rb:40
field :policy_document, String, null: true
```
```html
<!-- app-webclient/src/app/plan-statement/plan-statement-show/plan-statement-show.component.html:410-415 -->
<div *ngIf="planStatement?.plan.policyDocument">
  <small>{{ 'plan.policyDocument' | translate }}</small>
  <a [href]="planStatement.plan?.policyDocument" target="_blank">
    {{ 'plan.click_here' | translate }}
  </a>
</div>
```
```typescript
// app-webclient/src/app/plan/create/plan-create-form-builder.service.ts:67
private policyDocument = (value = ''): UntypedFormControl => new UntypedFormControl(value);
```

**Significance:** the field is a bare `<a href>` built directly from operator-entered text, with
no format validator on either side (backend `validates` list on `Plan`, lines 46-61 of
`app/app/models/plan.rb`, has no `policy_document` entry; the Angular form control above has no
validator array at all). This confirms the demand's premise precisely — the "policy" is a link
the employee's browser follows, which explains why a corporate network can block it. Replacing
it with a 4Shark-hosted, uploaded file removes the outbound link entirely.

### Finding 6: `Signature` is the closest existing precedent for a base64-uploaded, 4Shark-hosted, presigned-URL file — `Attachment` STI is the other, heavier option

**Evidence:**
```ruby
# app/app/models/signature.rb:1-38 (abbreviated)
class Signature < ApplicationRecord
  BASE64_REGEX = %r{\Adata:([-\w]+/[-\w+.]+)?;base64,(.*)}m
  attr_reader :base64_file
  belongs_to :acceptment, optional: true, inverse_of: :signature
  validate :file_presence
  validate :file_format
  mount_uploader :file, SignatureUploader

  def raw_file=(data)
    file_name = data[:name]
    @base64_file = data[:base64_content]
    ...
    self.file = temp_file
  end

  def presigned_url
    return if file.nil? || file.path.blank?
    Aws.connection.get_object_url(ApplicationConfiguration.aws_bucket, file.path, ...)
  end
end
```
versus the alternative, `Attachment` (STI, polymorphic, used for banners/reports/portable
exports):
```ruby
# app/app/models/attachment.rb:1-19 (abbreviated)
class Attachment < ApplicationRecord
  TYPES = %w[AuditAttachment BannerAttachment CommissionReportAttachment DocumentAttachment ...]
  belongs_to :attachable, polymorphic: true, optional: true
  validates :file, presence: { unless: :file_optional? }
  validates :type, presence: true, inclusion: { in: TYPES }
```

**Significance:** `Signature` is already invoked from exactly the code path this feature
touches — `PlanStatement#sign_by` (`app/app/models/plan_statement.rb:83-105`) builds a
`Signature` from `signature_attributes: { raw_file: { name:, base64_content: } }` at the moment
an employee accepts a declaration. Modeling the policy-document upload the same way (a small
dedicated model with `raw_file=`, `mount_uploader`, `presigned_url`) reuses a pattern the team
already has running in production on the very screen this feature changes, rather than
extending the more general-purpose but heavier `Attachment` STI (which would require adding a
new STI subtype to a shared `TYPES` array touched by unrelated features).

### Finding 7: items 4 and 5 are both already merged to `develop` — with one partial gap on item 4

**Evidence — item 4, rule declaration (plan-statement-show), signature lock:**
```typescript
// app-webclient/.../plan-statement-show.component.ts:275-277
readyToSign() {
  return this.allExpanded() && !this.loading;
}
```
confirmed via `git -C app-webclient log --oneline -- .../plan-statement-show.component.ts`:
commit `a174849a0` ("feat(declaration): add review-gated full-content view and honest
forced-acceptance rendering", 2026-07-20) introduced the gate, and `f2631bcc4` ("fix(declaration):
restore panel collapse during review and add expand-to-sign guidance", 2026-07-20) is the fix
that made the panels start collapsed for an admin and start pre-expanded only for the signer:
```typescript
// diff from f2631bcc4, plan-statement-show.component.ts
- if (this.planStatement.actions && this.planStatement.actions.includes('accept')) {
-   this.reviewing = true;
+ if (this.shouldExpandOnLoad || (this.planStatement.actions && this.planStatement.actions.includes('accept'))) {
+   this.expandPanels(true);
+ }
```
Both commits are already on `develop` HEAD (`f1920fb6b`), and `app-webclient/CHANGELOG.md:48-56`
(`## [1.281.0] - 2026-07-28`) lists the shipped entries: "Full-content view for the rule
declaration", "Full content review required before signing a declaration", "Guidance when a
declaration must be fully expanded to sign", and the follow-up fix "Panel collapse while
reviewing a declaration".

**Evidence — item 4, result declaration (statement-show), pagination-drain as the "scroll to
the end" equivalent:** see auxiliary
[`roadmap-atento-brasil_excerpt_2_statement-show-pagination.txt`](./roadmap-atento-brasil_excerpt_2_statement-show-pagination.txt) —
`allExpanded()` at line 991-993 requires `paginationDrained()` (every commissioning list fully
paged) in addition to every panel expanded.

**Evidence — item 5, infinite scroll:**
```
# app-webclient/CHANGELOG.md:129-130 (## [1.275.0] - 2026-07-06)
- Infinite scroll on payment type, plan acceptment, plan document, plan goal audit, plan participation approval batch, plan participation, plan, and plan rollback listings
- Infinite scroll on plan statement audit, plan statement, product document, product, rankifier incentives, rankifier, redemption incentives, and responsible audit listings
```
confirmed live in the main plan-statement listing:
```html
<!-- app-webclient/src/app/plan-statement/plan-statement.component.html:210-216 -->
<app-scroll-container
  [more]="hasMore()"
  [scrollOffset]="2500"
  [scrollDelay]="3000"
  (scrolled)="handleScroll($event)"
  class="scroll-container"
>
```
A repo-wide search for `mat-paginator`/`MatPaginator` (the classic, page-button paginator this
release replaced) returned zero matches in `app-webclient/src/app` — nothing was left on the
old pattern.

**Significance:** items 4 and 5 need no further engineering — both are fully merged to
`develop` and already released (1.281.0 and 1.275.0 respectively, both dated before today).
The ONE partial gap: on the rule-declaration side (plan-statement-show), "fully expanded" is
gated only by `allExpanded()` (every incentive panel expanded) — there is no scroll-position or
pagination-drain equivalent, because the rule declaration's incentives arrive in a single
GraphQL response with no pagination at all (see the query in auxiliary
[`roadmap-atento-brasil_excerpt_1_plan-statement-show.component.ts`](./roadmap-atento-brasil_excerpt_1_plan-statement-show.component.ts),
lines 59-137 — no `pageInfo`/`endCursor` on the `incentives` field). The demand's literal words
("expands everything and scrolls to the end") are satisfied on the result-declaration side by an
equivalent-or-stronger mechanism (pagination drain) but are satisfied on the rule-declaration
side only by "everything expanded" — there is nothing left to scroll to, since nothing is
paginated there.

### Finding 8: item 3's "tiers" are `RankifierVariable` rows, rendered today as a plain table with no distinct visual treatment

**Evidence:**
```html
<!-- app-webclient/.../plan-statement-show.component.html:219-249 (ranking incentive panel) -->
<div class="list" *ngIf="rankingIncentive?.rankifier?.rankifierVariables.length > 0">
  <div class="list-header">
    <span class="column-xl">{{ 'variable.one' | translate }}</span>
    <span class="column-l">{{ 'rankifier_variable.comparator' | translate }}</span>
    ...
  </div>
  <div *ngFor="let variable of rankingIncentive.rankifier.rankifierVariables" class="list-item">
    ...
  </div>
</div>
```
```ruby
# app/app/models/rankifier_variable.rb:3-5
class RankifierVariable < ApplicationRecord
  belongs_to :rankifier, optional: true, inverse_of: :rankifier_variables
  belongs_to :variable, optional: true, inverse_of: :rankifier_variables
```

**Significance:** a "tier" (a goal/cap/weight row within a ranking incentive) is already a
first-class, queryable model (`RankifierVariable`) — no backend change is needed for item 3;
the columns the demand wants distinguished (incentive type headers already exist as `<h4
class="middle-title">` per type; tiers are the `list-item` rows inside a ranking incentive
panel) already carry the raw data, so this is a front-end-only presentational task. The
"introductory text explaining how the rule works in plain language" has no existing field or
copy anywhere in the codebase — this is the one open point in this item (see Uncertain, below).

### Finding 9: no existing simulation feature — but the formula-evaluation engine it would need already exists and is shared across every rule type

**Evidence:**
```ruby
# app/app/models/rule.rb:12,58-66 (release 3.60.0, 2026-07-30)
TYPES = %w[FormulaRule IndicatorRule LimiterRule RankingRule RedemptionRule].freeze
...
def calculate(options = {})
  calculate!(options)
rescue *PARSE_EXCEPTIONS => _e
  0
end

def calculate!(options = {})
  Dentaku!(value, cast_values(options)).to_f
end
```
and the existing use of this same method with *synthetic* random inputs, purely to smoke-test
formula syntax at save time:
```ruby
# app/app/models/rule.rb:76-98 (formula_syntax, one of five per-type variants)
def formula_syntax
  validate_syntax(
    statuses_options
        .merge(metrics_options)
        .merge(deal_extra_fields_options)
        .merge(
          dias_em_aberto: rand(1..30),
          estado: 'executed',
          ...
        )
  )
end
```
A repository-wide search for "simulat" (case-insensitive) across both `app/app` and
`app-webclient/src/app` returned zero matches.

**Significance:** there is genuinely no existing simulation feature — item 6 is greenfield —
but `Rule#calculate!` is already the exact evaluation primitive a simulator needs: it accepts a
hash of variable values and returns a numeric result via the `Dentaku` formula engine, and it
already works identically across all five rule types (`FormulaRule`, `IndicatorRule`,
`LimiterRule`, `RankingRule`, `RedemptionRule`). What does NOT exist is (a) a UI to let an
engineer/manager input sample values, (b) a resolved, user-facing taxonomy of which variables a
given company's rules expect (today that taxonomy is scattered across five private methods —
`statuses_options`, `metrics_options`, `deal_extra_fields_options`, `indicator_variables_options`,
`easy_variables_options` — each building its keys from `company.statuses`/`company.variables`
at random-value-fill time, not from any documented schema), and (c) a decision on whether
simulation targets one rule, one incentive (chaining several rules), or a whole plan.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Item 1 — new `invalidated` status (0-3) vs reusing `canceled` (2) with a reason record | New status keeps "the company removed you" distinguishable from "you canceled/were canceled for another reason" in every listing, stat, and export that already branches on status | Every place that already special-cases `status: 2` (`Plan::Canceler`, `PlanStatementDataset`, `StatementDataset`, dashboards) must be re-audited for whether "invalidated" should be swept into the same bucket or kept separate | `app/app/workers/plan/canceler.rb:12-14`, `app/app/models/plan_statement_dataset.rb:24-31` |
| Item 1 — validation-loosening in `Groupification#finish` (current) vs a separate explicit "invalidate declarations" step called from the sweep worker | Keeping `finish` free of side effects on `PlanStatement` keeps the groupification-lifecycle code focused; the sweep worker becomes the one place that decides which declarations to touch | The current `finishing_date` validation is the ONLY thing enforcing the legal constraint today; removing it without the sweep replacing its guarantee leaves a window where an unprotected removal could occur before the invalidation logic ships | `app/app/models/groupification.rb:106-123` |
| Item 2 — dedicated model (`Signature`-shaped) vs `Attachment` STI subtype | Dedicated model matches the exact precedent already used on the same screen (`PlanStatement#sign_by`); no changes to the shared `Attachment::TYPES` array used by unrelated features | `Attachment` already has `presigned_url`, `maximum_file_size`, and an expiry/state machine (`processing`→`final`→`expired`) that a dedicated model would have to reimplement or do without | `app/app/models/signature.rb:1-63`, `app/app/models/attachment.rb:1-132` |
| Item 3 — static per-incentive-type intro copy (i18n only) vs a new configurable per-plan rich-text field | i18n-only ships fast with zero backend/migration work | Static copy cannot express a company- or plan-specific policy nuance; a configurable field requires a migration + form + display wiring, closer in shape to item 2 | `app-webclient/src/translations/*/models/plan.json` (not modified by either option as evidenced, but the natural home for i18n copy) |
| Item 6 — simulate a single rule vs a whole incentive vs a whole plan | A single-rule simulator is a thin, low-risk wrapper directly over `Rule#calculate!` | A whole-plan simulation would need to resolve every rule's required variables per company (today scattered across five private methods in `Rule`, not a documented schema) before any UI could ask the right questions | `app/app/models/rule.rb:76-225` |

## What remains uncertain

- Whether "invalidated" should be a new `PlanStatement` status value (and its `PlanStatementDataset`/`StatementDataset` mirror) or a `canceled` status plus a new reason record that only differs by *why* — this changes every downstream query/report that branches on status.
- Whether the sweep, when a user leaves ONE group, should touch only that group's plans or also plans the user reaches through any other group they remain in — `Plan#user_ids` (`app/app/models/plan.rb:170-187`) resolves membership through `Groupification`/`GroupificationHistory` per plan's own `group_id`, so a user in two groups feeding overlapping plans is a case the sweep's scope must explicitly decide.
- How the new sweep worker interacts with the resurrection risk in `PlanStatement::Consumer` (Finding 4) — whether the guard belongs in the `Consumer`, in a new `invalidated?` early-return, or in the state machine's transition rules.
- What "scroll to the end" should mean concretely for the rule-declaration side (plan-statement-show), given there is nothing paginated there to drain (Finding 7) — whether the demand is satisfied as-is by "all panels expanded", or whether a literal scroll-position listener is still wanted for a very long single-page declaration.
- The exact content and ownership of the item-3 introductory text — static i18n copy per incentive type, or a new plan-level configurable field (see Trade-offs).
- Whether the Barigui "opposite default per profile" ask is a per-company configuration toggle layered on top of the same `readyToSign()`/`allExpanded()` mechanism, or a conflicting requirement that needs product-level reconciliation before either client's variant ships — no code or plan document was found describing Barigui's version of this ask (a plans-repo and git-log search for "Barigui" found only an unrelated LGPD-compliance workstream, not this feature).
- Item 6's scope (single rule vs incentive vs plan simulation, and whether it must be multi-tenant/company-aware from day one) is undefined by the demand itself ("no date committed") and by the codebase (zero existing simulation code) — the task below is sized as a discovery spike, not an implementation.

## Suggested options for main and the engineer

The breakdown below is descriptive decomposition, not a recommendation of order — the engineer
chooses sequencing, scope splits, and which open questions (above) to resolve before work
starts. Every day estimate names what makes it that size; none are round numbers picked without
a reason.

### Item 1 — group removal → declaration invalidation (BLOCKED on legal opinion; duration only)

This entire item cannot get a start date: the demand states it is waiting on Danilo and
Atento's legal team to confirm the invalidation approach satisfies the same legal concern that
today's `finishing_date` validation exists for. The three tasks below are sequential once
unblocked.

**Task 1.1 — data model: invalidation reason + status.**
- Steps: (1) generate a migration adding the new status value to `plan_statements` (either a
  bare `invalidated` enum member, or a new `plan_statement_invalidation_reasons` table modeled
  on `acceptment_reasons` — pending the open question above); (2) mirror the same status value
  into `PlanStatementDataset` (`app/app/models/plan_statement_dataset.rb:24-31`) and, if
  `StatementDataset` also branches on this status (per `Plan::Canceler`'s third `update_all`),
  there too; (3) expose the new reason via `PlanStatementGraphqlType`
  (`app/app/graphql_types/plan_statement_graphql_type.rb`, `status` is already a plain `String`
  field, so no type change needed for the status itself — only for the reason association).
- Files touched: a new `db/migrate/*.rb`, `db/schema.rb`, `app/app/models/plan_statement.rb:27-34`,
  `app/app/models/plan_statement_dataset.rb:24-31`, a new reason model (if chosen) modeled on
  `app/app/models/acceptment_reason.rb`, `app/app/graphql_types/plan_statement_graphql_type.rb`.
- Dependencies: none (first task in the sequence).
- Acceptance criteria: a `PlanStatement` can be set to the new status with a required reason
  attached; the reason is queryable over GraphQL; `bin/rails db:migrate` runs clean; the
  Mongoid mirror accepts the same status value without raising.
- Estimate: **1–1.5 days.** Reasoning: `AcceptmentReason` (the direct precedent) is a ~25-line
  model plus a migration plus a `belongs_to`/`has_many` wire-up on one existing model
  (`app/app/models/plan_acceptment.rb:8,12`) — this task is the same shape, on two models
  (`PlanStatement` in Postgres, `PlanStatementDataset` in Mongo) instead of one, hence the top of
  the range rather than a straight copy of that precedent's size.

**Task 1.2 — backend: sweep worker + validation change + Consumer guard.**
- Steps: (1) replace or relax `Groupification#finishing_date`
  (`app/app/models/groupification.rb:106-123`) so it no longer blocks the `ends_at` date; (2)
  add a new worker (named for its topology per `DATA-PROCESSING.md` — likely a `Processor`,
  since it is one bounded sweep per groupification-finish event, not a fan-out) that, given a
  finished `Groupification`, resolves every currently-active plan reachable through the group
  (mirroring `Plan::Canceler`'s `plan.statements.pluck(:id)` shape, but sourced from
  `group.plans` instead of a single `plan_id`) and updates the affected `PlanStatement` rows to
  the new status with the reason, instead of `Plan::Canceler`'s bare `update_all(status: 2)`;
  (3) add a guard in `PlanStatement::Consumer` (`app/app/workers/plan_statement/consumer.rb:14-21`)
  so `find_or_initialize_by(user_id:)` does not silently resurrect an invalidated row (Finding 4).
- Files touched: `app/app/models/groupification.rb:106-123`, a new
  `app/app/workers/groupification/invalidator.rb` (or similarly named), `app/app/workers/plan_statement/consumer.rb:14-21`,
  request specs mirroring `app/spec/requests/graphql_mutations/graphql_controller_finish_groupification_spec.rb` and
  `app/spec/requests/api/v3/groups/groupifications_controller_spec.rb`.
- Dependencies: Task 1.1 (the status/reason must exist before anything can set it).
- Acceptance criteria: removing a user from a group no longer raises the `date_after_or_equal_to`
  validation error; every `PlanStatement` for that user, on every currently-active plan the
  group runs, tied to the removal, moves to the new status with a reason recorded; no
  `PlanStatement` row is ever `destroy`ed by this flow; re-running `PlanStatement::Consumer` for
  the same user/plan does not revert an invalidated statement back to `pending`/`accepted`.
- Estimate: **3–4 days.** Reasoning: this is the highest-risk task in the whole roadmap —
  unlike `Plan::Canceler` (17 lines, one `plan_id` in, one status out, three flat `update_all`
  calls), this worker must first *resolve* which plans and periods are affected starting from a
  group + user (not from a single known `plan_id`), respect the existing `Lock.acquire` /
  `RaceConditionException` concurrency pattern already present in `Groupification#start`/`#finish`
  (`app/app/models/groupification.rb:54-94`), and close the resurrection gap in Finding 4 —
  three genuinely separate pieces of logic, each touching a different worker/model.

**Task 1.3 — front-end: surface the new status.**
- Steps: (1) add a translation + badge treatment for the new status alongside the existing
  `pending`/`accepted`/`canceled` badges in `plan-statement-show.component.html:68-80`; (2) add
  the new status to the plan-statement listing's status filter/statistics block
  (`app-webclient/src/app/plan-statement/plan-statement.component.html:200-206` pattern,
  mirrored for the new bucket); (3) surface the reason text wherever the acceptment reason is
  already shown (`plan-statement-show.component.html:401-405` pattern).
- Files touched: `plan-statement-show.component.html`, `plan-statement.component.html`,
  `plan-statement.component.ts`, translation JSON files under `src/translations/{en,es,pt-BR}/models/plan_statement.json`.
- Dependencies: Task 1.1 (GraphQL field must exist) and, for the reason text specifically, the
  reason association from Task 1.1.
- Acceptance criteria: an invalidated declaration shows a distinct badge and its reason in the
  UI, in all three shipped languages; the listing's status filter/stat block includes the new
  bucket without breaking the existing percentage math.
- Estimate: **1–1.5 days.** Reasoning: same scale as commit `a174849a0` (Finding 7) — that
  merged front-end-only change touched 17 files (2 components × ts+html, 15 translation files)
  for ~230 net lines; this task touches fewer components (no `statement-show` equivalent, since
  invalidation is specific to group-fed declarations) but the same three-language translation
  fan-out.

**Item 1 total: 5.5–6.5 engineering days, sequential, no start date until the legal opinion lands.**

### Item 2 — policy document as an uploaded, hosted file

**Task 2.1 — backend: model + migration + GraphQL wiring.**
- Steps: (1) generate a migration adding a `plan_policy_documents` table (or equivalent) and
  dropping/deprecating `plans.policy_document` (`app/db/schema.rb:1647`); (2) build the new
  model on the `Signature` shape (Finding 6): `raw_file=` accepting base64, `mount_uploader`, a
  `presigned_url` method; (3) wire it into `Plan` (`belongs_to`/`has_one`); (4) update
  `CreatePlanGraphqlMutation`/`UpdatePlanGraphqlMutation`
  (`app/app/graphql_mutations/create_plan_graphql_mutation.rb:12,40`,
  `update_plan_graphql_mutation.rb:13,39`) to accept the new nested attributes instead of the
  bare string, and update `PlanGraphqlType` (`app/app/graphql_types/plan_graphql_type.rb:40`) to
  expose a `policy_document_url` (presigned) field instead of the raw string; (5) decide the
  migration path for existing plans that already have a URL in `policy_document` (keep the old
  column readable/deprecated vs a data migration — open question, not resolved by this spike).
- Files touched: new `db/migrate/*.rb`, new model + uploader (2 files, mirroring
  `app/app/models/signature.rb` + its uploader), `app/app/models/plan.rb`,
  `create_plan_graphql_mutation.rb`, `update_plan_graphql_mutation.rb`, `plan_graphql_type.rb`,
  `app/app/workers/plan_document/producer.rb:53,91,143` and `consumer.rb:98` (the bulk
  spreadsheet import path also reads/writes `policy_document` and needs the same shape change).
- Dependencies: none (first task).
- Acceptance criteria: creating/updating a plan accepts a base64 file instead of a URL string;
  the file is retrievable only via a time-limited presigned URL; the bulk plan-import
  spreadsheet flow (`PlanDocument::Producer`/`Consumer`) still round-trips a policy document
  correctly for the same column in its own CSV-backed `plan_document_rows` table
  (`app/db/schema.rb:1422-1441`).
- Estimate: **2–2.5 days.** Reasoning: `Signature` itself is ~80 lines plus an uploader; this
  task additionally touches two existing GraphQL mutations, one GraphQL type, and the bulk
  spreadsheet-import worker pair that also reference the same field — more integration surface
  than `Signature`'s single call site (`PlanStatement#sign_by`).

**Task 2.2 — front-end: upload widget on plan create/update.**
- Steps: (1) replace the bare `<input type="text">` (`plan-create.component.html:356-359`,
  `plan-update.component.html:339-342`) with a file-upload control that reads the selected
  file and base64-encodes it, following whatever pattern the existing signature-capture flow
  uses on the accept-declaration screens; (2) update both form-builder services
  (`plan-create-form-builder.service.ts:67`, `plan-update-form-builder.service.ts:63` — both
  currently a bare `new UntypedFormControl(value)` with no validators) to validate file
  type/size instead of the string it held before.
- Files touched: the two component `.html`/`.ts` pairs and the two form-builder services above.
- Dependencies: Task 2.1 (the mutation shape must accept the new payload before the form can
  send it).
- Acceptance criteria: an operator can attach a PDF or image when creating or editing a plan;
  the existing plan (edit mode) shows the currently-attached file, not a blank field; invalid
  file types/sizes are rejected client-side with a translated message.
- Estimate: **1.5–2 days.** Reasoning: two near-identical forms (create + update) need the same
  widget, each requiring its own template + form-builder change, plus error-state UI that does
  not exist today (the current field has zero validators to build from).

**Task 2.3 — front-end: render the hosted file instead of the raw link.**
- Steps: (1) replace the direct `<a [href]="planStatement.plan?.policyDocument">` in
  `plan-statement-show.component.html:410-415` with a call to the new presigned-URL field,
  shown before the accept button per the demand ("shown at the start of the declaration before
  the employee accepts"); (2) do the same for the read-only display in
  `plan-show.component.html:85-89`.
- Files touched: `plan-statement-show.component.html:410-415`, `plan-statement-show.component.ts`
  (a small method to fetch the presigned URL, mirroring `getSignature()` at lines 226-240 of the
  same file), `plan-show.component.html:85-89`.
- Dependencies: Task 2.1 (the GraphQL field must exist).
- Acceptance criteria: the employee sees the policy document (PDF/image) presented before
  signing, served from a 4Shark-hosted, time-limited URL — never the operator-entered string
  that exists today.
- Estimate: **0.5–1 day.** Reasoning: two small, localized template changes plus one small
  fetch method, directly mirroring the already-existing `getSignature()` pattern in the same
  file (lines 226-240) — the smallest task in this item.

**Item 2 total: 4–5.5 engineering days.** 2.2 and 2.3 can run in parallel once 2.1 is merged,
since they touch disjoint files.

### Item 3 — declaration readability

**Task 3.1 — visual separation of incentive types and tiers.**
- Steps: (1) restructure the incentive-type sections (`plan-statement-show.component.html:115-374`,
  currently five near-identical `<ng-container>` blocks, one per incentive type) with stronger
  visual differentiation (color/iconography per type, not just an `<h4>` label); (2) restructure
  the ranking-incentive tier table (`plan-statement-show.component.html:219-249`) so each tier
  row (`RankifierVariable`) is visually distinguishable from the next, not just a plain
  `list-item` row.
- Files touched: `plan-statement-show.component.html:115-374`, `plan-statement-show.component.scss`.
- Dependencies: none, but shares the same file as Task 1.3's status-badge work
  (`plan-statement-show.component.html`) — if both are worked concurrently on separate
  branches, expect a merge/rebase coordination point, not a functional dependency.
- Acceptance criteria: an employee can visually distinguish incentive types and tiers within a
  type without reading every row's text first (a qualitative UX criterion — the engineer/product
  owner signs off on the visual design, since no numeric threshold applies).
- Estimate: **1.5–2 days.** Reasoning: same file and comparable restructuring scope to commits
  `a174849a0`/`f2631bcc4` (Finding 7), which together changed ~60 lines of this same template
  for a comparably-scoped visual/behavioral change.

**Task 3.2 — introductory explanatory text.**
- Steps: contingent on the open question in Trade-offs. **If static i18n copy per incentive
  type**: (1) add a new translation key per incentive type under
  `src/translations/*/models/plan_statement.json` (or a new `incentive.json` section); (2)
  render it above each incentive-type section in `plan-statement-show.component.html`. **If a
  configurable per-plan field**: this becomes a fourth task shaped like Task 2.1/2.2/2.3
  (migration + form + display), not a same-day addition to 3.1.
- Files touched (static-copy path): `plan-statement-show.component.html`, three translation
  JSON files.
- Dependencies: the open decision itself (this spike does not resolve which path applies).
- Acceptance criteria: an employee sees plain-language guidance on how the incentive rule works
  before the rule's raw formula/table detail.
- Estimate: **0.5–1 day (static copy) or ~2 additional days (configurable field, folding in a
  migration + form + display — same shape as item 2's three tasks, at smaller scale since it is
  a single text field, not a file upload).** Reasoning: the static-copy path is pure content +
  template work with no backend touch; the configurable-field path repeats item 2's
  migration/form/display shape but without the base64/uploader complexity, hence roughly half
  of item 2's total.

**Item 3 total: 2–4 engineering days**, depending on which Task 3.2 path is chosen.

### Item 4 — expanded declaration + signature lock: verification only, one small optional follow-up

No implementation task — Finding 7 confirms both the rule-declaration and result-declaration
sides are fully merged and released (1.281.0, plus the `f2631bcc4` fix, both on `develop`
before this spike started). The one gap: the rule-declaration side has no "scroll to the end"
mechanism because it has nothing paginated to drain (Finding 7). If the engineer decides the
literal demand wording still needs a scroll-position listener on top of "all panels expanded" —
**optional task, 0.5–1 day**, reasoning: a single scroll-listener addition to one existing
component, no backend change, smallest possible front-end task in this roadmap.

### Item 5 — infinite scroll: verification only, no task

Finding 7 confirms full coverage (CHANGELOG 1.275.0, zero remaining `mat-paginator` usages
repo-wide). No task.

### Item 6 — rule simulation: discovery spike, not an implementation estimate

Given zero existing simulation code (Finding 9) and no committed date, this is sized as a
**discovery spike of 2–3 days**, not an implementation task — implementation cannot be
estimated honestly until the spike answers: (a) single-rule vs whole-incentive vs whole-plan
scope; (b) how to surface, per company, the variable taxonomy that today lives only inside
`Rule`'s five private `*_options` methods (`app/app/models/rule.rb:187-225`); (c) whether
`Rule#calculate!` (already multi-tenant-safe, since it always reads `incentive.company` for its
variable set) is reused as-is or wrapped. Reasoning for the 2–3 day size: the spike's job is
narrowly to resolve (a)-(c) against the existing `Rule#calculate!`/`Dentaku` engine (Finding 9),
not to design the whole UI — a comparable-scope investigation to this document itself.
