# NEXT TASKS — Granola to Meeting Notes Sync — Option 1 (Python + REST + launchd)

> **Objective of this iteration:** Build a nightly script that pulls Granola meetings from the last 7 days, applies Wispr vocabulary corrections, regenerates summaries via Sonnet, classifies meetings, writes them to `~/.meeting-notes/`, and notifies via macOS notification.
> **Reference:** derived from `PLAN.md` (all sections), decisions approved 2026-04-17.

---

## 0) Pre-conditions

- [x] `PLAN.md` approved (Option 1)
- [ ] Anthropic API key discoverable (1Password path confirmed by user)
- [ ] Granola desktop app running with cache populated at `~/Library/Application Support/Granola/cache-v3.json`
- [ ] Wispr Flow SQLite readable at `~/Library/Application Support/Wispr Flow/flow.sqlite`
- **Base branch:** n/a (personal tooling in `~/bin/`)
- **Working branch:** n/a

---

## 1) Step by Step (atomic tasks)

### Task 1 — Directory + entrypoint skeleton

- **Objective:** set up `~/bin/granola-sync/` as a Python package with a thin CLI entrypoint and a `config.yaml` for user-editable rules.
- **Actions:**
  - [ ] `mkdir -p ~/bin/granola-sync/{granola_sync,tests}`
  - [ ] Create `~/bin/granola-sync/pyproject.toml` with deps: `anthropic`, `requests`, `pyyaml`, `python-dateutil`
  - [ ] Create `~/bin/granola-sync/granola_sync/__init__.py` (empty)
  - [ ] Create `~/bin/granola-sync/granola_sync/__main__.py` with argparse: `--dry-run`, `--since DAYS` (default 7), `--verbose`
  - [ ] Create `~/bin/granola-sync/config.yaml` with default skeleton (see Task 5 for shape)
  - [ ] Create `~/bin/sync-granola-to-notes` (shebang wrapper) that invokes `python3 -m granola_sync "$@"` from the package dir
  - [ ] Make wrapper executable: `chmod +x ~/bin/sync-granola-to-notes`
- **Affected files/areas:** `~/bin/granola-sync/`, `~/bin/sync-granola-to-notes`
- **Completion criteria:** `~/bin/sync-granola-to-notes --help` prints usage without errors

### Task 2 — Wispr dictionary reader

- **Objective:** read the Wispr SQLite dictionary and return a `{phrase: replacement}` dict of word-level replacements (no snippets).
- **Actions:**
  - [ ] Create `granola_sync/wispr.py` with `load_vocabulary(db_path)` function
  - [ ] Copy the SQLite file to `/tmp/` before opening to avoid lock contention with the running Wispr app
  - [ ] Query: `SELECT phrase, replacement FROM Dictionary WHERE isDeleted=0 AND replacement IS NOT NULL AND replacement != '' AND isSnippet=0`
  - [ ] Return dict; log count of entries loaded
- **Affected files/areas:** `~/bin/granola-sync/granola_sync/wispr.py`
- **Completion criteria:** running `python3 -c "from granola_sync.wispr import load_vocabulary; print(len(load_vocabulary('~/Library/Application Support/Wispr Flow/flow.sqlite')))"` prints a positive integer

### Task 3 — Granola REST client

- **Objective:** authenticate with Granola's REST API using the token from the local cache, and implement `list_meetings(since)` + `get_transcript(meeting_id)`.
- **Actions:**
  - [ ] Create `granola_sync/granola.py`
  - [ ] Implement `_read_token()` — reads `~/Library/Application Support/Granola/cache-v3.json`, parses the double-JSON structure, returns `access_token`
  - [ ] Implement `list_meetings(since_days)` using `GET https://api.granola.ai/v1/get-documents` with `Authorization: Bearer <token>`; filter by `created_at >= now - since_days`
  - [ ] Implement `get_transcript(meeting_id)` using `GET /v1/get-document-transcript/<id>`; return raw transcript text + speaker timings if available
  - [ ] Implement `get_metadata(meeting_id)` returning `{title, date, time, duration, attendees (emails)}`
  - [ ] Handle 401 (expired token) — emit clear error message pointing user to re-login in Granola desktop
  - [ ] Handle 429 (rate limit) — exponential backoff, max 3 retries
- **Affected files/areas:** `granola_sync/granola.py`
- **Completion criteria:** `python3 -m granola_sync --since 1 --dry-run --verbose` prints a list of yesterday's meeting titles from Granola

### Task 4 — Corrector

- **Objective:** apply Wispr vocabulary as case-sensitive whole-word replacements to transcript text.
- **Actions:**
  - [ ] Create `granola_sync/corrector.py`
  - [ ] Implement `apply_vocabulary(text, vocab)` using regex with word boundaries: `r'\b{re.escape(phrase)}\b'` for each phrase, replaced with the mapped replacement
  - [ ] Sort phrases by length DESC before applying (longer matches first, so "Force Shark" beats "Shark")
  - [ ] Preserve original casing rules: replacements are literal (Wispr dictionary already has canonical casing)
  - [ ] Return corrected text + count of replacements per phrase for logging
- **Affected files/areas:** `granola_sync/corrector.py`
- **Completion criteria:** unit test with sample input "Force Shark is a Forchart company" and vocab `{"Force Shark": "4Shark", "Forchart": "4Shark"}` returns "4Shark is a 4Shark company"

### Task 5 — Classifier (rules-based only, no LLM fallback)

- **Objective:** classify a meeting based on invitee emails and title using a YAML rules file. If no rule matches, return `None` (caller will skip the meeting and notify user).
- **Actions:**
  - [ ] Create `granola_sync/classifier.py`
  - [ ] Define `config.yaml` schema:
    ```yaml
    domain_rules:
      atento.com: { type: client, entity: Atento }
      atento.com.br: { type: client, entity: Atento }
      commcenter.com.br: { type: client, entity: Commcenter }
      grupoluizhohl.com.br: { type: client, entity: Grupo Luiz Hohl }
      ecomenergia.com.br: { type: client, entity: Ecom Energia }
      # ... (populated from SPIKE.md canonical list)
    title_patterns:
      - match: "(?i)founders friday"
        type: internal
        entity: founders
      - match: "(?i)daily meeting.*4shark"
        type: client
        entity: Grupo Luiz Hohl
      - match: "(?i)alignment"
        type: internal
        entity: alignment
    internal_only:
      # meetings where ALL attendees are @4shark → internal, subtype based on title
      default_subtype: alignment
    ```
  - [ ] Populate `domain_rules` from `~/.claude/plans/completed/spike/spark-to-granola-migration/SPIKE.md` (canonical entities with confirmed domains ONLY — no assumed/guessed domains)
  - [ ] Populate `title_patterns` for entities without known domain (Almaviva, Positivo, Tahto, Self Telecom, BanaTech, Hiperbanco, Cielo, etc.) so name-in-title triggers classification
  - [ ] Populate `email_rules` for gmail-based contacts (brunap.magna@gmail.com, contatomacsynie@gmail.com, zingfuel@gmail.com)
  - [ ] Implement `classify(metadata)`:
    1. Check `title_patterns` first (most specific)
    2. If all attendees are `@4shark.com` → internal (subtype needs title heuristic or default)
    3. Otherwise, find first attendee whose domain matches `domain_rules` → return that entity
    4. If nothing matches → return `None`
- **Affected files/areas:** `granola_sync/classifier.py`, `~/bin/granola-sync/config.yaml`
- **Completion criteria:** given a test meeting with `@atento.com` attendees, returns `{type: client, entity: Atento}`. Given a meeting with only `@newclient.xyz` attendees, returns `None`.

### Task 6 — Summarizer (Sonnet)

- **Objective:** regenerate a Portuguese AI summary from the corrected transcript using Claude Sonnet, matching the structure of the Spark-era summaries.
- **Actions:**
  - [ ] Create `granola_sync/summarizer.py`
  - [ ] Load Anthropic API key from `op read "op://<vault>/<item>/credential"` (exact path TBD in Pre-conditions)
  - [ ] Implement `summarize(transcript, title, attendees)` calling `claude-sonnet-4-6` with a prompt that:
    - Generates a concise opening paragraph (1 sentence)
    - Emits "Key Points" section with bullet groups like the Spark format (see example in any `-resumo.md`)
    - Optionally "Action Items" if any are clearly stated
    - Responds in Portuguese (pt-BR)
  - [ ] Retry logic: 3 attempts with exponential backoff on 429/500
- **Affected files/areas:** `granola_sync/summarizer.py`
- **Completion criteria:** given a sample transcript, returns a Markdown-formatted summary string matching the Spark-era shape

### Task 7 — Writer

- **Objective:** produce paired markdown files (`-resumo.md`, `-transcript.md`) with correct frontmatter, respecting idempotency.
- **Actions:**
  - [ ] Create `granola_sync/writer.py`
  - [ ] Slug generator: kebab-case from title, max 60 chars
  - [ ] Write path: `~/.meeting-notes/4shark/YYYY/{date}-{slug}-{resumo,transcript}.md`
  - [ ] Frontmatter schema (match existing archive):
    ```yaml
    date: YYYY-MM-DD
    time: "HH:MM-HH:MM GMT-03:00"
    title: <title>
    <type>: <entity>    # client: Atento  OR  internal: founders  etc.
    invitees:
      - email1@domain
      - email2@domain
    source: granola
    summary_type: ai     # only in -resumo.md
    type: meeting-summary   # or meeting-transcript
    related: <paired filename>
    ```
  - [ ] Idempotency: if `-resumo.md` OR `-transcript.md` exists for that slug, skip the whole meeting
  - [ ] Create year dir if missing
- **Affected files/areas:** `granola_sync/writer.py`
- **Completion criteria:** given mock metadata + transcript + summary, produces two well-formed files that pass frontmatter grep (same format as existing archive)

### Task 8 — Orchestrator + notifier

- **Objective:** wire up the pipeline end-to-end and emit a macOS notification with the outcome.
- **Actions:**
  - [ ] Create `granola_sync/sync.py` — `run(since_days=7, dry_run=False)`
  - [ ] Pipeline per meeting:
    1. Check idempotency → skip if file exists
    2. Fetch metadata + transcript
    3. Classify → if `None`, add to `pending` list, skip
    4. Apply Wispr corrections to transcript
    5. Regenerate summary (Sonnet)
    6. Apply Wispr corrections to summary (for consistency — Sonnet may have echoed back original names)
    7. Write files
    8. Mark as `done`
  - [ ] Output stats: `{processed: N, skipped: M, pending_classification: K, failed: J}`
  - [ ] `granola_sync/notify.py` — invoke `osascript -e 'display notification "..." with title "Granola Sync" sound name "Glass"'`
  - [ ] Notification content:
    - All ok → `✅ N reuniões sincronizadas`
    - Pending → `⚠️ N ok, K precisam classificação: <titles>`
    - Config broken → `❌ config.yaml inválido (linha N). Fix antes do próximo run.`
    - Runtime failure → `❌ Granola sync falhou: <reason>`
  - [ ] Validate `config.yaml` on load — if YAML parse fails, emit `Config broken` notification and abort
  - [ ] For each UNCLASSIFIED meeting, log full YAML snippet that would classify it, so user can copy/paste:
    ```
    UNCLASSIFIED: "<title>" (<date>)
      invitees: <email1>, <email2>, ...
      Suggested rule (add to ~/bin/granola-sync/config.yaml):
        domain_rules:
          <domain_extracted>: { type: ???, entity: "???" }
    ```
  - [ ] Log full run to `~/Library/Logs/granola-sync.log` (append, rotate by month)
- **Affected files/areas:** `granola_sync/sync.py`, `granola_sync/notify.py`
- **Completion criteria:** `python3 -m granola_sync --since 1` runs end-to-end, writes at least 1 pair of files (or reports pending), fires a notification

### Task 9 — launchd agent

- **Objective:** schedule the script seg-sex 04:00 via user-level launchd.
- **Actions:**
  - [ ] Create `~/Library/LaunchAgents/com.plribeiro3000.granola-sync.plist` with:
    - `Label`: `com.plribeiro3000.granola-sync`
    - `Program`: `/Users/plribeiro3000/bin/sync-granola-to-notes`
    - `StartCalendarInterval`: array of 5 entries (Weekday 1-5, Hour 4, Minute 0)
    - `StandardOutPath`: `~/Library/Logs/granola-sync.out.log`
    - `StandardErrorPath`: `~/Library/Logs/granola-sync.err.log`
    - `RunAtLoad`: false
  - [ ] Load: `launchctl load ~/Library/LaunchAgents/com.plribeiro3000.granola-sync.plist`
  - [ ] Validate: `launchctl list | grep granola`
- **Affected files/areas:** `~/Library/LaunchAgents/com.plribeiro3000.granola-sync.plist`
- **Completion criteria:** `launchctl print gui/$(id -u)/com.plribeiro3000.granola-sync` shows next scheduled fire

### Task 10 — Dry-run backfill test

- **Objective:** run the script once in dry-run mode over the last 7 days to verify classification rules cover all recent meetings.
- **Actions:**
  - [ ] `~/bin/sync-granola-to-notes --since 7 --dry-run --verbose`
  - [ ] Review output: any pending classifications → add rules to `config.yaml`
  - [ ] Re-run until pending list is empty (or user accepts remaining as truly novel)
- **Completion criteria:** dry-run pending count is zero OR user explicitly accepts the remaining as cases to define later
- **[HOLD POINT]** Share dry-run output with user before first real write

### Task 11 — First real run (manual)

- **Objective:** execute the script for real once, covering last 7 days, to validate end-to-end behavior.
- **Actions:**
  - [ ] `~/bin/sync-granola-to-notes --since 7`
  - [ ] Verify files in `~/.meeting-notes/4shark/2026/`
  - [ ] Inspect 2-3 random pairs for correctness of frontmatter, slug, corrected transcript, regenerated summary
  - [ ] Confirm macOS notification appeared
- **Completion criteria:** files written, notification seen, user approves quality of outputs

---

## 2) Items Requiring User Confirmation

- [ ] **Anthropic API key 1Password path**: what's the exact `op read` path? (e.g. `op://Private/Anthropic/credential`)
- [ ] **Population of `config.yaml`**: should I extract all canonical entities from `SPIKE.md` automatically, or want to review the list first?
- [ ] **Summary prompt tone**: match Spark-era summaries literally (opening + Key Points + Action Items), or want a different structure?
- [ ] **Python runtime**: use system Python 3 (macOS `/usr/bin/python3`) or a pyenv/uv-managed interpreter?

> **Expected response (example):**
> `APPROVED: 1Pwd path op://Private/Anthropic/credential; extract from SPIKE automatically; Spark-era format; system python3.`

---

## 3) Pending Items After This Iteration

- [ ] Observability: error rate over time — later could add metrics export
- [ ] Monthly log rotation for `~/Library/Logs/granola-sync*.log`
- [ ] If Granola token expires more often than expected, consider OAuth refresh automation
- [ ] Update `~/.claude/plans/completed/spike/spark-to-granola-migration/SPIKE.md` with a note about the sync script existing (so future-you remembers the architecture)
