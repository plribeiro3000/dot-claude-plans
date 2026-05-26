# What the integrator is and why it exists

The integrator is the side of the integration that 4Shark owns. Every customer integration has two sides — the customer's data systems on one end, the 4Shark API on the other. Most platforms expose only the API and leave the bridge to the customer. 4Shark builds and operates the bridge as part of the product, because the customers we serve **could not build it themselves**.

## The two sides of an integration

A 4Shark customer is a sales-driven organization with a population of employees whose performance is measured against goals and rewarded with variable compensation. Their operational data — who works where, who reports to whom, what each person sold, which products are in catalog, which goals apply to which roles — already lives in their own systems. The customer's existing ERP, CRM, payroll, ticketing, and bespoke spreadsheets are the **source of truth** for that data.

The 4Shark platform consumes that data to compute commissions, track progress against goals, and feed the mobile and web apps the employees use. The platform's own database is **not** a system of record — it is a system of derived state, fed continuously from the customer's source.

The integrator's job is to keep the platform's view in sync with the customer's reality.

## Who 4Shark customers are

This is the central fact that shapes everything that follows: **4Shark customers do not have engineering teams capable of building integrations.**

The persona is large enterprise — workforces in the tens of thousands, often spread across many subsidiaries — operating in industries where commission is a major component of pay (retail, financial services, telecom, call centers, distribution). They are **technology consumers, not technology builders.** They buy software; they do not write it. Where IT exists at all, it is contractually outsourced or focused entirely on running purchased systems and keeping desktops alive.

A common counter-question is "why don't they just build a commissions system in-house, then?" The answer is that companies that *do* have engineering teams typically **do** build it in-house — a commissions calculator for a single firm, with rules everyone in the room already understands, is not a hard product to build. The hard product is the *flexible* one that absorbs every variation across an industry. That is what 4Shark sells, and it is precisely what the in-house engineering shop does not need. So the market for 4Shark is the segment of large enterprises who lack the engineering capability to roll their own.

What these customers **do** have, almost universally, is an MIS function — a small team whose entire daily work is extracting data from internal databases, cross-referencing across systems, and producing Excel reports for the rest of the business. They know SQL well, they know the customer's data schema intimately, and they are accustomed to writing extract scripts as part of their normal job.

This MIS team was the integration's original entry point on the customer side, and it remains the most common path. The 4Shark contract asks them to do exactly the kind of work they already do for internal reports — query the upstream systems and write the result into a target schema — but instead of writing into an Excel sheet for an internal stakeholder, they write into the **normalized database** the integrator will read.

That shape is where the integrator started, and it explains why the codebase still treats the normalized database as the canonical case. But over time, customers arrived who couldn't fit the mold — the system that holds their commission-relevant data is a SaaS product they don't control (so no SQL agent, no normalized table to populate), or it exposes a REST API but no usable database, or their internal IT *can* expose a custom-shaped database but won't agree to a normalized intermediate. The integrator absorbed those cases by generalizing the source side: any SQL-reachable database with a custom query, any REST API returning JSON, and a path open for future source types (FTP, message queues, S3 drops). The MIS-team-plus-normalized-database flow is one option in a wider menu now, not the only one.

The 4Shark side of the integration is thus designed around capabilities the customer already has — whether that is "an MIS team that can populate a target schema" or "an existing REST API the customer's vendor exposes" — not around a capability they would need to build.

## Why 4Shark builds the bridge

Given the persona, leaving the bridge to the customer is not an option — there is no engineering team on the other side to build it. So 4Shark builds it. The decision is forced by the market segment we serve.

Two derivative benefits make the choice work in practice:

- **Iteration freedom.** Changes to the API contract, new resource types, new validation rules — these can roll out across the entire customer base without coordinating a release with each customer's IT department. The integrator absorbs the delta on 4Shark's release cadence, not the customer's.
- **End-to-end positioning.** 4Shark is sold as a complete service — "your data flowing into our platform" — not as a platform with a bring-your-own-client clause. Owning the integrator is what makes that promise deliverable.

## What the integrator is, operationally

An integrator instance is a Rails application running on 4Shark's infrastructure (ECS Fargate, in 4Shark's AWS accounts), configured to talk to one customer's data source on one side and the 4Shark API on the other. The same codebase serves every customer; the difference between two customer instances is purely **configuration data** stored in the integrator's own MongoDB:

- Which Source(s) the integrator should read from (a normalized SQL database, an HTTP API, an FTP drop)
- How each Source authenticates (username/password, OAuth token, certificate)
- Which Streams the Source supplies (one Stream per resource type the customer integrates — Subsidiaries, Users, Deals, Goals, etc.)
- For each Stream: the query template (or the API endpoint), the field mappings (which source column becomes which API attribute), the sensitive keys to mask in logs, the pagination shape

The integrator runs the customer's integration on a fixed schedule — pulling the latest data, transforming it into 4Shark API payloads, and pushing it through the API. Failures, partial runs, throttling, and recovery are all the integrator's responsibility; the customer never sees them and the 4Shark API never has to know which customer the call is coming from beyond the authenticated company context.

## What the integrator is not

It is **not multi-tenant.** A 4Shark deployment for a customer is a dedicated integrator instance with its own MongoDB, its own Redis, its own VPN tunnel into the customer's network when needed. Two customers do not share an integrator process; their data does not share a database; an outage on one customer's integrator does not affect any other customer.

It is **not running on the customer's infrastructure.** The integrator is hosted by 4Shark, in 4Shark's cloud accounts. The customer never operates the integrator, never reads its logs, never accesses its database. The boundary between customer and platform sits at the data source the customer exposes — everything past that boundary is 4Shark's operational responsibility.

It is **not an authoritative system.** The integrator does not invent business rules, does not enrich data with conclusions of its own, does not arbitrate when the customer's data and the platform's data disagree. When there is a conflict, the customer's source wins — the integrator pushes whatever the source says, and the API rejects what it cannot accept. The integrator's only "smart" behavior is the per-stream transformer pipeline that reshapes data into the API contract; everything else is mechanical forwarding.

## The contract with the customer

The customer's commitment is narrow and explicit: **expose your data in a stable, queryable shape, and we'll do the rest.** Concretely, this is one of:

- A **normalized SQL database** with a fixed schema agreed during onboarding (a set of tables — `users`, `subsidiaries`, `hierarchy`, `deals`, etc. — that the integrator's bootstrap script knows how to read). The customer's MIS team populates this database from whatever upstream systems they have; the integrator reads from it on its schedule. This is the path the project started with and remains the most common, because it maps directly onto the MIS team's existing skill set.
- A **custom database query** against the customer's own existing schema, where the customer cannot or will not produce a normalized intermediate. The integrator's Stream configuration carries a SQL template that joins and projects whatever columns are needed. More fragile — every change to the customer's schema becomes a configuration update on the integrator side — but flexible.
- A **REST API** the customer already exposes for their own purposes, where the integrator polls endpoints and parses responses. Same trade-offs as the custom database query.
- A **future source type** (FTP, Kafka, S3 drops, etc.) — the architecture is designed to absorb new source types without a code rewrite.

The customer is responsible for the truth of what they expose. If their `users` table contains a row that should not be there, the integrator will faithfully push it to the API. If their `deals` table has duplicate rows, the API will see duplicates. The integrator is a pipe; the customer is the source.

In return, **4Shark is responsible for everything past that boundary**: catching schema drift, retrying transient failures, masking sensitive data in logs, alerting on sustained failure, scheduling the runs, paying for the infrastructure, scaling up and down, deploying new versions when the API contract changes, reading the integrator's logs at 2 AM when a job fails, and explaining to the customer why their data did or did not show up in their dashboard.

## Why the customer doesn't run the integrator

Even hypothetically — if a customer asked us to ship the integrator as software they could run themselves — we would refuse. Two reasons:

- **The integrator encodes 4Shark's per-customer integration logic.** It is written in Ruby (no compilation, no obfuscation), and the configuration data drives a transformer pipeline that decides how each customer's data shape becomes a valid 4Shark API payload. Putting the running code on the customer's side would expose every mapping decision, every workaround, every domain-specific transformation 4Shark has built up over years of onboarding. That intellectual capital is exactly what differentiates 4Shark from "a commissions API"; we don't ship it to the customer.
- **The customer has no operations team to run it.** A Rails application is not a turnkey appliance. It needs a Sidekiq worker fleet, a MongoDB instance, a Redis instance, a deploy pipeline, monitoring, alerting, on-call rotation, capacity planning, security patching. The customer persona has none of these capabilities. An outage on a customer-hosted integrator would extend for days before anyone noticed; "the dashboard hasn't been updating" is the kind of signal a customer organization without IT only catches at the end-of-month commission close, after a week of bad data has piled up. Hosting the integrator ourselves means the on-call engineer who notices the failure is also the engineer who can fix it, on the same call.

These two reasons reinforce the persona discussion above: the customer cannot build the integrator, and they cannot operate it either. 4Shark does both.

## How this chapter sets up the rest of the document

The remaining chapters describe how the integrator works end to end:

- **Chapter 2** covers topology — the per-customer-per-environment isolation model that makes "one instance per customer" practical
- **Chapter 3** describes the unified pipeline — one Job per run, three stages (Extract → Transform → Load), no central coordinator
- **Chapter 4** walks through the fixed sequence of 25 Streams the pipeline executes for a normalized customer, with the rationale for the order
- **Chapter 5** covers the configuration surface — Source, Stream, ResourceType, AttributeMapping — that turns "one customer's integration" from a code change into a data change
- **Chapter 6** dives into source data access — how the integrator reads from a customer's database without reopening connections per query
- **Chapter 7** covers identifier handling — how the integrator generates the customer-side identifiers the 4Shark API expects
- **Chapter 8** describes the transformer pipeline — how a row from the customer's source becomes the JSON body the API consumes
- **Chapter 9** covers Mongoid storage — how every Resource, Import, and Request is preserved as an audit trail
- **Chapter 10** explains the Redis-backed Computation primitive that coordinates multi-stream stages
- **Chapter 11** covers pre-flight — SourceCheck, StreamCheck, AvailabilityCheck — the early-failure layer
- **Chapter 12** describes the normalized database contract and the bootstrap task that creates a customer's configuration from scratch
- **Chapter 13** closes with the Resource lifecycle — pending → integrated → disabled → erased and the transitions between them

Each chapter answers "why does this exist" in domain terms. Implementation details appear only as far as they reveal a decision that mattered.
