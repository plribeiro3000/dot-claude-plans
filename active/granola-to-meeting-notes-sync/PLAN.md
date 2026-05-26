# PLAN — Granola → ~/.meeting-notes/ nightly sync

## Current Situation

- **Canonical archive**: `~/.meeting-notes/{4shark,personal}/{year}/{date}-{slug}-{resumo,transcript}.md` — 378+ meetings migrated from Spark, corrected and classified by frontmatter.
- **Granola**: active post-migration source. Granola's transcript and summary have speech-to-text errors (4Shark → "Four Shark", Almaviva → "Alma Viva", etc.).
- **Granola is read-only**: no official API/MCP to write transcripts or folders. Corrections have to happen outside Granola.
- **Wispr Flow**: local macOS app with a corrections dictionary stored in SQLite (`~/Library/Application Support/Wispr Flow/flow.sqlite`, table `Dictionary`). It currently has 48 relevant `phrase → replacement` entries (e.g., `foreshark → 4Shark`).
- **Skill `/meeting-context`**: already deployed, searches ONLY in `~/.meeting-notes/`. It depends on the sync to keep coverage up to date.
- **Folder structure in Granola**: visual/organizational classification, manual via UI. Recurring meetings inherit the folder automatically.

## Objective / Target State

- **Desired outcome**: meetings recorded on Granola during the day show up the next morning in `~/.meeting-notes/4shark/YYYY/` already with:
  - Transcript with Wispr corrections applied
  - Summary regenerated (Sonnet) from the corrected transcript
  - Classified frontmatter (`client:`/`vendor:`/`internal:`/etc.) based on heuristics + LLM fallback
  - Invitees extracted from Granola
- **macOS notification** at the end: "N meetings synced (X ok, Y with error)".
- **Success criteria**:
  - Script runs 04:00 Mon-Fri via launchd with no intervention
  - At least 95% of the previous day's meetings become file pairs in `~/.meeting-notes/` automatically
  - Meetings that fail automatic classification are surfaced in the notification for manual review
  - Wispr is the single source of truth for the vocabulary (edited in Wispr, the script reads from SQLite)
  - The `/meeting-context` skill can answer about a meeting from the previous day without a workaround

## Problem / New Feature

- **Objective description**: build nightly automation that consolidates Granola + Wispr vocabulary into a pipeline: extract → correct → re-summarize → classify → write → notify.
- **Dependencies**:
  - Granola macOS app installed (running in background, cache up to date)
  - Wispr Flow running or with the vocabulary edited (the SQLite can be read even with the app open via `PRAGMA busy_timeout`)
  - Anthropic API key (for Sonnet) — from 1Password

## Challenges, Difficulties and Risks

- **Technical**:
  - **Granola access**: the official MCP is for interactive agent invocation, not scripts. Alternatives: (a) read the local cache `~/Library/Application Support/Granola/cache-v3.json`, (b) use the REST API `api.granola.ai` with a token extracted from the cache, (c) adapt a community Python MCP.
  - **Granola cache format may change**: community implementations already handle v3 and v4. The script needs fallback or version-aware parsing.
  - **SQLite lock** on Wispr: if Wispr is writing, the read may block. Copying the SQLite to /tmp before reading mitigates it.
  - **Classification fidelity**: invitee domain matching (e.g., `@atento.com` → `client: Atento`) covers the easy path. Internal/ambiguous meetings will need LLM or manual review.
  - **Rate limit**: Sonnet has limits. On days with many meetings (10+), serialize calls with a small delay.
- **Product/UX**:
  - If the script fails silently, I only find out when I search and miss data — an error notification is critical
  - Duplicates: if the script runs twice on the same day, it must not duplicate files. Idempotency via existence check of `{date}-{slug}-resumo.md`
- **Security/privacy**:
  - The Granola token (WorkOS access_token) lives in the local cache — the script can extract it, but it must not be logged to /tmp/logs
  - The Anthropic API key must come from 1Password via `op read`, not hardcoded
- **Performance**:
  - The script must finish in <5 min even with 20 meetings. Sonnet regen is the bottleneck (~15s per meeting) — parallelize or serialize with a budget.

## Solution Options (comparative)

- **Option 1 — Python script + REST API + launchd**
  - **How it works**: Python 3 script. Reads the Wispr SQLite. Reads the Granola cache to get token + meeting IDs → calls the REST API `api.granola.ai` for metadata and transcript. Applies regex replacement from Wispr. Calls the Anthropic SDK (Sonnet) to regenerate the summary. Classifies via rules + LLM fallback. Writes markdown with frontmatter in `~/.meeting-notes/`. Notifies via `osascript -e 'display notification...'`. Schedules via a launchd plist in `~/Library/LaunchAgents/`.
  - **Pros**: full control; Python is readable and testable; launchd is the macOS-native way; the REST API is more stable than parsing the cache
  - **Cons**: token extraction from the cache is a documented but unofficial hack; if Granola revokes the token, the script breaks
  - **When NOT to use**: if Granola ever publishes an official write API (it would replace the architecture)

- **Option 2 — Shell script + jq + cache-only**
  - **How it works**: bash + jq read `cache-v3.json` directly. Sed/awk apply the corrections. curl + the Anthropic API for regen. Same write + notification.
  - **Pros**: zero Python dependencies; faster to set up
  - **Cons**: complex logic in shell is hell; parsing `cache-v3.json` (JSON nested inside a string) is painful in jq; summary regen and LLM classification become awkward; testability is zero
  - **When NOT to use**: when the script will be maintained longer than 2 months (which is the case here)

- **Option 3 — Python MCP client with the official SDK**
  - **How it works**: use Anthropic's `mcp` Python lib to connect to the Granola MCP, using the same tools Claude uses. Apply corrections, regen, write, notify.
  - **Pros**: uses an official API (no cache hacking); more resilient to Granola changes
  - **Cons**: the official Granola MCP is remote HTTP; authentication is via browser (OAuth); running headless under launchd may be problematic
  - **When NOT to use**: if OAuth auth does not work without interaction

## Proposed Steps (high level, don't execute yet)

1. **Setup scripts directory**:
   - `~/Projects/4Shark/.claude/scripts/` already exists. Put the personal script outside the team repo (in `~/bin/sync-granola-to-notes.py` or similar), since this is personal tooling.
   - Or, if consolidation is preferred, place it in the team repo as a skill/command with a conditional pre-check (other devs without Granola/Wispr do not activate it).

2. **Python script** (`~/bin/sync-granola-to-notes.py`):
   - Deps: `sqlite3` (stdlib), `requests` or `httpx`, the `anthropic` SDK, `pyyaml`
   - Modules:
     - `wispr.py` — reads the SQLite, returns a `{phrase: replacement}` dict
     - `granola.py` — Granola access (REST or cache), returns a list of meetings with transcripts
     - `corrector.py` — applies the Wispr dict as case-sensitive word-boundary regex
     - `summarizer.py` — calls Sonnet via the Anthropic SDK, regenerates the summary in a structure equivalent to the Spark format
     - `classifier.py` — rules engine (domain → entity map) + LLM fallback
     - `writer.py` — writes `{date}-{slug}-resumo.md` and `{date}-{slug}-transcript.md` following the migration template
     - `notify.py` — osascript display notification + a log file at `~/Library/Logs/granola-sync.log`
     - `sync.py` — orchestrator, idempotent (skips if the file already exists)

3. **Classification rules** (hardcoded + dynamic):
   - First pass: domain-based rules (`@atento.com` → `client: Atento`, `@4shark.com.br` only → `internal: alignment`, etc.). Take the conventions from the archived SPIKE.
   - Second pass (fallback): if no rule matched, call Sonnet passing title + invitees + the list of known entities → returns the classification
   - Third: if the LLM returns "unknown", write with `tags: [UNCLASSIFIED]` and surface it in the notification

4. **Idempotency and retry**:
   - Before writing, check whether `{date}-{slug}-resumo.md` already exists — skip
   - If Sonnet fails, 3 retries with exponential backoff
   - If the Granola API fails, abort that meeting and continue with the next; report in the notification

5. **launchd plist**:
   - `~/Library/LaunchAgents/com.plribeiro3000.granola-sync.plist`
   - `StartCalendarInterval`: 04:00, weekday 1-5 (Mon-Fri)
   - `Program`: the script path
   - `StandardOutPath` + `StandardErrorPath`: `~/Library/Logs/granola-sync-{out,err}.log`
   - `RunAtLoad: false` (do not run on initial load)

6. **macOS notification**:
   - Success: "✅ Granola sync: N meetings (all ok)" — silent click
   - With unclassified: "⚠️ Granola sync: N meetings (X need review)" — lists the unclassified titles
   - Total failure: "❌ Granola sync failed — see /tmp/granola-sync-*.log"
   - Use `osascript -e 'display notification ... with title ... sound name "Glass"'`

7. **Anthropic API key**:
   - `op read "op://Private/Anthropic API/credential"` (or the correct 1Password path)
   - The script does this read at the start and fails early if there is no MFA session in op

8. **Testing**:
   - Dry-run flag (`--dry-run`) that does not write files, only logs what it would do
   - Manual verbose run for the first time (today: sync 16-17/Apr)

9. **Documentation**:
   - Create `~/.meeting-notes/.README.md` with a link to the script + troubleshooting
   - Entry in the global CLAUDE.md explaining the flow (optional — this is the kind of thing only I use)

## Internal References

- Wispr SQLite: `~/Library/Application Support/Wispr Flow/flow.sqlite`, table `Dictionary`
- Granola cache: `~/Library/Application Support/Granola/cache-v3.json`
- Granola REST: `https://api.granola.ai/v1/get-documents`, `get-document-transcript/:id`
- Archived SPIKE: `~/.claude/plans/completed/spike/spark-to-granola-migration/SPIKE.md` — has canonical entity names, classification schema, naming conventions
- meeting-context skill: `~/.claude/commands/meeting-context.md`
- launchd format: https://www.launchd.info/ (reference for the plist)

---

## Decisions (approved 2026-04-17)

- **Option 1** — Python + REST API `api.granola.ai` + launchd
- **Script location**: `~/bin/sync-granola-to-notes.py` (personal, outside the repo)
- **Classification on miss = skip + notify**: if no rule matches a meeting, **do NOT write the file**. Notify the user with a list of the pending meetings. The user adds the new rule; the next run reprocesses it.
- **7-day lookback window**: the script always scans the last 7 days of Granola, not only the previous day. It skips idempotently whatever already exists in `~/.meeting-notes/`. That gives a 1-week window to handle new entities.
- **Granola folders**: not the script's responsibility. Decoupled.
- **Schedule**: Mon-Fri 04:00 via launchd. Monday covers Fri/Sat/Sun within the 7-day lookback.
