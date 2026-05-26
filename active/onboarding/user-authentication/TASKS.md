# NEXT TASKS — User Authentication and Management — Rails + Devise + devise_invitable

> **Objective of this iteration:** Implement a complete Rails authentication system with Devise and devise_invitable, supporting admin-managed user invitations, role-based access control, and password reset flow for all users.
>
> **Reference:** derived from `PLAN.md` (phases: 1–7).

---

## 0) Pre-conditions

- [x] `PLAN.md` **approved**
- [x] **Base branch:** `develop` • **Working branch:** `feature/user-authentication`
- [x] PostgreSQL is available and running locally
- [x] `rails` gem is installed (`gem install rails`)

---

## 1) Step by Step (atomic tasks)

### ✅ Task 1 — Generate Rails application with PostgreSQL and Devise
Done. Rails app generated with PostgreSQL, Devise, devise_invitable, letter_opener, foreman. Git repo initialized with `develop` → `feature/user-authentication` branches.

### ✅ Task 2 — Create lib/application_configuration.rb
Done. Centralized ENV access class created.

### ✅ Task 3 — Configure Puma, database.yml, and environments
Done. Puma reads from ApplicationConfiguration; database.yml with pool tied to puma_threads, prepared_statements: false; environment-specific settings applied.

### ✅ Task 4 — Create bin/ scripts and Procfile
Done. `bin/dev`, `bin/databases`, `bin/update`, `bin/rubocop`, `bin/setup`, `Procfile.dev.databases` created.

### ✅ Task 5 — Create initializers, .env, and CHANGELOG.md scaffold
Done. `schema_dumping.rb`, `filter_parameter_logging.rb`, `.env`, `CHANGELOG.md` created.

### ✅ Task 6 — Create and configure databases
Done. Development and test databases created.

### ✅ Task 7 — Install and configure Devise initializer
Done. Devise initializer configured with mailer sender, invite_for, reset_password_within, default_url_options.

### ✅ Task 8 — Generate User model with Devise
Done. User model with Devise modules (database_authenticatable, confirmable, recoverable, rememberable, validatable, invitable).

### ✅ Task 9 — Add role enum and invited_by association to User
Done. Role enum (client: 0, admin: 1) added. Migrations created with indexes inside `create_table` block (t.index pattern).

### ✅ Task 10 — Run all migrations
Done. All migrations ran cleanly. `User.roles` returns `{ "client" => 0, "admin" => 1 }`.

### ✅ Task 11 — Generate Devise views for customization
Done. All Devise views generated and customized with Bootstrap 5 + lazy i18n (`t('.key')`). Locale files created for pt-BR, en, es.

### ✅ Task 12 — Configure Action Mailer for development
Done. letter_opener configured in development.

### ✅ Task 13 — Prepare production email configuration (placeholders)
Done. SMTP config reads from ApplicationConfiguration in production.rb.

### ✅ Task 14 — Create ApplicationController access control helpers
Done. `authenticate_user!` global, `AuthorizedController` base class, `RootController` for home page.

### ⬜ Task 15 — Create Admin::UsersController with index action
**Pending — Phase 5 (Admin UI).** Not implemented yet. Admins currently have no web interface to list or invite users.

### ⬜ Task 16 — Create Admin::UsersController views (index and new)
**Pending — Phase 5 (Admin UI).**

### ⬜ Task 17 — Configure routes for admin namespace
**Pending — Phase 5 (Admin UI).**

### ✅ Task 18 — Create root route and home page
Done. `RootController#index` with root route, Bootstrap layout with navbar and sign-out button.

### ✅ Task 19 — Update Devise sign-in view with password reset link
Done. "Forgot your password?" link present on sign-in page.

### ✅ Task 20 — Create seeds file with founding admin accounts
Done. Seeds create 3 admins (danilo, sergio, paulo @4shark.com.br) with random passwords and confirmed_at set. Idempotent.
> **Note:** Seeds use `User.create!` (not `User.invite!`) with `confirmed_at: Time.current` because SMTP is not configured yet. Plan called for `User.invite!` but that requires working email in production.

### ⬜ Task 21 — Test seed invitations locally
Pending manual testing.

### ⬜ Task 22 — Test authentication flow: sign in with admin account
Pending manual testing.

### ⬜ Task 23 — Test access control: verify unauthenticated user redirects to sign-in
Pending manual testing.

### ⬜ Task 24 — Test access control: verify client user cannot access admin area
Pending — Admin area not implemented yet (Phase 5).

### ⬜ Task 25 — Test admin user listing
Pending — Admin area not implemented yet (Phase 5).

### ⬜ Task 26 — Test invitation flow: admin invites a new user
Pending — Admin area not implemented yet (Phase 5).

### ⬜ Task 27 — Test invitation acceptance: invited user completes sign-up
Pending — Admin area not implemented yet (Phase 5).

### ⬜ Task 28 — Test duplicate email validation on invitation
Pending — Admin area not implemented yet (Phase 5).

### ⬜ Task 29 — Test password reset flow: user requests password reset
Pending manual testing.

### ⬜ Task 30 — Test password reset completion
Pending manual testing.

### ✅ Task 31 — Create CHANGELOG.md entry
Done. Entry added: "User authentication with email and password, including sign-in and sign-out."

### ✅ Task 32 — CI/CD pipeline
Done. Build and deploy workflows implemented with blue/green deployment, Sidekiq quiet mode, Fargate migration tasks, autoscaling lock. PR merged to develop.

### ✅ Task 33 — Commit all changes
Done. Single commit `feat(auth): implement user authentication with Devise and invitable` on PR #4, merged to develop.

---

## 2) Items Requiring User Confirmation

- [x] **Founding admin emails:** Confirmed — danilo@4shark.com.br, sergio@4shark.com.br, paulo@4shark.com.br
- [x] **Application host for development email links:** localhost:3000
- [ ] **Production SMTP provider:** Confirm which SMTP service will be used in production (SendGrid, AWS SES, etc.)

---

## 3) Pending Items After This Iteration

- [ ] **Phase 5 — Admin UI:** `Admin::UsersController` with user listing and invitation form (Tasks 15–17, 24–28)
- [ ] **First deploy:** Configure GitHub Environment secrets (AWS, REDIS_URL, MIGRATION_DATABASE_URL, SMTP, etc.) and trigger first deploy
- [ ] **Login/logout manual testing:** Verify flows end-to-end in the running app
- [ ] **Password reset flow testing:** Verify with letter_opener in development
- [ ] **Production SMTP:** Configure before running `rails db:seed` in production (seeds currently use `create!` + random password instead of `invite!`)
