# SPIKE — simplex-harvester: first daily run always times out against the serverless-paused source database

## Investigation question

The engineer already established the root cause: one of `simplex-harvester`'s two SQL Server
databases is serverless and auto-pauses between the ETL's daily executions (the harvester runs
once a day as an ECS scheduled task, so the database is always paused when the job wakes). The
first request against it needs to "resume" the paused database, and that resume overruns the
first daily run's timeout budget.

Two questions drive this spike:

1. **Why does the existing mitigation (`OpenWithBackoff`, added in commit `9605907`) not
   eliminate the timeout?** The mitigation already retries the initial database connection with
   exponential backoff — the engineer reports the first run still times out.
2. **What are the available options — code-side (harvester) and infra-side — to close the gap,
   with their trade-offs?** No option is selected here; the engineer chooses.

## Sources consulted

- `Helpers/UtilHelper.cs:11-23` — the two `DataContext` factories, both calling
  `sqlOptions.EnableRetryOnFailure()` with no arguments.
- `Services/SimplexHarvesterService.cs:66-72, 461-530` — `EnsureDatabaseConnectivity` /
  `OpenWithBackoff`, the current mitigation, and its place in `Load()`'s pre-flight sequence.
- `Services/SimplexHarvesterService.cs:373-459, 716-746` — `ReifySubsidiaries` and
  `LoadJearquia`, the two places where the harvester issues its first real queries against each
  connection after the connectivity pre-flight.
- `git log` / `git show 9605907` and `git show 5aed4b0` (local repository) — history of the two
  prior connection-resiliency fixes.
- `appsettings.json`, `appsettings.example.json`, `appsettings.exampleDevOps.json` (local
  repository) — confirms no `CommandTimeout`/`ConnectTimeout`/`Connect Timeout` setting exists
  anywhere in the checked-in configuration; connection strings themselves are not in the
  repository (env-injected, per the engineer's note).
- `~/.claude/docs/PROJECTS-CATALOG.md:70` — confirms which of the two connections is the
  client-owned source vs the 4Shark-owned target.
- [`SqlServerTransientExceptionDetector.cs`](https://raw.githubusercontent.com/dotnet/efcore/main/src/EFCore.SqlServer/Storage/Internal/SqlServerTransientExceptionDetector.cs) (raw GitHub source, fetched directly via `curl` and read in full — not summarized by an intermediary) — the actual default transient-error check used by EF Core's SQL Server retrying execution strategy. See auxiliary `simplex-harvester-serverless-timeout_excerpt_1.cs` for the relevant tail of the switch statement.
- [EF Core `EnableRetryOnFailure()` API reference](https://learn.microsoft.com/en-us/dotnet/api/microsoft.entityframeworkcore.infrastructure.sqlserverdbcontextoptionsbuilder.enableretryonfailure?view=efcore-8.0) — default retry count and delay.
- [Azure SQL Database — Serverless compute tier overview](https://learn.microsoft.com/en-us/azure/azure-sql/database/serverless-tier-overview?view=azuresql) — auto-pause/auto-resume mechanics, latency, and the connectivity error contract.
- [Azure SQL Database — Working with Transient Errors](https://learn.microsoft.com/en-us/azure/azure-sql/database/troubleshoot-common-connectivity-issues?view=azuresql) — connection-vs-command retry guidance and default `SqlConnection`/`SqlCommand` timeout values.
- [`dotnet/SqlClient` issue #1957](https://github.com/dotnet/SqlClient/issues/1957) — documents the mismatch between serverless resume duration and the default retry logic provider's timeout window.

## Findings

### Finding 1: The current mitigation only proves the connection can be *opened* — it never issues a real query

**Evidence:**

```csharp
// Services/SimplexHarvesterService.cs:470-493
private void OpenWithBackoff(string label, Func<DataContext> contextFactory)
{
    var attempts = ConnectionRetryBackoffSeconds.Length + 1;
    for (var attempt = 1; ; attempt++)
    {
        try
        {
            using var dataContext = contextFactory();
            dataContext.Database.OpenConnection();
            dataContext.Database.CloseConnection();
            if (attempt > 1)
            {
                _logger.Information($"EnsureDatabaseConnectivity\t{label}\tconnected on attempt {attempt}/{attempts}");
            }
            return;
        }
        catch (SqlException e) when (attempt < attempts)
        {
            var delaySeconds = ConnectionRetryBackoffSeconds[attempt - 1];
            _logger.Warning(e, $"EnsureDatabaseConnectivity\t{label}\tattempt {attempt}/{attempts} failed, retrying in {delaySeconds}s");
            Thread.Sleep(TimeSpan.FromSeconds(delaySeconds));
        }
    }
}
```

**Significance:** `OpenWithBackoff` calls `OpenConnection()` then immediately `CloseConnection()` — a login/handshake check, not a query. It is invoked from `EnsureDatabaseConnectivity` (`Services/SimplexHarvesterService.cs:461-467`), which runs as the second pre-flight step in `Load()` (`Services/SimplexHarvesterService.cs:515-530`), before `ReifySubsidiaries` (Finding 2) issues the first real query. A successful open+close proves the database accepted a login — it does not prove the compute is warm enough to serve a query within the default command timeout (see Finding 6/7 on resume latency vs. compute readiness).

### Finding 2: The first real query after the connectivity check has no local retry and no surrounding catch

**Evidence:**

```csharp
// Services/SimplexHarvesterService.cs:396-401
var connectionStrings_Simplex = this.Configuration.GetSection("SimplexConnection").Value;
DataContext dataContextSimplex = UtilHelper.GetDataContext(connectionStrings_Simplex);
var empresasFromSimplex = dataContextSimplex.Empresas!
    .AsNoTracking()
    .Where(e => configuredCodes.Contains(e.EmpresaCodigo))
    .ToList();
```

```csharp
// Services/SimplexHarvesterService.cs:537-548 (Load())
try
{
    this.ReifySubsidiaries();
}
catch (Exception e)
{
    var error = $"ReifySubsidiaries\t{e.Message}";
    _logger.Error(e, error);
    RollbarReporter.Report(e);
    _logger.Information("---------------Fin (aborted)---------------");
    return;
}
```

**Significance:** `ReifySubsidiaries()` (`Services/SimplexHarvesterService.cs:373-459`) has no `try`/`catch` of its own around this LINQ query — the only catch is the outer one in `Load()`, which logs and **aborts the entire run** (`return;`) on any exception. This query executes through the `DbContext`'s configured execution strategy (`EnableRetryOnFailure()`, Finding 3) rather than through the harvester's own hand-rolled backoff loop. If this query times out with SQL error `-2` after the connection pre-flight already succeeded, nothing in the harvester code retries it, and nothing downstream of `EnsureDatabaseConnectivity` provides the same resilience `OpenWithBackoff` provides for the connection-open phase.

### Finding 3: Both `DataContext` factories enable EF Core's *default* retry strategy — no explicit error numbers, no explicit timeouts

**Evidence:**

```csharp
// Helpers/UtilHelper.cs:11-23
public static DataContext GetDataContext(string connString)
{
    var optionBuilder = new DbContextOptionsBuilder<DataContext>();
    optionBuilder.UseSqlServer(connString, sqlOptions => sqlOptions.EnableRetryOnFailure());
    return new DataContext(optionBuilder.Options);
}

public static DataContext GetNormalizedDatabaseContext(string connString)
{
    var optionBuilder = new DbContextOptionsBuilder<DataContext>();
    optionBuilder.UseSqlServer(connString, sqlOptions => sqlOptions.EnableRetryOnFailure());
    return new DataContext(optionBuilder.Options);
}
```

**Significance:** `EnableRetryOnFailure()` is called with zero arguments on both connections. No `errorNumbersToAdd`, no `CommandTimeout`, no `Connection Timeout`/`ConnectRetryCount`/`ConnectRetryInterval` override anywhere in the repository (confirmed by grep across `.cs` and `.json` — zero matches for `CommandTimeout`, `Connect Timeout`, `ConnectTimeout`). Every timeout in play is a SqlClient default.

### Finding 4: EF Core's default transient-error detector explicitly EXCLUDES the timeout error number (-2)

**Evidence** (verbatim, from the actual EF Core `main` branch source, fetched directly — see auxiliary `simplex-harvester-serverless-timeout_excerpt_1.cs` for the full quoted tail of the switch statement):

```csharp
// This exception can be thrown even if the operation completed successfully, so it's safer to let the application fail.
// DBNETLIB Error Code: -2
// Timeout expired. The timeout period elapsed prior to completion of the operation or the server is not responding. The statement has been terminated.
//case -2:
```

**Source:** [`SqlServerTransientExceptionDetector.cs`](https://raw.githubusercontent.com/dotnet/efcore/main/src/EFCore.SqlServer/Storage/Internal/SqlServerTransientExceptionDetector.cs), line 699 (of 709), inside the `ShouldRetryOn` method that `SqlServerRetryingExecutionStrategy` (the strategy `EnableRetryOnFailure()` activates) delegates to.

**Significance:** This is the direct explanation for "why the mitigation doesn't fully solve it." `case -2` is deliberately commented OUT of the switch, with the maintainers' own rationale attached (a `-2` timeout can fire even after the operation actually succeeded server-side, so EF treats retrying it as unsafe by default and lets the exception propagate instead). Concretely: if the first real query in `ReifySubsidiaries` (Finding 2) exceeds the default command timeout because the resumed database is still cold, the resulting `SqlException` (`Number == -2`) is **not** retried by the execution strategy — it propagates immediately, hits `ReifySubsidiaries`'s absent local catch, and is caught only by `Load()`'s outer handler, which aborts the whole run. Separately, error `40613` (the serverless "database not currently available, resuming" code — Finding 6) **is** in the default retriable list (it falls through to `return true;` alongside case `233`, confirmed in the same source file), so a query that hits `40613` specifically would be retried by EF's default strategy; a query that instead runs long and hits a genuine command-execution timeout (`-2`) would not be.

### Finding 5: EF Core's default retry strategy caps out at 6 attempts / 30 seconds max delay

**Evidence:** *"Default values of 6 for the maximum retry count and 30 seconds for the maximum default delay are used."*

**Source:** [`SqlServerDbContextOptionsBuilder.EnableRetryOnFailure` — Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/microsoft.entityframeworkcore.infrastructure.sqlserverdbcontextoptionsbuilder.enableretryonfailure?view=efcore-8.0), Remarks section of the parameterless overload.

**Significance:** Even for an error number that IS in the default retriable list (such as `40613`), the built-in strategy's own retry budget (6 attempts, exponential backoff capped at 30s between attempts) is independent of, and generally smaller than, the harvester's own `OpenWithBackoff` schedule (30/60/120/240s, Finding 1). Whether this budget is sufficient for a serverless resume depends on the resume latency, addressed in Finding 7.

### Finding 6: Azure SQL Database serverless — first connection attempt against a paused database always fails with 40613; retry after resume is the documented pattern

**Evidence:** *"If a serverless database is paused, the first connection attempt resumes the database and returns an error stating that the database is unavailable with error code 40613. Once the database is resumed, retry the connection."*

Also, the auto-resume trigger table's intro reads: *"Auto-resuming is triggered if any of the following conditions are true at any time:"* — and the table's first row, under the "Authentication and authorization" feature, lists the trigger verbatim as: *"Login attempt"*.

**Source:** [Serverless compute tier - Azure SQL Database — Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-sql/database/serverless-tier-overview?view=azuresql), sections "Auto-resume" and "Connectivity".

**Significance:** This is the exact shape `OpenWithBackoff` already handles correctly for the connection-open phase — a login attempt triggers resume, the first attempt is *expected* to fail with `40613` (a `SqlException`, caught generically by `OpenWithBackoff`'s `catch (SqlException e)`), and a subsequent attempt after the backoff succeeds once resume completes. This finding does NOT identify a gap in `OpenWithBackoff` itself — it corroborates that the connection-open mitigation is aligned with Microsoft's documented pattern. The gap is downstream, at the first real query (Findings 2 and 4).

### Finding 7: Serverless resume latency is variable and can exceed both the default command timeout and the default retry-logic timeout window

**Evidence:** *"The latency is generally in the order of one minute to auto-resume ... The latency for either operation can be as low as the order of one second."*

**Source:** [Serverless compute tier - Azure SQL Database — Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-sql/database/serverless-tier-overview?view=azuresql), section "Latency".

Separately: *"When connecting to a serverless database, it's reasonable to receive error code 40613 as the database resumes. But resuming can take as long as ~45 seconds, in which case driver generally times out even with the default Retry logic provider."*

**Source:** [`dotnet/SqlClient` issue #1957](https://github.com/dotnet/SqlClient/issues/1957) — "Consider handling error code 40613 with stretched timeout with default retry logic provider".

**Significance:** Resume duration is not a fixed, short number — Microsoft's own docs describe it as "generally... one minute" with no hard upper bound stated, and the SqlClient team's own issue acknowles a ~45-second case that is long enough to exceed the *default* retry-logic provider's timeout window even when 40613 IS being retried correctly. This directly bears on Finding 3/5: even the harvester's own connection-level backoff (max cumulative wait ~450s across 5 attempts) is generous enough to absorb most observed resume windows, but nothing analogous exists for the query-level path once the connection itself succeeds (Finding 2).

### Finding 8: Azure's own guidance distinguishes connection retry from command retry — and recommends re-establishing the connection before retrying a command, never retrying the command itself blindly

**Evidence:** *"A transient error occurs during a query command — Don't immediately retry the command. Instead, after a delay, freshly establish the connection. Then retry the command."*

Also, on default SqlClient values: *"Connection Timeout: Default is 15 seconds ... Command Timeout ... default is 30 seconds."*

**Source:** [Working with Transient Errors - Azure SQL Database — Microsoft Learn](https://learn.microsoft.com/en-us/azure/azure-sql/database/troubleshoot-common-connectivity-issues?view=azuresql), sections "Connection vs. command" and "Idle connection resiliency".

**Significance:** Confirms the two SqlClient default timeout values in play (15s connect, 30s command) since neither is overridden anywhere in this repository (Finding 3), and confirms that Microsoft's own guidance treats a query-command timeout as a distinct retry case from a connection-open timeout — it does not recommend simply re-running the same command on the same connection, but re-establishing the connection first. `ReifySubsidiaries` today does neither: it has no retry of any kind at the command level.

### Finding 9: The existing mitigation was written specifically to cover the "post-login phase" of the connection — its own comment scopes it to connection establishment, not query execution

**Evidence:**

```csharp
// Services/SimplexHarvesterService.cs:68-72
// Exponential backoff (seconds) between initial-connection attempts — 5 attempts total.
// The source SQL Server has timed out in the post-login phase at run start, aborting the
// whole day's load; EF's EnableRetryOnFailure does not cover a connection-open timeout, so
// the run reaches both databases explicitly and waits them out before giving up.
private static readonly int[] ConnectionRetryBackoffSeconds = { 30, 60, 120, 240 };
```

**Source:** `Services/SimplexHarvesterService.cs:68-72`, introduced in commit `9605907` ("fix(harvester): retry initial database connection with explicit backoff", PR #36, merged into release 1.2.0 per `git log`/`git show` on the local repository).

**Significance:** The comment itself documents the scope of the fix precisely: "connection-open timeout." It was never intended to, and does not, cover a timeout on the first query issued after that connection opens. The commit's own framing corroborates Findings 1 and 2 — this is a documented, deliberate scope boundary, not an oversight discovered only now.

### Finding 10: Which of the two databases is the serverless one is inferred, not directly confirmed in this repository

**Evidence:** *"Reads the Atento Simplex SQL Server, fetches and classifies the data, and writes the normalized base; the integrator continues the flow from there."*

**Source:** `~/.claude/docs/PROJECTS-CATALOG.md:70`.

**Significance:** This confirms `SimplexConnection` (`Services/SimplexHarvesterService.cs:463`, `:396`) is the client-owned Atento Simplex SQL Server (the source being *read*) and `NormalizedDatabaseConnection` (`:464`) is the 4Shark-owned normalized base (the target being *written*). Combined with the code comment at `Services/SimplexHarvesterService.cs:70-71` ("The source SQL Server has timed out in the post-login phase"), the source (`SimplexConnection`) is the one the existing bug reports/comments describe as timing out. Neither this repository nor `PROJECTS-CATALOG.md` states which cloud or SQL Server offering hosts either database, or confirms that the source is on Azure SQL Database serverless specifically (as opposed to another serverless-like offering, or a differently-configured always-on instance that merely idles/scales in some other way). This is flagged as an open question for the engineer in the section below — the whole external-research section of this spike assumes the Azure SQL Database serverless auto-pause/auto-resume model applies, because it is the best-known SQL Server serverless offering matching the engineer's description ("needs a request to wake up"), but this spike did not have access to the infrastructure/Terraform definition of either database to confirm it directly.

## Diagnosis (from the verified findings above)

`OpenWithBackoff` (Finding 1) faithfully implements the documented Azure SQL serverless connection-retry pattern (Finding 6) — a login attempt against a paused database resumes it and fails with `40613`, a subsequent attempt after backoff succeeds. This is why it does not fully solve the reported problem: it was scoped, by its own code comment (Finding 9), to the connection-open phase only, and it succeeds at that scope.

The daily run's timeout is most consistent with a failure one step later: the very first real query issued after the connectivity check succeeds — `ReifySubsidiaries`'s query against `dbo.empresa` on `SimplexConnection` (Finding 2) — executing while the resumed database's compute is still not fully warmed up (resume latency is "generally... one minute" and can run long enough, per Microsoft's own SqlClient team, to exceed default timeout windows — Finding 7), and hitting the default 30-second command timeout (Finding 8). That specific failure (`SqlException` number `-2`) is the ONE error number EF Core's default retry strategy deliberately excludes (Finding 4) — by the EF Core team's own comment, because a `-2` can fire even when the operation actually succeeded, making a blind retry unsafe by default. With no retry at the EF layer and no local `try`/`catch` around `ReifySubsidiaries` (Finding 2), the exception reaches only `Load()`'s outer handler, which aborts the entire day's run.

This diagnosis is consistent with, but not proven equivalent to, the engineer's framing ("the DB needs an initial request to wake up, and that first request times out") — the refinement this spike adds is that the connection-level "wake up" request (`OpenWithBackoff`) already appears to succeed (or eventually succeed, within its backoff budget), and the failure is one layer further in, at the first real query.

## Trade-offs surfaced

| Option | Code vs. infra | Effort | Risk | Notes |
|---|---|---|---|---|
| A — Add `-2` to `EnableRetryOnFailure(errorNumbersToAdd: ...)` globally for both `DataContext` factories | Code (harvester) | Low | Medium | Per Finding 4, the EF Core team's own rationale for excluding `-2` by default is that it "can be thrown even if the operation completed successfully." Applied globally, this would also cover the write-path stored-procedure calls (`create_user`, `create_subsidiary`, etc. — see `Services/SimplexHarvesterService.cs`), where a retried non-idempotent call could duplicate a side effect if the original call actually succeeded server-side despite the client-side timeout |
| B — Raise `Command Timeout` (and/or `Connect Timeout`) on the connection string(s) | Code/config (harvester) | Low | Low–Medium | Removes the 30s default ceiling (Finding 8) so a slow-but-successful first query on a still-warming database has more room to complete; does not touch retry semantics, so no duplicate-execution risk. Does not guarantee sufficiency — resume duration is described as variable with no documented hard cap (Finding 7), so a fixed timeout, however generous, is still a guess against an unbounded distribution |
| C — Add an explicit read-only warm-up query (e.g., a lightweight `SELECT`) after `OpenWithBackoff`, using the same manual backoff/`catch (SqlException)` pattern already used for the connection open | Code (harvester) | Medium | Low | Extends the already-proven pattern (Finding 1, Finding 9) one step further, to cover the gap this spike identifies (Finding 2), without changing EF's retry policy anywhere. A read-only warm-up query carries no duplicate-side-effect risk regardless of retry count |
| D — Wrap only the early read queries (e.g., `ReifySubsidiaries`, `LoadJearquia`) in an explicit `CreateExecutionStrategy().Execute(...)` call with a narrowly-scoped custom retry list (including `-2`), instead of enabling it globally on the shared `DataContext` factories | Code (harvester) | Medium–High | Low | Confines the `-2`-is-retriable relaxation (Option A's risk) to the specific read paths that need it, leaving the write/SP-execution paths on the safer default. Requires distinguishing read-only call sites from write call sites across the codebase |
| E — Infra-side: disable or lengthen the auto-pause delay on the serverless database, or schedule an unrelated keep-alive/ping ahead of the harvester's run window | Infra | Low (config) – Medium (coordination) | Low (technical) / cost trade-off | Removes the problem at the root (Finding 6's auto-pause trigger never fires, or the database is already resumed by the time the harvester connects) without touching harvester code. Directly works against the cost rationale for choosing serverless (billing drops to storage-only while paused — see the Azure serverless overview's "Auto-pause" and "Cost" sections). Depends on the open question in Finding 10 — whether 4Shark or the client (Atento) controls this setting, and on which cloud subscription |
| F — Combine C (a real warm-up query, not just open+close) with a narrowly-scoped `-2` retry (as in D) applied only inside that warm-up step | Code (harvester) | Medium | Low | Generalizes the already-working connection-level pattern (Finding 1/9) to also prove the first query succeeds, before the main pipeline's `ReifySubsidiaries`/`LoadJearquia` run — without touching the global retry policy used elsewhere in the codebase |

## What remains uncertain

- **Which of the two connections (`SimplexConnection` or `NormalizedDatabaseConnection`) is actually the serverless one, and on which cloud/offering.** This spike infers `SimplexConnection` (the Atento source) from the existing code comment and `PROJECTS-CATALOG.md`, but neither states this directly, and this spike had no access to the infrastructure/Terraform definition of either database. If `NormalizedDatabaseConnection` (the 4Shark-owned target) is the one that pauses, the analysis of "which query is first" changes — the first real write against it happens later in the company loop (`LoadFskUsers`, `Services/SimplexHarvesterService.cs:260-294`, and the various `Add`/SP-execution calls), not in `ReifySubsidiaries`.
- **Whether the offering is Azure SQL Database serverless specifically**, as opposed to a different vendor's serverless/auto-suspend SQL Server offering with different error codes and resume mechanics. All external findings in this spike (6, 7, 8) are scoped to Azure SQL Database; if the actual offering differs, those specific error codes and latency figures may not transfer directly, though the general shape of the problem (connection-level retry ≠ query-level retry) likely still applies.
- **Whether `sp_reporte_jeraquia_4shark` and the other stored procedures invoked later in the pipeline are idempotent/side-effect-free**, which bears directly on how safely Option A (or D) could be applied to read vs. write paths. This spike read `LoadJearquia`'s call site (`Services/SimplexHarvesterService.cs:716-746`) but not the SP body itself (it lives in the source database, outside this repository).
- **Whether the reported timeout is reproducible specifically at `ReifySubsidiaries`**, or could instead surface at `LoadJearquia` (the first query per company, also against `SimplexConnection`) depending on company ordering and exact timing. Both paths share the same underlying gap (Finding 2/4); this spike did not have production logs to confirm which one fails on a given day.

## Suggested options for main and the engineer

- Option A: broaden the default retry policy to include error `-2`, applied globally on both `DataContext` factories.
- Option B: raise `Command Timeout`/`Connect Timeout` on the connection string(s), leaving retry policy untouched.
- Option C: extend the existing `OpenWithBackoff` pattern with a genuine read-only warm-up query after the connection opens.
- Option D: scope a custom, `-2`-inclusive execution strategy narrowly to the early read-only call sites, leaving the shared factories on EF's safer default.
- Option E: address the pause/resume cycle at the infrastructure level (auto-pause delay, disabling auto-pause, or a scheduled keep-alive/ping ahead of the harvester's run window).
- Option F: combine C and D — a real warm-up query with a narrowly-scoped `-2` retry, isolated from the rest of the codebase's retry policy.

(No recommendation — the trade-offs above, and the open questions on which database is serverless and on which cloud, are for the engineer to resolve before choosing.)

---

## Update — 2026-07-22: resolved by the client alignment meeting + chosen direction

The two open questions this spike flagged (which of the two databases is serverless, and on which cloud) are now **resolved** by primary evidence — the "Time out | 4Shark" alignment meeting on 2026-07-22 between 4Shark and the client's (Atento) infrastructure team. The direction to implement is also decided. The original findings above are left intact; this section supersedes the specific inferences it names.

### Finding 11 — RESOLVES Finding 10: the serverless database is the NORMALIZED base, not the Simplex source

**Evidence (meeting transcript, verbatim):** the harvester logs into the Simplex source without problem, and the timeout happens when it logs into the normalized base — *"cuando el SS ejecuta el loggeo a la base de datos de Simplex, funciona normal, pero cuando trata de loguearse en la base de datos normalizada, está generando un time out."* The client's infra lead confirmed the per-country normalized databases (one for MX, one for CO) are Azure SQL Database **serverless**, whose compute is allocated on demand and pauses when idle — *"estas son bases de datos las que tienen para cada uno de los países que son serverless... los recursos se asignan por demanda."* Azure monitoring graphs were shown live in the meeting, confirming the Azure SQL offering.

**Source:** Granola meeting transcript, "Time out | 4Shark", 2026-07-22 (meeting id `4ce8ffc9-86d7-4563-a3c4-2373de800b5e`).

**Significance:** This **inverts** Finding 10's inference. The serverless, auto-pausing database is `NormalizedDatabaseConnection` (the 4Shark-owned base hosted in the client's Azure tenant — the *target* being written), NOT `SimplexConnection` (the source being read). The code comment at `Services/SimplexHarvesterService.cs:70-71` ("The source SQL Server has timed out in the post-login phase") is therefore misleading and should be corrected when the code is next touched — it points at the wrong connection.

### Finding 12 — the observed production symptom is the LOGIN/connection-open, and the existing mitigation already recovers it on the second attempt

**Evidence (meeting transcript):** the login to the normalized base times out even after the timeout was raised from 15s to 30s (*"aunque hace el handshake y todo, el tiempo se agota"*), and the current five-attempt backoff always succeeds on the second attempt — *"hasta cinco intentos y siempre en el segundo intento ya funciona bien el logueo."* Sixty back-to-back manual logins outside the 3:30am window all succeeded; the failure is specific to the run's cold-start hour.

**Source:** Granola meeting transcript, "Time out | 4Shark", 2026-07-22.

**Significance:** The observed cause is a **cold-start connection-open** timeout, which `OpenWithBackoff` (Finding 1) already absorbs — the daily run is not currently failing, it just burns one timed-out attempt plus a backoff wait every morning. This means the first-query `-2` hypothesis in the original Diagnosis (Findings 2/4) is **not** the production symptom; Finding 4 remains a true fact about EF Core's default retry policy, but it is not what is failing here. The goal is to eliminate the wasted first-attempt timeout by having the driver resume/retry the connection transparently, replacing the hand-rolled backoff.

### Finding 13 — the harvester runs Microsoft.Data.SqlClient 2.1.4, which predates the serverless-aware connection retry behavior

**Evidence:** the resolved transitive dependency is `Microsoft.Data.SqlClient/2.1.4` (pulled by `Microsoft.EntityFrameworkCore.SqlServer 6.0.11`), confirmed in `obj/project.assets.json`. The serverless-aware improvements — a default `ConnectRetryCount=5` specifically for serverless/on-demand endpoints, and robust "open connection resiliency" that applies the retry to the *initial* `Open()` against a paused database — landed in **SqlClient 5.x**: *"for Azure SQL serverless or on-demand endpoints, the default is 5 to improve connection success for connections to an idle or paused instance"* ([ConnectRetryCount — Microsoft Learn](https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqlconnectionstringbuilder.connectretrycount?view=sqlclient-dotnet-core-6.1)).

**Significance:** On 2.1.4 the `ConnectRetryCount`/`ConnectRetryInterval` connection-string keywords exist but are not serverless-aware for the cold-start *open*. Setting them alone (the client's suggestion — see Finding 14) will not reliably deliver the driver-native warm-up the engineer wants without also upgrading SqlClient.

### Finding 14 — the client's suggested fix is `ConnectRetryCount`/`ConnectRetryInterval`; it is real and Microsoft-recommended for serverless warm-up, with three constraints

**Evidence:** in the meeting the client's infra lead described connection-string properties that make the driver retry the connection so the timeout disappears, and noted Atento uses this pattern (they set the retry count to 30) across their solutions — *"en los connection string hay propiedades para que no exista ese time out... nosotros ponemos treinta."* Microsoft's guidance corroborates the mechanism for serverless: *"Configurable retry logic is capable of eliminating completely the side effect of connection issues during warm-up condition (when a serverless database is waking up after auto-pausing, usually between 30 and 60 seconds) by configuring proper number of retries covering that time interval"* ([Configurable Retry Logic — Azure SQL Dev Corner](https://devblogs.microsoft.com/azure-sql/configurable-retry-logic-for-microsoft-data-sqlclient/)).

**Constraints (from the same sources + Finding 13):**
1. **Version** — needs SqlClient 5.x for the serverless-aware initial-open behavior (Finding 13); on the current 2.1.4 the config alone is insufficient.
2. **No stacking** — the config must **replace** the existing `OpenWithBackoff`, not sit on top of it: Microsoft warns retries compound (a 4-attempt manual loop plus `ConnectRetryCount=3` yields 4×3=12 attempts) ([Working with Transient Errors — Azure SQL](https://learn.microsoft.com/en-us/azure/azure-sql/database/troubleshoot-common-connectivity-issues?view=azuresql)).
3. **Sizing** — a serverless resume can take ~45–60s and the driver can still time out even with retry unless count/interval and `Connect Timeout` are sized to cover the full resume window ([dotnet/SqlClient #1957](https://github.com/dotnet/SqlClient/issues/1957)).

### Chosen direction (engineer's decision, 2026-07-22)

Upgrade Microsoft.Data.SqlClient to 5.x (overriding the EF Core 6 transitive 2.1.4 via an explicit `PackageReference`), then activate the `ConnectRetryCount`/`ConnectRetryInterval` connection-string configuration on the `NormalizedDatabaseConnection` across all four harvester environments — MX and CO, staging and production (the four ECR/deploy targets in `.github/workflows/build.yaml`). The existing `OpenWithBackoff` is to be removed as part of the same change so the driver-native retry is the single retry layer (constraint 2 above). The exact retry values come from Atento (see open items).

This corresponds to **Option E's spirit realized at the client/driver boundary** rather than the harvester's manual-retry code — it is a distinct, better-grounded path than the original Options A–F, which were framed before the meeting confirmed the serverless database, the version gap, and the client-supplied config.

### Open items before/during implementation

1. **`ConnectRetryCount` / `ConnectRetryInterval` values — 4Shark's to choose, NOT an Atento dependency.** The mechanism is already known (Finding 14) and the values are simply sized to cover the serverless resume window (~45–60s, Finding 7) — e.g. a count × interval product that spans it, with `Connect Timeout` set per attempt. Atento offered the numbers they happen to use, but nothing here is blocked on them: the `NormalizedDatabaseConnection` strings live in 4Shark's own SSM/task-definitions (the harvester runs in 4Shark's AWS account), so 4Shark appends the keywords to its own connection strings. No value, credential, or action is required from Atento for this path.
2. **EF Core 6 ↔ SqlClient 5.x compatibility** — verify before merging. Known risk: SqlClient 4.0+ changed the `Encrypt` connection-string default from `false` to `true`, which can break an existing connection that lacks a valid server certificate; the connection strings may need `Encrypt`/`TrustServerCertificate` set explicitly. Verify against the actual normalized-base connection strings.
3. **`OpenWithBackoff` removal** — confirm removal (vs. keep) once the driver-native retry is validated, to avoid the compounding-retries trap.
4. **The four environments' connection strings** — confirm how each is provisioned (SSM / task-definition env var) so the retry keywords land in all four `NormalizedDatabaseConnection` values, not only the code image (which is identical across all four).
5. **Fix the misleading comment** at `Services/SimplexHarvesterService.cs:70-71` (Finding 11) when the code is touched.

---

## Resolution — 2026-07-22 (implemented + validated in staging)

### What shipped (three merged PRs)

1. **simplex-harvester #41** — upgraded `Microsoft.Data.SqlClient` to the 5.1 LTS line via an explicit `PackageReference` (overriding the EF Core 6 transitive 2.1.4), added `ConnectRetryCount=10` / `ConnectRetryInterval=10` on the normalized-base connection (sized to cover the ~45–60s serverless resume window), and removed the manual `OpenWithBackoff` / `EnsureDatabaseConnectivity` / `ConnectionRetryBackoffSeconds` so the driver-native retry is the single retry layer.
2. **terraform #808** — fixed the staging harvester task definitions (`compute_harvester_staging.tf`), whose `secrets` injected the two connection strings under the env-var names `ConnectionString_Simplex` / `ConnectionString_4Shark`, while the app reads `SimplexConnection` / `NormalizedDatabaseConnection`. The mismatch made both connection strings resolve empty (error 40, "server not found"). Renamed to match the app/production. Values untouched (they stay in SSM, referenced by ARN).
3. **simplex-harvester #42** — reverted the encryption adoption: set `Encrypt=false` on both connections. Rationale below.

### The encryption lesson (supersedes the earlier "adopt encryption" decision)

The SqlClient 5.x upgrade flips the `Encrypt` connection-string default from false to true. Adopting encryption (`Encrypt=true` + `TrustServerCertificate=true` on the source) was tried first, and a staging run surfaced error 35 — *"a connection was successfully established with the server, but then an error occurred during the pre-login handshake … connection reset by peer"*. The fleet's SQL Servers are legacy Windows instances with no TLS configured; they reset the connection during the encrypted pre-login handshake. `TrustServerCertificate` does not help — it skips certificate *validation*, not the handshake itself. The only working setting against a server with no TLS is `Encrypt=false` (the pre-upgrade default that connected for years). Encryption across this mixed fleet (legacy VMs + Azure serverless) would need per-environment config, not a static flag — deferred as a separate effort.

### Staging validation (2026-07-22, on-demand `aws ecs run-task`, mx)

After all three PRs, a staging run of `integrator-atento-harvester-mx-staging` connected to **both** databases and ran the full ETL: the source stored proc returned 9072 rows, the normalized base loaded 9867 users, and the run proceeded through the company loop creating/reactivating users. Both connection errors (40 server-not-found, 35 handshake) are gone. The remaining log entries are source-data-quality issues the ETL already handles per-record and continues past (duplicate register id — SQL error 2601; a record with no source external_id) — not connection/timeout errors, not regressions.

**What staging did NOT prove:** the serverless resume itself. The staging normalized base is a fixed VM SQL Server (always on), not Azure serverless, so it never pauses — the `ConnectRetry` resume path was not exercised. That behaviour, and the original timeout, only occur in **production**, whose normalized base is the Azure serverless instance that auto-pauses.

### How the fix actually works (clarification)

The mechanism is not a proactive "pre-warm". When the paused serverless base is hit, the first connection gets a resume-in-progress signal; SqlClient 5.x's `ConnectRetryCount`/`ConnectRetryInterval` retries the open *inside the driver* until the resume completes (within the ~100s the 10×10 sizing covers). Net effect is what the engineer wanted — the first daily connection no longer fails — but by retry-until-resumed, not by warming the server ahead of time.

### Pending

1. **~~Cut a release to `master`~~ — DONE (2026-07-22).** Release `1.3.1` shipped via HubFlow (PR #43 merged to master, tag `1.3.1` created, back-merged to develop). The master build completed successfully, so the production ECR images (`integrator-atento-harvester-{mx,co}:latest`) now carry the fix; the next scheduled 03:30 cron run picks them up.
2. **~~TASK FOR TOMORROW — verify the production 03:30 run.~~ DONE — CONFIRMED FIXED (2026-07-23).** Both production runs completed cleanly against the actually-pausing Azure serverless base, with no connection timeout, no handshake error, and no aborted run:
   - **MX** — `Inicio` 09:30:51 UTC → `Fin` 09:51:48 UTC (~21 min). No error 35/40, no `Fin (aborted)`.
   - **CO** — `Inicio` 08:30:35 UTC → `Fin` 08:45:19 UTC (~15 min). No error 35/40, no `Fin (aborted)`.
   - The integrator downstream consumed both results, corroborating that the harvester ran and wrote successfully. The only log noise is expected per-record source-data handling (duplicate register ids, hierarchy rows with no valid parent falling back to admin) — none of it connection-related.

**Outcome: the serverless first-connection timeout is resolved in production.** The fix (SqlClient 5.1 upgrade + driver-native ConnectRetry, secret-name correction, Encrypt=false for the legacy TLS-less servers) is validated end-to-end. This spike is complete.
