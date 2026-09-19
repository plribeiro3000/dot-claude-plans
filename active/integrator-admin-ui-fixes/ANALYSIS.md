# Integrator Admin UI — Correction Backlog & Analysis

Context: this backlog tracks work on the integrator admin web that followed PR #2435. Point 1 (the `ResourceType` → `Entity` rename) shipped across PRs #2436, #2437 and #2438. Point 2 (visual polish for a sellable admin) shipped across PR #2439 (Bootswatch Flatly base), the form/label refino #2441, and the palette rework #2442–#2444 (4Shark brand blue). Point 3 (asset pipeline moved to Propshaft) shipped via PR #2440. Point 4 (VKPI source authentication check) shipped via PR #2445. Point 5 (connection test button) shipped via PR #2446. The backlog stays open — a light `simple_form` pass remains optional.

Everything above is merged to `develop` and deployed to `atento-co-staging`. The whole thrust delivers a sellable, working integrator admin — the goal being to now read cost, confirm performance, and improve usability.

Repo: `~/Projects/4Shark/integrator` (Rails 8 + Mongoid). Work in an isolated worktree, Pattern Priming per view/controller, carry through to an open PR.

---

## Point 1 — `ResourceType` is misnamed (it is not a resource type)

### What the engineer observed
The "Tipos de Recurso" listing (`/resource_types`) shows a `Nome` column whose values are NOT resources — they are pipeline steps / actions (Admin, Coordinator, Director, ParentUpdate, ...). The actual resource is in the `Recurso` column. So the thing modeled as `ResourceType` is a different concept now; its name lies.

### What `ResourceType` actually is (confirmed from the code)
`app/models/resource_type.rb` — a standalone Mongoid collection (`resource_types`), NOT STI:
- `field :name` — unique. Holds the **pipeline step name**: Admin, President, VicePresident, Director, Superintendent, GeneralManager, Manager, Coordinator, Supervisor, SalesRepresentative, Unknown, Hierarchy, ParentUpdate, Subsidiary, UserIdentifier, UserField, UserActivity, Client, Product, Group, Groupification, Deal, DealExtraField, Modifier, Goal. This is exactly the "Stream Order" list in the project CLAUDE.md.
- `field :resource` — one of `Resource::TYPES` (User, Hierarchy, Modifier, Client, ...). Several `name`s map to the same `resource` (Admin/President/Director/... all → User; Hierarchy + ParentUpdate → Hierarchy).
- `has_many :streams` — it groups the concrete `Upstream`/`Downstream` records. The "Fluxos" count column is `streams.count`.

`Stream` (`app/models/stream.rb`) `belongs_to :resource_type` (FK field `stream.resource_type_id`, validated present).

Worker usage keys the whole pipeline off it, two shapes:
- `ResourceType.find_by(name: '<Step>').streams.enabled.upstreams` — the per-step producers (Admin, Goal, Hierarchy, ParentUpdate, ...).
- `ResourceType.where(resource: 'UserField'/'UserIdentifier').pluck(:id)` then `Stream.in(resource_type_id: ...)` — user_field / user_identifier producers.

So `ResourceType` is really the **catalog of pipeline steps / stream definitions**, each pointing at a `Resource` type and owning its streams.

### master vs dev — DOES IT NEED A DATA MIGRATION IN PRODUCTION?
`ResourceType` introduced 2026-05-05 by commit `06b5721a` ("feat(integrator): unify managed flow and bootstrap normalized streams"). `git branch --contains 06b5721a` → **only `develop` (+ feature branches). NOT on `master`.**

Consequence:
- **Production (master): has no `resource_types` collection at all → no prod data migration needed.**
- **Staging (develop): the 4 staging Mongo DBs DO have `resource_types` + `stream.resource_type_id` with data** (the CO-staging screenshot proves it).
- Staging data is entirely **bootstrap-seeded and idempotent**: `lib/tasks/integration/normalized/{postgresql,sql_server}/bootstrap.rake` create it via `find_or_initialize_by(name:)` for both the resource types and the streams. So staging can be regenerated under new names rather than migrated in place (decision for the correction phase — in-place Mongoid collection+field rename migration vs. re-bootstrap).

### Rename target — DECIDED: `ResourceType` → `Entity`
`ResourceType` → `Entity`; model file `app/models/entity.rb`; collection `resource_types` → `entities`; `Stream belongs_to :entity` (FK `stream.entity_id`); `entity.streams`; `entity.resource` (field unchanged); i18n label user-facing "Entidade"/"Entity"/"Entidad", route `resources :entities`, controller `EntitiesController`, views `app/views/entities/`, factory `:entity`. Full 68-ref surface below — substitute `Entity` throughout. Rationale: it is the target entity of the ETL (what all sources converge on), the engineer's own word, survives the future dynamic model.

Context that led here (rejected alternatives): `StreamType` rejected — `Stream` is STI (already has `_type` = Upstream/Downstream), a second "type" on the same object is the confusion itself. `Step`/`Operation` named the implementation, not the business. `Integration` too close to the "integrator" project + `Job`. `Target` collides with `stream.target_field`.

The `name` field is OVERLOADED — the full catalog is ~28 entries (2 UI pages), and `name` carries four different things: resource (Client, Product, Deal, Goal, Modifier — where `name == resource`), role under User (Admin…SalesRepresentative, Unknown), event (ParentUpdate, Hierarchy), and **resource + operation** (`UserFieldCreate`, `UserFieldDelete`, `UserIdentifierCreate`, `UserIdentifierDelete`, `UserIdentifierPrimary`). So the "it's an action/verb" instinct is real for the Create/Delete/Primary family (page 2), but ~15/28 are not operations.

Engineer reframed the whole axis: it is NOT "type of stream" nor "step of code" — it is the **target ENTITY of the ETL**. The business model the engineer wants (a dynamic T-E-L: code written once, register the entity you want to integrate): each registered entity has an ORDER relative to others (users before indicators) and is fed by MANY streams, each from a different source; together the streams produce the entity. That is the canonical ETL target — "a canonical entity_id that all sources map to" (community grounding, ETL/data-integration).

Name candidates (decision matrix: `/tmp/integrator_resource_type_rename_matrix_20260918.html`):
- **`Entity`** (recommended, 28/30) — the engineer's own word ("a entidade que a gente quer integrar"); ETL-canonical; `stream.entity`, `entity.streams`, `entity.resource`, `entity.integration_order`; survives the dynamic model. Only risk: generic word → disambiguate with `IntegrationEntity` if needed.
- **`Integration`** (strong runner-up, 26/30) — reads like the engineer speaks ("a integração de usuários antes da de indicadores"); loses because the project is already the "integrator" and a run is `Job` (concept proximity, no class collision).
- **`Subject`** (25/30) — data-warehousing "subject area"; clean, no collision, but more abstract than "entity".
- Rejected: `Target` (22, ETL-canonical but `Stream` already has `target_field`), and the earlier axis (`Step`/`Operation`/`StreamType`) which named the implementation, not the business.

The `resource` field stays `resource`. Collection `resource_types` → `<name>s` (`entities`); FK `stream.resource_type_id` → `stream.<name>_id` (`entity_id`).

### Deeper modeling smell (optional, bigger than the rename — engineer's call)
`name` doing double duty (embedding resource+operation in a free string for the UserField*/UserIdentifier* family while just repeating `resource` for Client) suggests a cleaner model: split `resource` + `operation`/`variant` instead of one overloaded `name` string. This is a modeling change beyond the rename — noted, not recommended unless the engineer wants it.

### Full rename surface (68 references; the correction PR must touch all)
- **Model**: `app/models/resource_type.rb` (class, `has_many :streams inverse_of:`, `index`).
- **Stream**: `app/models/stream.rb` — `belongs_to :resource_type`, `validates :resource_type_id`, `resource_inclusion` (`resource_type.blank?`, `resource_type.resource`, `errors.add(:resource_type, ...)`).
- **Controller/routes**: `app/controllers/resource_types_controller.rb`, `config/routes.rb` (`resources :resource_types`), `streams_controller.rb:62` (permitted param `resource_type_id`).
- **Views**: `app/views/resource_types/index.html.erb` (+ rename folder), `layouts/application.html.erb` nav link, `streams/_form.html.erb` (`ResourceType.all`, `resource_type_id` input), `streams/show.html.erb` (`@stream.resource_type.name`).
- **i18n**: `config/locales/{pt-BR,en,es}/views/resource_types.yml` (+ rename file), and `streams.yml` `fields.resource_type`. Keep translated LABEL user-facing ("Tipo de Fluxo" / "Stream Type" / "Tipo de Flujo").
- **Workers (48 refs)**: every `app/workers/**/{collection_extractor,enrichment_extractor,transformer}_producer.rb` — `ResourceType.find_by(name: ...)` and the user_field/user_identifier `ResourceType.where(resource: ...)` + `Stream.in(resource_type_id: ...)`.
- **Bootstrap rake (both SGBDs)**: `lib/tasks/integration/normalized/{postgresql,sql_server}/bootstrap.rake` — `ResourceType.find_or_initialize_by`, `.resource`, `Upstream.find_or_initialize_by(resource_type:)`, `downstream.resource_type =`, puts labels, `ResourceType.count`. NOTE: the `definitions` data source these read carries `name:`/`resource:` per step — check it does not itself need renaming.
- **Specs/factories**: `spec/factories/resource_types.rb` (+ rename), `spec/models/resource_type_spec.rb` (+ rename), `spec/models/{stream,upstream,downstream}_spec.rb`, `spec/requests/streams_controller_spec.rb`.
- **Data**: staging collection `resource_types` → `stream_types` and `stream.resource_type_id` → `stream.stream_type_id` (migration OR re-bootstrap; prod unaffected).

Status: SHIPPED — merged to develop via PR #2436 (rename), #2437 (controller strong-params ordering + `INTEGRATOR_DOMAIN.md` doc rename), #2438 (nav shows Entities before Streams). Production never carried the concept (unreleased on develop), so no prod migration. `atento-co-staging` was deployed and re-keyed in place: the 28 catalog docs copied `resource_types` → `entities` preserving `_id`s, the 54 streams `$rename`d `resource_type_id` → `entity_id` (the custom VKPI Modifier stream's 5 attribute mappings preserved), old `resource_types` collection dropped after verification. The other 3 staging (cl, mx, commcenter) were empty and bootstrap the `entities` catalog fresh on their next deploy. The bootstrap rake tasks (both SGBDs) and the request spec were part of #2436.

---

## Point 2 — Visual polish of the integrator admin (sellable UI)

Status: SHIPPED — PR #2439 (Flatly base) + #2441 (form/label refino) + #2442–#2444 (palette). The admin runs the Bootswatch **Flatly** theme as its base, with the palette overridden to the **4Shark brand blue**: `$primary = #0889e2` (the app-webclient brand blue) and a deep-blue accent `#0a4d8c` replacing Flatly's teal/green wherever it appeared — links, pagination, the navbar, and the status badges (`bg-success`, which every "passed"/"active" badge uses, so the `$success` override recolors them all). The overrides are set before the Flatly `@import` so they win, and hover/active variants are derived with `color.scale` (Bootstrap's own functions are unavailable pre-import). `simple_form` already emitted Bootstrap classes, so the theme restyled forms and tables globally; a small set of custom rules (form container full width, form section headers, card-wrapped labels, clickable-row cursor, centered pagination) rounds out the three shapes. Zero teal remains in the compiled CSS (verified: 0 occurrences of `#18bc9c`/`#20c997`). A light `simple_form_bootstrap.rb` pass (denser field spacing, aligned labels) remains optional and unstarted.

### Why
The integrator connects to any client database in a fully parameterized way (sources, streams, attribute mappings, sensitive keys — all configured from the admin, no per-client code). That makes the admin itself a sellable surface: it is the screen used to demo the product and the source of screenshots for marketing/site material. The look does not match the capability — it reads as an internal tool, not a product.

### What the engineer wants (constraints)
- A **simple** skin, NOT a widget/dashboard template. The admin is only three shapes: **listings**, a **show/visualization**, and **forms**. Nothing needs charts, KPI cards, or a dashboard grid.
- Fix the palette — the default Bootstrap **blue is bad**.
- Fix the **forms** — they read as ugly/unstyled even though `simple_form` is in use.
- Prefer something that themes `simple_form` output well, with minimal markup churn.

### Current front-end (facts that constrain the choice)
- Bootstrap **5.3.3 via CDN** (`<link>` in `app/views/layouts/application.html.erb`), not compiled from Sass.
- `simple_form` + `config/initializers/simple_form_bootstrap.rb` (Bootstrap wrappers already configured).
- `sassc-rails` + Sprockets asset pipeline; `app/assets/stylesheets/application.css` (plain CSS, small custom additions), `app/assets/javascripts/{application,clickable_rows}.js`.
- Views are hand-built ERB (`sources`, `streams`, `entities`, `jobs`, `resource_types`→now `entities`). No Rails admin framework.
- A CSP initializer is present; the current CDN is jsDelivr, so any replacement CSS must come from an already-allowed host (jsDelivr/cdnjs) or be vendored locally.

### Options (researched)
- **Bootswatch (recommended).** 25 free, MIT-licensed Bootstrap 5 themes that reskin by swapping Bootstrap's Sass variables — components, grid and JS keep working, only the look changes ([bootswatch.com](https://bootswatch.com/), [github.com/thomaspark/bootswatch](https://github.com/thomaspark/bootswatch)). Because `simple_form` already emits Bootstrap classes, a Bootswatch theme restyles the forms and tables globally with **zero markup change**. Two ways to adopt: (a) swap the Bootstrap CDN `<link>` for a Bootswatch build (fastest; fixes the blue immediately), or (b) with the existing `sassc-rails`, `@import` the theme's `_variables.scss` + `_bootswatch.scss` for a forward-compatible, locally-compiled theme (no CDN/CSP dependency). Pick one theme with a calmer palette — this alone answers "the blue is bad" and "forms are ugly".
- **Custom Bootstrap 5 theme (more control).** Keep Bootstrap, override `$primary` and a small `_variables.scss` with a 4Shark palette, compile via `sassc-rails`. More say over brand color/spacing; slightly more work than picking a Bootswatch theme, and no upstream theme to inherit polish from.
- **Ruled out — Rails admin frameworks (Administrate / ActiveAdmin / Avo).** They are ActiveRecord-oriented and the integrator is **Mongoid**; they are also full admin frameworks that would replace the hand-built ERB, which is heavier than the "simple skin" the engineer asked for.

### Direction to start with
Adopt a Bootswatch theme (drop-in first to see it live, then move to the Sass import for CSP-safe, forward-compatible compilation), then do a light pass on `simple_form_bootstrap.rb` + the form container so forms read as intentional (consistent field spacing, a card-wrapped form, aligned labels). Scope stays the three shapes — no new widgets.

### Remaining (optional)
- A light `simple_form_bootstrap.rb` pass — denser, intentional field spacing and aligned labels within the existing three shapes. Not started; not required for the sellable look Flatly already delivers.

---

## Point 3 — Asset pipeline moved to Propshaft

Status: SHIPPED — PR #2440.

### Why
Rails 8's default pipeline is Propshaft. On Sprockets, the libsass compressor (`sassc-rails`) cannot parse Bootstrap 5.3's CSS custom properties, so the vendored Flatly theme compiled only with the SassC compressor disabled — a workaround, not a fix. Propshaft with Dart Sass removes libsass entirely and aligns the admin with the framework default.

### What shipped
- `sassc-rails` and `uglifier` replaced by `propshaft` + `jsbundling-rails` (esbuild) + `cssbundling-rails` (Dart Sass).
- JS bundled from `app/javascript` by esbuild; the Flatly theme compiled from `app/assets/stylesheets/application.scss` by Dart Sass; both output to `app/assets/builds`. Dart Sass compiles Bootstrap 5.3 cleanly, so the `css_compressor = nil` workaround is gone.
- jquery, jquery-ujs, bootstrap, bootswatch, esbuild, sass and @popperjs/core all declared in `package.json`, so Renovate keeps opening version PRs; no runtime CDN.
- Production ships no JS source map (the `build` script matches the CSS build); the dev watcher keeps `--sourcemap`.
- `node_modules` git-ignored and installed at build; the Docker image and CI build assets before precompile/specs. Local dev runs `bin/dev` → `Procfile.dev` (web + esbuild/sass watchers).
- The jQuery-global load order is load-bearing: `setup_jquery.js` sets `window.jQuery` before `jquery-ujs` imports, because esbuild evaluates side-effect imports in source order.

### Front-end state (supersedes the pre-migration facts in Point 2)
Rails 8 + Propshaft; JS via jsbundling/esbuild, CSS via cssbundling/Dart Sass; Bootstrap 5.3 + Bootswatch Flatly vendored through Yarn; `simple_form` + `simple_form_bootstrap.rb` unchanged; no Sprockets, no CDN.

---

## Point 4 — Authentication check on non-normalized database sources

Status: SHIPPED — PR #2445.

### What the engineer observed
On the job's "Verificações de Fonte" screen, the VKPI database source (the client's custom Modifier base) showed both `Alcançabilidade` and `Autenticação` as `skipped`, while the Normalized database showed `passed`/`passed`. The engineer asked whether the auth check could run for the VKPI base too.

### Root cause (two independent reasons)
- **Authentication `skipped`** was gated in code: `Authorization::DatabaseConsumer` ran the real check only `if source.normalized?`; the `else` branch marked `authentication: :skipped`. The normalized-only work (`connection.permissions.missing`, `connection.locks.check`) is specific to the 4Shark normalized schema, so it does not apply to an arbitrary customer schema — but the effect was that a non-normalized DB source was never authenticated even though it holds credentials the extraction uses.
- **Reachability `skipped`** is per-source config, not code: `HealthCheck::Consumer` marks `:skipped` when the source has no `HealthCheck` associated. Cadastrando um `HealthCheck` para a fonte resolve a alcançabilidade sem código — still open, engineer's call.

### What shipped
`Authorization::DatabaseConsumer`'s `else` branch now runs a real connect for a non-normalized DB source and marks `authentication: :passed`, mirroring `Authorization::ApiConsumer` (which authenticates with no `normalized?` gate). The pushed review fix hardened it: the check forces a real round-trip so a cached/dead connection cannot report a false pass, and the existing `rescue TinyTds::Error, Sequel::DatabaseConnectionError, Sequel::DatabaseError` marks `:failed, :connection_error`. The normalized path (permissions + locks) is unchanged.

### Remaining (optional, engineer's call)
Configure a `HealthCheck` for the VKPI source to make its reachability run — pure cadastro, no code.

---

## Point 5 — "Testar Conexão" button on database sources

Status: SHIPPED — PR #2446.

### What the engineer wanted
A button inside the database source visualization that tries a live connection with the stored credentials and returns to the same page with a flash message (success/failure). No new screen, no AJAX — a POST that redirects back with a flash. Database sources only (API sources unchanged), because that is where credentials are entered directly.

### What shipped
- `DatabaseSource#connectable?` opens its OWN connection (not the process-cached pipeline adapter `connect!` reuses, which is keyed by id and would report a stale success after a credential edit and leak DB pools into the web tier), runs a real query, disconnects in `ensure`, and treats any connection error as `false` via a broad rescue matching the adapters' own `#valid?`. The PostgreSQL configuration gained a `connect_timeout` so an unreachable host cannot tie up a web thread.
- `DatabaseSources::ConnectionsController#create` (a RESTful `resource :connection` nested under `database_sources`, `POST /database_sources/:id/connection`) finds the source, branches on `connectable?`, and redirects to `source_path` with `notice:`/`alert:`. Named as a plural-noun resource per the `app` repo convention (NOT a verb-phrase controller), mirroring `Streams::ActivityController`.
- A `button_to` in the `@source.database?` block of `sources/show.html.erb`; i18n in all three locales (`test_connection` label + `connection.success`/`.failure` flash).
- `#connectable?` unit-tested (reachable → true, driver error → false); full suite green (689 examples). Nested action sub-controllers are not request-spec'd in this project (activity/attribute_mappings/sensitive_keys have none), so no controller spec, matching the convention.

---

## Deploy

`atento-co-staging` (integrator, slug `atento-co-staging` → `atento` GitHub environment) is deployed from `develop` after the merges, carrying all of Points 1–5 to staging. Trigger: `gh workflow run deploy.yaml -R 4shark/integrator --ref develop -f integrator=atento-co-staging` (staging → `--ref develop`; the image is that deployment's `:latest`, built on merge to develop — the Build for the merged commit was confirmed green before triggering). The deploy flow: preflight (Mongo nodes running) → quiet worker (TSTP Sidekiq) → migrate (ephemeral runner task) → deploy web + worker in parallel. Staging is non-productive, so no productive-queue gate applies.

---

## Open threads (not this session's scope, so nothing is lost)
- **v9.0.0 release + rollout** — tracked in `integrator-develop-release-validation/PLAN.md`. As of this session the integrator is still `v8.4.25` (`config/version.rb`), so 9.0.0 is NOT released; Phases 5 (release), 6 (7-integrator rollout) and 7 (close) remain. This session's work sits on `develop`, unreleased, and rides that future release.
- **VKPI reachability cadastro** (Point 4 remaining) — configure a `HealthCheck` for the VKPI source; no code.
- **Optional `simple_form` pass** (Point 2 remaining) — denser field spacing / aligned labels.
- **Cost/performance/usability read** — the engineer's stated next step now that the admin is sellable and deployed: observe staging cost, confirm performance, gather usability feedback. No task opened yet.
