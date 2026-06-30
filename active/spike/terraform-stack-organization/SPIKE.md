# SPIKE — Terraform Stack Organization: GA4 Access Gate Placement

## Investigation question

Should the GCP-only GA4 access gate (service account + IAM tokenCreator + GA Admin API
enablement) live in the existing `monitoring` stack (AWS + Rollbar providers, no GCP), or
in a new dedicated GCP stack? The GA4 properties themselves are not Terraform-managed.

## Sources consulted

- [HashiCorp — Refactor monolithic Terraform configuration](https://developer.hashicorp.com/terraform/tutorials/modules/organize-configuration) — blast radius and state separation rationale
- [HashiCorp — Providers Within Modules](https://developer.hashicorp.com/terraform/language/modules/develop/providers) — multi-provider configuration mechanics
- [Google Cloud — Best practices for root modules](https://docs.cloud.google.com/docs/terraform/best-practices/root-modules) — resource count and separation by application boundary
- [Spacelift — Multi-Cloud Provisioning and Management with Terraform](https://spacelift.io/blog/terraform-multi-cloud) — credential blast radius quote
- [AWS — The Difference Between Monitoring and Observability](https://aws.amazon.com/compare/the-difference-between-monitoring-and-observability/) — definitional distinction
- [CNCF — What is Observability 2.0?](https://www.cncf.io/blog/2025/01/27/what-is-observability-2-0/) — monitoring vs observability framing
- [OpsMatters — From Observability to Action](https://opsmatters.com/posts/observability-action-how-product-analytics-closing-loop-modern-operations) — product analytics vs infrastructure observability as separate disciplines
- See auxiliary: `terraform-stack-organization_doc_1.txt` — raw verbatim from Terraform provider/state sources
- See auxiliary: `terraform-stack-organization_doc_2.txt` — raw verbatim from observability and analytics sources

## Findings

### Finding 1: Adding a second cloud provider to a Terraform state couples its credentials to every plan/apply

**Evidence:**
> "Targeting multiple clouds from the same Terraform configuration requires Terraform to have
> credentials for all target clouds. This makes it even more important to handle these
> credentials carefully, due to the potential blast radius of having them leaked."

And, on why to separate state files:
> "By creating separate directories for each environment, you can shrink the blast radius of
> your Terraform operations and ensure you will only modify intended infrastructure."

**Source:** [Spacelift — Terraform Multi-Cloud](https://spacelift.io/blog/terraform-multi-cloud);
[HashiCorp — organize-configuration](https://developer.hashicorp.com/terraform/tutorials/modules/organize-configuration)

**Significance:** Adding a GCP provider to `monitoring` means every plan/apply — including
routine AWS/Rollbar changes — requires valid GCP ADC credentials in the environment.
Practitioner literature names this "credential blast radius." HashiCorp's own reference docs
(`Providers Within Modules`) describe multi-provider mechanics without discouraging it, so
the risk framing is practitioner-sourced, not an official prohibition.

**Verification block:**
- URL fetched: https://spacelift.io/blog/terraform-multi-cloud
- Verbatim quote checked: "Targeting multiple clouds from the same Terraform configuration requires Terraform to have credentials for all target clouds. This makes it even more important to handle these credentials carefully, due to the potential blast radius of having them leaked."
- Quote substring confirmed in fetched page body.
- URL fetched: https://developer.hashicorp.com/terraform/tutorials/modules/organize-configuration
- Verbatim quote checked: "By creating separate directories for each environment, you can shrink the blast radius of your Terraform operations and ensure you will only modify intended infrastructure."
- Quote substring confirmed in fetched page body.

---

### Finding 2: "monitoring" in SRE/DevOps terminology is scoped to infrastructure health, not product analytics

**Evidence:**
> "Monitoring is the process of collecting data and generating reports on different metrics
> that define system health."

> "Observability is a more investigative approach. It looks closely at distributed system
> component interactions and data collected by monitoring to find the root cause of issues."

> "Monitoring is the _when_ and _what_ of a system error, and observability is the _why_
> and _how_."

**Source:** [AWS — Observability vs Monitoring](https://aws.amazon.com/compare/the-difference-between-monitoring-and-observability/)

**Significance:** Both "monitoring" and "observability" in standard SRE framing refer to
infrastructure/system telemetry — not user-behavior or product analytics. A stack named
`monitoring` containing CloudWatch dashboards, SNS, and Rollbar (error tracking) sits
squarely within the SRE definition. "Observability" is the broader superset (logs + metrics
+ traces + root-cause analysis); "monitoring" is the narrower symptom-detection tier.
Neither term, by any authoritative definition found, covers product/web analytics.

**Verification block:**
- URL fetched: https://aws.amazon.com/compare/the-difference-between-monitoring-and-observability/
- Verbatim quote checked: "Monitoring is the process of collecting data and generating reports on different metrics that define system health."
- Quote substring confirmed in fetched page body.

---

### Finding 3: Product/web analytics (GA4's domain) is treated as a distinct discipline from infrastructure observability in practitioner literature

**Evidence:**
> "Observability tools are designed to answer technical questions: Is the system healthy?"

> "operations focus on uptime and latency" versus "product teams focus on engagement and
> retention"

> "Without connecting system metrics to user outcomes, teams are often left making
> assumptions about impact."

**Source:** [OpsMatters — From Observability to Action](https://opsmatters.com/posts/observability-action-how-product-analytics-closing-loop-modern-operations)

**Significance:** The practitioner article explicitly positions product analytics (clicks,
navigation, retention, engagement — GA4's subject matter) as a separate layer from
infrastructure observability, with different owners (product teams vs. operations teams) and
different questions (behavioral vs. technical). This is evidence that GA4 access
configuration is not a natural semantic fit inside a stack whose purpose is system health.

**Verification block:**
- URL fetched: https://opsmatters.com/posts/observability-action-how-product-analytics-closing-loop-modern-operations
- Verbatim quote checked: "Observability tools are designed to answer technical questions: Is the system healthy?"
- Quote substring confirmed in fetched page body.

---

### Finding 4: No established community convention exists for GA4 access gate placement in IaC

**Evidence:** Negative finding — no URL to cite.

Searched across gtm-gear.com, GitHub Gist (salrashid123), Google Cloud docs, Terraform
Registry, and practitioner blogs. The Terraform Registry has no `google_analytics_*`
provider resources — GA4 properties are not Terraform-manageable. The GA4 access gate
consists only of generic GCP resources (google_service_account, google_project_iam_member,
google_project_service) that happen to enable GA4 API access. No source addresses where
these resources belong relative to a monitoring or observability stack.

**Significance:** The decision cannot appeal to "what others do." It must rest on structural
arguments from Findings 1–3. The resources involved are generic GCP types with no
GA4-specific provider identity — their placement is an organizational choice, not a
technical constraint.

**Verification block:** Negative finding confirmed by exhausting available search queries.
"Not found" is the verified conclusion, not an omission.

---

## What this means for the monitoring-vs-dedicated-stack decision

| Factor | Finding | Trade-off |
|--------|---------|-----------|
| Credential coupling | 1 — adding GCP provider to `monitoring` requires GCP ADC on every AWS/Rollbar plan/apply | Dedicated GCP stack avoids coupling; shared stack simplifies to fewer stacks |
| Stack naming / semantic scope | 2, 3 — "monitoring" = infra health; GA4 = product analytics; different disciplines, different owners | Mismatched semantics in `monitoring`; `workspace-access` is also a naming question |
| Community precedent | 4 — none found | Decision is structurally driven, not precedent-driven |

The `workspace-access` stack is already GCP-credentialed. Whether GA4 access belongs there
or in a net-new stack is not settled by any source — it is a scope/naming decision parallel
to the `monitoring` question.

## What remains uncertain

- Whether `workspace-access` scope (OAuth/workspace-level GCP access) is semantically
  compatible with analytics API enablement — no source addresses this.
- Whether 4Shark's Terramate conventions specify how to group GCP stacks — not investigated
  here (codebase read would resolve this).
- Whether the 3-resource size of the GA4 gate (SA + IAM + API) justifies a new stack's
  orchestration overhead — a cost/complexity judgment the evidence does not make.

## Suggested options for main and the engineer

- **Option A — New dedicated GCP stack** (`gcp-analytics` or `analytics-access`): isolates
  GCP credentials, keeps `monitoring` scoped to AWS/Rollbar, avoids naming mismatch; adds
  a new stack to orchestrate.
- **Option B — Extend `workspace-access`**: already GCP-credentialed, avoids a new stack;
  couples unrelated GCP concerns (workspace OAuth vs. analytics API) in one state and
  carries the same naming-mismatch risk as Option C.
- **Option C — Add GCP provider to `monitoring`**: minimum new infrastructure; creates
  credential coupling on every AWS/Rollbar plan/apply and places product-analytics
  enablement inside an infrastructure-health stack.

(No recommendation — evidence surfaces trade-offs; main and the engineer decide.)
