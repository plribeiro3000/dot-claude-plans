# New Relic — per-transaction breakdown across the three runs

Source: NerdGraph NRQL, `FROM Transaction ... FACET name` scoped to each run's UTC window (§ 00). `total` = `sum(duration)` (wall-time spent in that transaction type across the run); `avg`/`db`/`ext` are per-transaction averages; Ruby/CPU per job ≈ `avg − db − ext`. Times in seconds.

## The transactions that hold the time (top by total, all three runs)

### Run 1 — 30 threads × 1 task (sends all failed fast 400)

| Transaction | txns | total | avg | db (Mongo) | ext (S3/HTTP) | ruby≈ |
|---|---|---|---|---|---|---|
| Modifier::CustomCollectionConsumer | 67 | 62,209 | 928.5 | 97.0 | 281.1 | ~550 |
| User::SalesRep::DatabaseEnrichmentExtractorConsumer | 2,185 | 11,484 | 5.3 | 0.4 | 1.5 | ~3.4 |
| User::SalesRep::EnricherConsumer | 5,743 | 10,501 | 1.8 | 0.5 | 1.2 | ~0.1 |
| Modifier::LoaderConsumer | 20,744 | 10,138 | 0.5 | 0.2 | 0.3 | ~0 |
| User::SalesRep::NormalizedCollectionConsumer | 12 | 4,256 | 354.7 | 72.5 | 216.9 | ~65 |

### Run 2 — 30 threads × 1 task (real 2xx load)

| Transaction | txns | total | avg | db | ext | ruby≈ |
|---|---|---|---|---|---|---|
| Modifier::CustomCollectionConsumer | 67 | 64,819 | 967.5 | 99.8 | 287.6 | ~580 |
| User::SalesRep::LoaderConsumer | 5,743 | 21,512 | 3.7 | 0.1 | 3.6 | ~0 |
| Modifier::LoaderConsumer | 23,895 | 15,692 | 0.7 | 0.2 | 0.4 | ~0.1 |
| User::SalesRep::DatabaseEnrichmentExtractorConsumer | 2,184 | 11,584 | 5.3 | 0.5 | 1.7 | ~3.1 |
| User::SalesRep::EnricherConsumer | 5,743 | 10,894 | 1.9 | 0.6 | 1.2 | ~0.1 |
| User::SalesRep::NormalizedCollectionConsumer | 12 | 4,418 | 368.2 | 75.1 | 222.9 | ~70 |

### Run 3 — 10 threads × 3 tasks (1.5 vCPU aggregate)

| Transaction | txns | total | avg | db | ext | ruby≈ |
|---|---|---|---|---|---|---|
| User::SalesRep::LoaderConsumer | 5,743 | 21,004 | 3.7 | 0.0 | 3.6 | ~0.1 |
| Modifier::CustomCollectionConsumer | 67 | 19,668 | 293.6 | 61.3 | 192.5 | ~40 |
| Modifier::LoaderConsumer | 28,127 | 12,172 | 0.4 | 0.0 | 0.4 | ~0 |
| User::SalesRep::EnricherConsumer | 5,743 | 5,980 | 1.0 | 0.3 | 0.7 | ~0 |
| User::SalesRep::DatabaseEnrichmentExtractorConsumer | 2,184 | 3,602 | 1.6 | 0.2 | 0.8 | ~0.6 |
| User::SalesRep::NormalizedCollectionConsumer | 12 | 1,585 | 132.1 | 25.2 | 98.7 | ~8 |

## What the three runs say when crossed

**The thread reduction (30→10) already captured the Ruby oversubscription win — and only that.** The two heavy transforms are the clearest: `Modifier::CustomCollectionConsumer` per-job went 928 → 968 → 294 s, and the drop is almost entirely Ruby (~550 → ~40 s), while its S3-external stayed high (281 → 288 → 192 s). Same shape on the user transform `NormalizedCollectionConsumer` (355 → 368 → 132 s; Ruby collapses, external ~217 → 99 s stays dominant). Under 30 threads on 0.5 vCPU the GIL stretched each CPU-bound job ~3×; at 10 threads that stretch is gone. That is the win Run 3 delivered, and it is done.

**After that win, the time is dominated by I/O the thread change did NOT touch — two levers stand out:**

**1. The user send is the biggest UNMOVED cost — `User::SalesRep::LoaderConsumer` = ~21,000 s in BOTH Run 2 and Run 3 (21,512 → 21,004), essentially unchanged.** It is 5,743 sends at ~3.7 s each, ~97% external (HTTP). A single user POST taking ~3.6 s is 5–9× slower than a modifier POST (0.4–0.7 s). The thread/task change moved it by ~2%, because it is pure HTTP round-trip wait per request — more parallel workers do not shorten a single request. This is now the single largest total-time consumer in Run 3, ahead of the Modifier transform. Two candidate causes, to separate next: the integrator opens a fresh TCP+TLS connection per request (`HTTParty.post` class method, no keep-alive — spike finding B1), and/or the app API's user-creation path is genuinely ~3.6 s. Its `db`≈0 and `ext`≈all confirms the cost is entirely on the wire / the far side, not in the integrator's own Mongo.

**2. The S3 restore in the transforms — `Modifier.get` → cold-storage restore that 404s per record on a clean run — is ~192 s/job × 67 = ~12,900 s, plus ~99 s × 12 = ~1,200 s on the user transform, ~14,000 s of S3 the thread change left in place.** It is the 66% external inside the Modifier transform (§ measured directly). On a clean/first load every record misses Mongo, attempts the S3 restore, and gets a guaranteed 404 before `create!`. This is the A4 finding, and the cross-run data confirms it survives the threading win intact.

**The enrichment path improved with parallelism, unlike the send.** `SalesRep DatabaseEnrichmentExtractorConsumer` + `EnricherConsumer` went ~22,000 s (Run 1/2) → ~9,600 s (Run 3) — the 3-task scale-out helped here (avg 5.3 → 1.6 s on the extractor) because those are many independent short jobs that parallelize, whereas one 3.6-second HTTP request does not.

## The ranking this produces (most impact, and whether effort is code or external)

- **User send latency (~21,000 s, unmoved):** the biggest lever left. Effort depends on the cause — connection reuse is a bounded integrator code change (B1); a slow app-side user-creation path is an app-API change. Must be split before estimating.
- **S3 restore on clean runs (~14,000 s):** gate the cold-storage restore on a first/clean load (A4). Bounded integrator code change; pays off exactly on production go-lives, which are clean runs.
- **Modifier send (~12,000–16,000 s):** already improved by parallelism; connection reuse (B1) would compound with the user-send fix since both go through the same `HTTParty` path.
- **Ruby/CPU transform (A1/A2):** ~40 s/job in Run 3, ~13% of that transaction and a fraction of the whole run — confirmed small; deprioritized.
