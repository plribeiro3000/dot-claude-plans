# Variable as referenced-but-not-managed registry

Variable is the most-referenced concept in the API surface and yet has no endpoint. Goal, Indicator, and DealField all carry a `variable` (or `variable` in nested attributes) in their payloads — but the client cannot create, update, or delete a Variable through any API call. Variables must already exist on the server before any of those payloads will succeed.

## What a Variable represents

A Variable is the platform's name for a measurable quantity that can participate in commission rules. Examples: `sales_target` (a number representing total sales over a period), `installation_count` (how many installations a technician completed), `nps_score` (a customer satisfaction metric). Each Variable has a key (the string the client references), a type (number, percentage, duration, date), a metric/no-metric flag, and a few format rules.

A Variable is configuration, not data. A client's plan structure is built on a small set of Variables defined at onboarding time; each Goal is a target for a Variable, each Indicator is a measurement of a Variable, each DealField is the value of a Variable on a specific Deal.

## Why no endpoint

Two reasons:

1. **Variables are not high-volume**. A typical client has a few dozen Variables, defined once and rarely changed. Building an API for something that runs once per year would be effort with no payoff.
2. **Variables couple to commission logic** in ways the client cannot self-service. Adding a new Variable means deciding its type, deciding whether it has a Metric (a unit of aggregation), deciding which calculation modules can read it, and updating the client's plans/rules to use it. None of those decisions can be made in isolation by an integration script.

The 4Shark team creates Variables on behalf of the client through internal tools, as part of onboarding or whenever the client requests new metrics.

## How Variables surface in the API

Every endpoint that references a Variable does so by `key` (a string the client agreed on). The controller resolves the key to the internal Variable row using a lookup; if the key is unknown, the lookup returns nil and the call rejects.

| Endpoint | Variable role |
|---|---|
| Goal create/update | `variable` key — the metric the goal targets |
| Indicator create/update | `variable` key — the metric the indicator measures |
| Deal create/update (nested fields) | `variable` key per DealField — the metric the field corresponds to |

The Variable's type drives what is acceptable as the corresponding `value`. A date-typed Variable rejects a non-ISO 8601 value. A number-typed Variable rejects a string that does not parse as numeric. The client's payload is validated against the Variable's contract at write time.

## Implication for the integrator and for client onboarding

The integrator cannot bootstrap a fresh client end-to-end via the API alone. Before any Goal, Indicator, or DealField call can succeed, the 4Shark team must have created the Variables the client's plan references. This is a coordination point that has burned multiple onboardings:

- The integrator team is configured with a list of Variables to use
- The 4Shark plan team configures the plan with a (possibly different) list of Variables
- The two lists drift, and the first integration run rejects half the calls because the Variable keys don't match

A drift in this dimension surfaces as cascading rejection: every call referencing the missing Variable rejects, the dependent calls (Goal → Indicator → calculation) cannot proceed, and the client sees no data for the affected metric. Diagnosis is a single Variable lookup; fix is a single Variable creation; but the symptom looks like a deep failure.

The runbook in the connector deliverable will cover how to diagnose this class of drift quickly: "if a payload references a `variable` key and rejects with `:invalid` or a `nil` foreign key error, check first whether the Variable exists on the server".
