# PROCESS - Secure Audit Downloads

> Reference: KNOWLEDGE.md

## Overview

Process for downloading audit files with proper security controls. Currently has two implementations: insecure (9 audit types using public S3 URLs) and secure (Plan Goal Audit using presigned URLs). Goal is to migrate all audits to the secure flow.

## Trigger

User clicks download button in audit list/detail screen (button only visible if `download` action is present in backend response).

## Actors

| Actor | Role | Responsibilities |
|-------|------|------------------|
| User | End user | Clicks download button |
| Frontend | Angular app | Displays download button (if `download` in actions), makes API call |
| Backend | Rails API | Validates auth/permissions/status, generates URLs, returns 302 redirect |
| S3 | Object storage | Stores files, serves content |

## Main Flow - Current (INSECURE)

**9 Audit Types:**
- Variable, Calendar, User, Group, Statement, Plan Statement, Responsible, User Identifier, Commission Indicator

```
User          Frontend         Backend              S3
 │               │                │                  │
 │─click────────►│                │                  │
 │               │─GET /download─►│                  │
 │               │                │─validate auth    │
 │               │                │─validate perm    │
 │               │                │─generate PUBLIC  │
 │               │                │  URL (permanent) │
 │               │                │                  │
 │               │◄─302 redirect──│                  │
 │               │  (public URL)  │                  │
 │               │                                   │
 │──────────────GET──────────────────────────────►│
 │◄─────────────file content──────────────────────│
 │                                                   │
[URL remains valid forever - anyone with it         │
 can download anytime, bypassing all security]      │
```

## Main Flow - Desired (SECURE)

**Reference Implementation:** Plan Goal Audit

```
User          Frontend         Backend              S3
 │               │                │                  │
 │─click────────►│                │                  │
 │               │─GET /download─►│                  │
 │               │                │─validate auth    │
 │               │                │─validate perm    │
 │               │                │─validate status  │
 │               │                │  === 'final'     │
 │               │                │─generate         │
 │               │                │  PRESIGNED URL   │
 │               │                │  (5min expiry)   │
 │               │                │                  │
 │               │◄─302 redirect──│                  │
 │               │  (presigned)   │                  │
 │               │                                   │
 │──────────────GET (with embedded creds)─────────►│
 │                                          validate │
 │                                          signature│
 │                                          check exp│
 │◄─────────────file content──────────────────────│
 │                                                   │
[After 5 minutes, URL expires automatically]        │
```

## Detailed Steps

### Step 1: User Clicks Download

- **Actor**: User
- **Input**: Download button visible (backend included `download` in `actions` field)
- **Action**: Click event
- **Output**: HTTP request to frontend
- **Next**: Frontend makes API call

### Step 2: Frontend Requests Download

- **Actor**: Frontend
- **Input**: Audit ID, session token
- **Action**: GET request to backend download endpoint
- **Output**: HTTP request with auth headers
- **Next**: Backend validates and processes

### Step 3: Backend Validates Request

- **Actor**: Backend
- **Input**: User credentials, audit ID
- **Action**:
  - Check authentication
  - Check `download` permission in actions table
  - **Current flow**: Skip status check
  - **Desired flow**: Validate `status === 'final'`
- **Output**: Pass/fail validation
- **Next**: Generate URL or return error

### Step 4: Backend Generates S3 URL

- **Actor**: Backend
- **Input**: Audit `path` and `filename` from database
- **Action**: Use CarrierWave + Fog to generate URL
  - **Current**: Public URL (permanent)
  - **Desired**: Presigned URL (5-minute expiration)
- **Output**: S3 URL
- **Next**: Return 302 redirect

### Step 5: Backend Returns 302 Redirect

- **Actor**: Backend
- **Input**: S3 URL
- **Action**: HTTP 302 response
- **Output**: Browser redirect (user never sees URL)
- **Next**: Browser requests file from S3

### Step 6: S3 Serves File

- **Actor**: S3
- **Input**: HTTP GET request
- **Action**:
  - **Current**: Serve file (public permissions, no validation)
  - **Desired**: Validate presigned URL signature + expiration, then serve
- **Output**: File content OR 403 if expired/invalid
- **Next**: Download complete

## Decision Points

### Decision 1: Show Download Button?

- **Question**: Should frontend display download button?
- **Options**:
  - **YES**: `download` present in `actions` field
  - **NO**: `download` not in `actions` field
- **Who decides**: Backend (returns `actions` based on permissions + status)
- **Based on**: User permission + audit status

### Decision 2: Allow Download?

- **Question**: Is user authorized to download?
- **Options**:
  - **YES**: User authenticated + has `download` permission
  - **NO**: Return 403 Forbidden
- **Who decides**: Backend
- **Based on**: Session validation + actions table query

### Decision 3: Audit Ready? (Secure Flow Only)

- **Question**: Is audit file complete and valid?
- **Options**:
  - **YES**: `status === 'final'`, generate URL
  - **NO**: Don't include `download` in `actions` field (button won't show)
- **Who decides**: Backend
- **Based on**: Audit status field

### Decision 4: URL Valid? (Secure Flow Only)

- **Question**: Is presigned URL still valid?
- **Options**:
  - **YES**: Generated less than 5 minutes ago, serve file
  - **NO**: Return 403, user must click download again
- **Who decides**: S3
- **Based on**: URL signature + expiration timestamp

## Outcomes

| Outcome | Condition | Result |
|---------|-----------|--------|
| **Success** | User has permission + status is final + URL valid | File downloads |
| **Button Hidden** | User lacks permission OR status not final | No download button visible |
| **403 Forbidden** | User forces URL without permission | Error message "You don't have permission" |
| **403 URL Expired** | Presigned URL older than 5 minutes (secure flow) | User clicks download again (new URL generated) |
| **Security Breach** | Someone uses shared public URL (current flow) | File downloads successfully (SECURITY HOLE) |

## Data Flow

| From | To | Data | Format |
|------|----|------|--------|
| Backend | Frontend | Audit list with `actions` field | JSON response |
| Frontend | Backend | Download request | HTTP GET with session |
| Backend | Backend | Permission check | SQL query (actions table) |
| Backend | S3 Config | File path + filename | CarrierWave/Fog API |
| Backend | Frontend | S3 URL | HTTP 302 redirect |
| Frontend | S3 | File request | HTTP GET |
| S3 | User | File content | Binary stream |

## Backend Actions Field Logic

```
Backend                    actions field
   │
   ├─user authenticated?
   │  └─NO─────────►────────[ empty ]
   │
   ├─user has 'download' permission?
   │  └─NO─────────►────────[ empty ]
   │
   ├─status === 'final'?
   │  └─NO─────────►────────[ empty ]
   │
   └─ALL YES────────►───────[ ..., 'download', ... ]
```

**Frontend Logic:** If `download` in actions → show button. Else → hide button.

## Error Handling

### Error 1: User Not Authenticated

- **Context**: User session expired or invalid
- **Frontend**: Redirect to login (handled globally, not in download flow)
- **User Never Sees**: This error in download context

### Error 2: User Lacks Permission

- **Context**: User forces download URL without having permission
- **Backend**: Returns HTTP 403 Forbidden
- **Frontend**: Displays error message "Você não tem permissão"
- **User Action**: None (cannot download)

### Error 3: Presigned URL Expired (Secure Flow)

- **Context**: User got presigned URL but waited more than 5 minutes
- **S3**: Returns HTTP 403 Forbidden
- **Frontend**: Error handling (download failed)
- **User Action**: Click download button again (new URL generated)

### Error 4: S3 Service Unavailable

- **Context**: S3 down or permission misconfiguration
- **Backend**: Cannot generate URL, returns HTTP 503
- **Frontend**: Displays "Service temporarily unavailable. Please try again later."
- **User Action**: Retry later

## Key Differences: Current vs Desired

| Aspect | Current (Insecure) | Desired (Secure) |
|--------|-------------------|------------------|
| **URL Type** | Public, permanent | Presigned, 5-minute expiry |
| **S3 Permissions** | Public read | Private (presigned only) |
| **Status Validation** | Backend checks before adding `download` to actions | Same (no change) |
| **CarrierWave API** | Public URL generation | Presigned URL generation |
| **Access Revocation** | Impossible (URL permanent) | Automatic (5-minute expiry) |
| **Security Audit Trail** | Cannot prove controls | Time-limited access proves controls |
| **User Experience** | 302 redirect (transparent) | 302 redirect (transparent, same UX) |
| **Performance** | Instant | Instant (no difference) |

## Notes

- **No Status Validation Change**: Backend already handles status validation by including/excluding `download` from `actions` field
- **No Frontend Changes Needed**: Frontend logic remains "if `download` in actions, show button"
- **Transparent UX**: 302 redirect means users never see S3 URLs, experience is identical in both flows
- **No Data Migration**: Audit records already store `path` and `filename`, URLs generated dynamically
- **CarrierWave Support**: Library already supports both public and presigned URL generation
- **Multi-Project Coordination**: Backend changes (app) must deploy simultaneously with S3 permission changes (Terraform)
- **URL Expiration Non-Issue**: User clicks download → immediate redirect → 5 minutes to complete download is plenty of time
- **LGPD Compliance**: Presigned URLs provide auditable proof of time-limited access controls

---

**Status:** READY FOR DOMAIN MODELING
