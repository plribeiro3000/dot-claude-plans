# SPIKE — Granola Format Migration

## Investigation question

What changed in Granola's local data format around 2026-05-12 that broke `meeting-hive`, and what are the viable paths to restore the integration — specifically: can `granola.db` be read without decryption, can the encrypted JSON caches be decrypted via macOS Keychain, or must the integration switch to the official REST API?

## Sources consulted

- `~/Library/Application Support/Granola/granola.db` — binary inspection (read-only); first 32 bytes captured
- `~/Library/Application Support/Granola/storage.dek` — full 51-byte read; prefix identified
- `~/Library/Application Support/Granola/cache-v6.json` — read in full; confirms empty skeleton
- `~/Library/Application Support/Granola/local-state.json` — read in full; feature flags confirm migration
- `~/Library/Application Support/Granola/supabase.json` — structure inspected (tokens masked)
- `~/Library/Application Support/Granola/stored-accounts.json` — structure inspected
- `/Users/plribeiro3000/Projects/OSS/meeting-hive/meeting_hive/sources/granola.py` — full read; dead code path identified at lines 80–145
- `/Users/plribeiro3000/Projects/OSS/meeting-hive/meeting_hive/sync.py` — full read; pipeline shape confirmed
- `/Users/plribeiro3000/Projects/OSS/meeting-hive/meeting_hive/sources/__init__.py` — full read; adapter protocol confirmed
- `/Users/plribeiro3000/Projects/OSS/meeting-hive/pyproject.toml` — full read; dependencies and version confirmed
- [Granola Updates page](https://www.granola.ai/updates) — changelog scanned; no encryption entry found in public-facing changelog
- [Granola Help Center changelog](https://docs.granola.ai/help-center/changelog) — v7.147.1 (week of April 20, 2026) confirmed encryption initiative announcement
- [Granola official API docs](https://docs.granola.ai/introduction) — endpoints, auth, response schema
- [Shadow.do blog post on Granola encryption](https://www.shadow.do/blog/granola-encrypted-its-local-database-heres-why-that-matters----and-what-to-use-instead) — community reaction, dates, Guido Appenzeller post
- [Week in Voice AI #12 — Granola Scramble](https://weekinvoiceai.substack.com/p/week-in-voice-ai12-granola-scramble) — founder clarification quote
- [Granola MCP blog post](https://www.granola.ai/blog/granola-mcp) — published 2026-02-04; MCP launch context
- [varadhjain/granola-claude-plugin (deprecated)](https://github.com/varadhjain/granola-claude-plugin) — archived 2026-04-12; confirms "direct cache access no longer works"
- [getprobo/reverse-engineering-granola-api (archived)](https://github.com/getprobo/reverse-engineering-granola-api) — archived 2026-02-05 when official API launched; v2 endpoint docs captured
- [theantichris/granola PR #21](https://github.com/theantichris/granola/pull/21/files) — Go cache reader diff; v3→v6 JSON format change documented
- [mvanhorn/printing-press-library pp-granola SKILL.md](https://github.com/mvanhorn/printing-press-library/blob/main/cli-skills/pp-granola/SKILL.md) — confirms Keychain approach for decryption; `supabase.json` token refresh mechanism
- [Electron safeStorage docs](https://www.electronjs.org/docs/latest/api/safe-storage) — v10 prefix mechanism confirmed
- [Daniel Moon — reverse-engineering Granola export (Medium)](https://medium.com/@danielmoon_65473/reverse-engineering-granolas-data-export-with-claude-code-and-a-script-to-do-it-d3d292452a43) — confirms `supabase.json` token reading still works as of April 2026
- See auxiliary: `granola_schema_excerpt_1.txt` — raw binary inspection outputs, storage.dek hex dump, local-state.json feature flags, cache-v6.json current structure

---

## Findings

### Finding 1: What actually changed on 2026-05-12

**Evidence:**

Granola founder Chris Pedregal clarified in a public thread (~March 16, 2026):

> "A week ago, we updated how we store data in our cache and broke the workarounds."

This was not encryption of previously-plaintext data — it was a migration of the primary data store from a flat JSON cache to an encrypted SQLite database (`granola.db`) backed by YDoc CRDTs, with the JSON files either emptied (for the main cache) or replaced by `.enc` variants (for auth/preferences).

The `local-state.json` feature flags (last updated 2026-05-05, before the final migration) confirm the migration was already in progress:

```
"ydoc_sqlite_storage": true
"encrypted_preferences_storage": true
"disable_storage_process": true
"partytime_use_ydocs": true
"partytime_ydoc_version": 1
"partytime_ydoc_version_private_notes": 2
```

Source: `~/Library/Application Support/Granola/local-state.json` (full content in `granola_schema_excerpt_1.txt`)

**Significance:** The change was a storage architecture migration, not a targeted lock-out of third-party tools. The migration was rolled out progressively (the flags were set in early May, the JSON was emptied on 2026-05-12). The `cache-v6.json` file still exists but is now a skeleton: the `documents` key is entirely absent. The plaintext `supabase.json` was also frozen on the same date.

---

### Finding 2: The dead code path in meeting-hive

**Evidence (`meeting_hive/sources/granola.py:108–144`):**

```python
def list_meetings(self, since_days: int) -> list[Meeting]:
    cache = self._load_cache()                                        # line 109
    docs = cache.get("cache", {}).get("state", {}).get("documents", {})  # line 110
    # ...
    for doc_id, doc in docs.items():                                  # line 115 — iterates empty {}
        # ...
    log.info("Granola: %d meetings in last %d days", len(meetings), since_days)  # line 144
    return meetings  # returns []
```

`_load_cache()` at line 80–83 reads `cache-v6.json` (which still exists, size ~2 KB) and parses its JSON successfully. `cache.get("cache", {}).get("state", {}).get("documents", {})` returns `{}` because the `documents` key is absent from the frozen skeleton. The loop at line 115 never executes. `list_meetings` returns `[]`. The log line at 144 emits `"Granola: 0 meetings in last 7 days"` — exactly the symptom reported.

No exception is raised. No error is logged. The run exits 0.

**Significance:** The failure is silent by design — the code path is valid Python and JSON, it just finds no data. Fixing it requires pointing the adapter at a live data source, not patching exception handling.

---

### Finding 3: granola.db is encrypted — SQLite-level access is not available without the key

**Evidence (binary inspection, 2026-05-20):**

```
First 32 bytes of granola.db:
b8c3eaf2dc72f6fde607be5869dd9dd116532666fd863d5fd54f5e8816852e67

SQLite plaintext magic: 53514c69 74652066 6f726d61 74203300 ("SQLite format 3\x00")
```

Both `sqlite3` CLI and Python `sqlite3` module return `"file is not a database"`. The file is ~4.5 MB with an active WAL (`granola.db-wal`, ~4.8 MB, updated throughout the day), confirming it is the active primary store — but it is not readable as plain SQLite.

Source: `granola_schema_excerpt_1.txt` — raw command output

**Significance:** Option A (SQLite-only access) is blocked without first obtaining the encryption key. The schema and row structure of `granola.db` are unknown; whether it even stores raw transcript text (vs YDoc binary blobs) is unknown.

---

### Finding 4: storage.dek uses Electron safeStorage v10 format (macOS Keychain)

**Evidence:**

```
storage.dek — 51 bytes
First 4 bytes ASCII: "v10B"
Full hex: 76313042eb36c8208fc225a4672faeaafd73248d1ea11987890881cd5162b37b585e9b0ed5caec565dd4ddaa456325bfbb7312
```

The `v10` prefix is the Electron/Chromium safeStorage format on macOS:
- `v10` = AES-GCM ciphertext encrypted with a key stored in the macOS Keychain
- The Keychain item service name is `"Granola Safe Storage"`
- To decrypt: retrieve the raw key from Keychain → use as AES-128-GCM key to decrypt the 47 bytes after `v10B` → the result is the actual Data Encryption Key (DEK)
- That DEK likely decrypts `cache-v6.json.enc`, `supabase.json.enc`, and `granola.db`

Source: `granola_schema_excerpt_1.txt`; [Electron safeStorage docs](https://www.electronjs.org/docs/latest/api/safe-storage)

The `pp-granola` SKILL.md from `mvanhorn/printing-press-library` independently confirms:

> "The CLI uses Granola's own Keychain-stored encryption key to decrypt `cache-v6.json.enc` and `supabase.json.enc`."
> "On macOS, the first invocation that needs the cache or tokens typically triggers a Keychain prompt for `Granola Safe Storage`, and users should click `Always Allow` so subsequent runs are silent."

Source: [mvanhorn/printing-press-library pp-granola SKILL.md](https://github.com/mvanhorn/printing-press-library/blob/main/cli-skills/pp-granola/SKILL.md)

**Significance:** Decryption via Keychain is technically feasible on macOS. The `security` CLI (`security find-generic-password -ga "Granola" -w`) can retrieve the key if the user grants access. However, the decrypted content of `cache-v6.json.enc` and whether it contains `documents` in any usable form is unknown — it may be equally empty, or it may contain the full document store. This is not confirmed.

Additionally: even if `cache-v6.json.enc` decrypts to something useful, Granola announced in v7.147.1 (week of April 20, 2026):

> "Over the next few weeks, we'll finish encrypting Granola's local cache."

Source: [Granola Help Center changelog](https://docs.granola.ai/help-center/changelog)

This suggests the encrypted cache will become the only cache and its format may keep changing.

---

### Finding 5: The official REST API is live and covers the needed data

**Evidence:**

Granola launched a public REST API on 2026-02-04 alongside the MCP server. Documentation at `https://docs.granola.ai/introduction`:

- **Endpoint:** `GET /v1/notes` — paginated list of notes/meetings
- **Endpoint:** `GET /v1/notes/{id}?include=transcript` — individual note with full transcript
- **Auth:** Bearer token using a personal API key (`grn_YOUR_API_KEY`), created in Settings → Connectors → API keys
- **Rate limit:** 25 requests burst / 5 per second sustained (300/min)
- **Response:** includes `id`, `title`, `owner`, `summary`, transcript with `source` and speaker labels
- **Attendees:** the documented response object shows `owner` but not a full attendees list; whether a `people` field exists requires live verification against the real API

The `get-documents` v2 endpoint (reverse-engineered, now superseded by official API) did return `created_at`, `title`, `id`. The official `/v1/notes` endpoint is the supported replacement.

The reverse-engineering repo `getprobo/reverse-engineering-granola-api` was archived on 2026-02-05:

> "Granola has released an official API, making this reverse-engineering effort obsolete."

Source: [getprobo/reverse-engineering-granola-api](https://github.com/getprobo/reverse-engineering-granola-api)

**Significance:** An API key (not OAuth, not WorkOS token rotation) is the supported authentication path. The key is created once in the Granola desktop app and stored as a static string — compatible with how `meeting-hive` currently loads secrets from `secrets.env`.

---

### Finding 6: supabase.json WorkOS token still readable but stale

**Evidence (`meeting_hive/sources/granola.py:67–78`):**

```python
def _load_token(self) -> str:
    data = json.loads(self._auth_path.read_text())          # reads supabase.json
    workos = data.get("workos_tokens")
    tokens = json.loads(workos) if isinstance(workos, str) else workos
    token = tokens.get("access_token")
    return token
```

`supabase.json` exists (2,735 bytes), is plaintext, and has the structure:
```json
{
  "workos_tokens": "{\"access_token\": \"...\", \"refresh_token\": \"...\"}",
  "session_id": "session_...",
  "user_info": "{...}"
}
```

The file was frozen on 2026-05-12 14:18. The `access_token` in it expired ~1 hour after that date. The `refresh_token` is single-use and was consumed when Granola app last ran a token refresh.

The `pp-granola` SKILL.md confirms:

> "open the Granola desktop app for a few seconds. It silently refreshes its token on launch and writes a fresh one back to `supabase.json`"

Source: [mvanhorn/printing-press-library pp-granola SKILL.md](https://github.com/mvanhorn/printing-press-library/blob/main/cli-skills/pp-granola/SKILL.md)

**Significance:** The WorkOS token path (used by the existing `_api_post` fallback at `granola.py:85–106`) is fragile: it requires the Granola desktop app to have been recently opened to keep `supabase.json` fresh. This was never a documented API — it was a reverse-engineered workaround. The official API key approach does not have this fragility.

---

### Finding 7: No OSS project has solved granola.db decryption publicly

**Evidence (GitHub searches conducted):**

- `varadhjain/granola-claude-plugin` — archived 2026-04-12. README: "Granola encrypted their local cache starting with v6, so direct cache access no longer works." No decryption code present.
- `pedramamini/GranolaMCP` — reads `cache-v3.json` only; no v6 handling.
- `cobblehillmachine/granola-claude-mcp` — reads `cache-v3.json` only; no encryption handling.
- `theantichris/granola` (Go) + PR #21 — handles the v3→v6 JSON double-encoding format change, but this is the *plaintext* `cache-v6.json` format before the encryption migration.
- `mvanhorn/printing-press-library/pp-granola` — confirms Keychain approach works but only shows `SKILL.md` documentation; no public Python decryption code found.

The `pp-granola` SKILL.md describes `doctor` command states `key_unavailable` and `decrypt_failed`, implying they ship working decryption — but their actual source code is in a `scripts/` directory not visible via GitHub web view.

**Significance:** No publicly available, ready-to-copy Python implementation of the `storage.dek` + Keychain decryption path was found. The mechanism is understood (v10 Keychain → AES-GCM → DEK → decrypt `.enc` files) but would need to be implemented from scratch, drawing on Chromium OSCrypt patterns.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| **A: Official REST API** (`GET /v1/notes`) | Supported, stable contract; API key stored in `secrets.env` (fits existing pattern); no Keychain access needed; no dependency on local file format; works even if Granola app not running | Requires `requests` call per run (already a dep); attendees field needs live verification; rate limit (300/min, should be fine for daily use); requires creating API key once in desktop app | [Granola API docs](https://docs.granola.ai/introduction), `meeting_hive/sources/granola.py:85–106` (fallback already exists) |
| **B: Decrypt cache-v6.json.enc via Keychain** | Local-only, no API calls; faster if it works | Keychain access requires macOS `security` CLI or `keyring` library (new dep); content of decrypted file unknown (may be empty or YDoc binary, not plain JSON); Granola explicitly plans to "finish encrypting" — format may keep changing; fragile against Granola updates; no public reference implementation found | `granola_schema_excerpt_1.txt`, [pp-granola SKILL.md](https://github.com/mvanhorn/printing-press-library/blob/main/cli-skills/pp-granola/SKILL.md), [Granola changelog v7.147.1](https://docs.granola.ai/help-center/changelog) |
| **C: Decrypt granola.db via Keychain + parse YDoc** | Direct access to primary store | First 32 bytes confirm not standard SQLite — schema entirely unknown; YDoc is a CRDT binary format (not plain JSON documents); would require a YDoc parser (complex, no Python reference impl found); two layers of unknowns: (1) DEK derivation and (2) YDoc schema; highest implementation risk | `granola_schema_excerpt_1.txt` |

---

## What remains uncertain

- Whether `GET /v1/notes` response includes an attendees/people field (the documented example shows only `owner`). This is verifiable with a single live API call once an API key is created.
- Whether the decrypted content of `cache-v6.json.enc` contains `documents` with the same shape as the old plaintext `cache-v6.json`, or whether the documents were fully migrated to `granola.db`.
- The exact schema of `granola.db` rows (table names, column types, whether transcripts are stored as plain text or YDoc binary blobs). This is inaccessible without the DEK.
- Whether the `mvanhorn/pp-granola` CLI ships working Python decryption code (the `scripts/` directory was not publicly visible in the GitHub web view).
- The transcript endpoint (`GET /v1/notes/{id}?include=transcript`) speaker label format: the docs show `source` (microphone/system) and optional `diarization_label`, but the existing `_join_segments` function in `granola.py:177–193` keys on `text` and `start_timestamp` — field name compatibility needs verification.

---

## What this means for meeting-hive

The integration broke because `list_meetings` reads `cache.get("cache",{}).get("state",{}).get("documents",{})` from `cache-v6.json`, and that key is now absent. Three viable paths exist:

**Option A — Switch GranolaSource to the official REST API**

Replace `list_meetings` to call `GET /v1/notes` (paginated, using `since_days` as a date filter or post-filter on `created_at`). Replace `get_transcript` to call `GET /v1/notes/{id}?include=transcript`. Auth: read an API key from `secrets.env` (same mechanism already used for `ANTHROPIC_API_KEY`). The existing `_api_post` infrastructure at lines 85–106 can be adapted; the WorkOS token path (`_load_token`) is replaced by a static API key read.

What needs verifying before coding: (1) whether `/v1/notes` returns attendees and whether the field name matches the existing `Meeting.attendees` usage in `sync.py:144`; (2) whether the transcript response fields (`text`, `start_timestamp`) match `_join_segments`' expectations.

**Option B — Decrypt cache-v6.json.enc using macOS Keychain + safeStorage**

Add a new `_load_encrypted_cache` method that (1) retrieves the raw key from Keychain under `"Granola Safe Storage"` using the `security` CLI or the `keyring` library, (2) decrypts `storage.dek` with that key (AES-128-GCM, strip `v10` prefix), (3) uses the resulting DEK to decrypt `cache-v6.json.enc`, (4) parses the plaintext. The parsed structure may or may not contain `documents` — this is unknown until attempted. New dependency: `keyring` or subprocess `security` call. New risk: the decrypted content format and stability.

**Option C — Decrypt granola.db and parse YDoc**

Same Keychain path as Option B to get the DEK, but applied to `granola.db`. After decryption, the file should be a standard SQLite database readable by Python `sqlite3`. However, the schema is unknown, and if documents are stored as YDoc CRDTs (binary format), a YDoc parser would be needed to extract plain text. No Python YDoc parser with the same CRDT schema as Granola's implementation was found in research. This option has the highest implementation uncertainty.

(No recommendation — the engineer decides after reading.)
