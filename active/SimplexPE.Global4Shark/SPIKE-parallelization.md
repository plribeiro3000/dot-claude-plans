# SPIKE — Parallelization feasibility of SimplexPE.Global4Shark

**Project**: `SimplexPE.Global4Shark`
**Local checkout**: `/Users/plribeiro3000/Projects/Atento/SimplexPE.Global4Shark`
**Date**: 2026-05-12
**Status**: Research only — no implementation decision yet

## Question

The application is a .NET 6 console ETL that runs **fully single-threaded, sequentially, in one process**, with `try/catch` swallowing exceptions on every method. The 4Shark integrator (Ruby/Sidekiq) processes ~100k API requests in 40min on a comparable workload via horizontal parallelism — the .NET app does ~12 SP calls per user (1 create_user + ~10 fields + 1 identifier) sequentially.

The engineer asked three things:

1. Is fully sequential `.NET` typical for an ETL of this volume?
2. Is this codebase "fine for now, easy to migrate to multi-thread later"?
3. What is the actual cost of migrating to a parallel design?

This document is the considered answer. **Decision deferred** — for now we keep single-thread and pay the debt later when volume forces it.

## Findings

### 1. `.NET` single-thread sequential ETL — is it typical?

No.

`.NET` is one of the stacks with the strongest native parallelism story:

- `async`/`await` — language-level concurrency since 2012 (`.NET 4.5`).
- TPL (`Task`, `Parallel.ForEach`, `Parallel.For`) — runtime-level since `.NET 4` (2010).
- `Channel<T>` — producer/consumer with backpressure, `.NET Core 3.0`.
- TPL Dataflow (`ActionBlock`, `BatchBlock`, `TransformBlock`) — pipelines with bounded concurrency.
- `BackgroundService` / `IHostedService` — long-running workers natively.
- Hangfire / Quartz.NET — job queue + scheduler libraries widely used in production.

Production `.NET` ETL almost always uses at least one of these. **Single-thread sequential is the shape of an admin script or a prototype**, not of an application that is meant to grow with data volume.

### 2. Comparison with the 4Shark Ruby integrator (different paradigm)

Ruby (MRI) has the **GIL** (Global Interpreter Lock) — only one Ruby thread executes at a time in a process. To parallelize, Ruby scales **horizontally**: Sidekiq enqueues jobs, multiple worker processes (multiple ECS tasks) consume them. The platform pays for parallelism in **infra**, not in `Thread`.

`.NET` does **not** have a GIL. Parallelism is **vertical and native**: one process, many threads, true parallel execution on multi-core. This is exactly where `.NET` has the architectural edge over Ruby — and it's the feature this codebase doesn't use at all.

The two paradigms have different consequences for this app:

- A Ruby rewrite of the same ETL would naturally come out as N Sidekiq workers, scaled per ECS task count — same shape as the integrator already has.
- A `.NET` rewrite should come out as one process with TPL Dataflow or `Parallel.ForEach` on multi-core. Adding more processes is wasted overhead vs. adding more threads.

The current code achieves the **worst** of both worlds: single Ruby-like sequential flow without Ruby's horizontal scaling story.

### 3. Is the current code "OK for now, easy to parallelize later"?

No. There are five structural debts that block parallelization. They have to be paid **before** any `Parallel.ForEach`, otherwise the result is silent race conditions.

#### 3.1 Mutable state on the class (`this.*`)

`Services/_4SharkService.cs` holds these as instance fields written by one method and read by another:

- `this.jerarquias` — `List<Jerarquia>` rebuilt per country/company iteration
- `this.fsk_users_caches` — `Dictionary<int, FskUser>` indexed by `AsesorCodigo`
- `this.mandos`, `this.supers`, `this.racs`, `this.analistas` — `HashSet<int>` of employee codes per role
- `this.admins` — `List<int>` of admin codes
- `this.ultima_nueva`, `this.nueva_ultima` — diff buckets between previous and current load

Every one of these is mutated from multiple methods during a single country/company iteration. Replacing the `foreach` with `Parallel.ForEach` over countries (the obvious first attempt) produces two threads writing to the same `Dictionary` — race condition guaranteed, often silent until production.

**Refactor to allow parallelization**:
- Take all state off the class.
- Pass it via method parameters / return values (functional style), or
- Use `ConcurrentDictionary<,>` and `ConcurrentBag<T>` where shared writes are unavoidable.

This is a non-trivial refactor across the whole file (currently ~1500 lines).

#### 3.2 Single shared `DataContext`

`GetDataContext4Shark(countryName)` returns one instance per country call, and that instance is then passed down through dozens of methods. EF Core's `DbContext` is **explicitly documented as not thread-safe** ([Microsoft docs](https://learn.microsoft.com/en-us/ef/core/dbcontext-configuration/#avoiding-dbcontext-threading-issues)) — two threads issuing SQL on the same `DbContext` is undefined behavior, often crashes with `InvalidOperationException: A second operation was started on this context instance before a previous operation completed`.

**Refactor to allow parallelization**:
- Switch to `IDbContextFactory<DataContext>` (introduced in EF Core 5).
- Each parallel branch creates its own short-lived `DbContext` via `factory.CreateDbContext()`.
- Significant: changes the dependency injection setup, every method signature that takes `DataContext`, and the lifetime management throughout the code.

#### 3.3 `try/catch` swallowing every exception

Every method in `_4SharkService.cs` follows this shape:

```csharp
try {
    // do the work
}
catch (Exception e) {
    var error = $"<MethodName>\t{...}\t{e.Message}";
    Logger.LogError(error);
    // continue
}
```

In sequential mode this is already bad — it masks bugs and turns "the run succeeded" into a meaningless signal (the run reports success even when half the users failed silently). The error log on disk is the only evidence.

In parallel mode it gets worse:
- N threads can hit the same kind of error simultaneously and each writes its own log line.
- A "the run succeeded" message will routinely hide dozens of silent failures.
- Stack traces in parallel logs are interleaved and harder to read.

**Refactor to allow parallelization**:
- Decide what should be **fatal** (abort the run — e.g. SP returned wrong table, missing config) and let it throw.
- What should be **per-user recoverable** (e.g. one user has bad data) — keep narrow catch but **collect** the failure into a list rather than just logging, and decide outcome at the end of the run (X users failed → fail the run or just report).
- Remove the global `catch (Exception)`. Use specific exception types only where retry/skip is intentional.

This change alone is independent of parallelization — it should happen regardless.

#### 3.4 Hierarchy creation order is sequential by nature

The hierarchy has strong ordering dependency:

```
Admin → VicePresident → Director → Superintendent → GeneralManager
       → Manager → Coordinator → Supervisor → SalesRepresentative (Rac/Analista)
```

Each level's `parent_id` references the level above. The code loads role-by-role in that order (`UploadMandos` → `UploadSupers` → `UploadRacs` → `UploadAnalistas`), and within `Mandos` it walks level-by-level so the parent always exists before the child.

This is **not pure sequential nostalgia** — it's a real data-flow constraint. You cannot parallelize across hierarchy levels.

What you **can** parallelize:
- All users **within the same hierarchy level** (e.g. all 297 Supervisors after all Managers exist — these 297 are siblings, none depends on another).
- The `SaveUserFields` / `SaveUserIdentifier` calls for one user are independent of any other user.

The natural parallelism granularity is "siblings at the same level", which is non-trivial to orchestrate but factually parallel.

#### 3.5 SQL Server throughput as the real ceiling

For each user the integrator does ~12 SP round-trips:

- 1 × `create_user`
- ~10 × `create_user_field` (CARGO, SITE, MODALIDAD, GRUPO_OCUPACIONAL, CECO, DESC_CECO, CLIENTE, PEP, DESC_PEP, CLIENTE_SAP)
- 1 × `create_user_identifier`
- + the parent-lookup queries during `FindParentMando` / `FindParentSuper`

For 10k users that's ~120k SP calls. At a network RTT of 5ms (LAN) — 10min sequential lower bound. At 50ms (Atento ↔ AWS over VPN) — 100min sequential lower bound.

Parallelism helps until the SQL server saturates. SQL Server can handle a few hundred concurrent connections per CPU core if the procs are cheap. So the realistic ceiling is **5–10x speedup**, not 100x. After that point the bottleneck is the database, not the application.

This means parallelism is worth doing — it turns 30min into 5min — but it does not turn this into an infinite-scaling architecture without addressing batching (bulk inserts / table-valued parameters).

### 4. Cost estimates for parallelizing

Three realistic paths, ordered by invasiveness:

#### Option A — `Parallel.ForEach` per role within each level

**Approach**:
- Keep the role-by-role outer loop (must remain sequential — parent dependency).
- Within each role's `Upload*`, replace `foreach (var je in items) Add(je, ...)` with `Parallel.ForEach`.
- Inject `IDbContextFactory<DataContext>` and create a per-task `DataContext`.
- Convert mutable caches to `ConcurrentDictionary`.
- Remove or narrow the catch-alls.

**Effort**: 1–2 weeks.
**Speedup**: ~5–10x (limited by SQL Server).
**Risk**: medium — refactor scope is contained but every method signature changes.

#### Option B — TPL Dataflow pipeline

**Approach**:
- Pipeline: `ExtractRoles → EnrichJerarquia → UpsertUserAndDeps → SaveSnapshot`.
- Each block has configurable `MaxDegreeOfParallelism`.
- Backpressure via `BoundedCapacity` — slow downstream stops upstream from flooding memory.
- Errors propagate as `Task` failures, not logged-and-swallowed.

**Effort**: 2–3 weeks.
**Speedup**: same ~5–10x.
**Risk**: medium-high — bigger rewrite, but yields a maintainable shape.

#### Option C — `BackgroundService` + Hangfire/Quartz

**Approach**:
- Each user becomes a job in a queue.
- N worker tasks consume the queue.
- Scheduler triggers a "kick-off" job that enqueues all per-user jobs.
- Operational model aligns with the Ruby integrator (queue + N workers).

**Effort**: 3–5 weeks.
**Speedup**: same ~5–10x in a single process, but **scales horizontally** if needed (multiple instances consuming the same queue).
**Risk**: high — deploy model changes (no longer a console + Windows scheduler; needs a long-running service host, a job storage backend like SQL Server or Redis).

### 5. Verdict

- **The codebase is not "fine for now"** — it has structural debt (mutable state, single `DbContext`, blanket `catch`) that any future parallelization will have to pay first. That refactor is ~30–40% of `_4SharkService.cs`.
- **It is not "easy to migrate later"** — the migration is exactly the refactor above. There is no smaller version of it.
- **It is not impossible to migrate** — `.NET` has all the tools; the code just doesn't use them.
- **For Atento Mexico (~10k users) the current shape is survivable** — 30min of sequential work per run is acceptable, and infrequent (daily delta is small).
- **For Atento Brasil or any larger tenant** the refactor becomes obligatory — sequential simply will not fit a reasonable run window.

### 6. Recommendation

**Short term (now)**:
- Keep single-thread. Do not attempt "light" parallelism with the current code — it produces silent races.
- Independent of parallelism: **remove the blanket `try/catch`** — that fix is good even at single-thread, and is a prerequisite for everything else.

**Medium term (before Atento BR or any second tenant)**:
- Execute Option A — `Parallel.ForEach` per role + `IDbContextFactory` + `ConcurrentDictionary`. Cheapest path that pays off and unblocks the rest.

**Long term**:
- If volume grows beyond what one process handles, move to Option C (queue + workers). The shape will then match the Ruby integrator's mental model and ops can be unified.

## References

- `~/.claude/plans/active/SimplexPE.Global4Shark/ANALYSIS.md` § "Architectural findings (not fixed yet — backlog)" — finding A documents the single-thread state and points back here.
- EF Core thread safety: https://learn.microsoft.com/en-us/ef/core/dbcontext-configuration/#avoiding-dbcontext-threading-issues
- TPL Dataflow: https://learn.microsoft.com/en-us/dotnet/standard/parallel-programming/dataflow-task-parallel-library
- Hangfire: https://www.hangfire.io/
- Quartz.NET: https://www.quartz-scheduler.net/
