# PLAN — Move auth-001 out of the shared management network

> Authored in the main session from live infrastructure research, not from a `PLAN-SPIKE.md`. Every factual claim below carries its source: a `file:line` in the terraform repository, or the AWS API call that produced it (2026-08-21, account 405749097490, `sa-east-1`).

## Objective

The Keycloak authenticator (`auth-001`) shares the `management` VPC with the Pritunl VPN. Give it a dedicated network instead, so that the identity provider's data plane stops being reachable from the network the VPN puts engineer laptops on, and so that neither component's future network changes can disturb the other. The VPN stays in `management` — it is the component whose job is to open access to internal networks, so that is where it belongs.

## Scope

### In scope

- A dedicated VPC for `auth-001`, with its own subnets, route tables and egress.
- Rebuilding the Keycloak ALB, ECS service and Postgres database inside that VPC.
- Moving the data across and cutting over with a bounded window.
- Replacing the CIDR-based security-group rules with security-group references while the module is being touched anyway.
- Decommissioning the `auth-001` resources left behind in `management`.

### Out of scope

- The VPN staging availability-zone fix and the production half of terraform PR #1053. Those are separate work already in flight; this plan must not be sequenced behind them, nor they behind it.
- Moving the VPN out of `management`. It stays.
- Any change to the Keycloak version, realm configuration, or client configuration.

## Why the SSO federations survive the move

The risk that decides whether this work is doable at all is the client-side SSO configuration: if a client's identity provider is pinned to an address rather than a name, rebuilding Keycloak elsewhere breaks their login. It is not pinned to an address, and `runbooks/client-onboarding/ADD-SSO-CLIENT.md` is the evidence.

**Every value 4Shark hands a client is a URL on the Keycloak hostname.** Under OIDC it is the broker redirect URI, `https://<keycloak-host>/auth/realms/<realm>/broker/<alias>/endpoint`. Under SAML it is the realm entity ID, `https://<keycloak-host>/auth/realms/<realm>`, and the ACS URL, `https://<keycloak-host>/auth/realms/<realm>/broker/saml/endpoint` (`ADD-SSO-CLIENT.md:159-167`). The four client-facing instruction files under `sso-client-instructions/` carry the same two placeholders and nothing resembling an address — `ENTRA-SAML.md:24-28` names them explicitly as the realm entity ID and the broker ACS endpoint.

**The hostname is preserved by the cutover, so those values keep resolving.** `auth-001.app4shark.com` is a Cloudflare CNAME whose content is the load balancer's DNS name (`dns/public_dns_app4shark_com.tf:15-17`); repointing it at the replacement load balancer leaves every URL the clients hold unchanged.

**Keycloak's own outbound federation calls reach only Microsoft and Google.** The runbook admits two identity-provider types, Microsoft Entra ID and Google Workspace (`ADD-SSO-CLIENT.md:54-55, 252-255`) — there is no client-hosted IdP in the catalog. Under SAML, trust is certificate-based and validated locally against the X509 certificate imported from the client's metadata (`ENTRA-SAML.md:15-20`), and the assertion travels through the user's browser, so Keycloak opens no back-channel connection to the client at all. Under OIDC the code-for-token exchange is a back-channel call, but its destination is Microsoft's or Google's public endpoint, and neither filters by customer source address.

### What this leaves open

The runbook proves 4Shark never asks a client for an address. It cannot prove that no client's IT team added a source-address rule on their own initiative. The reason that residual risk is small rather than unknown is the paragraph above: under both protocols Keycloak never originates a connection into a client's network, so there is nothing such a rule could be governing.

### Keycloak's egress address, for completeness

The `auth-001` ECS service runs with `assignPublicIp: DISABLED` in `subnet-03320c13f3efc36ce` (`management-prv-a`) and `subnet-0d7d244e85dcb5afb` (`management-prv-c`). Those subnets use the `management_prv` route table, whose default route points at the management NAT gateway (`networking/vpc_management.tf:141-148, 159-163`) — `nat-0d7fe84dc6c97f1ca`, public IP **54.233.103.227**, shared today only with the VPN's MongoDB host.

That address is not the one the integrator traffic leaves from. The integrator VPCs attach to the `sa-east-1` Transit Gateway on `spoke-rt`, whose default route sends internet traffic to the egress VPC (`networking/transit_gateway.tf:62-66`), and that VPC's NAT gateway is `nat-080d7a9d987fa3310`, public IP **54.207.183.89** (`networking/vpc_egress_sa_east_1.tf:54-71`). The `management` VPC has no attachment on that Transit Gateway.

Should Phase 0 turn up a client that did pin 54.233.103.227, the address is movable: an Elastic IP can be disassociated from one NAT gateway and associated with another when the network border group matches ([Work with NAT gateways](https://docs.aws.amazon.com/vpc/latest/userguide/nat-gateway-working-with.html), [Associate Elastic IP addresses with resources in your VPC](https://docs.aws.amazon.com/vpc/latest/userguide/vpc-eips.html)). That is an extra cutover step, not a blocker.

## Chosen approach

**Direction:** build the new network and a complete second Keycloak stack beside the running one, then cut over by repointing DNS.

**Why this shape.** Neither of the two components that carry state can be moved between VPCs in place. An Application Load Balancer is bound to subnets in one VPC, so a new VPC means a new ALB with a new DNS name. An RDS instance cannot change VPC either; it is replaced and the data copied — the same shape the `rds-reprovision` skill already implements for the `app` databases. Both constraints point at the same procedure: stand the replacement up alongside, sync, and switch a pointer.

**The pointer is already a CNAME, which is what makes a short window realistic.** `auth-001.app4shark.com` is a Cloudflare record whose content is the ALB's DNS name, resolved through a data source (`dns/public_dns_app4shark_com.tf:15-17`, `dns/alb_data.tf:6-7`). Cutting over is repointing that record at the new load balancer — which is exactly the "reaponto no domingo" shape, and it is reversible by repointing back.

## Execution phases

### Phase 0: confirm no client pinned an address

**Objective:** close the residual risk named above — that a client's IT team added a source-address rule 4Shark never asked for.

**Steps:** list the companies with an `AuthenticatorConfiguration` row and, for each, check with the person who ran the onboarding whether their side filters by source address. The runbook's own configuration surface is entirely URL-based, so the expected answer is no for every one; the point is to have it stated rather than assumed.

**Success criteria:**
- [ ] Every SSO client is accounted for, with who confirmed it.
- [ ] Any client that did pin an address is listed, so the Elastic IP move can be added to the cutover.

**Blocking:** the cutover design only. Phases 1–3 can be built before this is answered, because none of them changes a live path.

### Phase 1: the network

**Objective:** a dedicated VPC for the authenticator, empty and ready.

**Components:** a new `auth-001` VPC declared in the `networking` stack, following the shape of the existing per-component VPC files there; public and private subnets across two availability zones; internet gateway; NAT gateway; route tables; the subnet ids published to SSM the way `networking/ssm.tf` already publishes every other network.

**Decision to make here:** whether the new VPC egresses through its own NAT gateway or attaches to the Transit Gateway and shares the egress VPC. Sharing gives one fewer address to manage and one fewer NAT gateway to pay for; a dedicated NAT keeps the authenticator's egress independent of the integrator path. Phase 0's answer informs this.

**Success criteria:**
- [ ] `terraform plan` on `networking` shows only additions.
- [ ] Applied, with the SSM parameters readable.

### Phase 2: the database

**Objective:** a Postgres instance for Keycloak inside the new VPC, carrying the current data.

**Components:** a new RDS instance in the new VPC's private subnets, with its own subnet group and a security group that accepts 5432 **from the ECS tasks' security group**, not from a CIDR.

**Approach:** follow the `rds-reprovision` procedure — stand the replacement beside the original, sync by logical replication, and keep the predecessor until the application is proven to be serving from the replacement.

**Dependencies:** Phase 1.

**Success criteria:**
- [ ] Replication is caught up and the row counts match.
- [ ] The predecessor is untouched and still serving.

### Phase 3: the application

**Objective:** a complete Keycloak stack running in the new VPC, reachable, not yet receiving user traffic.

**Components:** a new ALB in the new VPC's public subnets; the ECS cluster and `auth-001` service in the private subnets; the security groups rewritten to reference each other; a temporary hostname pointing at the new ALB so the stack can be exercised before it carries anyone.

**The replacement cluster runs under a distinct Infinispan cluster name.** The image discovers cluster members through the database (`keycloak/Dockerfile:10-12` injects `cache-ispn-jdbc-ping.xml`, which uses JDBC_PING against a `JGROUPSPING` table). Discovery selects `WHERE cluster_name=?` and each node publishes the address peers should reach it on (`cache-ispn-jdbc-ping.xml:29-33`). Two clusters sharing a database therefore isolate only by cluster name — under the same name, nodes on both sides would try to form one cluster across VPCs that cannot route to each other.

**Bring the nodes up staggered, not all at once.** [keycloak#41290](https://github.com/keycloak/keycloak/issues/41290) reports that concurrent starts under JDBC_PING elect two coordinators — *"Two Keycloak instances in a cluster register themselves as an Infinispan coordinator in the jgroups_ping table"* — producing row locks and connection-pool exhaustion. It is open and reproduces on 26.3.1 and 26.4.0; the image runs 26.6.4.

**Dependencies:** Phases 1 and 2.

**Success criteria:**
- [ ] A login completes end to end against the temporary hostname.
- [ ] The new stack reads the replicated database.

### Phase 4: rehearse the cutover

**Objective:** know the real duration before committing to a window.

**Steps:** run the whole cutover against `auth-001-staging.app4shark.com`, which points at the same load balancer today (`dns/public_dns_app4shark_com.tf:25-27`) and therefore exercises the same mechanics with no productive impact. Time each step. If Phase 0 said the address must be preserved, rehearse the Elastic IP move here too.

**Success criteria:**
- [ ] The measured window is recorded.
- [ ] Every step that took longer than expected has a written cause.

### Phase 5: the cutover

**Objective:** production Keycloak served from the new VPC.

**Steps:** stop the old service; final replication sync and promote; bring the new service up staggered; repoint the Cloudflare origin at the new ALB; verify a real login.

**Cut with a short full stop, not with both clusters serving.** The Keycloak multi-cluster guidance states it directly: *"Neither site should be exposed to user requests via the load balancer until both Keycloak deployments have been upgraded and their Infinispan clusters synchronized."* Serving from two clusters over shared state is what the cluster-name constraint in Phase 3 exists to make survivable, not a mode to run in.

**No TTL lowering is needed, because the record is proxied.** `dns/public_dns_app4shark_com.tf:15-23` sets `proxied = true`, so clients resolve Cloudflare's anycast addresses and never the load balancer. The CNAME content is the origin Cloudflare connects to, which makes the switch a Cloudflare-side change with no resolver cache in the path — the item that usually dominates a DNS cutover is absent here.

**Rollback:** repoint the CNAME back. The predecessor stack is still running and its database is still the replication source until Phase 6, so the rollback is a DNS change and nothing else.

**Success criteria:**
- [ ] A real login succeeds through `auth-001.app4shark.com`.
- [ ] The application's own login path works, not only the Keycloak console.

### Phase 6: teardown

**Objective:** nothing of `auth-001` left in `management`.

**Steps:** destroy the old ALB, service, cluster and database; remove the `auth-001` resources from the `management` network's security groups; confirm the `management` VPC holds only VPN resources afterwards.

**Success criteria:**
- [ ] No network interface in any `management` subnet belongs to `auth-001`.
- [ ] The `management` VPC's remaining inventory is the VPN gateway, the staging host and the VPN MongoDB.

## Technical decisions

| Decision | Choice | Rationale |
|---|---|---|
| Where the VPN lives | Stays in `management` | It is the component that opens network access; that is what the network is for. |
| How the database moves | Replacement plus logical replication | An RDS instance cannot change VPC; this is the shape `rds-reprovision` already implements. |
| How the cutover happens | Cloudflare origin repoint | The record already resolves the ALB through a data source, so the switch is a pointer change and the rollback is the same change reversed. Being proxied, it carries no resolver cache to wait on. |
| Whether both clusters serve at once | No — short full stop | Keycloak's own multi-cluster guidance is that neither side should be exposed to the load balancer until both are synchronized. Sessions live in the database from 26 onward, so a stop costs no logins. |
| Infinispan cluster name on the replacement | Distinct from the incumbent | JDBC_PING discovers peers through the database and isolates only by cluster name; the same name across two VPCs produces one attempted cluster over a network that cannot carry it. |
| Where the rehearsal happens | `auth-001-staging.app4shark.com` | It points at the same load balancer, so it exercises the real mechanics with no productive impact. |
| Security-group rules | Security-group references, not CIDR | The current rules trust the whole VPC CIDR; see the risk below. |

## Risks

| Risk | Impact | Mitigation |
|---|---|---|
| A third party allowlists 54.233.103.227 for Keycloak traffic | High — a silent integration failure after cutover | Phase 0 answers it before the design is fixed; the address is movable if the answer is yes. |
| Persistent user sessions turn out to be disabled on this installation | Medium — a cutover expected to preserve logins would log everyone out instead | Keycloak stores user sessions in the database from 26 onward — *"Sessions stored in the database and cached in memory"*, *"Sessions available after cluster restart"* ([Storing sessions in Keycloak 26](https://www.keycloak.org/2024/12/storing-sessions-in-kc26)) — and the image runs 26.6.4 (`keycloak/Dockerfile:8`). The default is on, but this installation ships its own cache configuration, so read the effective setting in the environment during Phase 3 rather than trusting the upstream default. |
| Both clusters form one Infinispan view across VPCs that cannot route to each other | High — the replacement cluster fails to start cleanly | Distinct cluster name on the replacement while the database is shared or replicated; inspect the `JGROUPSPING` table before exposing traffic (Phase 3). |
| Two coordinators elected on a simultaneous start, exhausting the connection pool | High | Staggered node startup, rehearsed in Phase 4. [keycloak#41290](https://github.com/keycloak/keycloak/issues/41290) is open and reproduces on 26.3.x/26.4.x. |
| The rehearsal does not represent production | Medium — the real window is longer than measured | The staging hostname shares the load balancer, but not the data volume; treat the measured time as a floor. |
| The window overruns | Medium | The rollback is a CNAME repoint with the predecessor still running; define the abort point before starting. |
| The current security groups trust the whole VPC CIDR | Present today, independent of this plan | `modules/auth/security_groups.tf:19-23` opens all protocols and `:41-47` opens 5432, both to `10.255.0.0/16` — the range the VPN pushes to connected clients. Fixed as part of Phase 3; worth fixing sooner if this plan is deferred. |

## Assumptions

- The Keycloak hostname does not change, so realm and client configuration that embeds the issuer URL needs no edit. To be confirmed in Phase 3.
- The `management` VPC keeps its NAT gateway after the move, because the VPN MongoDB still egresses through it.
- Nobody outside AWS depends on the `auth-001` ALB's own AWS-assigned DNS name, only on the `app4shark.com` hostname in front of it.
