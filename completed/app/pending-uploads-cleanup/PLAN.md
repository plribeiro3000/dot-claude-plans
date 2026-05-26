# PLAN — Pending Uploads Cleanup

## Current Situation
- Documents are created with status `initial` when user initiates an upload
- Flow: 1) create document → 2) upload to S3 via presigned URL → 3) callback to create attachment
- If step 3 fails (connection error, user closes browser), document stays in `initial` forever
- Currently 72 documents in this state on shared environment (some >6 months old)

- Relevant context/architecture:
  - Document has state machine: `initial` → `processing` → `final` / `failed`
  - DocumentAttachment is only created in step 3
  - Workers use `with_uncached_connection` pattern and `document_processing` queue

- Impacted components:
  - `app/models/document.rb`
  - `app/workers/document/`

## Objective / Target State
- Abandoned documents (>24h without attachment) are automatically marked as `failed`
- System does not accumulate `initial` documents indefinitely
- Clients don't see "pending" documents that will never complete

- Success metrics / acceptance criteria:
  - Job runs daily without errors
  - Documents >24h without attachment are marked as `failed`
  - DocumentError is created with reason `upload_timeout`

## Problem / New Feature
- Objective description: Create scheduled job that marks abandoned documents as `failed`
- Symptoms/logs/errors: 72 documents in `initial` without attachment, affected clients: Rede Brasil (44), Brisanet (9), Almaviva (6), Self Telecom (6), Virtual Connection (4), Lavronorte (3)

## Challenges, Difficulties and Risks
- Technical:
  - Current state machine does NOT allow `initial` → `failed` transition (needs update)
  - Must use `with_uncached_connection` to avoid cache issues
- Product/UX:
  - User may see document marked as `failed` if they take too long to upload
  - 24h is enough time for any normal upload
- Security/privacy:
  - No risks identified
- Performance:
  - Query with LEFT JOIN on attachments may be slow with many documents
  - Use `find_each` to process in batches

## Solution Options (comparative)

- **Option 1 — Rake Task with Server Cron**
  - **How it works:** Rake task `documents:cleanup_pending` runs daily via server cron, finds documents `initial` >24h without attachment and marks as `failed`
  - **Pros:** Uses existing infrastructure, simple to implement
  - **Cons:** Cron configuration outside code
  - **When NOT to use:** N/A

## Proposed Steps (high level, don't execute yet)
1. Update state machine in `Document` to allow `initial` → `failed` transition
2. Create rake task `lib/tasks/documents.rake` with `cleanup_pending` task
3. Configure server cron to run daily
4. Test in staging
5. Deploy to production

## Internal References
- Code: `app/models/document.rb`, `app/workers/document/destroyer.rb`
- State machine: status `initial(0)`, `processing(1)`, `final(3)`, `failed(4)`
- Current transition: `document.error!` only from `processing`
- New transition needed: `initial` → `failed`

---

**Question:** Does this plan look correct?
Answer with: `APPROVED` or provide feedback.
