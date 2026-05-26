# PLAN — Integration Validation Portal (MVP)

> Reference: SPIKE.md (spike/integration-validation-portal/SPIKE.md)

## Current Situation

- Client integration onboarding requires IT teams to submit SQL queries per integration flow and Operations teams to validate them
- Today this process is entirely manual — email chains, spreadsheets, no audit trail, no structured handoff
- No existing system handles this: the `app` is API-only (GraphQL + REST), no HTML UI for external parties
- The `app` holds the source of truth for company, user, and indicator context

## Objective / Target State

A standalone Rails application (`integration.app4shark.com`) where:
- 4Shark admins configure which SQL queries are required per client and per wave
- IT contacts receive email invitations and submit queries through an authenticated portal
- Operations contacts review and validate query results through an authenticated portal
- Every action is audited with full timeline (who, when, IP, duration)
- When all queries in a wave are validated, a versioned PDF document is generated and emailed to stakeholders

## Problem / New Feature

A new standalone Rails application must be built from scratch. There is no existing codebase.

The portal removes the bottleneck in client integration onboarding by providing a structured, audited, and transparent validation process organized in waves (Wave 1 = Users, Wave 2+ = Indicators).

## Challenges, Difficulties and Risks

- **Technical**: Greenfield app — full setup required (DB, auth, email, PDF, storage, deployment)
- **Technical**: OTP brute-force protection and session management for external users
- **Technical**: Chrome/Chromium dependency in Docker for ferrum_pdf PDF generation
- **Technical**: API integration with `app` to fetch company/user/indicator context (contract not yet defined)
- **Security**: OTP codes must be short-lived; session TTL must balance usability vs. security
- **Security**: Immutable audit trail — records must never be updated or deleted
- **Product/UX**: IT and Operations are external clients — UI must be simple and self-explanatory
- **Infrastructure**: New ECS/EC2 setup, domain, DNS, SES configuration (SPF/DKIM)

## Solution Options (comparative)

Options were evaluated during the spike phase. All decisions are resolved — no open choices remain.

| Decision | Chosen | Rationale |
|----------|--------|-----------|
| Hosting | New standalone Rails app | Clean separation, own domain, independent deploy cycle |
| Stack | Ruby on Rails + ERB/Hotwire | Team's core competency, server-rendered HTML sufficient |
| PDF | ferrum_pdf | Actively maintained (5 releases in 2025), MIT license, HTML-to-PDF productivity |
| Email | AWS SES | Already on AWS, ~zero cost at this volume, no new vendor |
| Auth | OTP via email | Identity verification required; solves Outlook prefetch problem inherently |
| Sessions | Session-based after OTP | 24h TTL; no re-OTP per page |

## Scope

### In Scope (MVP)

1. Admin UI to define which queries are required per client and per wave
2. Email invitation to IT contacts with link to the portal
3. OTP email authentication for all external users (IT and Operations)
4. IT submission form to submit SQL queries per integration flow
5. Operations validation portal to review query results and mark as validated (with IP capture)
6. Timeline/audit trail — immutable event records per company
7. PDF generation (ferrum_pdf) when all queries in a wave are validated
8. Email with PDF attached to stakeholders

### Out of Scope (Post-MVP)

- Multi-wave dependency enforcement (Wave 2 cannot start before Wave 1 is complete — enforced manually for now)
- Versioning of queries after corrections (v2.0, v3.0 documents)
- Self-service admin registration
- In-app notifications (email only for MVP)
- Mobile-optimized UI (basic responsive is sufficient)

## Execution Phases

### Phase 1: Foundation

**Objective**: Working Rails application with database, authentication infrastructure, and core data model.

**Components**:
- New Rails application (Rails 8.1+) — generators, Gemfile, Dockerfile
- PostgreSQL database with initial schema
- OTP authentication flow: link -> OTP input page -> session (includes brute-force lockout after N attempts)
- `PortalUser` model — external users (IT and Operations contacts), email, locked_at
- `OtpCode` model — short-lived 6-digit codes (5-10 min TTL), used_at, attempt_count
- `ValidationToken` model — UUID token, portal_user_id, expires_at, used_at, ip_address (for invitation links)
- Admin authentication — separate admin session (email/password, Devise or simple custom)
- Application layout — base ERB layout for portal and admin

**Dependencies**: None (greenfield start)

**Success Criteria**:
- [ ] Rails app boots with database connected
- [ ] An invitation link renders the OTP input page
- [ ] OTP is sent via AWS SES when the page loads
- [ ] Valid OTP creates an authenticated session
- [ ] Invalid OTP increments attempt counter; N failures locks the user
- [ ] Expired OTP shows error and offers resend
- [ ] Admin can log in through a separate admin interface

---

### Phase 2: Query Catalog and Wave Configuration

**Objective**: Admins can define query templates globally and configure which queries each client needs per wave.

**Components**:
- `IntegrationQueryTemplate` model — global catalog of query types (name, description, wave assignment)
- `IntegrationWave` model — belongs to a Company reference (company_id from `app`); state machine: pending -> in_progress -> validated -> closed
- `IntegrationQuery` model — links Wave + Template; holds the SQL text submitted by IT; state: pending -> submitted -> approved / rejected
- `Company` reference model — lightweight mirror of company data from `app` API (company_id, name, it_contact_email, ops_contact_email)
- Admin UI: list/create/edit query templates
- Admin UI: create wave for a company, assign query templates to the wave
- Admin UI: list companies and their waves with status overview

**Dependencies**: Phase 1 complete

**Success Criteria**:
- [ ] Admin can create and edit query templates in the catalog
- [ ] Admin can create a wave for a company
- [ ] Admin can assign query templates to a wave
- [ ] Wave state transitions work correctly (state machine enforced)
- [ ] Query state transitions work correctly
- [ ] Company list is populated (can be seeded manually for MVP; API sync is Phase 5)

---

### Phase 3: IT Submission Portal

**Objective**: IT contacts receive email invitations, authenticate via OTP, and submit SQL queries for their assigned wave.

**Components**:
- Email invitation: admin triggers invitation send to IT contact; includes link with `ValidationToken`
- IT portal: authenticated view listing assigned IntegrationQueries for their wave
- SQL submission form: IT enters SQL for each query; submit saves it and transitions query to `submitted`
- Resubmission: IT can edit and resubmit a rejected query
- `IntegrationEvent` model — append-only audit trail; actor (email), event_type, metadata (JSON), ip_address, created_at
- Events recorded: invitation_sent, otp_verified, query_submitted, query_resubmitted

**Dependencies**: Phase 2 complete

**Success Criteria**:
- [ ] Admin can send invitation email to IT contact for a wave
- [ ] IT contact receives the email and clicks the link
- [ ] OTP flow authenticates the IT contact (Phase 1 flow)
- [ ] IT portal shows only the queries for their wave
- [ ] IT can enter and submit SQL for each query
- [ ] Submitted query transitions to `submitted` state
- [ ] Audit events are recorded for all actions
- [ ] IT can resubmit a query that was rejected by Operations

---

### Phase 4: Operations Validation Portal

**Objective**: Operations contacts authenticate via OTP and validate submitted query results, with full IP capture.

**Components**:
- Email invitation to Operations contact (same mechanism as IT)
- Operations portal: shows all submitted queries for the wave, grouped by flow
- Query review view: shows SQL submitted by IT, a results area (manual — Operations paste or describe results)
- Validation action: Operations marks a query as approved; records IP address and timestamp
- Rejection action: Operations marks a query as rejected with a reason; IT is notified by email
- Wave auto-completion check: when all queries in a wave reach `approved`, wave transitions to `validated`
- Events recorded: invitation_sent, query_approved, query_rejected, wave_validated

**Dependencies**: Phase 3 complete

**Success Criteria**:
- [ ] Admin can send invitation email to Operations contact
- [ ] Operations contact authenticates via OTP
- [ ] Operations portal shows all submitted queries for the wave
- [ ] Operations can approve a query; IP address is captured and stored
- [ ] Operations can reject a query with a reason
- [ ] IT receives rejection notification email
- [ ] When all queries are approved, wave automatically transitions to `validated`
- [ ] All validation events appear in the audit trail

---

### Phase 5: PDF Generation and Delivery

**Objective**: Generate an immutable versioned PDF when a wave is validated and email it to stakeholders.

**Components**:
- PDF template (ERB/HTML): wave summary, company info, list of queries with SQL and validation metadata, timeline excerpt, generated_at timestamp, version number
- ferrum_pdf integration: convert HTML template to PDF using Chrome
- `ValidationDocument` model — belongs to Wave; stores S3 URL, version (v1.0), generated_at, sha256 checksum
- S3 upload: store the generated PDF; URL saved on the record
- Stakeholder email: send PDF as attachment (or S3 download link) to IT contact, Operations contact, and admin
- Async generation: trigger PDF generation via background job (Sidekiq) after wave validates
- Events recorded: pdf_generated, pdf_delivered

**Dependencies**: Phase 4 complete; Sidekiq configured; S3 bucket configured; ferrum_pdf + Chrome in Dockerfile

**Success Criteria**:
- [ ] Wave validation triggers background job
- [ ] Background job generates PDF from HTML template
- [ ] PDF is uploaded to S3 and URL is persisted on `ValidationDocument`
- [ ] PDF contains all required information (wave metadata, queries, SQL, validations, timeline)
- [ ] Stakeholders receive email with PDF
- [ ] `ValidationDocument` record is immutable after creation
- [ ] PDF generation failure does not lose the validated state; job can be retried

---

### Phase 6: Timeline and Audit Trail UI

**Objective**: Admins and portal users can view the full event timeline for a company's integration process.

**Components**:
- Admin timeline view: chronological list of all `IntegrationEvent` records for a wave; shows actor, event type, IP, timestamp
- IT/Operations portal timeline: read-only summary of events visible to external users (filtered — no internal admin events exposed)
- Wave progress indicator: visual status of each query (pending / submitted / approved / rejected)

**Dependencies**: Phases 3 and 4 complete (events already being recorded)

**Success Criteria**:
- [ ] Admin can see full event timeline for any wave
- [ ] Timeline is immutable — no edit or delete actions exist
- [ ] IT and Operations users see a read-only progress summary
- [ ] Wave progress indicator reflects current state accurately

---

### Phase 7: API Integration with `app`

**Objective**: Populate company, IT contact, and Operations contact data from the existing `app` via API instead of manual seeding.

**Components**:
- HTTP client to call `app` API (Faraday or Net::HTTP)
- Sync job or admin-triggered sync to import/update company records
- Error handling: graceful failure if `app` is unreachable; portal continues to work with cached data

**Dependencies**: Phase 2 complete; API contract with `app` defined (requires coordination with `app` team)

**Success Criteria**:
- [ ] Portal can fetch company list from `app` API
- [ ] Company data in portal stays in sync with `app`
- [ ] Portal remains functional if `app` API is temporarily unavailable
- [ ] API authentication between portal and `app` is secured (API key or similar)

---

### Phase 8: Infrastructure and Deployment

**Objective**: Application running in production on AWS with proper domain, SSL, email, and monitoring.

**Components**:
- Dockerfile with Chrome/Chromium for ferrum_pdf
- ECS task definition or EC2 setup
- RDS PostgreSQL instance
- Domain setup: `integration.app4shark.com`
- SSL certificate (ACM)
- AWS SES: domain verification, SPF/DKIM DNS records, sending identity
- Sidekiq process (separate ECS task or thread in same container)
- S3 bucket for PDF storage
- Environment variables and secrets management (AWS Secrets Manager or Parameter Store)
- Basic health check endpoint

**Dependencies**: All application phases complete; infrastructure team coordination

**Success Criteria**:
- [ ] Application accessible at `integration.app4shark.com` over HTTPS
- [ ] Emails are delivered (SES verified, SPF/DKIM passing)
- [ ] PDFs are stored in S3 and accessible via signed URLs
- [ ] Sidekiq processes background jobs reliably
- [ ] Health check endpoint responds 200
- [ ] Database backups configured on RDS

---

## Technical Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Application | New standalone Rails 8.1+ | Clean domain separation, independent deploy, own infrastructure |
| UI | ERB + Hotwire (Turbo/Stimulus) | Server-rendered sufficient; minimal JS overhead; team knows Rails |
| Auth mechanism | OTP via email + session | Identity verification required; solves Outlook prefetch; 24h session TTL |
| OTP storage | Database table (`otp_codes`) | Need attempt counting, TTL enforcement, resend tracking |
| Invitation tokens | DB-stored UUID (`validation_tokens`) | Long-lived processes (months); need revoke/extend capability |
| PDF generation | ferrum_pdf + Chrome | Actively maintained, MIT, HTML-to-PDF productivity |
| Email provider | AWS SES | Already on AWS, ~zero cost at this volume |
| PDF storage | S3 via AWS SDK | Team already uses S3 on `app`; immutable object storage |
| Background jobs | Sidekiq | Industry standard for Rails; PDF generation must be async |
| Audit trail | Append-only `integration_events` table | No updates or deletes; full immutability guaranteed at DB level |
| State machine | Custom or `aasm` gem | Query and wave lifecycle management |
| Authorization | Role-based (admin / IT / operations) tied to session | Simple enough for MVP without Pundit overhead |

## Risks

| Risk | Impact | Mitigation |
|------|--------|------------|
| Chrome not available in Docker for PDF | High | Add Chromium to Dockerfile early; test PDF generation in Phase 5 before other phases depend on it |
| `app` API contract undefined | Medium | Use manual seeding in Phase 2; API integration is Phase 7 (non-blocking for MVP) |
| SES in sandbox mode (limited sending) | Medium | Request SES production access early; do not wait for Phase 8 |
| OTP brute force | High | Lockout after 5 failed attempts; short OTP TTL (5-10 min); rate limit resend |
| Session fixation / CSRF | High | Rails defaults handle CSRF; rotate session on OTP verification |
| PDF generation failures leaving wave in bad state | Medium | Idempotent Sidekiq job; `ValidationDocument` created only on success; wave state not dependent on PDF |
| Data loss from manual seeding in MVP | Low | Phase 7 API sync will reconcile; seed scripts can be re-run |

## Assumptions

- A new Git repository will be created for this application (separate from `app`)
- The `app` team will provide an API endpoint to fetch company/contact data (Phase 7 coordination needed)
- AWS infrastructure is managed by the team; Ansible or Terraform scripts will be adapted for the new service
- Chromium can be installed in the Docker image (no security policy blockers)
- SES production access request can be made early in the project
- The portal will be used by a small number of concurrent users (low traffic); no horizontal scaling needed for MVP
- Wave 1 = Users queries; Wave 2+ = Indicators queries (wave type is a catalog attribute)
- Operations contacts receive queries in bulk per wave, not per individual query

---

**Status:** READY FOR TASK CREATION
