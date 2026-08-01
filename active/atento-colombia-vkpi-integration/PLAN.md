# PLAN — VKPI Colombia integration

## Objective

Load the VKPI apurado value per person, per indicator, per period into the 4Shark platform as `Indicator` records, through the Colombia integrator's Modifier stream. The integration consumes **one table** — the indicator table. Every other VKPI table is Atento's internal use and out of scope.

## Position

**Atento owns the source database, so Atento fixes the source database.** Every open requirement is a property of a base they build and operate; none of them moves to 4Shark as a workaround. Compensating on our side for a key that does not identify a row would make 4Shark permanently responsible for a structure it does not control, and would hide the defect instead of closing it.

What 4Shark does contribute is the remediation itself: the SQL that creates the unique index, adds the not-null constraint on the value column, and supplies the load procedure that guarantees the date semantics. Handing over working code removes the last reason for the corrections not to land — the execution, and the ownership, stay with Atento.

## Gate

**No effort estimate and no delivery date are issued until the source meets the open requirements.** An estimate given against a base whose key repeats on 98% of its values would be a number invented to satisfy a request, and it would surface as a wrong payroll number rather than as an error.

The commitment stands and is honored: the roadmap is delivered, structured by phases whose durations count from the date the requirements close rather than from an absolute calendar. Santiago already set that expectation in the 29-jul call, stating the effort estimate would come the following Friday rather than that week.

## Requirement status

| Requirement | Status |
|---|---|
| A row is uniquely identifiable at period + person + service + indicator | Open — the proposed key repeats on 98.0% of its values |
| How the supervisor's accumulated value is computed, and by whom | Open — the two options promised in the 29-jul call never arrived, and the sample carries no supervisor rows to infer it from |
| A single person identifier, stable over time | Closed — `NR_RE` is the Simplex code, confirmed in the 29-jul call and consistent with the data |
| `DT_DATA` free of day/month ambiguity | Closed — delivered as `yyyymmdd` |
| One column carrying the indicator value | Closed |
| Per-record creation and update dates | Attention — process recommendation, not a requirement |
| Metas table | Deferred — follow-up after indicators |

## What 4Shark configures on its own side

The meaning of the value — percentage, count, duration, currency — and its calculation mode are **platform configuration**, not a source requirement. The API accepts `value` as a string (`indicators_controller.rb:22-26`) and the `Variable` carries `data_type` and `calculation` (`variable.rb:45-89`); `Indicator` only delegates to it (`indicator.rb:87-92`).

One consequence to carry into Variable registration: `PercentDataType#format` divides by 100 (`percent_data_type.rb:4-8`), so the platform expects a percentage on a 0–100 scale. The VKPI values for ratio-shaped indicators sit in 0–1. Whoever registers each Variable has to look at the indicator's real scale to choose between `PercentDataType` and `NumberDataType`, or a percentage enters a hundred times smaller.

## Phases

**Phase 0 — Remediation by Atento.** Atento executes the handed-over scripts. 4Shark runs the acceptance queries against the base. Phase 0 closes when the three open requirements pass. Duration is Atento's, not ours.

**Phase 1 — Agent-level indicators.** A second non-normalized Source pointing at the VKPI server plus a Modifier stream on the existing Colombia integrator (stack `co`, root mode). Estimated once Phase 0 closes.

**Phase 2 — Supervisor coverage.** Depends on the supervisor rows arriving pre-accumulated.

**Phase 3 — Metas.** Deferred; retaken after indicators close. Consumes `/goals`, never `/indicators`.

## Validation 4Shark owes itself before estimating Phase 1

Cross the 3,535 distinct `NR_RE` in the sample against the Colombia normalized base. The integrator runs in root mode, so an `NR_RE` that does not resolve is a rejected row. The identifier itself is settled — Andrés confirmed in the 29-jul call that `NR_RE` is the Simplex code the platform already receives, and the data corroborates it: a 4-to-6-digit internal code ranging 3,433 to 129,053, distinct from the document in every row, 1:1 with it, none empty. What remains is confirming they all resolve to existing users, which is a query, not a question.

## Decisions that belong to 4Shark

**Negative indicator values.** 272 rows are negative, 267 of them NPS. Accept them — the Modifier value is signed and NPS is negative by definition of the metric.

**Terminated employees.** 1,409 rows carry a termination marker. Import them. A person terminated mid-month still earns commission for that month, and excluding their indicators produces a wrong final settlement — on the one payment that cannot be corrected afterwards.

**Supervisor scope in Phase 1.** Whether supervisor coverage is contractually required in the first delivery decides whether it gates Phase 1 or only Phase 2. Engineer and commercial, not technical.

## Risks

The dominant risk is schedule pressure converting into a premature estimate. Atento has asked for effort and dates before the source is integrable, and the pressure will repeat in the next session. The mitigation is the gate above, held consistently and stated constructively: 4Shark wants to build, has said what is missing twice, and is now supplying the code — the remaining step is theirs.
