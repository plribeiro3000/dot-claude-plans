# Plan: Deprecate Performance Feature

## Overview

**Feature:** deprecate-performance
**Type:** Multi-project (app + app-webclient)
**Status:** ✅ Completed

## Problem

The Performance feature has critical bugs and is non-functional:
- `Performance::Consumer` calls non-existent method (`pre_aggregated_modifier.user_commission`)
- No test coverage for workers
- Cron job runs daily but produces errors

## Decision

**Keep tables and models for historical client data.**

We will NOT drop the tables. The data belongs to clients and may be needed for historical reports or audits. Last activity on these tables was in 2022, confirming no active usage, but the data must be preserved.

Models are kept frozen (read-only) to facilitate querying and generating reports if necessary. However, there is no longer any way to create, update, or access these models via the application - all endpoints have been removed and there is no more processing.

### What is being removed:
- GraphQL endpoints (types, resolvers, mutations) - no more access
- Workers (performance processing) - no more processing
- Rake task (`cron:performance:processor`) - no more scheduled jobs
- Actions (permissions) - no more access control
- Frontend components and routes - no more UI

### What is being kept:
- Database tables (historical client data - will NOT be dropped)
- Models (frozen with `before_save { throw :abort }` for read-only queries/reports)
- Specs, factories, locales, scopes, policies (for maintenance)

## Deploy Plan

1. ✅ **Frontend Release** (app-webclient) - v1.251.0
   - Remove Performance UI components and routes
   - Deployed to production

2. ✅ ~~**Remove Cronjob**~~ Not needed
   - Verified: `cron:performance:processor` is not configured in any environment
   - Job was never migrated or was removed long ago

3. ✅ **Backend Release** (app) - v3.5.0
   - Deploy with removed workers, endpoints, and rake task
   - Migration removes Performance actions (permissions)
   - Deployed to production

4. ✅ **Old Frontend Hotfix** (app-webclient old-front branch)
   - Remove Performance Analysis references from Calendar module
   - Merged and deployed to production

## Progress

### Backend (app) - PR #4713
- [x] Freeze models (read-only)
- [x] Remove GraphQL endpoints
- [x] Remove workers
- [x] Remove rake task
- [x] Remove queue from hire_fire.rb
- [x] Create migration to remove actions
- [x] Open PR to develop

### Frontend (app-webclient) - PR #5831
- [x] Create feature branch
- [x] Remove Performance components
- [x] Remove Performance routes
- [x] Open PR to develop

### Old Frontend (app-webclient old-front branch) - PR #5842
- [x] Remove Performance Analysis from Calendar create form (was sending `calendarPerformanceAnalysesAttributes` in mutation)
- [x] Remove Performance Analysis from Calendar show page (was querying `performanceAnalyses`)
- [x] Open PR to old-front
- [x] Merged and deployed to production

> **Note:** This was discovered after the main releases. The old frontend (used by some clients) was still trying to send/query performance data when creating/viewing calendars, causing failures. Should have been included in the original scope.

---

**Created:** 2026-01-07
**Updated:** 2026-01-12
