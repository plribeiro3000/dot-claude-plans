# NEXT TASKS — Integration Validation Portal MVP

> **Objective:** Build a standalone Rails application for secure, audited integration query validation in 8 sequential phases, from foundation (Phase 1) through infrastructure (Phase 8).
>
> **Reference:** PLAN.md (sections: Phase 1–8, Technical Decisions, Risks).

---

## 0) Pre-conditions

- [ ] PLAN.md **approved**
- [ ] **Base branch:** `develop` • **Working branch:** `feature/integration-validation-portal`
- [ ] AWS SES sandbox access **confirmed** (or production access requested early)
- [ ] New Git repository created for this standalone app
- [ ] Team has confirmed Rails 8.1+ compatibility with their CI/CD pipeline

---

## Phase 1: Foundation (Rails Setup, Authentication, Data Models)

### Task 1.1 — Initialize new Rails 8.1+ application with PostgreSQL

- **Objective:** Create a working Rails application with database connectivity and basic structure.
- **Actions:**
  - [ ] Run `rails new integration_portal --database=postgresql --skip-test --skip-action-mailbox` (or equivalent scaffolding tool)
  - [ ] Initialize Git repository and create initial commit
  - [ ] Add `Gemfile` entries: `devise` (optional for admin auth), `aws-sdk-s3`, `aws-sdk-ses`, `ferrum_pdf`, `sidekiq`, `redis`, `pg`, `enumerize`, `aasm` (or `state_machine`)
  - [ ] Run `bundle install`
  - [ ] Configure database connection (PostgreSQL)
  - [ ] Generate and run initial migration for `schema_migrations`
  - [ ] Verify Rails server starts without errors (`rails server`)

- **Affected files/areas:** `Gemfile`, `config/database.yml`, `db/schema.rb`, root directory structure

- **Completion criteria:** Rails app boots cleanly, database exists and connects, Gemfile has all core dependencies locked

---

### Task 1.2 — Create database schema for authentication and core models

- **Objective:** Define the relational schema for OTP flow, portal users, tokens, and audit trail.
- **Actions:**
  - [ ] Generate migration: `rails g migration CreatePortalUsers email:string name:string role:string company_id:uuid locked_at:timestamp`
    - Add unique index on `email`; add index on `role` and `company_id`
  - [ ] Generate migration: `rails g migration CreateOtpCodes portal_user_id:references code:string used_at:timestamp attempt_count:integer expires_at:timestamp`
    - Add unique index on `(portal_user_id, expires_at)` for easy cleanup
  - [ ] Generate migration: `rails g migration CreateValidationTokens portal_user_id:references token:string expires_at:timestamp used_at:timestamp ip_address:string user_agent:string`
    - Add unique index on `token`; add index on `expires_at` for cleanup jobs
  - [ ] Generate migration: `rails g migration CreateIntegrationCompanies company_id:uuid name:string it_contact_email:string ops_contact_email:string`
    - Add unique index on `company_id`
  - [ ] Generate migration: `rails g migration CreateIntegrationQueryTemplates name:string description:text wave_type:string` (wave_type: 'users' or 'indicators')
  - [ ] Generate migration: `rails g migration CreateIntegrationWaves company_id:uuid wave_type:string state:string created_at:timestamp updated_at:timestamp`
    - Add index on `(company_id, wave_type)`; state column has constraint on allowed values
  - [ ] Generate migration: `rails g migration CreateIntegrationEvents wave_id:references event_type:string actor_email:string metadata:jsonb ip_address:string user_agent:string`
    - Add index on `(wave_id, created_at)` for timeline queries
  - [ ] Run `rails db:migrate`
  - [ ] Verify schema in `db/schema.rb` is clean and complete

- **Affected files/areas:** `db/migrate/`, `db/schema.rb`

- **Completion criteria:** All tables exist with correct columns, types, and indices; migrations are reversible; no warnings from Rails

---

### Task 1.3 — Create PortalUser model with role-based access control

- **Objective:** Implement the external user model (IT and Operations contacts) with role differentiation.
- **Actions:**
  - [ ] Generate model: `rails g model PortalUser email:string name:string role:string company_id:uuid locked_at:timestamp`
  - [ ] Add to `PortalUser` model:
    - `enumerize :role, in: { it: 0, operations: 1, admin: 2 }`
    - `has_many :otp_codes, dependent: :destroy`
    - `has_many :validation_tokens, dependent: :destroy`
    - `has_many :integration_events, foreign_key: :actor_email, primary_key: :email`
    - Validation: `validates :email, presence: true, uniqueness: true`
    - Validation: `validates :role, presence: true`
    - Method: `locked?` -> returns `locked_at.present? && locked_at > Time.current`
    - Method: `unlock!` -> sets `locked_at = nil`
    - Method: `lock!` -> sets `locked_at = Time.current`
    - Scope: `unlocked` -> where "locked_at IS NULL OR locked_at < ?"
    - Scope: `by_role(role)` -> where role: role
  - [ ] Write RSpec tests:
    - Test validation of required fields
    - Test uniqueness of email
    - Test lock/unlock behavior
    - Test scope filters

- **Affected files/areas:** `app/models/portal_user.rb`, `spec/models/portal_user_spec.rb`

- **Completion criteria:** Model created with validations and associations; tests pass; no warnings

---

### Task 1.4 — Create OtpCode model with brute-force protection

- **Objective:** Implement short-lived OTP codes with attempt counting and expiration.
- **Actions:**
  - [ ] Generate model: `rails g model OtpCode portal_user:references code:string used_at:timestamp attempt_count:integer expires_at:timestamp`
  - [ ] Add to `OtpCode` model:
    - `belongs_to :portal_user`
    - Method: `self.generate_for(portal_user)` -> creates new code, sets `expires_at = 10.minutes.from_now`, returns code and record
    - Method: `valid?` -> returns `!expired? && !used? && attempt_count < 5`
    - Method: `expired?` -> returns `expires_at.past?`
    - Method: `used?` -> returns `used_at.present?`
    - Method: `verify(input_code)` -> increments `attempt_count`, returns `code == input_code && valid?`
    - Method: `mark_used!` -> sets `used_at = Time.current`
    - Scope: `expired` -> where "expires_at < ?"
  - [ ] Add to `PortalUser` model:
    - Method: `can_request_otp?` -> returns `!locked? && otp_codes.unexpired.count < 3`
    - Method: `lock_after_failed_attempts!` -> called if OTP attempt_count >= 5
  - [ ] Write RSpec tests:
    - Test OTP generation
    - Test expiration logic
    - Test attempt counting
    - Test brute-force lockout after 5 attempts
    - Test `can_request_otp?` limits

- **Affected files/areas:** `app/models/otp_code.rb`, `app/models/portal_user.rb` (update), `spec/models/otp_code_spec.rb`

- **Completion criteria:** OTP flow works end-to-end; brute-force protection tested; migrations clean

---

### Task 1.5 — Create ValidationToken model for invitation links

- **Objective:** Implement long-lived, single-use invitation tokens for email links.
- **Actions:**
  - [ ] Generate model: `rails g model ValidationToken portal_user:references token:string expires_at:timestamp used_at:timestamp ip_address:string user_agent:string`
  - [ ] Add to `ValidationToken` model:
    - `belongs_to :portal_user`
    - Method: `self.generate_for(portal_user)` -> generates secure random UUID, sets `expires_at = 30.days.from_now`, returns token and record
    - Method: `valid?` -> returns `!expired? && !used?`
    - Method: `expired?` -> returns `expires_at.past?`
    - Method: `used?` -> returns `used_at.present?`
    - Method: `consume!(ip, user_agent)` -> sets `used_at = Time.current`, `ip_address = ip`, `user_agent = user_agent`
    - Scope: `unexpired` -> where "expires_at > ?"
    - Scope: `unused` -> where "used_at IS NULL"
    - Scope: `valid` -> combination of unexpired and unused
  - [ ] Add to `PortalUser` model:
    - Association: `has_many :validation_tokens, dependent: :destroy`
  - [ ] Write RSpec tests:
    - Test token generation
    - Test token expiration
    - Test token consumption
    - Test scopes

- **Affected files/areas:** `app/models/validation_token.rb`, `app/models/portal_user.rb` (update), `spec/models/validation_token_spec.rb`

- **Completion criteria:** Token model works; tests pass; token format is a secure UUID

---

### Task 1.6 — Create IntegrationCompany model (lightweight company reference)

- **Objective:** Mirror company data from the main `app` (or seed manually for MVP).
- **Actions:**
  - [ ] Generate model: `rails g model IntegrationCompany company_id:uuid name:string it_contact_email:string ops_contact_email:string`
  - [ ] Add to `IntegrationCompany` model:
    - `has_many :integration_waves, dependent: :destroy`
    - Validation: `validates :company_id, presence: true, uniqueness: true`
    - Validation: `validates :name, presence: true`
    - Validation: `validates :it_contact_email, :ops_contact_email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true`
  - [ ] Create seed data for 2–3 test companies in `db/seeds.rb`
  - [ ] Write RSpec tests for validations

- **Affected files/areas:** `app/models/integration_company.rb`, `db/seeds.rb`, `spec/models/integration_company_spec.rb`

- **Completion criteria:** Company model created; test companies seeded; migrations clean

---

### Task 1.7 — Set up admin authentication (simple email/password, no Devise overhead)

- **Objective:** Lightweight admin login for the admin UI.
- **Actions:**
  - [ ] Generate migration: `rails g migration CreateAdminUsers email:string password_digest:string`
    - Add unique index on `email`
  - [ ] Generate model: `rails g model AdminUser email:string password_digest:string`
  - [ ] Add to `AdminUser` model:
    - `has_secure_password`
    - Validation: `validates :email, presence: true, uniqueness: true`
    - Class method: `authenticate(email, password)` -> finds user and verifies password; returns user or nil
  - [ ] Generate `SessionsController` (admin):
    - `new` action (login form)
    - `create` action (authenticate, set session)
    - `destroy` action (logout)
  - [ ] Add routes: `post '/admin/login', to: 'admin/sessions#create'`; `delete '/admin/logout', to: 'admin/sessions#destroy'`
  - [ ] Create admin layout template: `app/views/layouts/admin.html.erb` with logout link
  - [ ] Create admin login view: `app/views/admin/sessions/new.html.erb`
  - [ ] Add before_action filter: `AuthenticateAdmin` in admin controllers
  - [ ] Seed an initial admin user with credentials (output in log for initial setup)

- **Affected files/areas:** `app/models/admin_user.rb`, `app/controllers/admin/sessions_controller.rb`, `config/routes.rb`, `app/views/layouts/admin.html.erb`, `db/seeds.rb`

- **Completion criteria:** Admin login works; session persists across pages; logout clears session; no redirect loops

---

### Task 1.8 — Create base layout and portal user authentication flow (OTP only)

- **Objective:** Implement the OTP-based authentication flow and authenticated session for external users.
- **Actions:**
  - [ ] Create portal layout: `app/views/layouts/portal.html.erb` (unauthenticated design, minimal styling)
  - [ ] Generate `Portal::AuthenticationController`:
    - `show` action: displays OTP input form; accepts `token` param (from validation token)
    - `request_otp` action: POST endpoint; validates token, creates OTP, sends email, returns success
    - `verify_otp` action: POST endpoint; validates OTP code, creates session, redirects to portal home
  - [ ] Create views:
    - `app/views/portal/authentication/show.html.erb` — OTP input form
    - Partials for OTP input form and error messages
  - [ ] Generate `Portal::SessionsController`:
    - `destroy` action: clears session, redirects to login
  - [ ] Add routes:
    - `get '/authenticate', to: 'portal/authentication#show'` (receives `token` param)
    - `post '/request-otp', to: 'portal/authentication#request_otp'`
    - `post '/verify-otp', to: 'portal/authentication#verify_otp'`
    - `delete '/logout', to: 'portal/sessions#destroy'`
  - [ ] Create `AuthenticatePortalUser` before_action filter
  - [ ] Add helper method `current_portal_user` to application controller
  - [ ] Write integration tests:
    - Test happy path: token -> OTP page -> request OTP -> verify code -> authenticated
    - Test invalid token (expired)
    - Test invalid OTP code
    - Test brute-force lockout (5 failures)
    - Test logout

- **Affected files/areas:** `app/controllers/portal/authentication_controller.rb`, `app/controllers/portal/sessions_controller.rb`, `app/views/layouts/portal.html.erb`, `app/views/portal/authentication/`, `config/routes.rb`

- **Completion criteria:** OTP flow works end-to-end; session persists; logout clears session; integration tests pass

---

### Task 1.9 — Set up AWS SES for email sending

- **Objective:** Configure AWS SES and mailer infrastructure for OTP and notification emails.
- **Actions:**
  - [ ] Add to `config/credentials.yml.enc`:
    - `aws_region`
    - `aws_access_key_id`
    - `aws_secret_access_key`
    - `ses_sending_from_email` (verified sender email)
  - [ ] Generate `OtpMailer` class:
    - `send_otp(portal_user, code)` -> sends OTP code to `portal_user.email`
  - [ ] Generate `NotificationMailer` class:
    - `send_invitation(portal_user, validation_token_url)` -> sends invitation email with link
    - `notify_rejection(portal_user, query_name, rejection_reason)` -> sends rejection notification (Phase 4)
    - `send_validation_document(company_name, stakeholder_emails, pdf_attachment)` -> sends PDF to stakeholders (Phase 5)
  - [ ] Update mailer layout: `app/views/layouts/mailer.html.erb` with branding
  - [ ] Configure `config/environments/development.rb`:
    - `config.action_mailer.smtp_settings` -> use `:letter_opener` or local SMTP for dev
  - [ ] Configure `config/environments/production.rb`:
    - `config.action_mailer.delivery_method = :aws_ses`
    - Set `config.action_mailer.smtp_settings` with AWS credentials
  - [ ] Create spec for mailers (test email content, recipients, subject)
  - [ ] **NOTE:** Request AWS SES production access **early** (sandbox has sending limits)

- **Affected files/areas:** `config/credentials.yml.enc`, `app/mailers/`, `config/environments/`, `spec/mailers/`

- **Completion criteria:** Mailers created; email sending works in development (letter_opener); production config ready; SES access approved or pending

---

### Task 1.10 — Create health check endpoint

- **Objective:** Provide basic endpoint for deployment monitoring.
- **Actions:**
  - [ ] Generate `HealthController`:
    - `status` action: returns JSON `{ status: 'ok', timestamp: Time.current }`
    - Test database connectivity
  - [ ] Add route: `get '/health', to: 'health#status'`
  - [ ] Add to `config/routes.rb` (outside of session-authenticated scope)
  - [ ] Write RSpec test for successful response

- **Affected files/areas:** `app/controllers/health_controller.rb`, `config/routes.rb`, `spec/controllers/health_controller_spec.rb`

- **Completion criteria:** Health endpoint returns 200; database connectivity verified; no authentication required

---

## Phase 2: Query Catalog and Wave Configuration

### Task 2.1 — Create IntegrationQueryTemplate model (global query catalog)

- **Objective:** Define the catalog of available query templates that admins can assign per wave.
- **Actions:**
  - [ ] Generate model: `rails g model IntegrationQueryTemplate name:string description:text wave_type:string sort_order:integer`
  - [ ] Add to `IntegrationQueryTemplate` model:
    - `has_many :integration_queries, dependent: :destroy`
    - `enumerize :wave_type, in: { users: 0, indicators: 1 }`
    - Validation: `validates :name, presence: true, uniqueness: true`
    - Validation: `validates :wave_type, presence: true`
    - Scope: `by_wave_type(type)` -> where wave_type: type
  - [ ] Run migration: `rails g migration CreateIntegrationQueryTemplates ...`
  - [ ] Create seed data: 3–5 default query templates (e.g., "User Registration", "Manager Change")
  - [ ] Write RSpec tests for model validations and scopes

- **Affected files/areas:** `app/models/integration_query_template.rb`, `db/migrate/`, `db/seeds.rb`, `spec/models/integration_query_template_spec.rb`

- **Completion criteria:** Model created with validations; seed data loaded; tests pass

---

### Task 2.2 — Create IntegrationWave model with state machine

- **Objective:** Implement wave lifecycle (pending -> in_progress -> validated -> closed).
- **Actions:**
  - [ ] Generate model: `rails g model IntegrationWave integration_company:references wave_type:string state:string`
  - [ ] Add to `IntegrationWave` model:
    - `belongs_to :integration_company`
    - `has_many :integration_queries, dependent: :destroy`
    - `has_many :integration_events, dependent: :destroy`
    - `has_one :validation_document, dependent: :destroy`
    - State machine (using `aasm` or `state_machine` gem):
      - States: `pending`, `in_progress`, `validated`, `closed`
      - Transitions:
        - `pending` -> `in_progress` (admin action)
        - `in_progress` -> `validated` (automatic when all queries approved)
        - `validated` -> `closed` (admin action)
      - Callbacks: `before_transition` and `after_transition` hooks for logging
    - `enumerize :wave_type, in: { users: 0, indicators: 1 }`
    - Method: `all_queries_approved?` -> returns `integration_queries.all? { |q| q.approved? }`
    - Method: `auto_validate_if_ready!` -> transitions to validated if all_queries_approved?
    - Scope: `by_company(company_id)` -> where integration_company_id: company_id
    - Scope: `active` -> where state: [:pending, :in_progress]
  - [ ] Add `IntegrationEvent` logging:
    - Log state transitions in `after_transition` callback
  - [ ] Write RSpec tests:
    - Test state transitions
    - Test auto-validation logic
    - Test scopes

- **Affected files/areas:** `app/models/integration_wave.rb`, `spec/models/integration_wave_spec.rb`

- **Completion criteria:** State machine works; transitions logged; tests pass

---

### Task 2.3 — Create IntegrationQuery model with submission workflow

- **Objective:** Implement per-query submission and approval workflow.
- **Actions:**
  - [ ] Generate migration: `rails g migration CreateIntegrationQueries integration_wave:references integration_query_template:references sql_text:text state:string rejection_reason:text`
  - [ ] Generate model: `rails g model IntegrationQuery integration_wave:references integration_query_template:references sql_text:text state:string rejection_reason:text`
  - [ ] Add to `IntegrationQuery` model:
    - `belongs_to :integration_wave`
    - `belongs_to :integration_query_template`
    - State machine:
      - States: `pending`, `submitted`, `approved`, `rejected`
      - Transitions:
        - `pending` -> `submitted` (IT submits SQL)
        - `submitted` -> `approved` (Ops approves)
        - `submitted` -> `rejected` (Ops rejects with reason)
        - `rejected` -> `submitted` (IT resubmits)
      - Callbacks: log all transitions via `IntegrationEvent`
    - Validation: `validates :sql_text, presence: true, unless: :pending?`
    - Method: `template_name` -> delegates to template.name
    - Scope: `by_state(state)` -> where state: state
    - Scope: `awaiting_submission` -> where state: :pending
    - Scope: `submitted_or_awaiting_approval` -> where state: [:submitted]
    - Scope: `awaiting_approval` -> where state: :submitted
  - [ ] Add callback in `integration_wave.rb`:
    - After query state change, call `wave.auto_validate_if_ready!`
  - [ ] Write RSpec tests:
    - Test state transitions
    - Test validations
    - Test auto-wave-validation trigger

- **Affected files/areas:** `app/models/integration_query.rb`, `app/models/integration_wave.rb` (update), `spec/models/integration_query_spec.rb`

- **Completion criteria:** Query model created; state machine works; wave auto-validates when all queries approved

---

### Task 2.4 — Create IntegrationEvent model (append-only audit trail)

- **Objective:** Implement immutable event log for timeline and audit trail.
- **Actions:**
  - [ ] Generate migration: `rails g migration CreateIntegrationEvents integration_wave:references event_type:string actor_email:string metadata:jsonb ip_address:string user_agent:string`
  - [ ] Generate model: `rails g model IntegrationEvent integration_wave:references event_type:string actor_email:string metadata:jsonb ip_address:string user_agent:string`
  - [ ] Add to `IntegrationEvent` model:
    - `belongs_to :integration_wave`
    - `enumerize :event_type, in: { invitation_sent: 0, otp_verified: 1, query_submitted: 2, query_approved: 3, query_rejected: 4, wave_validated: 5, pdf_generated: 6, pdf_delivered: 7 }`
    - Validation: `validates :event_type, :actor_email, presence: true`
    - **IMPORTANT:** Make the table immutable at database level:
      - Add check constraint: `ALTER TABLE integration_events ADD CONSTRAINT immutable_events CHECK (true);`
      - Or: disable update/delete triggers via Rails model `readonly!` or migration
    - Class method: `log_event(wave, type, actor_email, metadata = {}, ip_address = nil, user_agent = nil)` -> creates record
    - Scope: `by_type(type)` -> where event_type: type
    - Scope: `by_actor(email)` -> where actor_email: email
    - Scope: `chronological` -> order(created_at: :asc)
    - Method to prevent any update/delete: override `update`, `destroy`, `delete` to raise error
  - [ ] Write RSpec tests:
    - Test event creation
    - Test immutability (no update/delete possible)
    - Test scopes

- **Affected files/areas:** `app/models/integration_event.rb`, `db/migrate/`, `spec/models/integration_event_spec.rb`

- **Completion criteria:** Event model works; immutability enforced; tests pass; no accidental updates possible

---

### Task 2.5 — Create admin UI: Query Template management

- **Objective:** Admin interface to create and edit query templates.
- **Actions:**
  - [ ] Generate `Admin::IntegrationQueryTemplatesController`:
    - `index` action: list all templates
    - `new` action: form for new template
    - `create` action: save template
    - `edit` action: form for editing
    - `update` action: save changes
    - `destroy` action: delete (soft delete optional)
  - [ ] Create views:
    - `app/views/admin/integration_query_templates/index.html.erb`
    - `app/views/admin/integration_query_templates/_form.html.erb`
    - `app/views/admin/integration_query_templates/new.html.erb`
    - `app/views/admin/integration_query_templates/edit.html.erb`
  - [ ] Add routes:
    - `namespace :admin do; resources :integration_query_templates; end`
  - [ ] Add authorization check (admin_user authenticated)
  - [ ] Write integration tests:
    - Test CRUD operations
    - Test form validation
    - Test unauthenticated access denied

- **Affected files/areas:** `app/controllers/admin/integration_query_templates_controller.rb`, `app/views/admin/integration_query_templates/`, `config/routes.rb`

- **Completion criteria:** Admin can create, read, update query templates; list displays all templates; form validation works

---

### Task 2.6 — Create admin UI: Wave creation and query assignment

- **Objective:** Admin interface to create waves and assign query templates to them.
- **Actions:**
  - [ ] Generate `Admin::IntegrationWavesController`:
    - `index` action: list waves by company
    - `new` action: form to create new wave (select company, select templates for the wave)
    - `create` action: save wave and auto-create IntegrationQuery records for each assigned template
    - `show` action: display wave with list of queries and their states
    - `edit` action: form to change wave state (move to in_progress, close)
    - `update` action: update wave state
  - [ ] Create views:
    - `app/views/admin/integration_waves/index.html.erb`
    - `app/views/admin/integration_waves/_form.html.erb`
    - `app/views/admin/integration_waves/new.html.erb`
    - `app/views/admin/integration_waves/show.html.erb` — display wave status with query list
  - [ ] Form includes:
    - Company dropdown (select from IntegrationCompany)
    - Multi-select checkboxes for query templates (filtered by wave_type)
    - Wave type selector (Users vs Indicators)
  - [ ] On create:
    - Validate: at least 1 query template selected
    - Create IntegrationQuery for each template (state: pending)
    - Log `wave_created` event
  - [ ] Add routes: `namespace :admin do; resources :integration_waves; end`
  - [ ] Write integration tests:
    - Test create wave with template selection
    - Test query auto-creation
    - Test state transitions
    - Test display of wave status

- **Affected files/areas:** `app/controllers/admin/integration_waves_controller.rb`, `app/views/admin/integration_waves/`, `config/routes.rb`

- **Completion criteria:** Admin can create waves and assign queries; queries auto-created and listed; wave state displayed

---

### Task 2.7 — Create admin UI: Company management (list only for MVP)

- **Objective:** Admin can view and list companies and their waves.
- **Actions:**
  - [ ] Generate `Admin::IntegrationCompaniesController`:
    - `index` action: list all companies with count of active waves
    - `show` action: display company details with list of all waves and their states
  - [ ] Create views:
    - `app/views/admin/integration_companies/index.html.erb` — table of companies
    - `app/views/admin/integration_companies/show.html.erb` — company detail with wave list
  - [ ] Display on show:
    - Company name, IT contact email, Operations contact email
    - Table of waves: wave_type, state, number of queries, number approved
    - Links to edit wave, send invitations (Phase 3)
  - [ ] Add routes: `namespace :admin do; resources :integration_companies, only: [:index, :show]; end`
  - [ ] Write integration tests

- **Affected files/areas:** `app/controllers/admin/integration_companies_controller.rb`, `app/views/admin/integration_companies/`, `config/routes.rb`

- **Completion criteria:** Admin can view companies and waves; list displays correctly; links work

---

## Phase 3: IT Submission Portal

### Task 3.1 — Implement invitation email sending from admin UI

- **Objective:** Admin can trigger invitation emails to IT contacts for a specific wave.
- **Actions:**
  - [ ] Add action to `Admin::IntegrationWavesController`:
    - `send_invitation` POST action
    - Accepts `portal_user_email` param (IT contact email)
    - Creates or finds PortalUser with role `:it` and company_id matching the wave's company
    - Creates ValidationToken for the user
    - Builds invitation URL: `/authenticate?token={token}`
    - Calls `NotificationMailer.send_invitation(portal_user, invitation_url).deliver_later`
    - Logs `invitation_sent` event to IntegrationEvent
    - Returns success/error message
  - [ ] Add view button on wave show page to send invitation
  - [ ] Add form/modal to enter IT contact email
  - [ ] Write integration tests:
    - Test invitation email sent with correct link
    - Test PortalUser created if not exists
    - Test event logged
    - Test mailer content includes invitation link

- **Affected files/areas:** `app/controllers/admin/integration_waves_controller.rb`, `app/views/admin/integration_waves/show.html.erb`, `app/mailers/notification_mailer.rb`

- **Completion criteria:** Admin can send invitation; email received; link works; event logged

---

### Task 3.2 — Create IT portal home page (list of assigned waves)

- **Objective:** After authentication, IT contacts see list of waves they are assigned to with query status.
- **Actions:**
  - [ ] Generate `Portal::ItPortalController`:
    - `index` action: display list of IntegrationWaves for the authenticated IT user's company
    - Each wave shows:
      - Wave type (Users/Indicators)
      - Current state
      - Progress: "X of Y queries submitted"
      - Link to submit queries
  - [ ] Create view: `app/views/portal/it_portal/index.html.erb`
  - [ ] Add route: `get '/portal/it', to: 'portal/it_portal#index'`
  - [ ] Add before_action to verify authenticated + role == :it
  - [ ] Write integration tests:
    - Test IT user sees only their company's waves
    - Test query count displays correctly
    - Test link to submit queries

- **Affected files/areas:** `app/controllers/portal/it_portal_controller.rb`, `app/views/portal/it_portal/index.html.erb`, `config/routes.rb`

- **Completion criteria:** IT user sees their assigned waves; query status displays; links work

---

### Task 3.3 — Create IT submission form (per-wave query submission)

- **Objective:** IT contacts submit SQL queries for each integration flow in their assigned wave.
- **Actions:**
  - [ ] Generate `Portal::ItSubmissionsController`:
    - `show` action: display form for a specific wave with list of pending/rejected queries
    - `create` action: save SQL text for a query and transition to `:submitted`
  - [ ] Create view: `app/views/portal/it_submissions/show.html.erb`
    - For each IntegrationQuery in the wave:
      - Display template name and description
      - Display form field for SQL input (textarea)
      - Show state (pending, submitted, rejected)
      - If rejected, show rejection reason
      - Submit button per query
    - Resubmit button for rejected queries
  - [ ] Form includes:
    - CSRF protection
    - Client-side validation (SQL not empty)
    - Server-side validation (sql_text required)
  - [ ] On submit:
    - Validate: query belongs to authenticated user's company's wave
    - Update query: `sql_text = params[:sql]`, state = `:submitted`
    - Log `query_submitted` event with actor IP, user agent
    - Call `wave.auto_validate_if_ready!` (in case all queries now submitted)
    - Return success message
  - [ ] Add routes:
    - `get '/portal/it/waves/:wave_id/submit', to: 'portal/it_submissions#show'`
    - `post '/portal/it/queries/:query_id/submit', to: 'portal/it_submissions#create'`
  - [ ] Write integration tests:
    - Test IT user can submit SQL
    - Test query state transitions to submitted
    - Test event logged with IP/user agent
    - Test cannot submit for another company's wave
    - Test resubmission of rejected query

- **Affected files/areas:** `app/controllers/portal/it_submissions_controller.rb`, `app/views/portal/it_submissions/`, `config/routes.rb`

- **Completion criteria:** IT can view queries and submit SQL; state transitions; events logged; form validation works

---

### Task 3.4 — Record submission metadata (IP address, user agent, timestamp)

- **Objective:** Capture full context when IT submits a query.
- **Actions:**
  - [ ] Add to query model migration (if not already):
    - `submitted_at` timestamp
    - `submitted_from_ip` string
    - `submitted_from_user_agent` string
  - [ ] Update `IntegrationQuery` model:
    - Add attributes: `submitted_at`, `submitted_from_ip`, `submitted_from_user_agent`
    - Callback `before_save`: if transitioning to `:submitted`, auto-populate IP and user_agent from request
  - [ ] Update IT submissions controller:
    - Capture `request.remote_ip` and `request.user_agent`
    - Pass to query update
  - [ ] Create IntegrationEvent with metadata:
    - `metadata: { query_template: template.name, submitted_from_ip: ip, user_agent: user_agent }`
  - [ ] Write tests to verify IP/user agent captured

- **Affected files/areas:** `db/migrate/`, `app/models/integration_query.rb`, `app/controllers/portal/it_submissions_controller.rb`

- **Completion criteria:** Submission metadata captured and stored; events include IP/user agent; tests pass

---

## Phase 4: Operations Validation Portal

### Task 4.1 — Create Operations portal home page (list of submitted queries per wave)

- **Objective:** Operations contacts see all submitted queries for their assigned waves grouped by flow.
- **Actions:**
  - [ ] Generate `Portal::OpsPortalController`:
    - `index` action: display list of IntegrationWaves for Operations user's company in `:in_progress` or `:validated` state
    - Each wave shows:
      - Wave type
      - Progress: "X of Y queries approved"
      - Link to review queries
  - [ ] Generate `Portal::OpsValidationsController`:
    - `show` action: display all queries for a wave grouped by template, with validation status
  - [ ] Create views:
    - `app/views/portal/ops_portal/index.html.erb`
    - `app/views/portal/ops_validations/show.html.erb` — query list with approval actions
  - [ ] Query list displays:
    - Template name
    - Current state
    - IT-submitted SQL (read-only)
    - Approval action buttons (Approve / Reject)
  - [ ] Add routes:
    - `get '/portal/ops', to: 'portal/ops_portal#index'`
    - `get '/portal/ops/waves/:wave_id/validate', to: 'portal/ops_validations#show'`
  - [ ] Add before_action to verify authenticated + role == :operations
  - [ ] Write integration tests

- **Affected files/areas:** `app/controllers/portal/ops_portal_controller.rb`, `app/controllers/portal/ops_validations_controller.rb`, `app/views/portal/ops_portal/`, `app/views/portal/ops_validations/`, `config/routes.rb`

- **Completion criteria:** Ops user sees waves and queries; list groups by flow; action buttons display

---

### Task 4.2 — Implement query approval action (Operations marks query as approved)

- **Objective:** Operations can approve a submitted query; captures IP and timestamp.
- **Actions:**
  - [ ] Add `approve` action to `Portal::OpsValidationsController`:
    - POST endpoint: `/portal/ops/queries/:query_id/approve`
    - Validation: query exists and belongs to ops user's company's wave
    - Validation: query state is `:submitted`
    - Update query:
      - State = `:approved`
      - `approved_at = Time.current`
      - `approved_from_ip = request.remote_ip`
      - `approved_from_user_agent = request.user_agent`
    - Log `query_approved` event with metadata (template name, ip, user_agent, approved_at)
    - Call `wave.auto_validate_if_ready!` to potentially auto-transition wave to `:validated`
    - Return success message
  - [ ] Add to migration (if not already):
    - `approved_at` timestamp
    - `approved_from_ip` string
    - `approved_from_user_agent` string
  - [ ] Update `IntegrationQuery` model with these attributes
  - [ ] Create button on validation show view: "Approve" for each `:submitted` query
  - [ ] Write integration tests:
    - Test query approved successfully
    - Test IP/user agent captured
    - Test event logged
    - Test wave auto-validates if all queries approved
    - Test cannot approve already-approved query

- **Affected files/areas:** `app/controllers/portal/ops_validations_controller.rb`, `app/views/portal/ops_validations/show.html.erb`, `db/migrate/`, `app/models/integration_query.rb`

- **Completion criteria:** Ops can approve queries; IP captured; wave auto-validates; tests pass

---

### Task 4.3 — Implement query rejection action (Operations rejects with reason)

- **Objective:** Operations can reject a query with a reason; IT is notified by email.
- **Actions:**
  - [ ] Add `reject` action to `Portal::OpsValidationsController`:
    - POST endpoint: `/portal/ops/queries/:query_id/reject`
    - Accepts `rejection_reason` param
    - Validation: query exists and belongs to ops user's company's wave
    - Validation: query state is `:submitted`
    - Validation: rejection_reason not blank
    - Update query:
      - State = `:rejected`
      - `rejection_reason = params[:rejection_reason]`
      - `rejected_at = Time.current`
      - `rejected_from_ip = request.remote_ip`
    - Log `query_rejected` event with metadata
    - Send email to IT contact: `NotificationMailer.notify_rejection(...)`
    - Return success message
  - [ ] Add to migration (if not already):
    - `rejected_at` timestamp
    - `rejected_from_ip` string
  - [ ] Update `IntegrationQuery` model with these attributes
  - [ ] Create rejection form on validation show view:
    - Modal or inline form with reason textarea
    - Submit button: "Reject with Reason"
  - [ ] Email content:
    - To: IT contact's email
    - Subject: "Query Rejected – [Wave] – [Template Name]"
    - Body: Query template name, rejection reason, link to resubmit
  - [ ] Write integration tests:
    - Test query rejected successfully
    - Test rejection email sent to correct IT contact
    - Test IT can resubmit after rejection

- **Affected files/areas:** `app/controllers/portal/ops_validations_controller.rb`, `app/views/portal/ops_validations/`, `app/mailers/notification_mailer.rb`, `db/migrate/`, `app/models/integration_query.rb`

- **Completion criteria:** Ops can reject with reason; email sent; IT can resubmit; tests pass

---

### Task 4.4 — Implement automatic wave validation (when all queries approved)

- **Objective:** When the last query is approved, wave automatically transitions to `:validated`.
- **Actions:**
  - [ ] This is already defined in Task 2.2 (`auto_validate_if_ready!` method)
  - [ ] Verify method is called after every query approval:
    - In `Portal::OpsValidationsController#approve` action
    - In callback after query state change
  - [ ] Implement method in `IntegrationWave`:
    - `auto_validate_if_ready!` -> checks if all queries `.approved?`
    - If yes: transitions state to `:validated`, logs event
    - Triggers Phase 5 (PDF generation) via background job
  - [ ] Write integration tests:
    - Test wave auto-validates when all queries approved
    - Test wave does NOT validate if any query still pending/rejected
    - Test event logged

- **Affected files/areas:** `app/models/integration_wave.rb`, `app/controllers/portal/ops_validations_controller.rb`

- **Completion criteria:** Wave auto-validates; event logged; tests pass

---

## Phase 5: PDF Generation and Delivery

### Task 5.1 — Set up Sidekiq and Redis for background jobs

- **Objective:** Configure infrastructure for async PDF generation and email delivery.
- **Actions:**
  - [ ] Add gems to Gemfile: `sidekiq`, `redis`, `sidekiq-scheduler` (optional, for maintenance jobs)
  - [ ] Run `bundle install`
  - [ ] Create initializer: `config/initializers/sidekiq.rb`:
    - Configure Redis connection
    - Set concurrency and queues
  - [ ] Update `config/environments/production.rb`:
    - `config.active_job.queue_adapter = :sidekiq`
  - [ ] Update `config/cable.yml` to use Redis
  - [ ] Create Dockerfile or update existing to include Redis
  - [ ] Write basic test to verify Sidekiq can enqueue jobs

- **Affected files/areas:** `Gemfile`, `config/initializers/sidekiq.rb`, `config/environments/`, `Dockerfile`

- **Completion criteria:** Sidekiq configured; Redis available; jobs can be enqueued

---

### Task 5.2 — Create ValidationDocument model (immutable PDF record)

- **Objective:** Store metadata about generated PDFs (version, URL, checksum).
- **Actions:**
  - [ ] Generate migration: `rails g migration CreateValidationDocuments integration_wave:references version:string s3_url:string sha256_checksum:string generated_at:timestamp`
  - [ ] Generate model: `rails g model ValidationDocument integration_wave:references version:string s3_url:string sha256_checksum:string generated_at:timestamp`
  - [ ] Add to `ValidationDocument` model:
    - `belongs_to :integration_wave`
    - Validation: `validates :version, presence: true, uniqueness: { scope: :integration_wave_id }`
    - Validation: `validates :s3_url, presence: true`
    - Validation: `validates :sha256_checksum, presence: true`
    - Make immutable: override update, destroy to raise error (similar to IntegrationEvent)
    - Method: `s3_signed_url` -> generates signed URL for S3 download (1-hour expiry)
  - [ ] Add association to `IntegrationWave`: `has_one :validation_document, dependent: :destroy`
  - [ ] Write RSpec tests:
    - Test immutability
    - Test signed URL generation

- **Affected files/areas:** `app/models/validation_document.rb`, `app/models/integration_wave.rb` (update), `db/migrate/`

- **Completion criteria:** Model created; immutable; tests pass

---

### Task 5.3 — Create PDF template (ERB) for validated wave document

- **Objective:** Design HTML template for PDF output.
- **Actions:**
  - [ ] Create view: `app/views/validation_documents/wave_summary.html.erb`
  - [ ] Template includes:
    - Header: "Integration Validation Report"
    - Company name, wave type, wave state
    - Generated timestamp, version number
    - Table of all queries:
      - Template name
      - Description
      - Submitted SQL (code block)
      - Submission IP / timestamp
      - Approval IP / timestamp
      - Status (approved)
    - Summary section: number of queries, all approved date
    - Footer: immutable, generated by Integration Validation Portal
  - [ ] Styling:
    - Basic CSS for readability (borders, spacing)
    - Page breaks if needed
    - Responsive to PDF width
  - [ ] Create partial: `app/views/validation_documents/_query_section.html.erb` for query detail
  - [ ] Write view spec to test rendering without errors

- **Affected files/areas:** `app/views/validation_documents/wave_summary.html.erb`, `app/views/validation_documents/_query_section.html.erb`

- **Completion criteria:** Template renders; includes all required data; styled for PDF

---

### Task 5.4 — Create background job to generate PDF (ferrum_pdf)

- **Objective:** Async job to render HTML template to PDF and upload to S3.
- **Actions:**
  - [ ] Generate job: `rails g job PdfGenerationJob`
  - [ ] Implement `GeneratePdfJob`:
    - Perform method accepts `wave_id`
    - Fetch `IntegrationWave` record
    - Render HTML template to string (use `render_to_string` with context)
    - Initialize ferrum_pdf: `Ferrum::PDF.new(html_string)` -> generates PDF bytes
    - Calculate SHA256 checksum of PDF bytes
    - Upload to S3 via AWS SDK:
      - Bucket: ENV['AWS_S3_PDF_BUCKET']
      - Key: `validation_documents/#{wave.id}/v#{version}.pdf`
      - Create signed URL (1-hour expiry)
    - Create `ValidationDocument` record with:
      - S3 URL
      - Version (format: "1.0")
      - SHA256 checksum
      - Generated timestamp
    - Log `pdf_generated` event
    - Return success or raise error for Sidekiq retry
    - Error handling: if PDF generation fails, job is retried; wave stays in `:validated` state (PDF is optional for MVP)
  - [ ] Add to Dockerfile:
    - Install Chromium/Chrome: `apt-get install chromium-browser` (for ferrum_pdf)
    - Verify it's available: `which chromium-browser`
  - [ ] Write RSpec tests:
    - Mock ferrum_pdf
    - Mock S3 upload
    - Test event logged
    - Test ValidationDocument created
    - Test error handling and retry

- **Affected files/areas:** `app/jobs/generate_pdf_job.rb`, `Dockerfile`, `spec/jobs/generate_pdf_job_spec.rb`

- **Completion criteria:** Job generates PDF; uploads to S3; creates record; tests pass; errors handled gracefully

---

### Task 5.5 — Integrate PDF generation into wave validation flow

- **Objective:** Trigger PDF generation when wave transitions to `:validated`.
- **Actions:**
  - [ ] Add callback to `IntegrationWave`:
    - `after_transition :to => :validated, :do => :trigger_pdf_generation`
    - Method: `trigger_pdf_generation` -> enqueues `GeneratePdfJob.perform_later(id)`
  - [ ] Log `pdf_job_enqueued` event (optional, for audit)
  - [ ] Write integration test:
    - Test wave validation triggers PDF job
    - Verify job is enqueued

- **Affected files/areas:** `app/models/integration_wave.rb`

- **Completion criteria:** PDF job triggered on wave validation; job enqueued; tests pass

---

### Task 5.6 — Create mailer to send PDF to stakeholders

- **Objective:** Email PDF (as S3 link or attachment) to IT, Operations, and admin contacts after generation.
- **Actions:**
  - [ ] Add to `NotificationMailer`:
    - `send_validation_document(company_name, stakeholder_emails, validation_document)` method
    - Email recipients: IT contact, Operations contact, admin email
    - Subject: "[Company] Integration Validation Report – [Wave Type] – [Date]"
    - Body:
      - Company and wave info
      - "All queries have been validated. Please see attached report."
      - Download link: `validation_document.s3_signed_url`
      - Or: attach PDF directly to email (if file size reasonable)
    - Add `validation_document` as attachment (if available)
  - [ ] Update `GeneratePdfJob`:
    - After creating `ValidationDocument`, call `NotificationMailer.send_validation_document(...).deliver_later`
  - [ ] Log `pdf_delivered` event after email sent
  - [ ] Write mailer spec:
    - Test email content
    - Test recipients
    - Test signed URL included or attachment present

- **Affected files/areas:** `app/mailers/notification_mailer.rb`, `app/jobs/generate_pdf_job.rb`, `spec/mailers/notification_mailer_spec.rb`

- **Completion criteria:** Email sent to stakeholders; PDF link/attachment included; event logged

---

### Task 5.7 — Set up AWS S3 bucket for PDF storage

- **Objective:** Configure S3 bucket and credentials for PDF upload.
- **Actions:**
  - [ ] Add to `config/credentials.yml.enc`:
    - `aws_s3_pdf_bucket` (bucket name)
    - AWS credentials (if not already set)
  - [ ] Update `config/environments/production.rb`:
    - Configure Active Storage or direct S3 access via AWS SDK
    - Bucket and region settings
  - [ ] Create S3 bucket policy (if not already done):
    - Allow signed URL downloads (public read not needed)
    - Allow app IAM role to upload objects
  - [ ] Update Dockerfile env vars to include S3 bucket name
  - [ ] Write test/rake task to verify S3 connectivity

- **Affected files/areas:** `config/credentials.yml.enc`, `config/environments/production.rb`, `Dockerfile`

- **Completion criteria:** S3 bucket configured; credentials stored; upload tested

---

## Phase 6: Timeline and Audit Trail UI

### Task 6.1 — Create admin timeline view (full event history for a wave)

- **Objective:** Admin can view complete chronological event log for any wave.
- **Actions:**
  - [ ] Add `show_timeline` action to `Admin::IntegrationWavesController`:
    - `get '/admin/waves/:wave_id/timeline', to: 'admin/integration_waves#show_timeline'`
    - Fetch wave and all associated `IntegrationEvent` records
    - Order by created_at ascending
  - [ ] Create view: `app/views/admin/integration_waves/show_timeline.html.erb`
    - Display timeline as chronological list (or vertical line)
    - For each event:
      - Event type (label)
      - Timestamp
      - Actor email
      - IP address and user agent (in expandable detail)
      - Event metadata (if any)
    - Filter by event type (optional dropdown)
  - [ ] Add navigation link from wave show page to timeline view
  - [ ] Write integration tests:
    - Test timeline displays all events
    - Test correct order
    - Test event details visible

- **Affected files/areas:** `app/controllers/admin/integration_waves_controller.rb`, `app/views/admin/integration_waves/show_timeline.html.erb`, `config/routes.rb`

- **Completion criteria:** Admin can view complete timeline; events ordered chronologically; details visible

---

### Task 6.2 — Create read-only timeline view for IT and Operations portals

- **Objective:** External users see a filtered, read-only summary of key events.
- **Actions:**
  - [ ] Add `timeline` action to `Portal::OpsValidationsController` and create similar for IT:
    - `get '/portal/it/waves/:wave_id/timeline', to: 'portal/it_submissions#timeline'`
    - `get '/portal/ops/waves/:wave_id/timeline', to: 'portal/ops_validations#timeline'`
    - Filter events: only show events relevant to external users
      - IT sees: query_submitted, query_approved, query_rejected (not internal admin events)
      - Operations sees: query_submitted, query_approved, query_rejected, wave_validated
    - Order by created_at
  - [ ] Create view: `app/views/portal/it_submissions/timeline.html.erb` and similar for ops
    - Simplified timeline display (no IP details for privacy)
    - Show: event type, timestamp, query template name (if applicable)
  - [ ] Add navigation link from wave submission/validation pages to timeline
  - [ ] Write integration tests

- **Affected files/areas:** `app/controllers/portal/it_submissions_controller.rb`, `app/controllers/portal/ops_validations_controller.rb`, `app/views/portal/it_submissions/timeline.html.erb`, `app/views/portal/ops_validations/timeline.html.erb`

- **Completion criteria:** IT/Ops see filtered timeline; no sensitive data exposed; read-only

---

### Task 6.3 — Create wave progress indicator (visual status of queries)

- **Objective:** Display query state counts and progress bar on wave pages.
- **Actions:**
  - [ ] Create partial: `app/views/shared/_wave_progress.html.erb`
    - Query state breakdown:
      - Pending (count)
      - Submitted (count)
      - Approved (count)
      - Rejected (count)
    - Progress bar: percentage of approved queries
    - Color coding: pending=gray, submitted=yellow, approved=green, rejected=red
  - [ ] Add to Admin wave show page
  - [ ] Add to IT submission page
  - [ ] Add to Operations validation page
  - [ ] Make real-time if Hotwire Turbo used (optional, for MVP not critical)
  - [ ] Write view spec

- **Affected files/areas:** `app/views/shared/_wave_progress.html.erb`, relevant wave views

- **Completion criteria:** Progress indicator displays on all wave views; counts accurate; colors clear

---

## Phase 7: API Integration with `app`

### Task 7.1 — Define and document API contract with `app` team

- **Objective:** Establish what company/contact data needs to be fetched from main `app`.
- **Actions:**
  - [ ] Document required data from `app`:
    - Company list: company_id, company_name, it_contact_email, ops_contact_email
    - Indicator list: indicator_id, indicator_name, company_id (for Phase 2+ reference)
  - [ ] Coordinate with `app` team:
    - API endpoint(s) to provide this data
    - Authentication mechanism (API key, Bearer token, etc.)
    - Rate limits and caching strategy
  - [ ] Create spec document in project README or separate API_CONTRACT.md
  - [ ] **NOTE**: This task depends on `app` team coordination. For MVP, manual seeding is acceptable.

- **Affected files/areas:** `README.md` or `API_CONTRACT.md`

- **Completion criteria:** API contract documented; `app` team confirmed; endpoint URL known

---

### Task 7.2 — Implement HTTP client to fetch company data from `app` API

- **Objective:** Create a client to call the `app` API and fetch company/contact data.
- **Actions:**
  - [ ] Add gem to Gemfile: `faraday` (or use Net::HTTP)
  - [ ] Create service class: `app/services/app_api_client.rb`
    - Method: `fetch_companies` -> calls `/api/companies` on `app`, returns list
    - Method: `fetch_company(company_id)` -> calls `/api/companies/{id}`, returns details
    - Error handling:
      - Timeout: rescue and log error; return nil
      - 4xx/5xx: rescue and log error; return nil
      - Network error: rescue and log error; return nil
    - Include API key authentication in headers
  - [ ] Create background job: `SyncCompaniesJob`
    - Fetches all companies from `app` API
    - Upserts `IntegrationCompany` records (create if not exists, update name/emails if changed)
    - Log `companies_synced` event (or store in sync history table)
    - Error handling: if API unavailable, job fails gracefully and is retried
  - [ ] Write RSpec tests:
    - Mock API responses
    - Test upsert logic
    - Test error handling

- **Affected files/areas:** `app/services/app_api_client.rb`, `app/jobs/sync_companies_job.rb`, `config/credentials.yml.enc` (API key), `spec/services/app_api_client_spec.rb`, `spec/jobs/sync_companies_job_spec.rb`

- **Completion criteria:** API client works; job syncs companies; tests pass; error handling robust

---

### Task 7.3 — Integrate company sync into initialization and periodic refresh

- **Objective:** Keep company data in sync with `app` automatically.
- **Actions:**
  - [ ] Create rake task: `rake companies:sync` -> calls `SyncCompaniesJob.perform_later`
  - [ ] Add to deployment/initialization:
    - Run `rake companies:sync` after initial deployment
  - [ ] Set up periodic sync (using sidekiq-scheduler or similar):
    - Run `SyncCompaniesJob` daily at 2:00 AM
  - [ ] Add admin UI button to trigger sync manually (for emergencies)
  - [ ] Add logging to track sync history (timestamps, success/failure)
  - [ ] Write integration tests:
    - Test rake task works
    - Test periodic job enqueued

- **Affected files/areas:** `lib/tasks/companies.rake`, `config/initializers/sidekiq_scheduler.rb` (if used), `app/controllers/admin/system_controller.rb` (manual trigger)

- **Completion criteria:** Company sync works; periodic refresh configured; admin can trigger manually

---

## Phase 8: Infrastructure and Deployment

### Task 8.1 — Create Dockerfile with Chrome/Chromium for ferrum_pdf

- **Objective:** Package Rails app in Docker with all dependencies including Chrome for PDF generation.
- **Actions:**
  - [ ] Create `Dockerfile`:
    - Base image: `ruby:3.2` or later (or `ruby:3.3`)
    - Install system dependencies:
      - `postgresql-client` (for database connection)
      - `chromium-browser` or `google-chrome-stable` (for ferrum_pdf)
      - `build-essential`, `libpq-dev` (for gem compilation)
    - Copy `Gemfile` and `Gemfile.lock`
    - Run `bundle install --production` (with no-dev flag)
    - Copy app code
    - Run `bundle exec rails assets:precompile` (if using assets)
    - Expose port 3000 (or configured port)
    - Set entrypoint: `bundle exec rails server -b 0.0.0.0`
  - [ ] Create `.dockerignore` to exclude unnecessary files
  - [ ] Test Dockerfile builds without errors
  - [ ] Test Rails server starts in container
  - [ ] Test Chrome availability in container: `chromium-browser --version`
  - [ ] Create docker-compose.yml (optional, for local dev):
    - Rails service
    - PostgreSQL service
    - Redis service (for Sidekiq)
  - [ ] Write documentation in README: how to build and run

- **Affected files/areas:** `Dockerfile`, `.dockerignore`, `docker-compose.yml` (optional), `README.md`

- **Completion criteria:** Docker image builds; Rails starts; Chrome available; all services available

---

### Task 8.2 — Set up AWS ECS task definition and CloudFormation/Terraform template

- **Objective:** Define ECS task for running the Rails app.
- **Actions:**
  - [ ] Create ECS task definition (JSON or Terraform):
    - Container: Rails app image
    - Port mapping: 3000
    - Environment variables:
      - `RAILS_ENV=production`
      - `DATABASE_URL` (RDS endpoint)
      - `REDIS_URL` (ElastiCache endpoint)
      - `AWS_REGION`, `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY` (from Secrets Manager)
      - `RAILS_MASTER_KEY` (from Secrets Manager)
    - Log driver: CloudWatch Logs
    - CPU: 512–1024 (adjust as needed)
    - Memory: 1024–2048 (adjust as needed)
  - [ ] Create separate ECS task for Sidekiq workers (same image, different entrypoint):
    - Entrypoint: `bundle exec sidekiq -c 5 -q default`
    - Same environment variables
  - [ ] Create CloudFormation or Terraform template for:
    - ALB (Application Load Balancer)
    - ECS service (linked to ALB)
    - Auto-scaling group or desired task count
  - [ ] Verify task definition is valid
  - [ ] Document deployment steps in README

- **Affected files/areas:** `terraform/` or `cloudformation/` directory, `README.md`

- **Completion criteria:** Task definition created; both web and worker tasks defined; template valid

---

### Task 8.3 — Set up RDS PostgreSQL database for production

- **Objective:** Create and configure production database.
- **Actions:**
  - [ ] Create RDS PostgreSQL instance:
    - Engine: PostgreSQL 14+ (or latest stable)
    - Instance type: db.t3.micro or db.t3.small (adjust as needed)
    - Multi-AZ: false (for MVP; can enable later)
    - Backup retention: 7 days
    - Storage: 20 GB (adjust as needed)
    - Security group: allow port 5432 from ECS task security group
    - Database name: `integration_portal_prod` (or configured)
  - [ ] Create parameter group with appropriate settings:
    - `max_connections` appropriate for app load
  - [ ] Create subnet group spanning multiple AZs
  - [ ] Document RDS endpoint URL
  - [ ] Test connectivity from local machine (optional)
  - [ ] Document in README: how to connect, backup info

- **Affected files/areas:** `terraform/` or AWS console, `README.md`

- **Completion criteria:** RDS instance created; accessible from ECS; endpoint documented

---

### Task 8.4 — Set up ElastiCache Redis for Sidekiq and sessions

- **Objective:** Create Redis cluster for background jobs and session storage.
- **Actions:**
  - [ ] Create ElastiCache Redis cluster:
    - Engine: Redis 7+ (or latest stable)
    - Node type: cache.t3.micro or cache.t3.small
    - Number of cache nodes: 1 (for MVP)
    - Automatic failover: disabled (for MVP)
    - Parameter group: default with no special settings
    - Security group: allow port 6379 from ECS task security group
  - [ ] Configure Rails to use Redis:
    - `config/environments/production.rb`:
      - `config.cache_store = :redis_cache_store, { url: ENV['REDIS_URL'] }`
      - Session store: Rails default (cookie) or `config.session_store = :redis_session_store` (optional)
  - [ ] Document Redis endpoint URL in credentials
  - [ ] Update Sidekiq initializer with Redis connection
  - [ ] Test connectivity from ECS task (optional)

- **Affected files/areas:** `config/environments/production.rb`, `config/initializers/sidekiq.rb`, `terraform/` or AWS console, `README.md`

- **Completion criteria:** Redis cluster created; accessible from ECS; Sidekiq configured to use it

---

### Task 8.5 — Configure AWS SES for production email sending

- **Objective:** Set up SES for outbound email with verified domain and proper authentication.
- **Actions:**
  - [ ] Create SES sender identity (domain or email):
    - Verify domain: add DKIM and SPF records to DNS
    - AWS provides exact record values — add to DNS registrar
  - [ ] Request SES production access (if still in sandbox):
    - Fill AWS SES sandbox exit form
    - Wait for approval (usually 24 hours)
  - [ ] Test sending email:
    - Use AWS CLI or SES mailer in Rails to send test email
    - Verify it arrives
  - [ ] Create SES DKIM signing certificate (if needed)
  - [ ] Document SES configuration in README:
    - Verified sender email
    - SPF/DKIM records added
    - Sandbox status

- **Affected files/areas:** `config/credentials.yml.enc`, `config/environments/production.rb`, AWS console, DNS registrar, `README.md`

- **Completion criteria:** SES verified; production access granted; test email sent successfully

---

### Task 8.6 — Set up domain and ACM SSL certificate

- **Objective:** Configure custom domain (`integration.app4shark.com`) and HTTPS.
- **Actions:**
  - [ ] Reserve domain `integration.app4shark.com` (if not already done)
  - [ ] Create ACM SSL certificate:
    - Domain: `integration.app4shark.com`
    - Validation: DNS (CNAME record)
    - AWS provides record values — add to DNS registrar
  - [ ] Wait for certificate to be "Issued"
  - [ ] Link certificate to ALB:
    - Create HTTPS listener on ALB (port 443)
    - Attach ACM certificate
    - Redirect HTTP (port 80) to HTTPS
  - [ ] Update DNS CNAME to point to ALB endpoint:
    - `integration.app4shark.com CNAME <ALB-endpoint>`
  - [ ] Test HTTPS connection:
    - Visit `https://integration.app4shark.com` in browser
    - Verify SSL certificate is valid
  - [ ] Document domain and certificate in README

- **Affected files/areas:** `terraform/` (ALB config), AWS console (Route 53, ACM), DNS registrar, `README.md`

- **Completion criteria:** Domain resolves; SSL certificate valid; HTTPS works; HTTP redirects to HTTPS

---

### Task 8.7 — Configure AWS S3 bucket for PDF storage with proper access control

- **Objective:** Set up S3 bucket with security best practices.
- **Actions:**
  - [ ] Create S3 bucket:
    - Name: `integration-portal-pdfs-{account-id}` (ensure global uniqueness)
    - Region: same as ECS cluster
    - Versioning: disabled (not needed, version in filename)
    - Block public access: enabled (no public read)
  - [ ] Create bucket policy:
    - Allow ECS task IAM role to `PutObject`, `GetObject`
    - Deny direct public read
  - [ ] Enable server-side encryption:
    - Default: AES-256
  - [ ] Enable bucket logging (optional):
    - Log to CloudWatch or separate logging bucket
  - [ ] Set lifecycle policy (optional):
    - Delete old PDFs after N days (for archival)
  - [ ] Create IAM policy for ECS task role:
    - Grant: `s3:PutObject`, `s3:GetObject` on bucket
  - [ ] Update app credentials with bucket name and region
  - [ ] Test upload and download

- **Affected files/areas:** `terraform/` or AWS console, `config/credentials.yml.enc`, IAM policies, `README.md`

- **Completion criteria:** S3 bucket created; ECS task can upload/download; public access blocked

---

### Task 8.8 — Set up CloudWatch Logs and basic monitoring

- **Objective:** Configure centralized logging and alerting for production.
- **Actions:**
  - [ ] Create CloudWatch log groups:
    - `/ecs/integration-portal-web` (Rails app logs)
    - `/ecs/integration-portal-sidekiq` (Sidekiq logs)
  - [ ] Configure ECS tasks to log to CloudWatch:
    - Task definition: set `logDriver: awslogs` with log group
  - [ ] Create CloudWatch alarms:
    - ECS task count: alert if less than desired (container crashes)
    - RDS CPU: alert if > 80%
    - RDS storage: alert if > 80%
    - SES bounce/complaint rate: alert if > 5%
  - [ ] Create Dashboard:
    - Display task count, CPU, memory usage
    - Display recent errors from logs
  - [ ] Configure SNS notification for alarms (email or Slack)
  - [ ] Document monitoring in README

- **Affected files/areas:** `terraform/` or AWS console, `README.md`

- **Completion criteria:** Logs visible in CloudWatch; alarms created and working; dashboard shows key metrics

---

### Task 8.9 — Set up Secrets Manager for sensitive configuration

- **Objective:** Securely store and rotate credentials.
- **Actions:**
  - [ ] Create AWS Secrets Manager secrets:
    - `integration-portal/prod/database_url` — RDS connection string
    - `integration-portal/prod/redis_url` — ElastiCache endpoint
    - `integration-portal/prod/rails_master_key` — Rails encryption key
    - `integration-portal/prod/aws_access_key_id` — AWS SDK credentials
    - `integration-portal/prod/aws_secret_access_key` — AWS SDK credentials
    - `integration-portal/prod/app_api_key` — API key for `app` integration
  - [ ] Create IAM policy to allow ECS task to read secrets:
    - Grant: `secretsmanager:GetSecretValue` on secret ARNs
  - [ ] Update ECS task definition:
    - Map secrets as environment variables (not plain text)
  - [ ] Create rotation lambda (optional, for MVP not critical):
    - Rotate database password periodically
  - [ ] Document secret names in README

- **Affected files/areas:** `terraform/` or AWS console, ECS task definition, `README.md`

- **Completion criteria:** Secrets stored securely; ECS task can read them; no plain text in task definition

---

### Task 8.10 — Create deployment documentation and runbook

- **Objective:** Document how to deploy, monitor, and troubleshoot in production.
- **Actions:**
  - [ ] Update `README.md` with:
    - Deployment steps (git push, CI/CD trigger)
    - How to build Docker image
    - How to deploy new version (ECS task update, rollback)
  - [ ] Create `DEPLOYMENT.md`:
    - Infrastructure overview diagram
    - Service dependencies (RDS, Redis, S3, SES)
    - Environment variables and secrets
    - Database migration strategy (if any)
    - Health check procedures
  - [ ] Create `TROUBLESHOOTING.md`:
    - Common issues and resolutions:
      - "App won't start" -> check logs in CloudWatch
      - "PDF generation fails" -> check Chrome/Chromium availability
      - "Email not sending" -> check SES status, production access
      - "Sidekiq not processing jobs" -> check Redis connectivity
  - [ ] Create `SCALING.md`:
    - When to increase ECS task count
    - When to increase RDS instance size
    - When to increase Redis node type
  - [ ] Create incident response playbook (optional)

- **Affected files/areas:** `README.md`, `DEPLOYMENT.md`, `TROUBLESHOOTING.md`, `SCALING.md`

- **Completion criteria:** Comprehensive documentation written; deployment steps clear; troubleshooting guide complete

---

### Task 8.11 — Set up automated CI/CD pipeline (GitHub Actions or similar)

- **Objective:** Automate testing, building, and deploying on git push.
- **Actions:**
  - [ ] Create `.github/workflows/ci.yml`:
    - Trigger on: push to `develop` and `feature/*` branches
    - Steps:
      - Checkout code
      - Set up Ruby
      - Bundle install
      - Run RSpec tests
      - Run linter (Rubocop)
      - Report coverage
  - [ ] Create `.github/workflows/deploy.yml`:
    - Trigger on: merge to `develop` or `main` (or manual trigger)
    - Steps:
      - Build Docker image
      - Push to ECR (Amazon Elastic Container Registry)
      - Update ECS task definition with new image
      - Deploy to ECS cluster
      - Wait for service to stabilize
      - Run smoke tests (health check endpoint)
      - Notify on success/failure
  - [ ] Configure ECR:
    - Create repository for app image
    - Set lifecycle policy to delete old images (keep last 5)
  - [ ] Configure GitHub secrets:
    - AWS credentials for ECR push
    - ECS cluster/service names
  - [ ] Document CI/CD flow in README

- **Affected files/areas:** `.github/workflows/`, ECR repository, `README.md`

- **Completion criteria:** CI pipeline runs on push; tests pass; deploy pipeline pushes to ECR; ECS updates automatically

---

### Task 8.12 — Create database backup and recovery strategy

- **Objective:** Ensure data safety and recovery capability.
- **Actions:**
  - [ ] RDS automated backups:
    - Already configured in Task 8.3: 7-day retention
    - Enable multi-AZ backup (optional, for MVP: disabled)
  - [ ] Create manual backup procedure (documentation):
    - How to trigger on-demand backup via AWS Console or CLI
  - [ ] Create recovery procedure (documentation):
    - How to restore from backup
    - Time required
    - Data loss implications
  - [ ] Create S3 backup for PDFs (optional):
    - Use S3 cross-region replication (for MVP: not critical)
    - Or: manual S3 bucket backup
  - [ ] Create PostgreSQL dumps (optional):
    - Export database to S3 weekly (for archival)
  - [ ] Test recovery process:
    - Restore from backup to test environment
    - Verify data integrity
  - [ ] Document in `DEPLOYMENT.md`

- **Affected files/areas:** `DEPLOYMENT.md`, AWS RDS console, S3 bucket lifecycle policies

- **Completion criteria:** Backup strategy documented; recovery procedure tested; RDS backups enabled

---

## 2) Items Requiring User Confirmation

- [ ] **Rails version**: Rails 8.1+ confirmed for team's CI/CD
- [ ] **AWS SES sandbox access**: Sandbox sufficient for MVP, or production access requested early
- [ ] **Domain**: `integration.app4shark.com` confirmed or adjust
- [ ] **PDF generation timing**: Async (Sidekiq) is acceptable for MVP (users wait a few seconds to minutes)
- [ ] **Chrome in Docker**: Security policy allows Chromium in container?
- [ ] **API contract with `app` team**: Postponed to Phase 7; manual seeding acceptable for MVP testing
- [ ] **Deployment target**: ECS vs EC2 vs other AWS service — confirm with team
- [ ] **Multi-AZ setup**: MVP can be single-AZ; HA can be added post-launch
- [ ] **Team capacity**: 8-phase breakdown assumes 1–2 engineers; adjust timeline as needed

---

## 3) Pending Items After This Iteration (if any arise)

- [ ] **Phase 7 coordination**: Requires `app` team to define API contract (blocking until Phase 7)
- [ ] **AWS SES production access**: Request early; may take 24 hours for approval
- [ ] **Post-MVP features**: Wave dependency enforcement, query versioning, mobile optimization (documented in PLAN.md Out of Scope)

---

## Execution Notes

**Task Ordering & Dependencies:**

1. **Phase 1** (Tasks 1.1–1.10): All foundation tasks must complete before starting Phase 2. No parallelization possible.
2. **Phase 2** (Tasks 2.1–2.7): Depends on Phase 1 complete. All tasks can run in parallel.
3. **Phase 3** (Tasks 3.1–3.4): Depends on Phase 2 complete. All tasks can run in parallel.
4. **Phase 4** (Tasks 4.1–4.4): Depends on Phase 3 complete. All tasks can run in parallel.
5. **Phase 5** (Tasks 5.1–5.7): Depends on Phase 4 complete. PDF template (5.3) can start once Phase 4 UI is complete.
6. **Phase 6** (Tasks 6.1–6.3): Depends on Phase 5 complete (events already logged in Phase 3). Can start once event logging is implemented.
7. **Phase 7** (Tasks 7.1–7.3): Depends on Phase 2 complete (Company model). Can start anytime but requires `app` team coordination.
8. **Phase 8** (Tasks 8.1–8.12): Depends on all application phases complete. Infrastructure and deployment are final phase.

**Estimated Effort (very rough):**

- Phase 1: 8–10 engineer-days
- Phase 2: 4–6 engineer-days
- Phase 3: 4–6 engineer-days
- Phase 4: 4–6 engineer-days
- Phase 5: 4–6 engineer-days
- Phase 6: 2–4 engineer-days
- Phase 7: 2–4 engineer-days (blocked by `app` team)
- Phase 8: 6–8 engineer-days

**Total: ~35–50 engineer-days** for a team of 1–2 engineers.

---

**Status:** READY FOR EXECUTION
