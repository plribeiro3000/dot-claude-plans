# TASKS — Secure Downloads (Frontend) — 🚀 READY FOR DEPLOY

> **Status:** PR Ready - Deploy scheduled for 2025-12-19
> **PR:** #5783 (hotfix/1.247.13)
> **Backend PRs:**
>   - #4655 (2.218.25) - temporaryCampaign resolver (merged)
>   - #4656 (2.218.26) - CampaignPolicy download authorization (merged)

---

## Phase 1: Secure Audit Downloads ✅ COMPLETE

All audit components migrated to use `actions` field for download permission.
- PR #5724 (merged)
- Backend hotfix #4628 (merged)

---

## Phase 2: Migrate presignedUrl to temporaryX Resolvers ✅ COMPLETE

### Backend Changes (merged)
- [x] Create `temporaryCampaign` resolver (hotfix/2.218.25)
- [x] Add `download?` method to CampaignPolicy (hotfix/2.218.26)

### Frontend Changes (PR #5783 - ready for merge)
- [x] Remove `profileAttachmentId` dead code from storage
- [x] Fix `parseInt(profileId, 10)` type mismatch in profile components
- [x] Simplify ProfileService (remove redundant cache-first override)
- [x] Add `url` property to Campaign model
- [x] Migrate campaign-show to use `temporaryCampaign` resolver
- [x] Migrate payment-report to use `temporaryPaymentReport` resolver
- [x] Fix variable shadowing (campaignResponse/temporaryCampaignResponse)
- [x] Run Prettier on modified files
- [x] Update CHANGELOG date to 2025-12-18

### Copilot Comments (all resolved/dismissed)
- 31 resolved (code quality on unmodified files)
- 11 dismissed (N+1 performance issues - future optimization)

### ChatGPT Review (analyzed)
- connection.use naming: Not a problem (Apollo creates on demand)
- Cache on temporary URLs: Already fixed (using no-cache)
- N+1 requests: Valid but out of scope (future optimization)
- profile_id storage: OK (CredentialsService handles it)
- File/Upload model removal: OK (no remnant references)

---

## Phase 3: Dashboard Loading & Error Handling ✅ COMPLETE

### Dashboard Profile Image Loading
- [x] CalendarDashboard: Wait for profile images before hiding loading
- [x] PlanDashboard: Wait for profile images before hiding loading
- [x] IncentiveDashboard: Wait for profile images before hiding loading
- [x] Use `ChangeDetectorRef.detectChanges()` to trigger re-render after mutations
- [x] Consolidate duplicate rxjs imports

### Error Handling for Downloads
- [x] Add error handling to commission-show download
- [x] Add error handling to payment-show download
- [x] Add error handling to payment-report download (added showMessage method)

### Session Credentials Fix
- [x] Add profileId persistence in SessionCredentialsService

---

## Next Steps (2025-12-19)

1. **Deploy** - Merge PR #5783 and release frontend version 1.247.13
2. **Validate** - Test all secure download flows in production

---

## Future Optimizations (out of scope)

- Batch profile URL requests to avoid N+1 queries in dashboards
- Consider backend returning profile URLs directly in user queries
