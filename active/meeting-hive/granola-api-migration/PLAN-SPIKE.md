# PLAN-SPIKE — Granola API Migration

> Reference: `~/.claude/plans/active/spike/granola-format-migration/SPIKE.md` (canonical prior research)

## Objective

Replace `GranolaSource`'s broken local-cache path with the official Granola REST API (`https://public-api.granola.ai/v1`). The engineer has chosen the hybrid summarization pipeline: **transcript (full) → Claude (with Granola's `summary_markdown` as additional context, instructed to verify against transcript and fill gaps) → Wispr vocabulary pass → write to disk**. This document surfaces the remaining design choices the engineer must make before implementation begins.

## Correction to SPIKE.md

The SPIKE.md at `~/.claude/plans/active/spike/granola-format-migration/SPIKE.md` records the base URL as `https://api.granola.ai/v1`. Live probes on 2026-05-20 confirm the correct URL is **`https://public-api.granola.ai/v1`**. The `API_BASE` constant at `granola.py:29` must be updated to the correct host. This is a required fix regardless of which options are chosen below.

## Scope

### In scope

- Replace `_load_token` (WorkOS path) with `os.environ["GRANOLA_API_KEY"]`
- Delete `_load_cache` (no local cache anymore)
- Re-implement `list_meetings` via `GET /v1/notes?created_after=...` with pagination
- Re-implement `get_transcript` via `GET /v1/notes/{id}?include=transcript`
- Fix `_join_segments`: key `start_timestamp` → `start_time`
- Integrate `summary_markdown` from the API into the Claude prompt (hybrid design)
- Add `GRANOLA_API_KEY=` to `secrets.env`; update README, CHANGELOG, `pyproject.toml` version
- Add tests for the new adapter behavior (no tests for Granola exist today)

### Out of scope (open question)

- Decryption of `granola.db` / `cache-v6.json.enc` — engineer chose REST API
- Re-evaluating the hybrid vs. Claude-only vs. Granola-summary-only choice — engineer chose hybrid
- Changes to `FathomSource`, `MarkdownSource`, or any other adapter

---

## Mother Rule findings — sibling adapter pattern

Read: `meeting_hive/sources/fathom.py`, `meeting_hive/sources/markdown.py`, `meeting_hive/sources/__init__.py`.
See auxiliary: `adapter_siblings_excerpt_1.txt` — full excerpts.

**Established pattern:**

1. `__init__(self, config: dict[str, Any] | None = None)` — all config via `cfg.get(...)`. No positional args for settings.
2. Config keys: `base_url` (testability override), `api_key_env` (env var name), `api_key` (inline, test-only), `retries` (int, default 3). Source: `FathomSource`.
3. Private HTTP method `_request(path, params)` handles retry loop, 401 → `SourceAuthError`, 429 → exponential backoff, `ConnectionError` → `SourceUnavailable`, `HTTPError` → `SourceError`.
4. `list_meetings` returns a sorted `list[Meeting]`, logs at INFO.
5. `get_transcript` returns `str | None` — `None` is the not-ready signal, not an exception.
6. Module-level `_join_segments` and `_parse_dt` helper functions (pure, no side effects).

**Anti-pattern check for the proposed new `GranolaSource`:**

- Iceberg Class: not present — the Protocol surface stays at 2 methods; `_request` is a meaningful retry loop, not a large hidden surface.
- Parameter-Passing Pipeline: not present — config is unpacked in `__init__`, not threaded through every method.
- Extracted Wrapper Methods: not present — `_request` is not a thin wrapper around a single `requests.get`; it handles retries, error translation, and backoff.
- Phase Extraction: not present — no save_/finalize_ split.
- Per-Branch Delegation: not present — no case/switch.

**Sibling pattern summary:** The `FathomSource` shape includes constructor / `_request` / `list_meetings` pagination loop. Whether the new `GranolaSource` mirrors that shape is decision 5 below.

---

## Required changes (not options — these are settled)

| File | Change | Lines affected |
|------|--------|----------------|
| `meeting_hive/sources/granola.py:29` | `API_BASE`: fix host `api.granola.ai` → `public-api.granola.ai` | 29 |
| `meeting_hive/sources/granola.py:67-78` | Delete `_load_token` (WorkOS); replace with API key read from env via `_headers()` pattern from `fathom.py` | 67–78 |
| `meeting_hive/sources/granola.py:80-83` | Delete `_load_cache` | 80–83 |
| `meeting_hive/sources/granola.py:85-106` | Replace `_api_post` (POST + WorkOS token) with `_request` (GET + Bearer key), following `fathom.py:60-82` | 85–106 |
| `meeting_hive/sources/granola.py:108-145` | Re-implement `list_meetings` via `GET /v1/notes?created_after=...` with pagination | 108–145 |
| `meeting_hive/sources/granola.py:147-174` | Re-implement `get_transcript` via `GET /v1/notes/{id}?include=transcript` | 147–174 |
| `meeting_hive/sources/granola.py:183` | `_join_segments`: key `start_timestamp` → `start_time` | 183 |
| `secrets.env` | Add `GRANOLA_API_KEY=` | — |
| `meeting_hive/__init__.py` | Version bump | — |
| `CHANGELOG.md`, `README.md` | Update | — |

---

## Candidate approaches — decisions the engineer must make

---

### Decision 1: Attendees acquisition strategy

**Context:** `list_meetings` must populate `Meeting.attendees` for the classifier in `sync.py:144`:

```python
# sync.py:144
meta = classifier.ClassifyMeta(title=m.title, attendees=m.attendees)
result = classifier.classify(meta, cfg)
```

`classifier.classify` applies `email_rules` and `domain_rules` against attendee email addresses. If `attendees` is empty, only `title_patterns` and `internal_only` rules fire — `email_rules` and `domain_rules` are silently skipped. This is the load-bearing concern: `GET /v1/notes` does NOT return attendees at the list level (confirmed by live probe — see `api_response_samples_1.txt`).

**Option A: N+1 — one extra GET per meeting during `list_meetings`**

`list_meetings` fetches the full detail (`GET /v1/notes/{id}?include=transcript` or `GET /v1/notes/{id}`) for each meeting to extract attendees. The transcript is also returned in the same call and can be cached on the `Meeting` object (or discarded and re-fetched by `get_transcript`).

- Pros: `Meeting.attendees` is populated before classification; no architectural change to `sync.py`; all data in one pass; if transcript is cached, `get_transcript` becomes a dict lookup.
- Cons: N API calls during `list_meetings` (one per meeting in the window); for a 7-day window with ~10 meetings/week, that is 10 calls, well within the 300/min rate limit; for heavy users with 50+ meetings/week, still comfortably within limits at ~50 calls.
- Cost: small — one `_request` call per meeting in the pagination loop.
- Risk: low — rate limit is not a practical concern for daily personal use.

**Option B: `list_meetings` returns meetings without attendees; attendees extracted inside `get_transcript`**

`list_meetings` returns `Meeting` objects with `attendees=[]`. `get_transcript` fetches `GET /v1/notes/{id}?include=transcript`, extracts the transcript, and also returns attendees — but the Protocol for `get_transcript` is `str | None`, so attendees have nowhere to go. This option requires either mutating the `Meeting` object after the fact or changing the Protocol.

- Pros: `list_meetings` stays fast (no extra calls per item).
- Cons: `sync.py:144` runs classification with empty `attendees` — `email_rules` and `domain_rules` never fire; meetings are unclassified or misclassified; this breaks the existing classification logic without a `sync.py` change. The Protocol for `get_transcript` returns `str | None` — no channel to return attendees. Requires either changing the Protocol (breaking change across all adapters) or adding side effects.
- Cost: medium — requires `sync.py` change or Protocol change.
- Risk: high — breaks classification silently for all users relying on `email_rules`/`domain_rules`.

**Option C: Restructure the adapter contract**

Add a `get_meeting_detail(meeting_id) -> dict` method to the Protocol; `sync.py` calls it after `list_meetings` to get attendees and transcript in one call. This collapses `get_transcript` into `get_meeting_detail`.

- Pros: explicit method on the Protocol; one call per meeting.
- Cons: breaking Protocol change — `FathomSource`, `MarkdownSource` must also implement `get_meeting_detail`; larger diff than the task requires; the existing Protocol already works for Fathom and Markdown.
- Cost: high — touches 3 adapters + `sync.py` + tests.
- Risk: medium — well-defined change, but scope is larger than the migration itself.

**Codebase note:** `sync.py:144` consumes `meeting.attendees` for classification. Options B and C require changes to `sync.py` or the `Source` Protocol; Option A does not. The N+1 call count is not a practical concern at personal-use scale (confirmed: rate limit is 300/min, typical window is ~10 meetings).

---

### Decision 2: Pagination implementation

**Context:** `GET /v1/notes` returns `{"notes": [...], "hasMore": bool, "cursor": string}` (confirmed by live probe). `FathomSource.list_meetings` uses an eager `while True` loop with a cursor.

**Option A: Eager — collect all pages into a list inside `list_meetings` (mirrors `fathom.py`)**

```python
# Pattern: fathom.py:84-104
while True:
    data = self._request("/notes", params=params)
    for item in data.get("notes") or []:
        meetings.append(self._to_meeting(item))
    cursor = data.get("cursor") or None
    if not data.get("hasMore"):
        break
    params["cursor"] = cursor
```

- Pros: identical shape to `FathomSource` — no new pattern to understand; returns `list[Meeting]` as the Protocol requires; simple to test with `responses` fixtures.
- Cons: loads all meeting metadata into memory before returning; for a 7-day window this is ~10 objects (negligible).
- Cost: minimal — copy the `fathom.py` loop with the correct field names.
- Risk: low.

**Option B: Generator-based lazy iteration**

`list_meetings` becomes a generator that yields `Meeting` objects one page at a time.

- Pros: lower peak memory; in principle more aligned with the "Data Processing Pattern" in `CLAUDE.md` (return IDs/aggregations, not loaded lists).
- Cons: the Protocol signature is `def list_meetings(self, since_days: int) -> list[Meeting]` — a generator violates it. `sync.py` iterates meetings in a `for m in meetings:` loop, which works with both, but the declared return type does not. Changing the Protocol return type is a breaking change across all adapters. The "Data Processing Pattern" note in `CLAUDE.md` is framed for 4Shark server-side systems with millions of records; this project's scale is ~10–50 meetings/week.
- Cost: medium — requires Protocol + type annotation change across all adapters.
- Risk: low functionally, medium for type correctness.

**Codebase note:** The Protocol return type is `list[Meeting]`; a generator does not satisfy it without a Protocol change.

---

### Decision 3: Granola summary integration into the Claude prompt

**Context:** The engineer chose the hybrid pipeline. `summary_markdown` is available in the `GET /v1/notes/{id}?include=transcript` response (confirmed by live probe — see `api_response_samples_1.txt`). The prompt is built by `format_prompt(transcript, title, attendees)` in `meeting_hive/summarizers/__init__.py:95-102`. See full prompt and call chain in auxiliary: `prompt_excerpt_1.txt`.

The current PROMPT_TEMPLATE structure is:
```
[system instructions]
# Meeting
- Title / Attendees
# Summary format
[format spec]
# Transcript
{transcript}
```

There is **no system message** today — it is all one user message. There are three options for where `summary_markdown` goes.

**Option A: Append a "# Reference Draft" block after the transcript**

`format_prompt` receives an optional `granola_summary: str | None = None` parameter. When present, a new section is appended:

```
# Transcript
{transcript}

# Reference Draft (Granola's auto-summary — verify against the transcript above; fill in gaps it missed)
{granola_summary}
```

- Pros: the model sees the transcript first (primary evidence), then the summary (secondary); the instruction to "verify against transcript and fill gaps" is in-context; minimal PROMPT_TEMPLATE change; optional param means all existing call sites (`openai`, `ollama`) work unchanged.
- Cons: appending after the transcript may be less prominent; some models attend more to earlier context.
- Cost: small — add one optional param to `format_prompt`; update PROMPT_TEMPLATE.
- Risk: low.

**Option B: Insert a "# Granola Pre-Summary" block before the transcript**

The reference draft goes between the format instructions and the transcript:

```
# Reference Draft (Granola's auto-summary — verify against the transcript below; fill in gaps it missed)
{granola_summary}

# Transcript
{transcript}
```

- Pros: the summary is near the top where attention is highest; sets context before reading the transcript.
- Cons: transcript (the primary evidence) appears after the prompt instructions and the reference — the model may over-rely on the draft rather than the transcript; "verify against transcript" is harder when the transcript comes later.
- Cost: same as Option A.
- Risk: low structurally; medium for output quality (may bias toward Granola summary rather than transcript).

**Option C: Pass `summary_markdown` via the `transcript` string itself (pre-concatenate in `GranolaSource.get_transcript`)**

`get_transcript` returns a combined string: `"[Granola Summary]\n{summary_markdown}\n\n[Transcript]\n{transcript_text}"`. `format_prompt` receives it as-is via the existing `transcript` slot.

- Pros: no changes to `format_prompt`, PROMPT_TEMPLATE, or the Summarizer Protocol; the summary integration is entirely inside `GranolaSource`.
- Cons: the `transcript` field in the written markdown file will contain both the summary and the transcript mixed together (since `sync.py:167` passes `transcript_fixed` to `corrector` and then writes it to the transcript file); this contaminates the archive with a non-transcript blob inside transcript files. Also, the Wispr vocabulary corrector will run over the Granola summary text unnecessarily.
- Cost: smallest diff — one change in `get_transcript`.
- Risk: medium — side-effects on the written transcript file content and on the corrector pass.

**Codebase note on Summarizer Protocol:** the Protocol is `def summarize(self, transcript: str, title: str, attendees: list[str]) -> str`. Options A and B require `format_prompt` to accept an optional fourth param; they do NOT change the Protocol itself. `sync.py` calls `summarizer_adapter.summarize(transcript=transcript_fixed, title=m.title, attendees=m.attendees)` — to pass `granola_summary` here, `sync.py` would need to know it. This means either: (a) `get_transcript` returns a dict `{transcript, granola_summary}` (Protocol change), or (b) `GranolaSource` stores the summary as a side-channel attribute keyed by meeting ID, or (c) `format_prompt` is called inside `GranolaSource` directly (violates adapter boundary).

**This is a consequential interaction with Decision 1:** if Option A of Decision 1 is chosen (N+1 calls), the `summary_markdown` is already fetched by `list_meetings` and can be stored on a per-ID dict. `get_transcript` then returns `f"[Granola Draft]\n{cached_summary}\n\n[Transcript]\n{raw_transcript}"`. The Wispr contamination risk of Option C still applies.

---

### Decision 4: Handling not-yet-ready transcripts

**Context:** A meeting that just ended may exist in `GET /v1/notes` but have `transcript: []` (empty list) or the `transcript` key may be absent. Today, `sync.py:161-165` handles a `None` return from `get_transcript`:

```python
# sync.py:161-165
if not transcript:
    log.warning("No transcript for %s — skipping", m.title)
    stats["failed"] += 1
    continue
```

It counts the meeting as `failed` and moves on. Three options for how `get_transcript` signals "not ready yet":

**Option A: Return `None` — silent skip, picked up next run**

If `transcript` is empty/absent, return `None`. `sync.py` logs the warning and increments `failed`. The meeting will appear again in the next run's window (if within `since_days`) and be processed once the transcript is ready. The existing `writer.already_exists` check prevents re-processing if a file was already written.

- Pros: zero `sync.py` changes; matches current behavior for all adapters; simple.
- Cons: `failed` counter is incremented, which triggers the "❌ N failure(s)" notification — this may be confusing for a meeting that is simply not processed yet vs. one that genuinely failed.
- Cost: minimal — no change from current behavior.
- Risk: low — minor UX confusion from the failure notification.

**Option B: Return `None` with an explicit `log.info` (not `log.warning`) before returning**

Same as Option A but the log level inside `get_transcript` is INFO rather than WARNING, distinguishing "not ready" from "error".

- Pros: not-ready transcripts log at INFO instead of WARNING.
- Cons: `sync.py` still counts it as `failed`; the notification text still says "failure".
- Cost: trivial.
- Risk: none.

**Option C: Raise a new `SourceNotReady` exception; `sync.py` catches it separately**

A new exception class `SourceNotReady(SourceError)` signals "transcript not available yet, try again later". `sync.py` catches it and increments a `pending_transcript` counter instead of `failed`.

- Pros: pending transcripts are counted and reported separately from failures.
- Cons: requires adding a new exception class to `sources/__init__.py`; requires changing `sync.py` to catch it; touches two files outside `granola.py`.
- Cost: small but multi-file.
- Risk: low.

**Codebase note:** The current `sync.py` already has `stats["pending_classification"]` for the analogous "meeting found but not ready to write" case. The pattern for Option C already exists in the stats dict shape — it would be adding `stats["pending_transcript"]`.

---

### Decision 5: Rate-limit and error handling shape

**Context:** The current `_api_post` (lines 85–106) handles 401 → `SourceAuthError`, 429 → exponential backoff, `HTTPError` → re-raise after retries. `FathomSource._request` adds `ConnectionError` → `SourceUnavailable`. Auth is now a static API key — no token refresh needed.

**Option A: Mirror `FathomSource._request` exactly**

Replace `_api_post` with `_request(path, params)` following `fathom.py:60-82`:
- `requests.get` (not POST)
- `_headers()` method that reads the API key from env (same pattern as `FathomSource._headers`)
- 401 → `SourceAuthError`
- 429 → exponential backoff + `continue`
- `ConnectionError` → `SourceUnavailable`
- `HTTPError` → `SourceError` after retries
- `retries` config key (default 3)

- Pros: identical shape to the sibling adapter; no new patterns; easy to read side-by-side.
- Cons: ~20 lines of retry/error logic in the adapter.
- Cost: minimal.
- Risk: low.

**Option B: Simplify — remove the retry loop, keep only 401 and 429**

Since the API key is static (no refresh), auth failures are permanent. A 401 means "wrong key", not "expired token". A simplified handler could raise immediately on 401 and 429 without retrying.

- Pros: fewer lines of code (no retry loop).
- Cons: 429 with no retry means a single burst of requests during a paginated `list_meetings` could abort the run; transient 5xx errors (server hiccup) would also abort without retry; the retry coverage that `fathom.py:60-82` provides is dropped.
- Cost: trivial.
- Risk: medium — reduced robustness on rate-limited or flaky network conditions.

**Codebase note:** `fathom.py:60-82` implements a retry loop covering 429, 5xx, and `ConnectionError`. Option A carries that robustness into `GranolaSource`; Option B drops it.

---

### Decision 6: Adapter constructor shape

**Context:** Current `GranolaSource.__init__` accepts `cache_path` and `cache_filename` config keys — both dead with the cache gone. The constructor must be updated.

**Option A: Follow `FathomSource` constructor shape exactly**

```python
def __init__(self, config: dict[str, Any] | None = None):
    cfg = config or {}
    self._base_url = cfg.get("base_url", DEFAULT_BASE_URL).rstrip("/")
    self._api_key_env = cfg.get("api_key_env", "GRANOLA_API_KEY")
    self._explicit_key = cfg.get("api_key")
    self._retries = int(cfg.get("retries", 3))
```

- Pros: identical shape to the sibling; `base_url` override enables testing without network; `api_key` inline enables test fixtures; `retries` matches the established config key.
- Cons: none.
- Cost: trivial.
- Risk: low.

**Option B: Add `page_size` as a constructor config key**

The Granola API appears to use a fixed page size of 10 (observed in live probe). If the API ever supports a `page_size` parameter, exposing it as a config key would allow tuning. Currently there is no evidence the API accepts a page size parameter.

- Pros: forward-compatible if Granola adds a `limit` parameter.
- Cons: no evidence the API accepts it today; adding a config key that has no effect is noise; can be added later without breaking the interface.
- Cost: trivial to add; trivial to add later.
- Risk: none if not added now.

**Codebase note:** Adding `page_size` now is speculative — not found in Granola API docs.

---

### Decision 7: Backward-compatibility for users on old Granola versions

**Context:** The SPIKE.md confirms `cache-v6.json` is frozen/empty for all users who updated to Granola ≥ v7.147.1 (rolled out around 2026-05-12). The adapter currently has a cache path and a REST API fallback. After this migration, the cache path is entirely removed.

**Option A: Hard break — remove all cache/supabase.json code, REST API only**

All code referencing `_cache_path`, `_auth_path`, `_load_token`, `_load_cache` is deleted. Any user still on old Granola (before v7.147.1) who has a valid `cache-v6.json` will no longer work — but they would need to set `GRANOLA_API_KEY` anyway.

- Pros: removes all cache and token-load code paths from `granola.py`; the SPIKE.md confirms the old path is broken for everyone on the current version.
- Cons: a user on Granola < v7.147.1 loses the cache path. In practice, Granola auto-updates aggressively (Electron app); the SPIKE.md found no active OSS projects still using the cache path as of May 2026.
- Cost: none — this is the minimal diff.
- Risk: negligible — the cache is empty for everyone on the current Granola version.

**Option B: Keep cache path as a deprecated fallback with a log warning**

If `GRANOLA_API_KEY` is not set, attempt to fall back to `cache-v6.json` with a deprecation log warning.

- Pros: backward-compatible for users on old Granola who haven't set up an API key yet.
- Cons: the cache is empty for current Granola — the fallback succeeds (no error) but returns zero meetings, which is the exact silent failure that started this whole investigation. The warning may go unseen in cron runs. Keeping dead code paths creates ongoing maintenance burden.
- Cost: small to write; medium to maintain.
- Risk: medium — the fallback gives false confidence that the adapter is working when it isn't.

**Codebase note:** The SPIKE.md is explicit: "Fixing it requires pointing the adapter at a live data source, not patching exception handling."

---

## Technical decisions to be made

| Decision | Options | Trade-off summary | Engineer to choose |
|----------|---------|-------------------|---------------------|
| 1. Attendees acquisition | A: N+1 calls in list_meetings / B: empty attendees, fix downstream / C: new Protocol method | A works within current contract; B breaks classification; C is scope expansion | □ |
| 2. Pagination | A: eager list (mirrors fathom.py) / B: generator | A matches Protocol return type; B requires Protocol change | □ |
| 3. Granola summary in prompt | A: append after transcript / B: insert before transcript / C: pre-concatenate in get_transcript | A/B require format_prompt change; C contaminates transcript file on disk | □ |
| 4. Not-yet-ready transcripts | A: return None, count as failed / B: return None with log.info / C: new SourceNotReady exception | A/B require no sync.py change; C distinguishes pending from failed but touches two files | □ |
| 5. Error handling shape | A: mirror FathomSource._request / B: simplified | A carries the retry coverage from fathom.py:60-82; B drops it | □ |
| 6. Constructor config keys | A: mirror FathomSource (base_url, api_key_env, api_key, retries) / B: add page_size | A matches the existing sibling constructor; B adds page_size which is not in Granola API docs | □ |
| 7. Backward-compat | A: hard break (remove cache code) / B: deprecated fallback | A removes all cache code; B retains a fallback that silently returns zero meetings on current Granola | □ |

---

## Risks (cross-cutting)

| Risk | Impact | Possible mitigation |
|------|--------|---------------------|
| `summary_markdown` absent from API response for some notes | Prompt injection fails silently or raises KeyError | Guard with `.get("summary_markdown") or ""` before injection; treat empty summary as "no draft available" |
| Transcript empty for a just-ended meeting | Meeting counted as failed each run until transcript populates | See Decision 4 options |
| Rate limit exceeded for large windows (`since_days=30`) | Requests aborted mid-pagination | Exponential backoff (Decision 5 Option A); 30-day window at 10/day = 300 notes = 300 detail calls if N+1 chosen; approaches but does not exceed 300/min burst limit |
| `GRANOLA_API_KEY` not set | `SourceAuthError` on first run | Clear error message in `SourceAuthError`; README update required |
| `start_time` vs `start_timestamp` key rename in `_join_segments` | Silent empty transcript (no timestamps, just text) if wrong key | Confirmed by live probe: new key is `start_time`; fix is a one-line change |
| `calendar_event` absent on a note (no calendar invite) | `KeyError` if attendees are read from `calendar_event.invitees` | Read from `attendees` key (top-level in detail response), not `calendar_event.invitees` — live probe confirms `attendees` is the richer source |

---

## Open questions for the engineer

1. **Decision 1 (attendees):** Option A (N+1 calls) requires no `sync.py` or Protocol change; Options B and C do. Which trade-off do you accept?

2. **Decision 3 (hybrid prompt):** Option C (delimited string returned by `get_transcript`) avoids a Protocol or `sync.py` change; the written transcript file on disk will then contain the Granola draft header. Options A and B require a `format_prompt` change. Which trade-off do you accept?

3. **Decision 4 (not-ready transcripts):** Should not-ready transcripts be silently skipped (Option A/B, no sync.py change) or distinguished from errors via a new exception (Option C)?

4. **Tests:** There are no tests for `GranolaSource` today. The project has a clear test pattern (monkeypatching `requests` via stub classes, not `responses` library — see `test_sync_dry_run.py`). Should new tests be added as part of this migration, or deferred?

5. **Version bump:** The current version in `meeting_hive/__init__.py` is `1.1.4`. What should the new version be (patch: `1.1.5` for a bug-fix migration, minor: `1.2.0` for new feature of hybrid summarization)?

---

## Execution order (once decisions are made)

The changes have minimal internal dependencies. The natural order:

1. **`granola.py` — constructor and auth** (delete cache keys, add `base_url`/`api_key_env`/`api_key`/`retries`, implement `_headers`)
2. **`granola.py` — `_request`** (replace `_api_post`)
3. **`granola.py` — `list_meetings`** (re-implement with pagination; attendees per Decision 1)
4. **`granola.py` — `get_transcript`** (re-implement with detail endpoint; summary integration per Decision 3)
5. **`granola.py` — `_join_segments`** (key rename: `start_timestamp` → `start_time`)
6. **`summarizers/__init__.py`** (prompt update per Decision 3, if Options A or B)
7. **`secrets.env`** (add `GRANOLA_API_KEY=`)
8. **`meeting_hive/__init__.py`** (version bump)
9. **`CHANGELOG.md`**, **`README.md`** (update)
10. **Tests** (new `tests/test_granola_source.py` per test question above)

Steps 1–5 are sequential within `granola.py` (each builds on the previous). Step 6 is independent of steps 1–5 and can be done in parallel. Steps 7–10 are independent of everything above.

---

## Sources

- `~/Projects/OSS/meeting-hive/meeting_hive/sources/granola.py:1-194` — current adapter, dead code paths identified
- `~/Projects/OSS/meeting-hive/meeting_hive/sources/fathom.py:1-175` — sibling adapter (Mother Rule reference)
- `~/Projects/OSS/meeting-hive/meeting_hive/sources/__init__.py:1-77` — Protocol definition, Meeting dataclass, exception hierarchy
- `~/Projects/OSS/meeting-hive/meeting_hive/sources/markdown.py:1-189` — third sibling adapter
- `~/Projects/OSS/meeting-hive/meeting_hive/sync.py:135-175` — attendee/transcript/classify consumption in the pipeline
- `~/Projects/OSS/meeting-hive/meeting_hive/summarizers/__init__.py:12-102` — PROMPT_TEMPLATE and `format_prompt`
- `~/Projects/OSS/meeting-hive/meeting_hive/summarizers/anthropic.py:52-72` — how `format_prompt` is called
- `~/Projects/OSS/meeting-hive/meeting_hive/__init__.py` — current version `1.1.4`
- `~/Projects/OSS/meeting-hive/pyproject.toml:25-31` — dependencies; `requests>=2.31.0` confirmed present
- `~/Projects/OSS/meeting-hive/tests/test_sync_dry_run.py` — established test pattern (stub classes + monkeypatch)
- `~/.claude/plans/active/spike/granola-format-migration/SPIKE.md` — canonical prior research (API choice, rate limits, auth scheme)
- `/tmp/granola_notes_20260520_v3.json` — live probe: `GET /v1/notes` response shape
- `/tmp/granola_note_detail_20260520.json` — live probe: `GET /v1/notes/{id}?include=transcript` response shape
- See auxiliary files:
  - `adapter_siblings_excerpt_1.txt` — verbatim excerpts from fathom.py, __init__.py, markdown.py
  - `prompt_excerpt_1.txt` — PROMPT_TEMPLATE verbatim + call chain
  - `api_response_samples_1.txt` — annotated API response samples + field mapping table
