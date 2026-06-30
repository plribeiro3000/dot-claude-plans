# Angular.json "src/gtag.js" Asset Removal — Implementation Notes

The 11th PLAN step includes removing the `"src/gtag.js"` plain-string asset entry from all 39 projects' `angular.json` assets arrays. This document covers the three implementation approaches and the verification strategy.

---

## Current state

`angular.json` contains 39 instances of `"src/gtag.js"` as a plain string in assets arrays:

```json
// Example from one of the 39 projects:
{
  "projects": {
    "project-name": {
      "architect": {
        "build": {
          "options": {
            "assets": [
              "src/assets",
              "src/_redirects",
              "src/gtag.js",        // ← Plain string, not an object
              "src/.well-known"
            ]
          }
        }
      }
    }
  }
}
```

**Count verification:**
```bash
grep -c '"src/gtag.js"' angular.json
# Output: 39
```

---

## Approach 1: Manual removal (safe, auditable, tedious)

**Procedure:**
1. Open `angular.json` in an editor
2. Use find-and-replace: find `"src/gtag.js",` or `"src/gtag.js"`, replace with empty string
3. Verify: `grep -r '"src/gtag.js"' angular.json` returns empty
4. Spot-check a few projects in the diff to ensure formatting is correct

**Pros:**
- ✓ Every change is visible in the diff
- ✓ Easy to understand what happened
- ✓ Can spot-check before merge

**Cons:**
- ✗ Tedious for 39 projects
- ✗ Risk of manual copy-paste errors
- ✗ PR diff is large (many small changes to the same file)

---

## Approach 2: sed/awk scriptlet (fast, requires verification)

**Command-line example:**
```bash
# Remove all instances of "src/gtag.js" as a standalone asset entry
# This assumes the file is well-formatted (one entry per line)

# Dry-run (safe, just show what would be deleted):
sed -n '/"src\/gtag\.js"/p' angular.json

# Actual removal (careful with escaping):
# Remove lines containing exactly "src/gtag.js" (with quotes and trailing comma)
sed -i '/"src\/gtag\.js"/d' angular.json

# Verify:
grep -c '"src/gtag.js"' angular.json
# Should output: 0
```

**Pros:**
- ✓ Fast (one command)
- ✓ Deterministic (same regex every time)

**Cons:**
- ✗ Requires careful regex escaping
- ✗ Risk if the file format has variations (extra spaces, different quote styles, etc.)
- ✗ Must verify with grep afterward

**Verification step (mandatory):**
```bash
# After sed, verify all entries are removed:
grep -r '"src/gtag.js"' angular.json
# Should return empty

# Verify JSON is still valid:
npm exec jq . angular.json > /dev/null && echo "JSON valid" || echo "JSON invalid"

# Build succeeds:
npm run build  # or equivalent
```

---

## Approach 3: Node.js script (safest, requires development time)

**Script skeleton:**
```javascript
const fs = require('fs');
const path = require('path');

// Read angular.json
const angularJson = JSON.parse(fs.readFileSync('angular.json', 'utf8'));

// Iterate all projects
Object.keys(angularJson.projects || {}).forEach((projectName) => {
  const project = angularJson.projects[projectName];
  const buildOptions = project.architect?.build?.options;

  if (buildOptions && Array.isArray(buildOptions.assets)) {
    // Remove "src/gtag.js" from assets array
    buildOptions.assets = buildOptions.assets.filter(
      (asset) => asset !== 'src/gtag.js'
    );
  }
});

// Write back to angular.json
fs.writeFileSync('angular.json', JSON.stringify(angularJson, null, 2) + '\n');

console.log('✓ Removed "src/gtag.js" from all projects');
```

**Pros:**
- ✓ Parses JSON properly (no regex escaping errors)
- ✓ Handles variations in formatting
- ✓ Easy to verify (count before/after)
- ✓ Least risk of corrupting the file

**Cons:**
- ✗ Requires writing/testing a Node script (development overhead)
- ✗ Not auditable as easily as sed (the changes are all at once in the diff)

---

## Recommendation for the engineer

**Recommended approach:** Approach 2 (sed + grep verification)

**Rationale:**
- Balance of speed (one command) and safety (grep verification is built-in)
- Developer testing: run sed on a copy of angular.json first, verify the output, then apply to the real file
- Verification command is clear and mandatory (grep -r '"src/gtag.js"' angular.json should return empty)

**Command sequence:**
```bash
# 1. Dry-run: see what will be deleted
sed -n '/"src\/gtag\.js"/p' angular.json

# 2. Apply removal
sed -i '/"src\/gtag\.js"/d' angular.json

# 3. Verify all removed
grep '"src/gtag.js"' angular.json
# Should output nothing

# 4. Verify JSON is still valid
node -e "JSON.parse(require('fs').readFileSync('angular.json', 'utf8'))" && echo "Valid JSON"

# 5. Build succeeds
npm run build
```

**Alternative (if sed fails due to escaping):**
```bash
# Use Perl or Node.js for more robust replacement
# Perl example:
perl -i -ne 'print unless /"src\/gtag\.js"/' angular.json
```

---

## Risks and mitigations

| Risk | Impact | Mitigation |
|------|--------|-----------|
| Incomplete removal | Some projects retain the asset entry; build may succeed but `/gtag.js` 404 occurs at runtime | Verify with `grep -r '"src/gtag.js"' angular.json` (must return empty) |
| JSON corruption | Build fails with JSON parse error | Test on a copy first; use a JSON parser (Node or jq) to verify |
| Unintended deletions | Other assets removed by mistake (if regex is too broad) | Use exact string match (`"src/gtag.js"` with quotes) to avoid false positives |
| Format variations | sed misses entries due to spacing or quote differences | Dry-run first (`sed -n '...'p`) to see what matches |

---

## Verification checklist

After removal, confirm all of these before merge:

- [ ] `grep -r '"src/gtag.js"' angular.json` returns empty (0 matches)
- [ ] `node -e "JSON.parse(require('fs').readFileSync('angular.json', 'utf8'))"` succeeds (JSON is valid)
- [ ] `npm run build` succeeds for at least one project (CI verifies the rest)
- [ ] Network tab on page load shows no 404 for `/gtag.js` (after Task 1 is deployed first)
- [ ] `git diff angular.json` shows only removal of `"src/gtag.js"` lines, no other changes

---

## Edge cases

- **Windows/CRLF line endings:** sed may behave differently on Windows. Use `dos2unix angular.json` first if needed, or use Perl.
- **Mixed quote styles:** If the file has both single and double quotes, the regex must account for that (unlikely in this project, but possible).
- **Asset objects vs. strings:** The current `angular.json` uses plain strings for `"src/gtag.js"`. If any project uses an object format (e.g., `{ "glob": "...", "input": "src/gtag.js", "output": "/" }`), that regex would miss it. Verify with grep after removal.
