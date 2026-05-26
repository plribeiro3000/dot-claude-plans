# DOMAIN - Secure Audit Downloads

> Reference: KNOWLEDGE.md, PROCESS.md

## Overview

This domain model represents the audit file download security system. The core problem is transforming insecure permanent public S3 URLs into secure time-limited presigned URLs while maintaining the existing permission model and user experience.

The domain spans three bounded contexts:
1. **Backend Context** - Permission validation, URL generation, audit lifecycle
2. **Frontend Context** - UI state management based on backend permissions
3. **Infrastructure Context** - S3 storage and access control

## Entities

### Audit

- **Identity**: Audit ID (unique identifier)
- **Purpose**: Represents a generated report file containing compliance or analytical data
- **State**:
  - `id`: Integer - Unique identifier
  - `type`: String - Type of audit (Variable, Calendar, User, Group, Statement, Plan Statement, Responsible, User Identifier, Commission Indicator, Plan Goal)
  - `status`: Enum - Processing state (`awaiting_processing`, `processing`, `final`)
  - `path`: String - S3 object path (without URL prefix)
  - `filename`: String - Original filename for download
  - `client_id`: Integer - Client this audit belongs to
- **Behavior**:
  - `is_downloadable?()`: Returns true if status is `final`
  - `generate_download_url(user)`: Validates permissions and returns presigned URL
  - `storage_path()`: Combines path and filename for S3 access
- **Lifecycle**: `awaiting_processing` → `processing` → `final`
- **Relationships**:
  - Belongs to one Client
  - Has many DownloadAttempts (audit trail, future)
  - Accessed by many Users (through permissions)

### User

- **Identity**: User ID
- **Purpose**: Represents an authenticated system user who may download audits
- **State**:
  - `id`: Integer - Unique identifier
  - `client_id`: Integer - Client context
  - `role_id`: Integer - User's role (for inherited permissions)
  - `session`: Session - Current authentication state
- **Behavior**:
  - `has_permission?(action, resource)`: Checks if user can perform action on resource
  - `can_download?(audit)`: Specifically checks download permission for audit
  - `is_authenticated?()`: Validates active session
- **Lifecycle**: Created → Active → (Suspended/Deactivated)
- **Relationships**:
  - Belongs to one Client
  - Has one Role
  - Has many ActionAssignments (permissions)

### ActionAssignment

- **Identity**: Composite key (action_id, resource, assignable_type, assignable_id)
- **Purpose**: Grants specific permission to user or role for a resource
- **State**:
  - `action_id`: Integer - What permission (e.g., "download")
  - `resource`: String - What resource type (e.g., "Audit::Variable")
  - `assignable_type`: String - Who gets permission ("User" or "Role")
  - `assignable_id`: Integer - Specific user or role ID
  - `client_id`: Integer - Client context
- **Behavior**:
  - `applies_to?(user, resource)`: Check if this assignment grants permission
  - `is_inherited?()`: True if assigned to role (changes when role changes)
  - `is_direct?()`: True if assigned to user (permanent until removed)
- **Lifecycle**: Created → Active → (Deleted)
- **Relationships**:
  - Belongs to one Action
  - Belongs to one User OR one Role (polymorphic)
  - Belongs to one Client

## Value Objects

### PresignedURL

- **Purpose**: Represents a temporary, cryptographically-signed S3 URL with embedded credentials
- **Attributes**:
  - `url`: String - Full S3 URL with signature
  - `expires_at`: Timestamp - When URL becomes invalid (5 minutes from generation)
  - `signature`: String - Cryptographic signature (embedded in URL)
- **Behavior**:
  - `is_valid?()`: Check if not expired
  - `time_remaining()`: Seconds until expiration
- **Immutable**: Yes

### AuditStatus

- **Purpose**: Represents the processing state of an audit file
- **Attributes**:
  - `value`: Enum - One of: `awaiting_processing`, `processing`, `final`
  - `is_downloadable`: Boolean - Derived (true only if `final`)
- **Behavior**:
  - `allows_download?()`: Returns true if status is `final`
  - `display_name()`: Human-readable status
- **Immutable**: Yes

### DownloadPermission

- **Purpose**: Encapsulates the "download" action permission
- **Attributes**:
  - `action_name`: String - Always "download"
  - `granted`: Boolean - Whether user has permission
  - `source`: String - "role" or "direct" (for audit trail)
- **Behavior**:
  - `is_granted?()`: Returns granted value
  - `explain()`: Returns why permission was granted/denied
- **Immutable**: Yes

### S3Object

- **Purpose**: Represents the physical file in S3 storage
- **Attributes**:
  - `bucket`: String - S3 bucket name (environment-specific)
  - `key`: String - Object key (path + filename)
  - `permissions`: String - "public-read" (current) or "private" (desired)
- **Behavior**:
  - `generate_public_url()`: Create permanent URL (insecure)
  - `generate_presigned_url(expiration)`: Create temporary URL (secure)
  - `is_private?()`: Check if object requires presigned access
- **Immutable**: Yes

## Aggregates

### AuditDownload

- **Root**: Audit
- **Members**:
  - Audit (root entity)
  - S3Object (value object)
  - DownloadPermission (value object)
  - PresignedURL (value object)
- **Invariants**:
  - Download URL can only be generated if `status === 'final'`
  - Presigned URL must not exceed 5-minute expiration
  - Permission must be validated before URL generation
  - User must be authenticated
- **Boundary**: Everything needed to authorize and execute a download
  - Inside: Audit state, permission check, URL generation
  - Outside: User authentication (handled by session layer), S3 file serving

## Domain Services

### DownloadAuthorizationService

- **Purpose**: Validates if user can download audit and generates appropriate URL
- **Input**:
  - `user`: User - Who is requesting download
  - `audit`: Audit - What audit to download
- **Output**:
  - `PresignedURL` - If authorized and status is final
  - `Error` - If unauthorized or audit not ready
- **Dependencies**:
  - ActionAssignment repository (permission lookup)
  - S3URLGenerator service
- **Logic**:
  ```
  1. Validate user is authenticated
  2. Check audit.status === 'final'
  3. Query ActionAssignment for 'download' permission
  4. If all pass: generate presigned URL
  5. Else: raise authorization error
  ```

### S3URLGenerator

- **Purpose**: Generate S3 URLs using appropriate method (public vs presigned)
- **Input**:
  - `s3_object`: S3Object - What file to generate URL for
  - `url_type`: String - "public" or "presigned"
  - `expiration`: Integer - Seconds until expiry (for presigned only)
- **Output**:
  - `String` - Public URL (permanent)
  - `PresignedURL` - Presigned URL with expiration
- **Dependencies**:
  - CarrierWave (file upload library)
  - Fog (S3 client library)
- **Logic**:
  ```
  IF url_type === 'public':
    Return permanent S3 URL
  ELSE IF url_type === 'presigned':
    Generate temporary signed URL (default 300 seconds)
  ```

### PermissionResolver

- **Purpose**: Determine if user has specific permission for resource
- **Input**:
  - `user`: User - Who we're checking
  - `action`: String - What action (e.g., "download")
  - `resource`: String - What resource type (e.g., "Audit::Variable")
- **Output**:
  - `DownloadPermission` - Permission grant/denial with reason
- **Dependencies**:
  - ActionAssignment repository
- **Logic**:
  ```
  1. Check direct user assignments
  2. If not found, check role assignments
  3. Return first match or deny
  4. Include source (direct vs role) for audit
  ```

## Relationships

```
User ──1:N──► ActionAssignment ◄──N:1── Role
  │
  └──1:N──► DownloadAttempt ◄──N:1── Audit
                                      │
                                      └──1:1──► S3Object
                                      │
                                      └──N:1── Client

AuditDownload (Aggregate)
    │
    ├──► Audit (root)
    ├──► S3Object (value object)
    ├──► DownloadPermission (value object)
    └──► PresignedURL (value object)
```

| From | To | Type | Description |
|------|----|------|-------------|
| User | ActionAssignment | 1:N | User can have multiple direct permission assignments |
| Role | ActionAssignment | 1:N | Role grants permissions to all users with that role |
| User | Audit | N:N | Users access audits through permissions (not direct FK) |
| Audit | S3Object | 1:1 | Each audit maps to one file in S3 |
| Client | Audit | 1:N | Client owns many audits |
| Client | User | 1:N | Client has many users |

## Responsibilities Matrix

| Object | Knows | Does | Decides |
|--------|-------|------|---------|
| **Audit** | ID, type, status, path, filename, client | Check if downloadable, generate storage path | Is status final? |
| **User** | ID, role, client, session | Check permissions, authenticate | Can I download this audit? |
| **ActionAssignment** | Action, resource, assignable, client | Check if applies to user/resource | Does this grant permission? |
| **PresignedURL** | URL, expiration, signature | Validate still active | Is URL expired? |
| **AuditStatus** | Current state value | Check downloadability | Is audit ready? |
| **DownloadPermission** | Granted status, source | Explain permission result | - |
| **S3Object** | Bucket, key, permissions | Generate URLs | Is file private? |
| **DownloadAuthorizationService** | - | Validate full authorization chain | Should this download be allowed? |
| **S3URLGenerator** | - | Generate appropriate URL type | Which URL type to create? |
| **PermissionResolver** | - | Query permission assignments | Does user have this permission? |

## Gap Analysis

### Existing (in codebase)

| Object | Exists? | Needs Change? |
|--------|---------|---------------|
| Audit Entity | Yes | Change URL generation method (public → presigned) |
| User Entity | Yes | No change |
| ActionAssignment | Yes | No change |
| Permission Check | Yes | No change (already validates before adding to `actions` field) |
| CarrierWave Config | Yes | Add presigned URL support |
| S3 Object Storage | Yes | Change permissions (public → private) |
| Status Validation | Partial | 9 audits already check status; standardize all 10 |

### New (to create)

- **PresignedURL Value Object**: Explicit representation of temporary URL (currently implicit in string)
- **DownloadAuthorizationService**: Formalize authorization logic (currently scattered in controllers)
- **S3URLGenerator Service**: Extract URL generation (currently coupled to CarrierWave)
- **AuditStatus Value Object**: Make status behavior explicit (currently primitive enum)

### Modified (to change)

- **Audit#download_url method**: Change from `url` (public) to `presigned_url(expires_in: 300)`
- **S3 Bucket Policy** (Terraform): Change from public-read to private
- **CarrierWave Uploader**: Configure fog_public = false (was true for 9 audit types)

### Removed (if any)

- None (migration is additive/replacement, no deletions)

## Domain Rules

| Rule | Description | Enforced By |
|------|-------------|-------------|
| **Download Only Final** | Only audits with status='final' can be downloaded | Backend (excludes `download` from `actions` if not final) |
| **5-Minute Expiration** | Presigned URLs must expire after 5 minutes | S3URLGenerator (passes expires_in: 300) |
| **Server-Side Validation** | Download permission must be checked server-side, never trust frontend | DownloadAuthorizationService |
| **Unique Permission Assignment** | Same action cannot be assigned twice to same user/role for same resource | Database unique constraint |
| **Client Isolation** | Users can only download audits from their own client | ActionAssignment query (filtered by client_id) |
| **Authenticated Access** | All download requests must have valid session | Rails authentication layer (before controller) |
| **No Public S3 URLs** | S3 objects must be private (no public-read ACL) | S3 bucket policy + object ACL |
| **Permission Inheritance** | Role-based permissions apply to all users with that role | PermissionResolver (checks role assignments) |
| **Status Progression** | Audit status can only move forward (awaiting→processing→final) | Audit state machine |

## Bounded Contexts

### Backend Context (app)

**Language**: User, Audit, Permission, Action, Role, Client, Status, Download

**Responsibilities**:
- Authenticate users
- Validate permissions
- Check audit status
- Generate presigned URLs
- Return 302 redirects
- Enforce domain rules

**Boundaries**:
- Does NOT serve file content (delegated to S3)
- Does NOT store URLs (generates dynamically)
- Does NOT manage S3 permissions (Terraform handles)

### Frontend Context (app-webclient)

**Language**: Download Button, Actions Field, Audit List, Permission

**Responsibilities**:
- Display download button (if `download` in actions)
- Make download API calls
- Handle redirect responses
- Show error messages

**Boundaries**:
- Does NOT validate permissions (trusts backend `actions` field)
- Does NOT generate URLs (receives from backend)
- Does NOT know about presigned vs public (transparent)
- Does NOT validate status (backend controls button visibility)

### Infrastructure Context (Terraform)

**Language**: S3 Bucket, Object Permissions, ACL, Policy

**Responsibilities**:
- Configure S3 bucket permissions
- Set default object ACL (private)
- Manage bucket policies
- Configure per-environment buckets

**Boundaries**:
- Does NOT know about audit types
- Does NOT know about users or permissions
- Does NOT generate URLs

## Context Map

```
Frontend Context          Backend Context          Infrastructure Context
     │                         │                           │
     │    "Show download?"     │                           │
     │◄────actions field───────│                           │
     │                         │                           │
     │    "Download audit"     │                           │
     ├─────API request────────►│                           │
     │                         │                           │
     │                         │  "Generate presigned URL" │
     │                         ├───────CarrierWave────────►│
     │                         │◄──────presigned URL───────│
     │                         │                           │
     │    302 redirect         │                           │
     │◄────(presigned URL)─────│                           │
     │                         │                           │
     │             "Serve file (if URL valid)"             │
     ├──────────────────HTTP GET────────────────────────►│
     │◄───────────────file content────────────────────────│
```

**Anti-Corruption Layer**:
- Frontend doesn't need to know URL is presigned (backend abstracts)
- Infrastructure doesn't need to know about permissions (backend validates)
- Backend translates between permission model and S3 access control

## Notes

### Key Design Decisions

1. **Use 302 Redirect**: Keeps URLs invisible to users, prevents URL sharing
2. **5-Minute Expiration**: Long enough for download, short enough for security
3. **No URL Storage**: Generate on-demand to avoid stale URLs and simplify logic
4. **Status in Actions Field**: Backend controls button visibility (frontend is dumb)
5. **Presigned Over Signed Cookies**: Per-file granularity, simpler implementation

### Trade-Offs Made

| Decision | Pro | Con | Rationale |
|----------|-----|-----|-----------|
| **Generate on-demand** | No expiration tracking needed | Slight latency per download | Latency is negligible (<100ms), simplicity wins |
| **302 Redirect** | Transparent UX, hides URLs | Extra HTTP round-trip | Security benefit outweighs round-trip cost |
| **5-minute expiry** | Balances security and UX | User must re-click if >5min | Downloads complete in seconds, edge case acceptable |
| **No audit logging** | Simpler implementation | Cannot track who downloaded | LGPD requires ability to prove controls, not track individual actions |
| **CarrierWave + Fog** | Reuse existing libraries | Coupled to library API | Already in use, no reason to change |

### Security Properties

**Before (Current State)**:
- ❌ Permanent public URLs
- ❌ No access revocation
- ❌ No expiration
- ❌ Anyone with URL can download
- ❌ Cannot prove proper controls

**After (Desired State)**:
- ✅ Time-limited presigned URLs
- ✅ Automatic revocation (5-minute expiry)
- ✅ Server-side permission validation
- ✅ Auditable authorization chain
- ✅ LGPD-compliant access controls

### Implementation Risks

| Risk | Mitigation |
|------|------------|
| S3 permissions changed before backend deploy | Deploy together, test in alfa/beta first |
| CarrierWave doesn't support presigned URLs | Already supports (Plan Goal Audit uses it) |
| 5 minutes too short for large files | Tested: Even large files download in <1min; can adjust to 15min if needed |
| Breaks existing shared URLs | Acceptable: Those URLs are the security hole we're fixing |
| Frontend changes needed | Verified: No changes needed (302 redirect is transparent) |

---

**Status:** READY FOR PLANNING
