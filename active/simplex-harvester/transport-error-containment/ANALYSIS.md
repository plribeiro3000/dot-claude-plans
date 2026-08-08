# Simplex Harvester — a transport-level connection drop aborted a company's update pass (2026-08-07)

Handoff record for the incident of 2026-08-07 and the two releases that followed. Written so a cold reader (or a new session) can pick up the open items without re-deriving anything.

## What happened

The daily run raised `Microsoft.Data.SqlClient.SqlException: A transport-level error has occurred when receiving results from the server. (provider: TCP Provider, error: 35 - An internal exception was caught)` at `Services/SimplexHarvesterService.cs:1869` (pre-fix line numbering), inside `LoadUpdates`, while `ToDictionary` materialised the per-user `fsk_user_fields` read.

Rollbar's raw payload gave the full chain, which the message alone hides: `SqlException` → `System.IO.IOException` *"Unable to read data from the transport connection: Connection reset by peer."* → `System.Net.Sockets.SocketException` *"Connection reset by peer"*. Error 35 is the managed-SNI wrapper code (`An internal exception was caught`), not a SQL Server error — the same signature reported in `dotnet/SqlClient` [#3052](https://github.com/dotnet/SqlClient/issues/3052) and [#2103](https://github.com/dotnet/SqlClient/issues/2103), both open with no maintainer-confirmed root cause.

**Blast radius.** The exception reached `Load`'s per-company catch, which logs, reports to Rollbar, and lets the `foreach` continue to the next company. So for the company that failed: `LoadFskUsers`, `EnsureAdmins`, `LoadNuevos` (creations and reactivations) and `ProcessTerminations` had already run and committed, because they precede `LoadUpdates` in the sequence; inside `LoadUpdates`, the users iterated before the failing one received their hierarchy and field updates; from that user onward the company got nothing. Every other company ran normally.

**Trap worth remembering — the integrator's run email does not contradict this, and cannot confirm it either.** That report (`Versión del Integrador`, `Versión de la base normalizada`) belongs to a different system: the harvester reads the customer's Simplex source and writes the normalized base, and the integrator reads the normalized base and pushes to the app. A `163 / 163 / 100%` from the integrator means everything it *found* was delivered. It has no way to see updates the harvester never wrote, so a 100% there is evidence about delivery, never about completeness.

## Why no manual correction was needed

The harvester reconciles in full on every run rather than consuming a delta, which is what makes the next run recover whatever was skipped. Two facts carry that:

`LoadJearquia` pulls the whole hierarchy with no watermark parameter — `Services/SimplexHarvesterService.cs:693`:

```csharp
this.jerarquias = dataContext.Jerarquias!.FromSqlInterpolated($"EXEC sp_reporte_jeraquia_4shark @empresa_codigo={companyId}").ToList();
```

And each field is compared against its current value before anything is written — `Services/SimplexHarvesterService.cs:1772-1777`:

```csharp
private void UpdateUserField(DataContext dataContext, Dictionary<string, FskUserField> userFields, int userId, string key, string? value)
{
    userFields.TryGetValue(key, out var fsk);
    bool existencia = fsk != null && fsk.Type.Equals("create");
    this.RealizarCambio(fsk, existencia, userId, key, value, dataContext);
}
```

`RealizarCambio` writes only when the value actually differs, and `UpdateUserHierarchy` compares the current parent and type against the computed ones. Once the missing update lands in the normalized base, the integrator picks it up on its next pass through its own `Búsqueda de registros desde` watermark.

## The code defect — the asymmetry, not the connection

The dropped connection is external and unexplained upstream. The defect that turned one network blip into a company-wide loss is that **the field read was the only call in the loop body without per-record containment**. `UpdateUserHierarchy` catches and returns `"error"` (`:1636-1662`), and each of the seven `UpdateX` helpers catches, logs a tab-separated line and continues. Only the read propagated.

**EF's retry was already enabled and deliberately did not fire.** Both contexts call `EnableRetryOnFailure` (`Helpers/UtilHelper.cs:48` and `:71`). EF Core's `ExecutionStrategy` has exactly two exits: a failure its detector classifies as transient is retried internally and, once the budget is spent, rethrown wrapped in `RetryLimitExceededException`; a failure it does not classify is rethrown raw via `throw;` on the first occurrence and never retried. The Rollbar `trace_chain` begins with the bare `SqlException` and carries no wrapper, so this error took the second exit. Whatever its number is, it is not in EF's transient list — which already contains `10054`, `10053`, `121`, `64`, `233` and `10060`.

**Trap worth remembering — `ConnectRetryCount` is not the knob for this failure.** It is idle-connection resiliency: it reconnects a broken *idle* connection and does not apply to a connection that breaks during active command execution with pending results, which is where this one broke (reading the first result packet).

## What was shipped — 1.4.1

Per-record containment on the field read, following the shape the loop already used. The read was moved below the role dispatch and `UpdateArea`, neither of which takes `userFields`, so a failed read costs the user only the six updates that depend on it. Consequence accepted: a user whose read then fails is counted in both its action bucket and `field_read_error`, so the buckets no longer sum to the user count.

`field_read_error` is its own counter rather than part of `error`, because `error` already means the hierarchy write failed *and the field updates still ran* — folding them together would make the summary line unreadable.

A ceiling of ten consecutive failed reads rethrows, so a database that is gone aborts the company instead of walking the remaining population logging one failure per user and finishing with nothing done. The summary line is logged immediately before that rethrow, tagged `(abortado)`, because the rethrow leaves the method before the summary at the end of it — and what would otherwise be lost is the count of users processed **successfully** before the outage, which the per-record error lines cannot give.

Rollbar receives at most one event per company for this failure class (a method-local flag), plus a second one from the per-company catch when the ceiling aborts. Without that flag the containment would have removed this failure class from Rollbar entirely: the per-company catch is the only other reporting site on this path, and the injected Serilog logger writes to stdout alone.

`RollbarReporter.Report` was widened from `catch (TimeoutException)` to `catch (Exception)` and now logs the reporting failure. The widening is required because this branch introduced the first call site inside a containment handler, where anything escaping the report would abort the company — the outcome that handler exists to prevent. `Serilog.ILogger` is qualified there because `using Rollbar` brings its own `ILogger` into scope in that file (`CS0104` otherwise).

`UtilHelper.DescribeSqlErrors` was made public and wired into both catches that see this failure class, so the next occurrence records `number` / `class` / `state` per entry of the `Errors` collection instead of stopping at the provider's wrapper text.

## A retry helper was written and removed — the expensive lesson

A `ReadWithRetry<T>(Func<T> read, string operation)` helper with `Thread.Sleep` was added mid-work and then deleted. It was a near-exact recreation of `OpenWithBackoff(string label, Func<DataContext> contextFactory)` and its `ConnectionRetryBackoffSeconds = { 30, 60, 120, 240 }` array — same signature shape, same `catch (SqlException)` + `_logger.Warning` + `Thread.Sleep` body — which commit `c20d8cc` (2026-07-22, *"fix(harvester): resume the auto-paused database via driver connection retry"*) deliberately removed in favour of connection-string configuration (`ConnectRetryCount` / `ConnectRetryInterval`) plus a `SqlRetryLogicOption` provider.

**Retry policy in this repository is configuration on the driver and on EF, never a loop in the code.** A future session that reaches for a retry loop here is undoing that decision.

**Where retry belongs if it is ever revisited**, and why it is not free: `EnableRetryOnFailure(maxRetryCount, maxRetryDelay, errorNumbersToAdd)`. That collection applies to the whole context and therefore to the writes as well, and `Helpers/UtilHelper.cs:24-28` already reasons through the same trade-off for `-2`, keeping it on the connection open alone because a command-side retry can replay a call the server already applied.

The summary log is **repeated** at the two exits rather than extracted into a method. § No Premature DRY puts the Rule of Three as the minimum and calls two occurrences too early, and this file already carries seven near-identical tab-separated error lines. A `try`/`finally` around the loop was rejected for re-indenting ~120 lines to avoid duplicating five, and breaking out of the loop to rethrow after the existing summary would need `ExceptionDispatchInfo`, because `throw;` preserves the original stack only inside the `catch`.

## The CI block, and the release that closed it — 1.5.0

The hotfix PR could not merge normally. `Verify Minimum Age` sat `pending` with **zero statuses reported and zero workflow runs on the branch** — it was never failing, it never ran. `verify-minimum-age.yaml` existed only on `develop`, while the hotfix was cut from `master`, which carried only `build.yaml`. For the `pull_request` event the workflow file comes from the PR's own ref; only `pull_request_target` takes it from the default branch. Branch protection on `master` requires that context (`app_id` 15368, GitHub Actions), and a required check that is never reported stays pending and blocks the merge.

The daily `reverify-minimum-age.yaml` cron does not rescue this case. Its first step skips any PR whose files touch no `.github/workflows` or `.github/actions` path (`:44-48`), which the hotfix did not.

`1.5.0` carried the four missing files to `master` — `verify-minimum-age.yaml`, `reverify-minimum-age.yaml`, `renovate.yml` and `.github/scripts/verify-minimum-age.sh` — so **this class of block is closed for future hotfixes cut from `master`**. The release PR itself ran the check and passed (*"All 8 SHA-pinned action(s) at or above 7 days"*).

## Deploy — there is nothing to trigger

The repository has no deploy workflow. `build.yaml` builds the image and pushes it to ECR, selecting the destination by branch: `master` publishes the production repositories (`integrator-atento-harvester-{mx,co}`), any other ref publishes the `-staging` pair. Both merges' builds succeeded, so all four ECR repositories carry the new image.

Nothing needs to be applied afterwards. The four task definitions (`integrator-atento-harvester-{mx,co}[-staging]-cron-integration`) reference the mutable tag — verified for MX production as `...integrator-atento-harvester-mx:latest` — and the harvester runs as an ECS **scheduled task**, not a service, so the next cron run starts on the new image. A `run-task` would be an extra off-schedule execution, not a deploy.

## Open items

**1. `SqlException.Number` is still unknown.** It is captured nowhere today: the exception message stops at the provider wrapper, and the error reporter serialized only the `Exception.Data` entries (`HelpLink.ProdName`, `EvtSrc`, `EvtID`, `BaseHelpUrl`, `LinkId`) — `Number` is a property, not a `Data` entry. With `DescribeSqlErrors` now wired into both catches, the next occurrence records it in CloudWatch. That number is the only thing that would settle whether EF's detector could be taught to cover this failure through `errorNumbersToAdd` — subject to the write-replay trade-off above.

**2. Verify the dependency bumps on the first run after deploy.** `1.5.0` carried EF Core `6.0.13` → `6.0.36`, `Microsoft.Data.SqlClient` `5.1.6` → `5.2.3` and `Serilog` `3.1.1` → `4.4.0`. The SqlClient bump moves the driver on the exact connection layer this hotfix corrected, and Serilog is a major. The build compiles clean, which covers API breaks but not behaviour.

**3. Two process rules that cost time here and are not written down.** First, a decision record belongs in the PR body's `## Decisions` block and must not be duplicated as inline review threads — nine were posted that way on the hotfix PR, each of which then had to be replied to and resolved, because they asked nothing. Second, `/pr-triage`'s instruction *"You do not classify non-FPs... everything else stays open"* is written for findings raised by *other* reviewers and does not fit threads the agent authored itself; applying it literally left eleven threads open that the engineer could not act on.

Neither is covered by dot-claude [#504](https://github.com/4shark/dot-claude/pull/504) (*"docs(pr-review): require one inline thread per finding when posting a review"*, merged to `develop` 2026-08-07), which closed the adjacent gap: findings go one inline thread per finding, never a blanket comment enumerating them, and a moved anchor is a reason to recompute line numbers from the current head diff rather than to collapse. That rule lives in `docs/PR-REVIEW-PIPELINE.md`, `scripts/inject-pr-review-pipeline.sh`, `agents/pr-review.md` and the `CLAUDE.md` summary. What it does not say is which findings should have been threads at all.

## Reference

PRs: [#65](https://github.com/4shark/simplex-harvester/pull/65) (hotfix 1.4.1), [#67](https://github.com/4shark/simplex-harvester/pull/67) (release 1.5.0). Tags `1.4.1` (on the hotfix commit) and `1.5.0` (on the `chore(release)` commit), both messaged with the bare version, matching `1.4.0`.

A rendered diagnostic report was written to `/tmp/diagnostic_report_simplex_harvester_transport_error_20260807_071006.html`. It is in `/tmp` and will not survive a reboot — this document is the durable record.
