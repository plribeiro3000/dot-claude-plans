---
name: spark-to-granola-migration
description: Migration of email/calendar/notes client from Spark (Readdle) to Apple Mail + Apple Calendar + Granola, including the archival strategy for historical meeting notes
type: spike
---

# SPIKE — Spark → Apple Mail/Calendar + Granola migration

**Conducted by:** Paulo Ribeiro
**Date:** 2026-04-15
**Status:** Research complete — execution in progress (manual migration of historical notes is ongoing)

---

## Goal

Resolve frustration with Spark Desktop and define an alternative setup that covers:
1. Email client (personal use + 4Shark Google Workspace account)
2. Calendar (personal + 4Shark)
3. Meeting notes with **local** recording (no bot joining the call, invisible to participants) tied to calendar events — **this is the must-have**

Spark problems that motivated the change:
- Google Workspace calendar sync stuck — new events do not appear even after closing/reopening the app; there is no manual refresh button
- Bad email client (broken formatting)
- Useful feature in Spark today: only the meeting notes + AI search

Cost constraint: up to ~2× the price of Spark Premium (~$20/month); not acceptable to reach $500.

---

## Method

- Web research on known Spark sync problems (confirmed: long-standing complaint, no fix from Readdle)
- Comparison of alternatives: Superhuman, Shortwave, Granola
- Reading Granola's official documentation (pricing, Slack/MCP integrations, calendar sync)
- Evaluation of meeting-notes history migration scenarios

---

## Evidence

### About the Spark problem

- Google Workspace sync on Spark Desktop is a recurring complaint documented on MacPowerUsers, with no official Readdle fix.
- Spark **has no** force-refresh button — the official doc does not mention manual refresh.
- Only effective "reset": remove and re-add the account (forces re-OAuth + initial sync).

### Alternatives evaluated

| Tool | Email | Calendar | Local notes without bot | Price | Verdict |
|---|---|---|---|---|---|
| Superhuman | ✅ | ✅ | ❌ (only via Fireflies — bot) | $30/mo | Rejected — loses the must-have |
| Shortwave | ✅ (Gmail only) | ✅ basic | ❌ | $9/mo | Rejected for the same reason |
| **Granola** | ❌ | ❌ (read-only) | ✅ | $14/mo (Business) | **Chosen** |
| Apple Mail + Calendar | ✅ | ✅ | ❌ | Free | Chosen for email/calendar |

**No single tool delivers the 3 things (email + calendar + local notes) in one app today** — Spark is unique on that, but bad at sync.

### Granola — confirmed operational details

- **Captures system audio locally** (macOS). No bot joins the call; participants do not know.
- **Recording is always manual**: Granola shows a warning ~1 min before the event and you click to start. If you do not click, it does not record. There is no risk of back-to-back meetings being merged.
- **Calendar sync**: only reads from the provider used at sign-in. The user signed in with `paulo@4shark.com.br` (Workspace).
- **Multi-account Google**: Granola **does not** support adding multiple accounts. Official workaround: share the personal calendar with the main account via Google Calendar ("See all event details" permission) and enable it in Settings > Calendar.
- **Slack integration**:
  - Manual mode: click the Slack button on each note, pick the channel
  - Auto mode per folder: Granola folders mapped to Slack channels
  - Requires Google Workspace or Microsoft 365 (does not work with personal Gmail) — OK for this user
- **Official MCP**: available only on the Enterprise plan (beta). The Business plan does not have access to the official MCP — community MCPs on GitHub work with any plan.
- **Chosen plan**: Business ($14/mo), but the user is testing on **free tier** first.

### Migrating the historical Spark meeting notes

- Spark **has no** bulk meeting notes export. No public API, no community tool for automation.
- Official options: copy/paste per note (manual) or individual "Save as PDF".
- Granola **does not import** historical notes — even exported, they become dead files in another app (the calendar events that produced the notes are already in the past; there is no way to attach them to Granola retroactively).
- **Decision**: archive the history as local markdown in a hidden folder. Granola starts from now on.

---

## Conclusions

### Stack defined

| Function | Tool | Cost |
|---|---|---|
| Email | Apple Mail (or Spark Free as fallback) | $0 |
| Calendar | Apple Calendar | $0 |
| Meeting notes | **Granola** (free tier first; Business later) | $0 → $14/mo |
| Notes history | Local markdown in `~/.meeting-notes/` | $0 |

### Meeting notes archival structure

**Location**: `~/.meeting-notes/` (hidden folder with `.` prefix, hidden from Finder and Spotlight by default — privacy goal)

**Hierarchy**:
```
~/.meeting-notes/
├── 2024/
├── 2025/
│   ├── 2025-04-29-aster-ponto-controle-integracao-resumo.md
│   └── 2025-04-29-aster-ponto-controle-integracao-transcript.md
└── 2026/
```

- Folder per **year only** (month/day would be overkill — would create orphan folders with 1 file)
- Date in the filename in ISO format (`YYYY-MM-DD`) for chronological sorting
- **One separate file for the summary and another for the transcript** (user decision) — connected via the `related` field in the frontmatter

**File template**:

```markdown
---
date: YYYY-MM-DD
time: HH:MM-HH:MM GMT-03:00
title: [exact title of the calendar event]
client: [client name]
invitees:
  - Name (company)
source: spark  # or granola when produced by the new tool
summary_type: ai  # or manual — optional, only on the summary file. ai = generated by the tool, manual = short user note
type: meeting-summary  # or meeting-transcript
related: [sibling file name]
---

# [title] — Summary/Transcript

[content]
```

**Why this structure**:
- Frontmatter enables metadata search (date, client, attendees)
- Pure markdown is universal — works on Obsidian/VS Code/TextEdit
- Summary/Decisions/Transcript sections allow precise search without scanning the noisy transcript
- Hidden folder: anyone casually opening the machine does not see the history

### Slack integration usage (when reaching Business)

- **Default**: manual mode (confidential meeting = do not share)
- **Exception**: auto folders only for recurring meetings with fixed teams (weekly 1:1s, dailies)

---

## Next Steps

### Done
- [x] Stack decision (Apple Mail/Calendar + Granola)
- [x] Granola installed, signed in with 4Shark account
- [x] Archival structure defined
- [x] `~/.meeting-notes/` folder created with hierarchy `{scope}/{year}/`
- [x] First file pair migrated: Áster/4Shark meeting from 2025-04-29 (summary + transcript)
- [x] Áster 2025-04-29 event invitees verified via Google Calendar MCP and frontmatter corrected (field renamed from `participants` to `invitees` — the transcript cannot tell who effectively attended, only who was invited)
- [x] **60 meetings migrated** (2025-04-29 to 2025-06-20) — 120 files (-resumo.md + -transcript.md)
- [x] Structure reorganized: `~/.meeting-notes/{scope}/{year}/` where scope = `4shark` or `personal`
- [x] Invitees filled in for all 60 meetings via Google Calendar MCP
  - 27 meetings had invitees filled via Calendar search (session 2026-04-16)
  - 2 kept with empty invitees by design (Adam interview, Suelen WhatsApp — no Calendar event)
  - 1 kept with empty invitees (Salesforce 06-18 — solo event without invitees)
- [x] `client` field correction in 2 meetings: "4Shark" → "Grupo Luiz Hohl" (Suelen WhatsApp 06-09, Status Report Comissionamento 06-17)
- [x] Automation scripts created in `~/spark_extract.sh` (Chrome + AppleScript) + `~/spark_write.py` (generates the .md files)
- [x] **Session 2026-04-16 — +16 meetings migrated** (2025-06-23 to 2025-06-30) — total reaches 76 meetings / 153 files (145 in 4shark/2025, 8 in personal/2025)
- [x] **Session 2026-04-16 continuation — +24 meetings migrated** (2025-07-01 to 2025-07-18) — total reaches 100 meetings / 201 files (193 in 4shark/2025, 8 in personal/2025)
- [x] **Session 2026-04-16 batch 3 — +27 meetings migrated** (2025-07-21 to 2025-07-31) — total reaches 127 meetings / 255 files (247 in 4shark/2025, 8 in personal/2025)
- [x] **Session 2026-04-16 batch 4 — +43 meetings migrated** (2025-08-01 to 2025-09-30) — total reaches 170 meetings / 341 files (333 in 4shark/2025, 8 in personal/2025). New types: `community:` (RAP program), `investor:` (Vortex Capital)
- [x] **Session 2026-04-16 batch 5 — +90 meetings migrated** (2025-10-01 to 2025-12-22) — total reaches 260 meetings / 521 files (513 in 4shark/2025, 8 in personal/2025). `spark_write.py` script adjusted: `Action Items` became optional (Spark's modern format omits the section)
- [x] **Session 2026-04-16 batch 6 — +89 meetings migrated** (2025-12-23 to 2026-03-27) — total reaches ~349 meetings / 697 files. Folder `~/.meeting-notes/4shark/2026/` created. `spark_write.py` permissions generalized in `settings.local.json` (`Bash(~/spark_write.py:*)`)
- [x] **Session 2026-04-16 batch 7 — +29 meetings migrated** (2026-03-27 to 2026-04-14) — total reaches ~378 meetings / 755 files. New vendors: Agência Mestre (media planning)
- [x] **Session 2026-04-17 — consistency audit and retroactive normalization**:
  - Casing normalization (102 files): `atento` → `Atento`, `commcenter` → `Commcenter`, `ecom-energia` → `Ecom Energia`, `magnatech` → `Magnatech`, `virtual-connection` → `Virtual Connection`, `spray-tools` → `Spray Tools`, `positivo` → `Positivo`, `cielo` → `Cielo`, `"Grupo Luiz Hohl"` (with quotes) → without quotes, `Atento México` → `Atento`, `Áster` → `Aster Máquinas`, `Maq Nelson` → `Maqnelson`, `Macsynie Silva` → `Macsynie`
  - Reclassifications: 4 files with `client: 4Shark` corrected to the right category (`Brisanet`, `vendor: Orbe`, `internal: novo-produto`), `Jackson Tirone` and `Adam` became `internal: interview`, `Luis Quintino` became `vendor:`, `mestre-seo` became `Agência Mestre`, `pentest-vendor` became `Avant Services`
  - Content: 1033 occurrences of 4Shark misspellings (`Force Shark`, `Forcheck`, `Forchar`, `ForChat`, `For Shark`) in 239 files normalized to `4Shark`; 17 occurrences of Almaviva misspellings (`Alma Viva`, `AlmaViva`, `almaviva`) normalized to `Almaviva`
  - Dadosfera: full pair regenerated (summary + transcript were orphans — re-extracted from Spark via URL)
- [x] `spark_write.py` extended: new 4th parameter `context_type` replacing the implicit mapping (scope → client/event)
  - `client:` — paying client
  - `vendor:` — supplier (new, e.g. Elven Works, Salesforce)
  - `internal:` — internal 4Shark meeting, value = type (new, e.g. `alignment`)
  - `event:` — personal category (wedding, family, etc.)
- [x] Retroactive classification fixes:
  - 6 dailies (12/06, 13/06, 16/06, 17/06, 18/06, 20/06): `client: 4Shark` → `client: Grupo Luiz Hohl` (12 files)
  - 2 old Barigui (08/05): `client: Barigui` → `client: Grupo Barigui` (2 files)
  - 1 Salesforce (18/06): `client: Salesforce` → `vendor: Salesforce` (2 files)

### In progress / pending

1. **Add the personal account to Granola** via Google Calendar sharing:
   - Open Google Calendar for `plribeiro3000@gmail.com` in the browser
   - Calendar settings → Share with specific people → add `paulo@4shark.com.br` with "See all event details" permission
   - Accept the sharing in the 4Shark account
   - Enable the new calendar in Granola → Settings → Calendar

2. **Continue manual migration** of old Spark meeting notes:
   - User pastes title + date + summary + transcript
   - Create two files per meeting (summary and transcript) following the template
   - Invitees come from the Google Calendar MCP (not the transcript) — `invitees` field in the frontmatter
   - The user said there is "almost a year" of notes in Spark — can prioritize the ones that really matter instead of migrating everything
   - **Last migrated meeting: 2026-04-14** — the next session starts from 2026-04-15 (or the next date with notes)

3. **Cancel Spark** only after the relevant manual migration is done (keep it paid for another ~1 month).

4. **Evaluate the Granola Business upgrade** after testing on free, if the experience confirms the value.

### Execution notes

#### Invitee lookup on Google Calendar

- **Main calendar**: `paulo@4shark.com.br` — has access to every 4Shark employee's calendar
- **Personal calendar**: `plribeiro3000@gmail.com` — for personal and Spark-created ad-hoc meetings
- **Other accessible calendars**: sergio@, danilo.assis@, camila.bergamasco@, santiago.velasquez@, patrick.mares@, ione.ruguzina@, elisio.filho@ (all @4shark.com.br)
- **Atento LATAM meetings**: when not found in paulo@, search in santiago.velasquez@4shark.com.br
- **Tip**: use `fullText` with a key term from the title + `timeMin/timeMax` with a 2h window around the time
- **Invitees format**: emails only, one per line, no names or companies

#### Mappings of recurring events

- **"4SHARK Daily | Comissionamento"** (organized by suelen.santana@grupoluizhohl.com.br) = daily meeting of the Grupo Luiz Hohl project. Mapped to:
  - `daily-acompanhamento-interno` (12/06, 13/06, 16/06, 17/06, 18/06, 20/06)
  - `ponto-controle-grupo-luiz-hohl` (18/06 — same meeting, first 3 min before the daily)
- **"Alignment"** (organized by paulo@4shark.com.br, recurring) = internal 4Shark meeting. Mapped to:
  - `status-report-sistema-comissionamento` (17/06 — status report discussed at the Alignment)
- **"Áster / 4Shark - Ponto de Controle Integração"** (organized by camila.bergamasco@) = weekly recurring
- **"Alignment"** (internal recurring at 4Shark, organized by paulo@) → `internal: alignment` (context_type `internal`, value = internal meeting type)
- **"bate papo founders"** (ad-hoc between Paulo + Sergio + Danilo Assis) → `internal: founders`
- **"Ponto de Controle Grupo Luiz Hohl | 4Shark"** = alias for the recurring daily (Suelen), same invitees

#### Entity naming conventions

- **Salesforce** = `vendor:` (not client — Salesforce is the supplier of Heroku)
- **Elven / Elven Works** = `vendor:` (domain `elven.works`)
- **Grupo Barigui** (not "Barigui") = `client:` (canonical name, domain `grupobarigui.com.br`)
- **Grupo Luiz Hohl** = `client:` for the "4SHARK Daily | Comissionamento" dailies (organized by suelen.santana@grupoluizhohl.com.br)
- **Aster Máquinas** = `client:` (domain `astermaquinas.com.br`)
- **Atento** = `client:` (unified — not "Atento Mexico" nor "Atento MX"; regional context goes into the slug)
- **Orbe** = `vendor:` (domain `orbe.ai` — AI consultancy hired by 4Shark)
- **Macsynie** = `client:` (email `contatomacsynie@gmail.com`)
- **Self Telecom** = `client:` (canonical name)
- **Grupo SADAR** = `client:` (Peugeot operator in Uruguay, domain `peugeot.com.uy`)
- **Commcenter** = `client:` (domain `commcenter.com.br`)
- **Grupo Barigui** = `client:` (domain `grupobarigui.com.br`)
- **Ecom Energia** = `client:` (domain `ecomenergia.com.br`)
- **Brisanet** = `client:` (domain `grupobrisanet.com.br`)
- **PageGroup** = `vendor:` (recruiting — domains `pageinterim.com.br` / `michaelpage.com.br`)
- **Giftty** = `vendor:` (voucher supplier)
- **Livve** = `vendor:` (partner via arista.com.br)
- **Incentivale** = `vendor:` (incentive supplier)
- **Maqnelson** = `client:` (domain `maqnelson.com.br`)
- **Rede Brasil** = `client:` (domain `redebrasil.com.br`)
- **Vortex Capital** = `investor:` (domain `vortexcapital.io` — new type)
- **RAP** = `community:` (entrepreneurship program, new type)
- **Hiperbanco** = `vendor:` (BaaS — Banking as a Service for the 4Shark Pay product)
- **Swap** = `vendor:`/competitor (`vortexcapital.io`) — classified as `internal: founders` when it's an internal discussion about them
- **Frete.com** = `client:` (domain `frete.com`)
- **Lavronorte** = `client:` (domain `lavronorte.com.br`)
- **Grupo Oyama** = `client:` (domain `grupooyama.com.br`)
- **Tecar** = `client:` (via cairodale/dvaassets — external partners)
- **Lumira Tech** = `vendor:` (domain `lumiratech.com`)
- **Ciarama Máquinas** = `client:` (domain `ciarama.com.br`)
- **BanaTech Consulting** = `vendor:` (technology consultancy)
- **Datarails** = `vendor:` (FP&A platform, domain `datarails.com`)
- **Hevo** = `vendor:` (data integration, domain `hevodata.com`)
- **Airbyte** = `vendor:` (data integration, domain `airbyte.io`)
- **Zing** = `vendor:` (podcast that invited Paulo as a guest, `zingfuel@gmail.com`)
- **PageGroup** = `vendor:` (recruiting)
- **Wonderful** = external recruiting → `internal: interview` (Paulo as the candidate pitched by GM Helder Somoggi)
- **Magnatech** = `client:` (integration, contact `brunap.magna@gmail.com`)
- **Virtual Connection** = `client:` (domains `vconnection.com.br` / `virtualconnection.com.br`)
- **Positivo** = `client:` (security assessment — 4Shark being assessed)
- **Cielo** = `vendor:` (acquirer support — 4Shark as a Cielo client)
- **Avant Services** = `vendor:` (pentest provider for Positivo compliance, domain `avantservices.com.br`) — replaces the `pentest-vendor` placeholder
- **Spray Tools** = `client:` (domain `spraytools.com.br`)
- **Agência Mestre** = `vendor:` (media planning / SEO agency, domain `mestreseo.com.br`) — canonical (replaces `mestre-seo`)
- **Almaviva** = `client:` (canonical name — correct the speech-to-text variants `Alma Viva`/`AlmaViva`/`almaviva` to `Almaviva` in the content)
- **Luis Quintino** = `vendor:` (external partner for internationalization)
- **Dadosfera** = `vendor:` (ETL/AI PoC, domains `dadosfera.io` / `dadosfera.ai`)
- **Archbit** = `vendor:` (consultancy/partner — internal 4Shark meetings when discussing the engagement with them)

#### New internal meeting types (`internal:`)

- `interview` — candidate interviews. Convention: invite the candidate via external email, slug = `entrevista-{name}` or `bate-papo-{name}-roundN`
- `learning` — external learning events (CTO Fellowship, conferences, trainings)
- `1-on-1` — 1:1 meetings between 4Shark members. Slug = `1-on-1-{person1}-{person2}`
- `founders` — conversations between founders (Paulo + Sergio + Danilo)
- `estrategia-comercial` — sales/commercial strategy meetings
- `novo-produto` — discussions of new product design (Incentive Card, campaigns, new frontend, 4Shark Pay, Integrador PivotXL)
- `roadmap` — internal product roadmap discussions, platform feedback, improvement initiatives (renamed from `melhoria-processos` — the idea is "what we want to build/improve", not execution)

#### New context_types

- `investor:` — meetings with investors / VCs (e.g., Vortex Capital)
- `community:` — programs / learning communities with module/session structure (e.g., RAP)

### Context for continuation in a new session

- This spike documents everything. A new session should read `SPIKE.md` first and resume from the "In progress / pending" item.
- **Filesystem structure**:
  ```
  ~/.meeting-notes/
  ├── 4shark/2025/    # ~257 meetings (513 files)
  ├── 4shark/2026/    # ~117 meetings (234 files)
  └── personal/2025/  # 4 meetings (8 files)
  ```
- **Last migrated meeting**: 2026-04-14 (magnatech-configuracoes-integracao-regras, atento-integracao-pagamentos)
- Confirmed user preferences:
  - Communication in pt-BR
  - Direct response, no fluff
  - Prefers to split transcript and summary into separate files
  - Prefers hidden folder (privacy)
  - Folder per year only, date in the filename
  - Invitees = Calendar emails only (no names)
