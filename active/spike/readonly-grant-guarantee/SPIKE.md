# SPIKE — Guaranteeing Readonly-Role SELECT Grants on New Tables

## Investigation question

`app` (Rails 8.1, Aurora PostgreSQL 16) runs a primary/replica split in productive environments. Migrations run as the table-owning role (a different role per environment); reads go through a separate readonly role. `pg_default_acl` is empty in `shared-001` production, so every `create_table` produces a table the readonly role cannot `SELECT` — a failure that is silent until a web/GraphQL read hits the table and returns HTTP 500. Eleven tables had accumulated this gap in `shared-001` before being fixed by hand; a fourth-environment env var (`DATABASE_READONLY_USERNAME`) was found to carry the wrong value in `atento-001` and the engineer has decided to drop that env var entirely.

Two questions:

- **Q1** — How do we guarantee the grant exists for every table created from now on, without depending on an engineer remembering to hand-write a grant migration, and without depending on `DATABASE_READONLY_USERNAME`?
- **Q2** — How do we guarantee a newly created environment (a future third master+follower stack) starts out correct, so the gap does not silently reappear there?

## Sources consulted

- [PostgreSQL 16 docs — ALTER DEFAULT PRIVILEGES](https://www.postgresql.org/docs/16/sql-alterdefaultprivileges.html) — retroactivity, `FOR ROLE` semantics, per-schema scope, syntax
- [PostgreSQL 16 docs — Predefined Roles](https://www.postgresql.org/docs/16/predefined-roles.html) — `pg_read_all_data` description
- [Percona — Dispelling Myths About PostgreSQL Default Privileges](https://www.percona.com/blog/dispelling-myths-about-postgresql-default-privileges/) — `FOR ROLE` scoping, common misconception
- [Crunchy Data — Creating a Read-Only Postgres User](https://www.crunchydata.com/blog/creating-a-read-only-postgres-user) — `ALTER DEFAULT PRIVILEGES` creator-role limitation, `pg_read_all_data` as an alternative
- [GitLab infrastructure issue #3890 — "New tables don't get permissions of read-only users"](https://gitlab.com/gitlab-com/infrastructure/issues/3890) — the same production failure documented at another organization
- [VeloDB docs — Aurora RDS PostgreSQL Source Setup](https://docs.velodb.io/cloud/4.x/integration/data-source/postgres-cdc/aurora-rds) — granting `pg_read_all_data` on Aurora RDS
- [`ankane/strong_migrations` README (GitHub)](https://github.com/ankane/strong_migrations) — `StrongMigrations.add_check` custom-check mechanism, `safety_assured`
- `~/Projects/4Shark/app/db/migrate/2025/04/20250415161945_add_select_permission_to_signatures.rb` — existing ad-hoc grant migration shape
- `~/Projects/4Shark/app/lib/application_configuration.rb:261-263` — `pg_primary_readonly_username` reads `DATABASE_READONLY_USERNAME`
- `~/Projects/4Shark/app/config/database.yml` — primary/replica role selection
- `~/Projects/4Shark/terraform/modules/atento_001_task_config/main.tf:18`, `~/Projects/4Shark/terraform/modules/shared_001_task_config/main.tf:19` — the hardcoded, identical `DATABASE_READONLY_USERNAME` value across both stacks
- `~/Projects/4Shark/app/vendor/bundle/ruby/4.0.0/gems/strong_migrations-2.7.0/lib/strong_migrations/checker.rb:36-103` — how custom checks actually dispatch
- `~/Projects/4Shark/app/config/initializers/strong_migrations.rb` — current initializer (no custom checks configured)
- `~/Projects/4Shark/app/.github/workflows/ci.yaml:21-26` — CI Postgres container setup
- `~/Projects/4Shark/terraform/app-shared-001/rds.tf` — no role/grant management in the RDS stack
- `~/.claude/docs/runbooks/INDEX.md` — no runbook for provisioning a new productive app stack's DB roles

## Findings

### Finding 1: `ALTER DEFAULT PRIVILEGES` is not retroactive

**Evidence:** "ALTER DEFAULT PRIVILEGES allows you to set the privileges that will be applied to objects created in the future. (It does not affect privileges assigned to already-existing objects.)"
**Source:** https://www.postgresql.org/docs/16/sql-alterdefaultprivileges.html
**Significance:** Confirms the given incident fact (#4) directly from the primary source: setting this up today does nothing for the eleven tables already fixed by hand, and does nothing for any table that already exists uncovered. It only prevents the gap on tables created *after* the statement runs.
**Verification:** URL fetched 2026-07-27 / verbatim quote checked / quote substring confirmed at the "Description" section of the fetched page.

### Finding 2: `FOR ROLE` targets the object-creating role, defaulting to "current role"

**Evidence:** "Change default privileges for objects created by the target_role, or the current role if unspecified."
**Source:** https://www.postgresql.org/docs/16/sql-alterdefaultprivileges.html
**Significance:** The default privilege entry is keyed by *who creates the table*, not by who will read it. If the bootstrap statement omits `FOR ROLE`, it applies only to tables created by whichever role executed the `ALTER DEFAULT PRIVILEGES` statement itself — which may not be the migration-running role at all (e.g., if an admin/master user runs the bootstrap by hand). This is the exact mechanism behind the given incident fact that the bulk grant was not retroactive and did not "stick" for future tables: the historical bulk `GRANT SELECT ON ALL TABLES` was a one-time ACL grant, not a default-privilege entry, so it never covered future `create_table` calls regardless of role.
**Verification:** URL fetched 2026-07-27 / verbatim quote checked / quote substring confirmed at the "Description" section of the fetched page.

### Finding 3: Default privileges do not propagate through role membership

**Evidence:** "While you can change your own default privileges and the defaults of roles that you are a member of, at object creation time, new object permissions are only affected by the default privileges of the current role, and are not inherited from any roles in which the current role is a member."
**Source:** https://www.postgresql.org/docs/16/sql-alterdefaultprivileges.html
**Significance:** If, in a given environment, table creation is ever performed by a role that is a *member of* the writer role (rather than the writer role itself — e.g., an admin console session), the default privilege set `FOR ROLE <writer>` does not apply to what that session creates, even though the session might have write access via membership. This is a candidate failure mode for the "different creating role" gotcha the investigation asked to identify.
**Verification:** URL fetched 2026-07-27 / verbatim quote checked / quote substring confirmed at the "Description" section of the fetched page.

### Finding 4: Default privileges are global or per-schema, and per-schema entries add to (not replace) global ones

**Evidence:** "Privileges can be set globally (i.e., for all objects created in the current database), or just for objects created in specified schemas." and "Default privileges that are specified per-schema are added to whatever the global default privileges are for the particular object type. This means you cannot revoke privileges per-schema if they are granted globally... Per-schema REVOKE is only useful to reverse the effects of a previous per-schema GRANT."
**Source:** https://www.postgresql.org/docs/16/sql-alterdefaultprivileges.html
**Significance:** A schema-scoped `IN SCHEMA public` grant and a global (no `IN SCHEMA`) grant are not interchangeable, and mixing them creates asymmetric revoke behavior. Whichever option is adopted needs to pick one scope and be consistent about it — a later attempt to narrow a global grant down to a specific schema via a per-schema `REVOKE` will not work as expected.
**Verification:** URL fetched 2026-07-27 / verbatim quote checked / quote substring confirmed at the "Description" and "Notes" sections of the fetched page.

### Finding 5: `FOR ROLE` accepts a comma-separated list of roles in one statement

**Evidence:** Syntax synopsis: `ALTER DEFAULT PRIVILEGES [ FOR { ROLE | USER } target_role [, ...] ] [ IN SCHEMA schema_name [, ...] ] abbreviated_grant_or_revoke`
**Source:** https://www.postgresql.org/docs/16/sql-alterdefaultprivileges.html
**Significance:** If a single database ever sees table creation from more than one role (e.g., the migration-running role and a separately-authenticated admin), one statement can name all of them: `FOR ROLE writer_a, writer_b`. This does **not** help across environments — `shared-001` and `atento-001` are separate databases/clusters, each needing its own bootstrap statement naming that environment's own writer role — it only helps when multiple distinct roles create tables *within the same database*.
**Verification:** URL fetched 2026-07-27 / verbatim quote checked / quote substring confirmed at the "Synopsis" section of the fetched page.

### Finding 6: Community confirmation that `FOR ROLE` scoping is a frequent point of confusion

**Evidence:** "the default permission only works if the object creator is the same as the executor of the `ALTER DEFAULT PRIVILEGES` statement (by default, the current user, in this case, postgres)." and "Many users assume that as we have granted the default permissions, it will always work no matter who the object creator is." and "**FOR ROLE** clause is particularly useful in environments where multiple roles create objects, and each role has its own set of users with specific access requirements."
**Source:** https://www.percona.com/blog/dispelling-myths-about-postgresql-default-privileges/
**Significance:** Independent corroboration (Percona, a PostgreSQL support vendor) that the creator-role coupling documented in the official docs (Findings 2–3) is the most common way teams get this wrong in practice — reinforcing that whatever bootstrap statement is chosen for Q1/Q2 must be run once per environment, explicitly naming that environment's writer role.
**Verification:** URL fetched 2026-07-27 / verbatim quote checked / quote substring confirmed in the article body under the sections on default-privilege scoping.

### Finding 7: `ALTER DEFAULT PRIVILEGES` only ever covers the role that ran it — confirmed independently

**Evidence:** "ALTER DEFAULT PRIVILEGES only work for the user that is creating the objects" and "With ALTER DEFAULT PRIVILEGES, the role that creates the objects will assign the privileges for those objects. This means that if a different user were to create a new table, [the readonly role] would not be able to access it."
**Source:** https://www.crunchydata.com/blog/creating-a-read-only-postgres-user
**Significance:** A second independent source restating Findings 2/6 in operational terms, from a team that hit the same limitation while automating a scraper's readonly access. Reinforces that this is a well-known, cross-project limitation of the `ALTER DEFAULT PRIVILEGES` approach, not something specific to 4Shark's setup.
**Verification:** URL fetched 2026-07-27 / verbatim quote checked / quote substring confirmed in the article body.

### Finding 8: `pg_read_all_data` grants read access independent of who created the object

**Evidence:** "Read all data (tables, views, sequences), as if having `SELECT` rights on those objects, and USAGE rights on all schemas, even without having it explicitly. This role does not have the role attribute `BYPASSRLS` set. If RLS is being used, an administrator may wish to set `BYPASSRLS` on roles which this role is GRANTed to."
**Source:** https://www.postgresql.org/docs/16/predefined-roles.html
**Significance:** This is a *membership-based* privilege, not an ACL entry attached to individual objects — the phrase "even without having it explicitly" describes a check performed at query time against role membership, not against a stored per-table grant. This is a structurally different mechanism from `ALTER DEFAULT PRIVILEGES`: it is granted once to the readonly role (`GRANT pg_read_all_data TO <readonly-role>`) and, because it is not tied to a specific creating role at all, it does not carry the `FOR ROLE` coupling documented in Findings 2, 6, and 7. The one documented caveat is Row-Level Security: this role does not automatically bypass RLS, so if any table uses RLS policies, an administrator would need to evaluate whether the readonly role should also get `BYPASSRLS`.
**Verification:** URL fetched 2026-07-27 (fetched twice, re-confirmed) / verbatim quote checked / quote substring confirmed byte-identical on both fetches, in the predefined-roles table row for pg_read_all_data (the fetched-page summary reported the table numbering inconsistently across the two fetches — 22.3 vs 22.1 — so the table NUMBER is not asserted, only the row content, which matched exactly both times).

### Finding 9: No row-level security usage found in the app's migrations

**Evidence:** `grep -rln "ROW LEVEL SECURITY\|row_level_security\|enable_row_level_security" ~/Projects/4Shark/app/db/migrate` returned no matches.
**Source:** `~/Projects/4Shark/app/db/migrate/` (full-tree grep, no matches)
**Significance:** The RLS caveat from Finding 8 does not appear to be triggered anywhere in the current schema — no migration in the repo sets up row-level security. This is a negative result from the codebase, not proof that RLS could never be introduced later; it narrows, but does not eliminate, the caveat's relevance today.

### Finding 10: `pg_read_all_data` can be granted on Aurora RDS through the ordinary master user, without full superuser

**Evidence:** "GRANT pg_read_all_data TO cdc_user;" and "Aurora master user does NOT have full SUPERUSER privileges. Use roles instead."
**Source:** https://docs.velodb.io/cloud/4.x/integration/data-source/postgres-cdc/aurora-rds
**Significance:** Confirms this predefined role is usable in 4Shark's actual environment (Aurora PostgreSQL, master user without true `SUPERUSER`), not just on a self-hosted Postgres instance. The article documents the same `GRANT pg_read_all_data TO <target>` statement Finding 8 describes, in the context of Aurora specifically.
**Verification:** URL fetched 2026-07-27 / verbatim quote checked / quote substring confirmed in the "Grant necessary privileges" section of the fetched page.

### Finding 11: The same production failure is documented at another organization, independent of Rails

**Evidence:** "New tables don't appear to have the same access for read-only users." — established tables like `projects` show `readonly=r/gitlab` grants, while newly created tables (e.g. `project_repository_states`) show no grant entries at all. Two remediation ideas were floated in the issue text itself: "We need to add some configuration in PostgreSQL to make these tables inherit these values." and "Do we need to grant privileges to each of the users via omnibus or Chef periodically?"
**Source:** https://gitlab.com/gitlab-com/infrastructure/issues/3890
**Significance:** Confirms the underlying failure mode (readonly grants do not automatically extend to new tables) is a known, cross-organization class of problem, not an artifact of 4Shark's specific setup. The issue's own two proposed directions mirror the option space this spike is evaluating: a PostgreSQL-side configuration fix (matches the `ALTER DEFAULT PRIVILEGES` / `pg_read_all_data` options below) versus a periodic/scheduled re-grant script (matches the "post-deploy verification" option below). The issue's eventual resolution could not be confirmed — see "What remains uncertain."
**Verification:** URL fetched 2026-07-27 / verbatim quote checked / quote substring confirmed in the issue description text.

### Finding 12: `strong_migrations` has a custom-check mechanism, and the installed version supports it

**Evidence:** From the README: "Add your own custom checks with: `StrongMigrations.add_check do |method, args| if method == :add_index && args[0].to_s == "users" stop! "No more indexes on the users table" end end`". Confirmed present in the installed gem: `def self.add_check(&block)\n  checks << block\nend` at `~/Projects/4Shark/app/vendor/bundle/ruby/4.0.0/gems/strong_migrations-2.7.0/lib/strong_migrations.rb:68-70`.
**Source:** https://github.com/ankane/strong_migrations (README) and `~/Projects/4Shark/app/vendor/bundle/ruby/4.0.0/gems/strong_migrations-2.7.0/lib/strong_migrations.rb:68-70`
**Significance:** A custom check on `method == :create_table` could inspect every table-creating migration and enforce a project rule (e.g., require the migration to also perform a grant, or simply refuse `create_table` outside a designated wrapper). This is a real, already-available mechanism in the exact gem version this repo runs.
**Verification (GitHub):** URL fetched 2026-07-27 / verbatim quote checked / quote substring confirmed in the "Custom Checks" section of the README.

### Finding 13: Custom checks are validators, not auto-executors, and only fire outside `safety_assured`

**Evidence:**
```ruby
# strong_migrations/checker.rb:36-103 (abridged)
def perform(method, *args, &block)
  ...
  if !safe? || safe_by_default_method?(method)
    case method
    when :create_table
      check_create_table(*args)
    ...
    end
    if !safe?
      # custom checks
      StrongMigrations.checks.each do |check|
        @migration.instance_exec(method, args, &check)
      end
    end
  end
  result = ... perform_method(method, *args, &block) ...
  result
end
```
**Source:** `~/Projects/4Shark/app/vendor/bundle/ruby/4.0.0/gems/strong_migrations-2.7.0/lib/strong_migrations/checker.rb:36-103`
**Significance:** Two structural constraints on this mechanism, read directly from the code the repo actually runs. First, `StrongMigrations.checks` are invoked with `instance_exec(method, args, &check)` — they can inspect the call and call `stop!` to raise an error, but the block itself does not run the underlying schema statement; it has no built-in way to *also perform* a `GRANT` as a side effect of a passing check. It is a gate, not a hook that executes additional DDL. Second, custom checks are gated by `if !safe?` (line 97) — they do not run for any statement wrapped in `safety_assured`, matching the existing four grant migrations' own pattern of wrapping their `execute "GRANT ..."` calls in `safety_assured do ... end`. A `create_table` call itself is ordinarily not wrapped in `safety_assured`, so a custom check targeting `:create_table` would fire on every normal table-creation migration in this repo as it stands today.
**Significance for Q1:** this mechanism can enforce "the engineer did the right thing" (e.g., by requiring a specific comment, a companion grant statement, or refusing to let `create_table` proceed at all until a grant is present), but it cannot itself execute the grant automatically as a byproduct of `create_table` succeeding.

### Finding 14: The repo's current pattern is one manual grant migration per table

**Evidence:**
```ruby
class AddSelectPermissionToSignatures < ActiveRecord::Migration[7.2]
  def up
    return if ApplicationConfiguration.pg_primary_readonly_username.blank?

    safety_assured do
      execute "GRANT SELECT ON signatures TO \"#{ApplicationConfiguration.pg_primary_readonly_username}\""
    end
  end
  ...
end
```
**Source:** `~/Projects/4Shark/app/db/migrate/2025/04/20250415161945_add_select_permission_to_signatures.rb`
**Significance:** Confirms the given incident fact (#5) — only four such migrations exist in the whole repo, all hand-written, all reading the same env-var-backed configuration method, all guarding on it being blank (so they silently no-op in `beta-001`/`demo-001`, matching given fact #8). This pattern requires an engineer to remember, for every new table, to write a second migration — the exact gap the investigation is trying to close.

### Finding 15: `ApplicationConfiguration.pg_primary_readonly_username` reads the env var the engineer has decided to drop

**Evidence:** `def pg_primary_readonly_username; ENV.fetch('DATABASE_READONLY_USERNAME', ''); end`
**Source:** `~/Projects/4Shark/app/lib/application_configuration.rb:261-263`
**Significance:** Any Q1 option built on the existing migration pattern (Finding 14) or a variant of it currently depends on this method, which depends on the env var the engineer has already decided to remove. Whichever Q1 option is chosen, if it needs to know the readonly role's *name* inside a Ruby migration, that name must come from somewhere else (a different config source, or the option must avoid needing the name in Ruby at all — e.g. by running entirely as a one-time SQL bootstrap outside Rails).

### Finding 16: The terraform-level bug is confirmed at the source — identical, hardcoded readonly username across two distinct writer-role environments

**Evidence:** `DATABASE_READONLY_USERNAME = "..."` appears with byte-identical values at `~/Projects/4Shark/terraform/modules/atento_001_task_config/main.tf:18` and `~/Projects/4Shark/terraform/modules/shared_001_task_config/main.tf:19` (value withheld per credential-handling policy — it is a role identifier, not a secret, but is not reproduced here since it is not load-bearing for this finding).
**Source:** `~/Projects/4Shark/terraform/modules/atento_001_task_config/main.tf:18`, `~/Projects/4Shark/terraform/modules/shared_001_task_config/main.tf:19`
**Significance:** Directly confirms given fact #7 from the codebase itself: the two stacks' task-config modules hardcode the same readonly-role name, even though the stacks are separate databases with separate writer roles. This is exactly the kind of copy-paste-across-environments failure that a per-environment bootstrap (Q2) needs to avoid reproducing.

### Finding 17: The CI test database has no readonly role and is not the same shape as production

**Evidence:**
```yaml
postgres:
  image: postgres:18
  env:
    POSTGRES_USER: postgres
    POSTGRES_PASSWORD: postgres
    POSTGRES_DB: app_test
```
**Source:** `~/Projects/4Shark/app/.github/workflows/ci.yaml:21-26`
**Significance:** Confirms given fact #8's implication in the CI environment specifically: the test database is a vanilla, single-role `postgres:18` container. There is no readonly role, no replica split, and no `ALTER DEFAULT PRIVILEGES`/grant configuration mirroring production. A CI-time check that actually connects as a readonly role and attempts a real `SELECT` cannot run against this database as it is configured today — it would first need CI to provision a parallel role and apply whatever grant mechanism production uses, which is a second thing to keep in sync with production's real setup (and could itself drift, silently, the same way the production gap did).

### Finding 18: No Terraform module in the repo manages PostgreSQL roles or grants

**Evidence:** `grep -rl 'provider "postgresql"'` across `~/Projects/4Shark/terraform` returned no matches; `~/Projects/4Shark/terraform/app-shared-001/rds.tf` (141 lines, read in full) defines the Aurora cluster, its subnet group, and its security group, but contains no role, user, or grant resource of any kind; `~/Projects/4Shark/terraform/modules/` has no module named for Postgres roles (only `rds_aurora_cluster` and `rds_instance`, both purely infrastructure-shaped).
**Source:** `~/Projects/4Shark/terraform/app-shared-001/rds.tf` (full read); directory listing of `~/Projects/4Shark/terraform/modules`
**Significance:** Whatever mechanism ends up guaranteeing correctness for Q1, the role/grant bootstrap itself is not, today, expressed anywhere in the Terraform that provisions a stack's database. This is a negative/absence finding: it tells us where the guarantee does *not* currently live, which bears directly on Q2 — a new environment's DB roles and grants are provisioned by some means outside of what Terraform tracks (per the given facts, this has been manual/ad hoc so far).

### Finding 19: No runbook exists for provisioning a new productive app stack's database roles

**Evidence:** `~/.claude/docs/runbooks/INDEX.md`, read in full, lists runbooks under `client-onboarding`, `compliance`, `databases` (all MongoDB/Atlas-focused), `development`, `disaster-recovery`, `engineer-access`, `migrations`, `security`, `services`, `terraform-operations`, and `vpn`. None of these entries covers provisioning a new productive `app` stack's Postgres roles or default privileges.
**Source:** `~/.claude/docs/runbooks/INDEX.md`
**Significance:** There is no existing 4Shark process document this investigation can point to as "where a new-environment checklist would already live." Whichever Q2 answer is chosen, it either needs a new runbook entry, a Terraform-side change, or both — there is no existing artifact to simply extend.

## Trade-offs surfaced — Q1 (guarantee on every new table, going forward)

| Option | What it guarantees | What it does NOT guarantee | Failure modes | Cost to adopt |
|---|---|---|---|---|
| **A. `ALTER DEFAULT PRIVILEGES FOR ROLE <writer> IN SCHEMA public GRANT SELECT ON TABLES TO <readonly>`**, run once per environment as a bootstrap | Every table subsequently created **by that specific writer role** in that schema automatically carries the grant (Finding 1, 2) | Nothing for tables that already exist at the time it is run (Finding 1); nothing for a table created by any role other than the one named in `FOR ROLE` — e.g. an admin console session (Finding 3, 6, 7) | Silent regression if a table is ever created by a role other than the named writer (e.g., manual DBA work, a different automation path); silent regression if the writer role is ever rotated/renamed without re-running the statement; global-vs-per-schema scope must be chosen consistently (Finding 4) | Low — a single SQL statement per environment, no Rails code changes required, no dependency on `DATABASE_READONLY_USERNAME` if the readonly role name is embedded directly in the bootstrap SQL rather than read from Ruby config |
| **B. `GRANT pg_read_all_data TO <readonly-role>`**, run once per environment as a bootstrap | Every table, present and future, in the database is readable by the readonly role — independent of which role created it, because the check is role-membership-based rather than an ACL entry per object (Finding 8, 10) | Row-level security bypass is not automatic — a table using RLS would still need `BYPASSRLS` considered separately (Finding 8); does not narrow access to a subset of tables — it is all-or-nothing for the database (this is a structural property of the role, not confirmed as a requirement or non-requirement by the engineer) | None specific to "which role created the table" — that entire class of failure mode is structurally eliminated. Residual risk is scope: any *future* table containing data that should NOT be readable by the readonly role would also be covered, since the grant is blanket | Low — a single statement per environment, no per-role coupling to track or re-run on writer-role rotation |
| **C. Rails migration lifecycle hook** (a custom `ActiveRecord::Migration` subclass or `schema_statements` override that runs a `GRANT` automatically after every `create_table`) | Would guarantee the grant fires as part of every migration that creates a table, if adopted consistently by every migration author | Nothing was found describing this as an established Rails/community pattern — no verified source surfaced one; "not found" is the honest conclusion for the community-practice half of this option (see "What remains uncertain") | Depends entirely on 4Shark writing and maintaining custom migration-base-class code; a migration author who does not subclass correctly (or who calls `create_table` inside a `change_table`/`reversible` block in a way the hook does not intercept) reproduces the original gap; still needs to resolve where the readonly role's name comes from now that `DATABASE_READONLY_USERNAME` is gone (Finding 15) | Medium — custom Ruby code to write and keep correct across Rails/migration-DSL edge cases (e.g. `create_join_table`, `change_table`) |
| **D. `strong_migrations` custom check** (`StrongMigrations.add_check` on `:create_table`) | Can force every `create_table` migration to be reviewed/blocked at migration-run time — a real, already-available mechanism in the installed gem (Finding 12) | Cannot itself execute the `GRANT` as a side effect — it is a validator/gate, not a hook that performs additional DDL (Finding 13). It can require the engineer to do something, but cannot do the something for them | A check that merely blocks (`stop!`) still relies on the engineer writing the correct follow-up grant statement by hand each time — it converts "silently forgotten" into "loudly forgotten," which is real progress but does not remove the manual step | Low-to-medium — one custom check block in an initializer; does not touch existing migrations, does not depend on `DATABASE_READONLY_USERNAME` unless the check itself is written to reference it |
| **E. CI/test guard** (a spec or rake task asserting every table in `public` has `SELECT` granted to the readonly role) | Would catch the gap before merge, if it could run against a database shaped like production | As configured today, cannot run at all — the CI Postgres container has no readonly role and no default-privilege setup mirroring production (Finding 17). Making it work requires CI to independently stand up a parallel role + grant configuration, which is a second copy of the "real" setup that itself needs to be kept in sync with whatever bootstrap mechanism (A/B) protects production | If CI's parallel setup drifts from production's actual bootstrap (e.g., production is on Option A but CI's guard was written for Option B, or the writer-role name changes in production and CI is not updated), the guard could pass in CI while production is still broken — a false sense of safety | Medium-to-high — requires building and maintaining a second, CI-local replica of whatever the real bootstrap does, on top of the guard code itself |
| **F. Post-deploy/runtime verification** (a rake task run against the real environment, e.g. as an ECS task, checking `information_schema` grants and alerting rather than blocking) | Detects the gap against the real database and the real readonly role, closing the CI-guard's fidelity problem (contrast with Option E) | Does not prevent the gap from existing between deploys — it is a detection mechanism, not a prevention mechanism; needs a place to run (a scheduled ECS task, a post-deploy CI step) and a place to alert to, neither of which currently exists per this investigation's scope | An alert with no auto-remediation still requires an engineer to notice and fix it — smaller blast radius than the original incident (caught same-day instead of accumulating eleven tables) but not a structural guarantee | Medium — needs a new scheduled task/step and an alerting destination; the query itself is a straightforward `information_schema.role_table_grants` / `has_table_privilege` check, not researched further in this spike |

## Trade-offs surfaced — Q2 (a newly created environment starts out correct)

| Option | What it guarantees | What it does NOT guarantee | Failure modes | Cost to adopt |
|---|---|---|---|---|
| **A. A new runbook entry** documenting the bootstrap step (whichever Q1 option is chosen) as part of "provision a new productive app stack" | A documented, discoverable procedure — closes the "no existing artifact to extend" gap (Finding 19) | Nothing mechanical — a runbook is followed by a human, and a skipped step reproduces exactly the failure this investigation started from (a step someone forgot). This is the same category of guarantee the original four ad-hoc migrations offered, just at the environment level instead of the table level | An engineer standing up a new stack in a hurry, or delegating the work, can still skip the step; there is no verification that the step was actually run | Low — writing the runbook itself is cheap; the guarantee it provides is weak relative to its cost |
| **B. Terraform-side change** — introduce a PostgreSQL provider (e.g. `cyrilgdn/postgresql`, not currently used anywhere in this repo per Finding 18) to declare the role/grant/default-privilege state as part of the stack's `.tf` files | The bootstrap becomes part of `terraform apply` for the stack — a new environment cannot be stood up without it, and `terraform plan` would show drift if the grant state is ever changed out-of-band | Does not by itself resolve the Q1 "different creating role" gotcha (Finding 2, 3, 6, 7) unless the Terraform-managed statement also correctly names the environment's actual writer role, which Terraform would need to know | Introducing a new provider is itself a piece of infrastructure surface (state, credentials to connect to the DB from the Terraform run) that does not exist in this repo today (Finding 18) — this is new capability, not a reuse of an existing pattern | Medium-to-high — new provider, new state, new apply-time DB connectivity requirement (this spike did not investigate `cyrilgdn/postgresql`'s specific auth/connectivity requirements against Aurora) |
| **C. A bootstrap migration** — a Rails migration, run once via the normal `db:migrate` path on a fresh environment, that performs the grant/default-privilege bootstrap using Rails' own DB connection (which is already the table-owning role) | Reuses the exact same deploy mechanism every environment already goes through (`db:migrate` runs on every environment, new or old); the migration naturally runs as the correct writer role for that environment, since it uses the app's own DB connection, removing the "which role" ambiguity for Option Q1-A specifically | Only covers the moment this specific migration runs; still needs the readonly role's *name* passed in from somewhere other than `DATABASE_READONLY_USERNAME` (Finding 15) — either hardcoded per environment (reproducing the "hardcoded, sometimes wrong" pattern documented in Finding 16) or via a new config source not evaluated in this spike | If migrations are ever replayed against a different database (e.g., restoring from another environment's snapshot for testing), a migration containing an environment-specific hardcoded role name would be wrong in that context unless guarded | Low — no new infrastructure, reuses the existing migration mechanism; the open question is only where the role name comes from |
| **D. Combine with Q1-B (`pg_read_all_data`)** — whichever of A/B/C above is chosen as the *mechanism* for delivering the bootstrap, using `GRANT pg_read_all_data TO <readonly-role>` as the *content* of that bootstrap removes the need to know or track the environment's writer-role name at all | A new environment's bootstrap statement is identical across every environment (no per-environment writer-role substitution needed), directly addressing the given fact that the writer role differs per environment (given fact #1) and that the wrong-role-name class of bug already happened once (given fact #7, Finding 16) | Still carries the all-or-nothing scope trade-off from Q1 Option B — the readonly role reads every table in the database, not a chosen subset | Same as Q1 Option B — RLS bypass is not automatic if RLS is ever introduced (Finding 8, 9) | Same cost as whichever delivery mechanism (A/B/C) is chosen — the `pg_read_all_data` substitution itself does not add cost, it removes the per-environment role-name variable from whichever mechanism carries it |

## What remains uncertain

- Whether the readonly role is intended to have **blanket read access to every table** (favoring `pg_read_all_data`, Q1 Option B) or a deliberate, curated subset of tables (favoring `ALTER DEFAULT PRIVILEGES`, Q1 Option A, or per-table grants). The historical bulk `GRANT SELECT ON ALL TABLES IN SCHEMA public` (given fact #4) suggests the intent was always "everything," but this was not explicitly confirmed with the engineer in this spike.
- Whether row-level security will ever be introduced in this schema. Finding 9 found no current usage, but this is a point-in-time absence, not a guarantee — it bears directly on the one documented caveat of `pg_read_all_data` (Finding 8).
- Whether any process other than Rails migrations ever creates tables in a productive environment (a DBA console session, a one-off script run as a different role) — this bears directly on whether the `FOR ROLE`-coupling failure mode (Finding 3) is a real, exercised risk or a theoretical one. Not verified in this spike.
- What the replacement lookup mechanism for the readonly role's name will be, now that `DATABASE_READONLY_USERNAME` is being dropped (given fact #7). This spike surfaces that several Q1/Q2 options need this name from *somewhere* (Finding 15), but designing that replacement was out of scope for this investigation.
- Whether GitLab's issue #3890 (Finding 11) was ever actually resolved, and how — the fetched page did not expose comment history or the closing resolution. This is marked UNVERIFIED and does not sustain any option above; it is cited only for the problem-description quotes, which were independently confirmed.
- Whether a CI-local parallel role/grant setup (Q1 Option E) is worth the maintenance cost given the fidelity risk described in that option's row — this spike surfaces the trade-off but does not resolve it.
- Whether `cyrilgdn/postgresql` (or an alternative Postgres Terraform provider) can authenticate against Aurora in this repo's network topology without new infrastructure surface — not investigated in this spike.

## Suggested options for main and the engineer

- **Q1**: Option A (`ALTER DEFAULT PRIVILEGES FOR ROLE`), Option B (`pg_read_all_data`), Option C (Rails migration hook), Option D (`strong_migrations` custom check as a gate, not an executor), Option E (CI guard), Option F (post-deploy verification) — these are not mutually exclusive; for example, Option B (or A) as the underlying grant mechanism can be paired with Option D as a belt-and-suspenders gate, or with Option F as a detection backstop.
- **Q2**: Option A (runbook), Option B (Terraform provider), Option C (bootstrap migration), and Option D (using `pg_read_all_data` as the *content* of whichever delivery mechanism is picked, to remove the per-environment writer-role-name variable entirely).

(No recommendation — the trade-off tables above surface what each option guarantees, what it does not, and its cost; the engineer decides.)
