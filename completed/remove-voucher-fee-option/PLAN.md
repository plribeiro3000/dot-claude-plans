# Plan: Remove Fee and Simplify Option Structure

## Context

The fee was implemented to charge end users during voucher redemption, but the business decided that the fee should only be charged to the client company (via contract), not to the end user. The contract has already been adjusted. Now the application needs to match.

With the fee removed, the `VoucherItem::Option` class (which existed to wrap a value and calculate a fee) becomes pointless — it just wraps an integer. The migration eliminates this unnecessary abstraction entirely.

**Constraint**: Zero downtime. Each step must be deployed before the next one starts.

---

## Step 1: Frontend - Remove fee from UI ✅ DEPLOYED

**PR #6035** (app-webclient) — Merged and released

Removed all fee display, calculations, translations, and model properties from the frontend. The frontend stopped consuming `fee` but continued using `options { value }` in GraphQL queries.

---

## Step 2: Backend - Remove fee from API + add `optionValues` field ✅ DEPLOYED

**PR #4793** (app) — Merged and released (v3.10.0)

- Removed `field :fee` from 4 GraphQL types
- Removed fee calculation from `VoucherItem::Option`
- Added `field :option_values, [Int]` to `VoucherCatalogationGraphqlType` and `VoucherItemGraphqlType`
- Kept `options` field returning objects `{ value }` for backwards compatibility

---

## Step 3: Frontend - Migrate from `options { value }` to `optionValues` ✅ DEPLOYED

**PR #6037** (app-webclient) — Merged and released (v1.257.0)

- All GraphQL queries changed from `options { value }` to `optionValues`
- All `.map((opt) => opt.value)` mapping logic replaced with direct integer consumption
- Added `optionValues: number[]` to `VoucherCatalogation` model

---

## Step 4: Backend - Remove Option class, redefine `options` as `[Int]` ✅ DEPLOYED

**PR #4796** (app) — Merged and released

- Deleted `VoucherItem::Option` class and `VoucherItemOptionGraphqlType`
- Redefined `options` field to return `[Int]` directly
- Kept `optionValues` field for backwards compatibility (frontend still consumes it)

---

## Step 5: Frontend - Migrate from `optionValues` to `options` ✅ MERGED

**PR #6045** (app-webclient) — Merged

- All GraphQL queries changed from `optionValues` to `options`
- Removed `optionValues` from `VoucherCatalogation` model
- Removed `VoucherItemOption` model
- Updated `VoucherItem.options` type from `VoucherItemOption[]` to `number[]`

---

## Step 6: Backend - Remove `optionValues` field (cleanup) ✅ MERGED

**PR #4802** (app) — Merged (deploy pending)

- Removed `field :option_values` and `def option_values` resolver from both GraphQL types
- Final state: only `options` field exists, returning `[Int]` directly

---

## COMPLETED

All 6 steps merged. Migration from fee+Option wrapper to plain integer array is done.
