# Auxiliary file: web source summaries for BR pooler network topology spike.
# Every quote below is a verbatim substring from the fetched page at the listed URL.
# URLs that returned errors are marked UNVERIFIED.

---

## Source 1 — AWS blog: Cross-Region Connectivity for AWS PrivateLink (Dec 2024)

**URL:** https://aws.amazon.com/blogs/networking-and-content-delivery/introducing-cross-region-connectivity-for-aws-privatelink/

**Fetched:** yes (HTTP 200, re-confirmed during self-check pass)

**Verbatim quotes used in SPIKE.md:**

> "You can only enable cross-region access for NLB-based services. AWS services and Marketplace services are not supported at this time."

> "All traffic stays on AWS network without going over the public internet."

> "Cross-region connectivity is only supported for Interface type VPC endpoints."

**Context / significance:** Establishes that cross-region PrivateLink (Candidate 4) requires an NLB in the origin region fronting the target service. The NLB would sit in app-atento-001 (us-east-1) in front of the existing pooler. Consumers in sa-east-1 connect via Interface VPC endpoint. Traffic stays on the AWS backbone, avoiding the public internet.

---

## Source 2 — AWS blog: Access Amazon RDS across VPCs using AWS PrivateLink and NLB

**URL:** https://aws.amazon.com/blogs/database/access-amazon-rds-across-vpcs-using-aws-privatelink-and-network-load-balancer/

**Fetched:** yes (HTTP 200, prior session)

**Verbatim quotes used in SPIKE.md:**

> "A. Database users or applications connect to Amazon RDS using VPC endpoints. B. The endpoints establish the user connection to VPC endpoint services (AWS PrivateLink) in other VPCs. C. The VPC endpoint services establish the connection request to the Network Load Balancer. D. The Network Load Balancer forwards the connection to the RDS primary instance."

> "This solution works across AWS accounts and VPCs within the same Region."

**Context / significance:** Describes the NLB + PrivateLink pattern for exposing RDS across VPCs. The "same Region" limitation in this article applies to the RDS-NLB pattern specifically; the cross-region PrivateLink blog (Source 1) extends endpoint services themselves across regions when NLB-backed. For Candidate 4, the pooler (not RDS directly) is exposed via NLB in us-east-1, then cross-region PrivateLink reaches it from sa-east-1.

---

## Source 3 — AWS whitepaper: Building a Scalable and Secure Multi-VPC AWS Network Infrastructure

**URL:** https://docs.aws.amazon.com/whitepapers/latest/building-scalable-secure-multi-vpc-aws-network-infrastructure/centralized-access-to-vpc-private-endpoints.html

**Fetched:** yes (HTTP 200, prior session)

**Verbatim quotes used in SPIKE.md:**

> "you can host the interface endpoints in a centralized VPC. All the spoke VPCs will use these centralized endpoints via Transit Gateway."

> "Single policy document also results in larger blast radius."

> "Private hosted zones are associated with specific VPCs. Managed private hosted zones only work within the VPC containing the VPC endpoint."

**Context / significance:** Describes the shared-services VPC pattern. The blast-radius warning is relevant to Candidate 1 (pooler inside maqnelson) — maqnelson already serves multiple client tenants; adding a pooler expands the blast radius if the pooler is compromised or misconfigured. The PHZ association caveat confirms that each consumer VPC that needs to resolve `pgbouncer-br.4shark.internal` must be explicitly associated via `aws_route53_zone_association`.

---

## Source 4 — RevenueCat blog: Running PgBouncer on AWS ECS

**URL:** https://www.revenuecat.com/blog/engineering/pgbouncer-on-aws-ecs/

**Fetched:** yes (HTTP 200, prior session)

**Verbatim quote used in SPIKE.md:**

> "If all of the clients and the downstream PostgreSQL server are already in an AWS VPC, you can save on bandwidth charges by using AWS ECS Service Discovery."

**Context / significance:** Confirms the canonical ECS PgBouncer pattern: pooler in same VPC as consumers and RDS, with ECS Service Discovery for DNS. The 4Shark br-pooler deviates from this pattern because the consumer (sa-east-1) and the RDS (us-east-1) are in different VPCs and different regions. Any candidate must bridge this gap.

---

## Source 5 — Blog: PgBouncer Transaction Pooling: The Multi-Tenant Nightmare

**URL:** https://blog.sagarregmi.info.np/transaction-pooling-the-multi-tenant-nightmare

**Fetched:** yes (HTTP 200, re-confirmed during self-check pass — original fetch used an incorrect slug; correct URL verified and quotes re-confirmed)

**Verbatim quotes used in SPIKE.md:**

> "In Transaction Pooling, PgBouncer gives your app a fresh connection for each transaction — but it doesn't clean up session-level settings like `search_path`."

> "Thread B reuses the connection, assumes it's for tenant_b, but still sees tenant_a's context. Result: tenant_b sees tenant_a's data."

**Context / significance:** Confirms that transaction pooling causes cross-tenant session state leakage when `search_path` is used per tenant. 4Shark's existing pattern (from PLAN.md) is `auth_type=md5` with static userlist and session pooling — this is the correct pattern for multi-tenant use. Any BR pooler must also use session pooling.

---

## Source 6 — PgBouncer official documentation: features

**URL:** https://www.pgbouncer.org/features.html

**Fetched:** yes (HTTP 200, re-confirmed during self-check pass)

**Verbatim quotes used in SPIKE.md:**

> "Most polite method. When a client connects, a server connection will be assigned to it for the whole duration it stays connected."

(Session pooling description)

> "This mode breaks a few session-based features of PostgreSQL. You can use it only when the application cooperates by not using features that break."

(Transaction pooling warning)

**Context / significance:** Official PgBouncer documentation confirming that transaction pooling breaks session-based features. Session pooling is "most polite" and supports all PostgreSQL features. This is the second independent corroboration (alongside Source 5) that session pooling is the only safe mode for multi-tenant use with search_path.

---

## Source 7 — AWS samples: hub-and-spoke with shared-services VPC (Terraform)

**URL:** https://github.com/aws-samples/hub-and-spoke-with-shared-services-vpc-terraform

**Fetched:** yes (HTTP 200, prior session)

**Finding:** Database connection poolers are NOT mentioned as canonical shared services in this reference architecture. The canonical shared services in the hub-and-spoke pattern are: VPC endpoints (to AWS services like S3, SSM, etc.) and Route 53 Resolver endpoints (for DNS forwarding). A PgBouncer is an application-layer service, not a network infrastructure service, so it does not fit the canonical shared-services-VPC pattern.

**Significance for spike:** Candidate 2 (dedicated pooler VPC) is NOT the "shared services VPC" pattern — it is closer to a single-purpose service VPC that happens to serve multiple consumers, a simpler construct. No Route 53 Resolver or centralized endpoint policy overhead is needed.
