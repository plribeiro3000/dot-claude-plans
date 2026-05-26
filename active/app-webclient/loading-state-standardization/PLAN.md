# Loading State Standardization

## Problem Statement

Loading state flags (`loadingX = true/false`) are not consistently reset in all code paths, causing infinite spinners in edge cases.

### Current Pattern (Problematic)

```typescript
getParents(value = '') {
  this.loadingParents = true;

  this.service.query(...).valueChanges.subscribe((response: any) => {
    // Early exit for Apollo v3 empty response - loading NOT reset!
    if (!response?.data || Object.keys(response.data).length === 0) {
      return;
    }

    if (response.data.items.nodes.length > 0) {
      this.items = response.data.items.nodes;
      this.loadingParents = false;  // Only reset here
    } else {
      this.items = [];
      this.loadingParents = false;  // And here
    }
  });
}
```

### Why the Early Return Exists

Apollo v3 changed behavior: when a `watchQuery` is created, it immediately emits an empty response before the actual data arrives. The early return prevents processing this empty response.

### The Problem

If the response comes back with `data: null` or `data: {}` (which triggers the early return), the loading flag stays `true` forever, showing an infinite spinner.

## Scope

- **131 files** have loading state patterns
- Not all may have the problem - need to audit each

## Expected Behavior

Loading state should ALWAYS be reset to `false` when the operation completes, regardless of:
- Success with data
- Success with empty data
- Early return for Apollo empty response
- Error response

## Proposed Solutions

### Option A: Reset loading after all conditions

```typescript
getParents(value = '') {
  this.loadingParents = true;

  this.service.query(...).valueChanges.subscribe((response: any) => {
    if (!response?.data || Object.keys(response.data).length === 0) {
      return;  // Don't reset here - this is the Apollo v3 initial empty emit
    }

    if (response.data.items.nodes.length > 0) {
      this.items = response.data.items.nodes;
    } else {
      this.items = [];
    }

    // Always reset after processing (not in early return)
    this.loadingParents = false;
  });
}
```

**Pros**: Simple, clear
**Cons**: Doesn't handle actual error cases

### Option B: Use finalize operator

```typescript
import { finalize } from 'rxjs/operators';

getParents(value = '') {
  this.loadingParents = true;

  this.service.query(...).valueChanges
    .pipe(
      finalize(() => this.loadingParents = false)
    )
    .subscribe((response: any) => {
      if (!response?.data || Object.keys(response.data).length === 0) {
        return;
      }
      // ... rest of logic
    });
}
```

**Pros**: Handles completion AND error cases automatically
**Cons**: More invasive change, adds import

### Option C: Track Apollo initial emit separately

```typescript
getParents(value = '') {
  this.loadingParents = true;
  let isInitialEmit = true;

  this.service.query(...).valueChanges.subscribe((response: any) => {
    if (!response?.data || Object.keys(response.data).length === 0) {
      if (isInitialEmit) {
        isInitialEmit = false;
        return;  // Skip Apollo's initial empty emit
      }
      // Subsequent empty response = actual problem
      this.loadingParents = false;
      return;
    }

    isInitialEmit = false;
    // ... process data
    this.loadingParents = false;
  });
}
```

**Pros**: Distinguishes Apollo quirk from real empty responses
**Cons**: Complex, adds state tracking

### Option D: Use skip(1) to ignore initial emit

```typescript
import { skip } from 'rxjs/operators';

getParents(value = '') {
  this.loadingParents = true;

  this.service.query(...).valueChanges
    .pipe(skip(1))  // Skip Apollo's initial empty emit
    .subscribe((response: any) => {
      // Now all responses are real - always reset loading
      if (!response?.data || Object.keys(response.data).length === 0) {
        this.items = [];
        this.loadingParents = false;
        return;
      }

      this.items = response.data.items.nodes || [];
      this.loadingParents = false;
    });
}
```

**Pros**: Clean, addresses root cause
**Cons**: May skip legitimate first response in some edge cases

## Recommendation

**Option A (Reset after all conditions)** for simplicity, with the understanding that:
- The early return is ONLY for Apollo's initial empty emit
- After that check passes, we're in "real data" territory and should always reset

This is the minimal change that fixes the problem without introducing new patterns.

## Pattern to Apply

**Before:**
```typescript
if (!response?.data || Object.keys(response.data).length === 0) {
  return;
}

if (response.data.items.nodes.length > 0) {
  this.items = response.data.items.nodes;
  this.loadingX = false;
} else {
  this.items = [];
  this.loadingX = false;
}
```

**After:**
```typescript
if (!response?.data || Object.keys(response.data).length === 0) {
  return;
}

if (response.data.items.nodes.length > 0) {
  this.items = response.data.items.nodes;
} else {
  this.items = [];
}

this.loadingX = false;
```

## Files to Audit

131 files have loading patterns. Each needs to be checked for:
1. Does it have the early return pattern?
2. Is the loading flag reset in all code paths after the early return?

<details>
<summary>Click to expand full list (131 files)</summary>

See grep output for complete list.

Key modules to prioritize:
- src/app/user/
- src/app/deal/
- src/app/group/
- src/app/campaign/
- src/app/company/
- src/app/payment/
- src/app/plan/

</details>

## Execution Strategy

1. Create a script to identify files with the problematic pattern
2. Group by module
3. Fix one module at a time
4. Test after each module
5. One PR per module or one large PR

## Automation Potential

This fix is partially automatable:
- Can use regex to find loading flags inside if/else blocks after early return
- Manual review needed to confirm the pattern applies

## Estimated Effort

- 131 files to audit
- Not all will need changes (some may already be correct)
- Simple structural change when needed

## Status

- [ ] Planning approved
- [ ] Audit complete (identify which files need changes)
- [ ] Files updated
- [ ] Tests passing
- [ ] PR created
