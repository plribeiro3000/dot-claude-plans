# KNOWLEDGE - Secure Audit Downloads

## The Problem

**Security vulnerability: Public S3 URLs expose audit files without proper access control.**

Currently, 9 out of 10 audit types generate permanent, public S3 URLs that bypass application security. Anyone with the URL can download sensitive audit files indefinitely, regardless of:
- User authentication state
- Download permissions in the system
- Audit processing status (final, processing, corrupted)

This creates a serious liability exposure:
- **LGPD compliance risk**: Personal data in audit files accessible without proper controls
- **Legal responsibility**: If a data leak occurs, 4Shark cannot prove they had proper security measures in place
- **Reputation risk**: Even if the leak source is unclear, 4Shark will be considered responsible by default

The issue is particularly critical for **4Shark-generated audits** (vs client uploads) because there's no alternative explanation for how the data could have leaked.

## Current State

### How It Works Today

**9 Audit Types (Incorrect Implementation):**
- Variable Audit
- Calendar Audit
- User Audit
- Group Audit
- Statement Audit
- Plan Statement Audit
- Responsible Audit
- User Identifier Audit
- Commission Indicator Audit

Process:
1. Backend stores file in S3 with **public read permissions**
2. Backend saves `path` and `filename` to database
3. Backend uses **CarrierWave + Fog** to generate public S3 URL dynamically
4. Frontend displays download button (if user has `download` permission)
5. User clicks → Backend endpoint → **302 Redirect to public S3 URL**
6. **Security hole**: Anyone with the URL can download anytime, forever

**1 Audit Type (Correct Implementation):**
- Plan Goal Audit

Process:
1. Backend stores file in S3 with **private permissions**
2. Backend saves `path` and `filename` to database
3. Frontend displays download button (if user has `download` permission)
4. User clicks → Frontend calls backend API
5. Backend validates: authentication + `download` permission + `status === 'final'`
6. Backend uses **CarrierWave + Fog** to generate **temporary presigned URL** (5-minute expiration)
7. Backend returns **302 Redirect** to presigned URL
8. Browser follows redirect automatically (user never sees presigned URL)
9. After 5 minutes, URL becomes invalid

### What Works Well

**Permission System:**
- Robust backend validation through `actions` table
- Flexible assignment: by role (inherited) or direct to user
- Unique key constraint prevents duplicates
- Client-specific configuration

**Plan Goal Audit:**
- Implements industry best practice (presigned URLs)
- Validates user permissions server-side
- Enforces audit status rules (`final` only)
- Time-limited access (5 minutes)
- Provides clear security audit trail
- Transparent user experience (302 redirect)

**Status Validation:**
- `status === 'final'` prevents downloading:
  - Files still being processed
  - Corrupted/incomplete files
  - Non-existent files
- Better user experience (no broken downloads)

**CarrierWave + Fog Integration:**
- Already handles S3 operations
- Supports both public and presigned URL generation
- Configuration-driven (no code duplication needed)

### Pain Points

**Security Liability:**
- Cannot prove proper access controls were in place
- No way to revoke access to already-shared URLs
- No visibility into who downloaded files or when
- If LGPD violation occurs, 4Shark is first suspect

**Inconsistency:**
- 9 audits use one pattern, 1 uses another
- No clear reason why they're different
- Confusion for developers maintaining the code

**Technical Debt:**
- S3 bucket configured for public read (for 9 audits)
- Mixed permission model in same bucket

### Difficulties

**Multi-Layer Problem:**
- **Backend**: Change CarrierWave/Fog API from public URL to presigned URL
- **Infrastructure**: S3 bucket permissions (public vs private)
- **Validation**: Ensure all 9 audits validate `status === 'final'` before download

**Cannot Isolate Fix:**
- Changing S3 permissions breaks 9 audit downloads
- Backend changes must be coordinated with S3 permissions
- All layers must change together

**No Data Migration Needed:**
- Backend already stores `path` and `filename` (not URLs)
- URLs are generated dynamically via CarrierWave
- Just need to change which API generates the URL

## Domain Concepts

| Term | Definition |
|------|------------|
| **Audit File** | Generated report file (CSV, Excel, PDF) containing data for compliance, analysis, or regulatory purposes |
| **Audit Status** | Processing state: `awaiting_processing`, `processing`, `final`. Only `final` audits have complete, valid files |
| **Download Permission** | Action permission (`download`) checked in `actions` table. Controls who can download audit files |
| **Public S3 URL** | Permanent, publicly-accessible S3 object URL. Anyone with URL can download, no expiration |
| **Presigned URL** | Temporary S3 URL with embedded credentials and expiration (5 minutes). Generated server-side on-demand |
| **CarrierWave** | Ruby gem for file uploads. Handles storage abstraction and URL generation |
| **Fog** | Cloud services library used by CarrierWave for S3 operations |
| **302 Redirect** | HTTP redirect response. Backend validates, generates URL, redirects browser to S3 (user never sees URL) |
| **4Shark-Generated Audit** | Audit file created by 4Shark system (vs uploaded by client). Higher liability if leaked |
| **Action Assignment** | Permission granted via role (inherited, changes with role change) or directly to user (permanent until removed) |

## Constraints

**Security:**
- Must prevent unauthorized access to audit files
- Must provide time-limited access (5 minutes standard)
- Must validate permissions server-side (never trust frontend)
- Must enforce `status === 'final'` rule

**Technical:**
- S3 bucket permissions must align with access strategy
- CarrierWave configuration must support presigned URLs
- Backend must use correct Fog API for presigned URL generation
- URLs must expire automatically (no manual cleanup)
- One S3 bucket per environment (alfa/beta, pré-prod, prod-compartilhado, prod-dedicado)

**Business:**
- Cannot break existing audit generation workflows
- Must maintain user experience quality (no broken downloads)
- Permission model must remain flexible (role vs direct assignment)
- Client-specific permission configurations must be preserved

**Compliance:**
- LGPD requirements for data access controls
- Audit trail capability (who downloaded what, when) - nice to have, not priority
- Ability to prove security measures were in place

**No Migration:**
- Existing audit records already have `path` and `filename`
- No database changes needed
- URLs generated dynamically, so change is transparent

## Open Questions

**Status Validation Consistency:**
- Do all 9 audits currently validate `status === 'final'` before download?
- Or do some allow downloading while `processing`?
- Need to verify and standardize

**CarrierWave Configuration:**
- Current configuration for public vs private files?
- What changes needed to support presigned URLs?
- Any environment-specific differences?

**Error Handling:**
- What happens if presigned URL generation fails (S3 down, permissions issue)?
- Standard error response: HTTP 503 + message "Service temporarily unavailable"?

**Terraform/S3 Changes:**
- What S3 bucket policies need updating?
- Impact on existing files (retroactive permission change)?
- Deployment coordination strategy?

## Key Insights

**Root Cause:**
- Plan Goal Audit was implemented last, by Claude Code
- Claude identified the correct security pattern
- Other 9 audits predate this knowledge
- This is technical debt from earlier implementations

**Severity Level: HIGH**
- Not about fixing known breach
- About preventing future liability
- Critical for LGPD compliance positioning
- Essential for business reputation protection

**Security Posture:**
- With fix: "All files secured via application, user/password, temporary 5-minute URLs"
- Without fix: "Files accessible via public URLs, no way to prove proper controls"

**Implementation Scope:**
- Multi-project: app (backend), app-webclient (frontend validation), terraform (S3 permissions)
- Coordinated deployment required
- No data migration needed (URLs generated dynamically)

**User Impact:**
- No complaints about current system
- Users won't notice change (same workflow, same 302 redirect)
- Behind-the-scenes security improvement
- No performance impact (presigned URL generation is instant)

**Technical Simplification:**
- No URL expiration scenario (generated on-demand during click)
- No "wait 10 minutes" issue (redirect is immediate)
- Transparent to user (never sees presigned URL)
- CarrierWave already supports both URL types

---

**Status:** READY FOR PROCESS MODELING
