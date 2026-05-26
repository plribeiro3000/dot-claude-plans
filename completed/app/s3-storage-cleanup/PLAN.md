# Plan: S3 Storage Cleanup

## Overview

**Feature:** s3-storage-cleanup
**Type:** Single-project (app - operational)
**Status:** ✅ Completed
**Related:** Discovered during [secure-downloads](../../completed/secure-downloads/PLAN.md) implementation

## Context

When the Atento client was separated from the shared environment, the S3 bucket `4shark-atento-001` was cloned from `4shark-shared`. This cloning process left:

- **Orphan files in Atento bucket:** Files from other companies that don't belong to Atento
- **Orphan files in Shared bucket:** Files from Atento that should have been removed after migration

This cleanup task was identified after the Secure Downloads feature deployment, but the root cause is the tenant separation process, not the feature itself.

---

## Phase 1: CarrierWave Bug Investigation ✅ COMPLETED

### Initial Hypothesis

We suspected CarrierWave was NOT deleting S3 files when records were destroyed.

**Evidence investigated:**
- No explicit `after_destroy` callback on Attachment models
- Reference: [CarrierWave Issue #456](https://github.com/carrierwaveuploader/carrierwave/issues/456)

### Investigation Results

After checking GitHub issues and testing in the database:

| Check | Result |
|-------|--------|
| CarrierWave version | 3.1.2 with fog-aws 3.33.1 |
| Default deletion behavior | ✅ Working correctly |
| Files being deleted on destroy | ✅ Confirmed |
| GitHub issue #456 | Not applicable to our version |

### Conclusion

**NO BUG EXISTS.** CarrierWave is correctly deleting files when records are destroyed.

The orphan files are a result of the tenant separation process (bucket cloning), not a CarrierWave bug.

**Decision:** No code changes needed. Proceed with manual cleanup only.

---

## Phase 2: S3 Analysis ✅ COMPLETED

### S3 Path Patterns Reference

| Model | Uploader | S3 Path Pattern |
|-------|----------|-----------------|
| AuditAttachment | AuditUploader | `uploads/audit/{attachable_id}/` |
| BannerAttachment | BannerUploader | `uploads/campaign/banner/{attachable_id}/` |
| CommissionReportAttachment | CommissionReportUploader | `uploads/commission/{attachable_id}/` |
| DocumentAttachment | DocumentUploader | `uploads/document/{attachable_id}/` |
| PaymentExportationAttachment | PaymentExportationUploader | `uploads/payment_exportations/{attachable_id}/` |
| PaymentReportAttachment | PaymentReportUploader | `uploads/payment_reports/{attachable_id}/` |
| PlanStatementPortableAttachment | PlanStatementPortableBatchUploader | `uploads/plan_statement_portable_batches/{attachable_id}/` |
| ProfileAttachment | ProfileUploader | `uploads/profile/{attachable_id}/` |
| Signature | SignatureUploader | `uploads/signature/{acceptment_id}/` |
| Profile | ProfileUploader | `uploads/profile/{id}/` |

---

## Phase 3: Atento Bucket Cleanup ✅ COMPLETED

**Bucket:** `4shark-atento-001`
**Objective:** Remove files from other companies that were copied during bucket cloning

### Analysis Results (Atento)

| Category | S3 Files | DB Records | Orphans | Missing |
|----------|----------|------------|---------|---------|
| Banner | 1 | 1 | 0 | 0 |
| Commission | 1 | 0 | 1 | 0 |
| Profile | - | - | 0 | 0 |
| Audit | 507 | 507 | 0 | 0 |
| Document | 20,392 | 19,879 | 83 | 7* |
| Signature | 14,960 | 14,960 | 0 | 0 |

*Missing documents are PasswordDocument with state=final - files removed by design after processing.

### Cleanup Actions Executed

| Category | Action | Result |
|----------|--------|--------|
| Banner | None required | Valid incomplete upload |
| Commission | Deleted 1 file from S3 | TTL expired record |
| Profile | None required | Clean |
| Audit | Removed 39 DB records | Records from other companies |
| Document | **Deleted 83 files from S3** | Files from other companies |
| Signature | None required | Clean (false positives) |

### Temporary Tables Cleanup

```sql
DROP TABLE s3_document_ids, s3_signature_ids, s3_audit_ids;
```

✅ **Bucket `4shark-atento-001` is 100% clean.**

---

## Phase 4: Shared Bucket Cleanup ✅ COMPLETED

**Bucket:** `4shark-shared`
**Objective:** Remove orphan files (files in S3 without corresponding database records)

### Analysis Results (Shared)

| Category | S3 Files | Analyzed |
|----------|----------|----------|
| Document | 22,545 | ✅ |
| Audit | 3,011 | ✅ |
| Signature | 4,008 | ✅ |

### Orphan Documents Found: 79

| Category | Quantity | Action |
|----------|----------|--------|
| Reset Senha files | 14 | ✅ Deleted |
| XLSX invalid files | 44 | ✅ Deleted |
| Unprocessed uploads | 21 | ✅ Deleted |
| **TOTAL** | **79** | ✅ **All deleted** |

### Unprocessed Uploads Detail (21)

These files were uploaded to S3 via presigned URL but the client never called the endpoint to create the Document record.

| Client | Company ID | Qty | Document IDs |
|--------|------------|-----|--------------|
| Almaviva | 33 | 1 | 30091 |
| Rede Brasil | 56 | 11 | 34504, 34837, 36286, 45576, 47382, 61653, 68750, 68751, 68752, 71070, 75208 |
| Maqnelson | 97 | 1 | 78669 |
| LG - Lugar de Gente | 262 | 1 | 38181 |
| Virtual Connection | 1879 | 3 | 78983, 78984, 78986 |
| Óticas Carol | 2242 | 4 | 80352, 80353, 80354, 80355 |

✅ **Bucket `4shark-shared` is 100% clean.**

---

## Summary

| Phase | Status | Result |
|-------|--------|--------|
| CarrierWave Investigation | ✅ Completed | No bug - working correctly |
| S3 Analysis | ✅ Completed | Paths mapped |
| Atento Bucket Cleanup | ✅ Completed | 84 files cleaned |
| Shared Bucket Cleanup | ✅ Completed | 79 files cleaned |

**Total orphan files removed: 163**

---

## Scripts Reference

See [SCRIPTS.md](./SCRIPTS.md) for detailed documentation of all SQL scripts used during analysis.

---

**Started:** 2025-01-01
**Completed:** 2025-01-05
