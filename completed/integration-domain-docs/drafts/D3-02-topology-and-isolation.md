# Topology and isolation

The integrator deployment model is one isolated stack per customer per environment. There is no shared infrastructure, no multi-tenancy, no cross-customer process. Whatever scaling, fault, or breach affects one customer stops at that customer's boundary.

## The unit of deployment

A 4Shark customer in production gets a dedicated stack:

- One **ECS cluster** with the integrator's Sidekiq + web processes
- One **MongoDB replica set** holding the customer's configuration (Sources, Streams, Authentications) and the customer's audit trail (Resources, Imports, Requests)
- One **Redis instance** for Sidekiq queues, the `Computation` primitive, and the `Lock` primitive
- One **VPN tunnel** into the customer's network when their data source is not internet-reachable
- One set of **secrets** (AWS Secrets Manager + Terraform-managed SSM parameters) holding the customer's database credentials, API tokens, and certificates

Every artifact above is provisioned per customer per environment via Terraform stacks in the `terraform` repository. The same set is duplicated for staging — when staging exists for a given customer, which is not always — using a separate Terraform stack with the same shape and different parameters.

The integrator codebase is the same across all customers. What makes "the Commcenter integrator" different from "the Atento integrator" is the configuration data in MongoDB, the credentials in Secrets Manager, and the customer-specific environment variables (timezone, page sizes, table prefix, etc.) injected at deploy time.

## Why isolation

The choice of one stack per customer is deliberate. The alternatives (shared cluster with logical tenancy, single multi-tenant database, etc.) were never implemented. The reasons:

- **Data confidentiality.** Each customer's commission data is sensitive — names, salaries, performance metrics, organizational hierarchies. No customer wants their data sharing a database with a competitor's. The simplest answer to "is my data isolated from other customers?" is "yes, it's in a different database in a different VPC", and the simplest path to that answer is to actually do it that way.
- **Blast radius.** A bug in the integrator that corrupts MongoDB, exhausts Redis memory, or floods Sidekiq affects only that customer's stack. A noisy neighbor on the customer side (sudden 10× data volume) saturates only that customer's workers. There is no scenario where one customer's incident becomes another customer's incident.
- **Per-customer scaling.** Customer load profiles are heterogeneous. A retailer running a Black Friday campaign has a one-day spike of two orders of magnitude over baseline; a financial firm has a one-day spike at month close; a call center has steady continuous load. Per-customer ECS clusters can scale up and down independently, optimizing infrastructure cost to actual demand.
- **Per-customer release control.** Most of the time every customer runs the same integrator version. But a customer-specific bug fix can be deployed to that customer's stack only, validated, then rolled out across the fleet. Hotfixes do not have to be either "all customers at once" or "wait for the next release train".
- **Per-customer credential boundary.** A breach of one customer's database credentials does not transitively expose other customers' credentials. Each Secrets Manager scope is per-customer.

## What is shared

Three things are explicitly **not** per-customer:

- **The 4Shark API.** All integrators talk to the same API endpoints. The API tells customers apart by the authenticated company token in each request; the integrator does not invoke a customer-specific API surface. From the API's perspective, the integrator is just one more API client.
- **The Terraform module that defines the stack shape.** A single module (`integrator` in the terraform repo) generates every customer's stack. Per-customer stacks differ only in parameters — instance sizes, VPC CIDRs, customer name, environment. Adding a customer is creating a new Terraform stack file with the right inputs and applying it.
- **The CI/CD pipeline.** GitHub Actions builds the integrator image once and pushes it to a shared ECR. Each customer's deploy is an ECS service update pointing the customer's ECS cluster at the new image tag. There is no per-customer build.

This split — shared codebase + shared API + shared deploy pipeline + shared Terraform module, but per-customer running stack — is what keeps the per-customer cost manageable. The expensive parts (engineering the integrator, defining the API contract, designing the deploy pipeline) are paid once. The replicated parts (ECS cluster, MongoDB, Redis) are commodity infrastructure that AWS provisions in minutes.

## Network isolation

All integrator infrastructure is accessible only inside the 4Shark internal VPN. The ECS cluster has no public ingress; the MongoDB and Redis instances are in private subnets with security groups restricted to the cluster; logs and metrics flow to internal Datadog/CloudWatch endpoints. Engineers reaching the integrator stacks for operational work (logs, console, manual triggers) do so through the VPN.

The only public-facing endpoint per customer stack is the VPN concentrator on the customer's side (when applicable) — the channel through which the integrator reaches the customer's data source. Even that is restricted to the integrator's egress IPs and is established as a site-to-site tunnel, not as an open ingress.

## How customer stacks are addressed operationally

Each ECS cluster carries AWS tags that make it discoverable without keeping a separate inventory:

- `Project=integrator` — distinguishes integrator clusters from other 4Shark services
- `Client=<customer-name>` — the customer this cluster belongs to
- `Environment=<env>` — `production` or `staging`

Operational tooling (the `/integrators` slash command, monitoring filters, log queries) discovers the right cluster by querying AWS by tag rather than by hardcoded names. The cluster name is a derived value (e.g., `integrator-commcenter-production`); the source of truth is the tags. This matters because customer names change (rebranding, mergers), and naming-by-tag means a rename is a metadata update, not a stack rebuild.

## Connecting to the customer's source

The integrator reads from the customer's data system on every job. The connection model depends on what the customer exposes:

- **Customer-hosted database in their own datacenter.** Reached via a site-to-site VPN tunnel from the integrator's VPC to the customer's network. This is the most common path historically — large enterprises run their own SQL Server or Oracle instances inside their corporate network and won't expose them to the internet.
- **Customer-hosted database with public access.** Less common; some customers host their normalized database on AWS or Azure with a public endpoint and a strict allowlist for the integrator's egress IPs. Faster to set up but rarer because the customer security team usually rejects "public + allowlist" in favor of VPN.
- **Customer SaaS with a public REST API.** The customer's commission-relevant data lives in a SaaS product that already exposes an authenticated API (Salesforce, Trackmob, others). The integrator reaches the SaaS endpoint over the public internet using the customer's API credentials. No VPN needed.
- **Customer SaaS with no API.** Out of scope by definition — if the data is in a SaaS that doesn't expose data, the integration cannot exist as built today. The customer must arrange to export from the SaaS into a secondary store the integrator can reach.

The MongoDB on the integrator side is **always** internal to the integrator's stack, regardless of where the customer's source lives. The integrator's own audit trail and configuration never leave 4Shark's infrastructure.

## Why one stack per environment, not per customer

A common question during onboarding is whether staging is per-customer or shared. The answer is per-customer when staging exists. The reason is the same as production: staging tests the customer-specific configuration, not the codebase. Staging integrators connect to staging copies of the customer's data source, push to a staging API instance, and run with the same per-customer Streams, Mappings, and AttributeMappings as production. A shared staging would force every customer's configuration into one MongoDB and obscure exactly the per-customer concerns staging is meant to validate.

In practice, not every customer has staging — small customers run only production, accepting that any change is validated in production after a careful manual review. Larger customers (where a bad commission run can cost weeks of reconciliation) have staging by default.

## Summary

A customer integration is, infrastructurally, an entirely separate deployment of the integrator codebase, with its own data, its own credentials, its own scaling, its own release cadence when needed, and its own connection back to the customer's source. The codebase, the API, the Terraform module, and the deploy pipeline are shared. Everything else is per-customer.
