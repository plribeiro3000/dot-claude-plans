# SPIKE — Keycloak version upgrade process (26.1.5 → 26.6.x)

## Question

How does 4Shark upgrade the Keycloak base image to a newer version, validated on the non-productive staging authenticator before it reaches the productive SSO? Design the process and decide whether a runbook is warranted.

## Context (what we already have)

The keycloak repo restructure this session gives us the machinery an upgrade rides on:

- **Image**: a thin wrapper over `quay.io/keycloak/keycloak`, pinned by **tag + digest** in the `Dockerfile` (currently `26.1.5@sha256:be6a862...`). Renovate tracks the base image (the tag is kept precisely so Renovate can open digest-update PRs).
- **Build/deploy split**: a push to `develop` builds + pushes `auth-001-staging:latest`; a push to `master` builds + pushes `auth-001:latest` (both ECRs, sa-east-1). Deploy is a manual `deploy.yaml` dispatch (`environment=auth-001-staging` or `auth-001`) that does `aws ecs update-service --task-definition auth-001-web[-staging] --force-new-deployment` → ECS rolls to the latest task-def revision.
- **Two instances share the `auth-001-cluster`**: `auth-001-staging` (the safe validation target — its own `keycloak_staging` DB, dedicated admin, own realms) and `auth-001` (productive SSO — `desired 2`, rolling `minHealthy 100% / maxPercent 200%`, circuit breaker + rollback → zero-downtime).
- **Clustering**: both nodes cluster via **JDBC_PING** (embedded Infinispan, discovery table in Postgres) configured by our custom `cache-ispn-jdbc-ping.xml` (`KC_CACHE_CONFIG_FILE`).
- **DB migration**: Keycloak runs **Liquibase automatically on boot** — the schema migrates itself when the new image starts (confirmed on the fresh staging DB this session).

**Engineer decision (this session)**: target the latest **26.6.x** directly — a single jump `26.1 → 26.6`, all within major `26.x`.

## Findings

### F1 — Version landscape

- Current: **26.1.5**. Latest: **26.6.3** (26.6.x line, released ~Apr–May 2026).
- The jump is entirely **within major 26.x** (minor bumps 26.1 → 26.6).
- Keycloak 26.0+ **guarantees backward compatibility in minor releases** for fully-supported features/APIs; a minor that carries a breaking change makes it **opt-in**.
- Source: WebSearch (keycloak.org releases) + the upgrading guide (below).

### F2 — DB migration is automatic and one-way

- The upgrading guide: *"Automatic relational database migration"* is available; **the schema migration runs automatically on server startup**. No manual DB steps are documented between 26.1 and 26.6.
- Liquibase applies **all pending changesets in order**, so a direct multi-minor jump migrates cumulatively — skipping intermediate minors does not skip schema changesets.
- **One-way**: once the newer server migrates the schema, the *older* image can no longer read it (backward-compat is forward-only). So **rollback by redeploying the old image is NOT clean after the migration** — the real safety net is (a) staging validation and (b) a DB snapshot immediately before the prod migration.
- Source: https://www.keycloak.org/docs/latest/upgrading/index.html

### F3 — Infinispan 16 (26.6.0) — the top risk for us

- 26.6.0 upgrades embedded caching to **Infinispan 16.0**.
- Our `cache-ispn-jdbc-ping.xml` declares the **Infinispan config schema `urn:infinispan:config:15.0`** (`xmlns` + `xsi:schemaLocation`, lines 21-22).
- Infinispan generally parses older config schema namespaces, but a jump to Infinispan 16 is exactly the case where a custom cache config can fail to parse or need namespace/element adjustments.
- **Action**: the upgrade PR very likely needs the namespace bumped `15.0 → 16.0` (and any element changes Infinispan 16 introduced), and **staging must confirm the server boots AND the 2-node JDBC_PING cluster forms** (check the startup logs for the cluster view / `ISPN` cluster-formed line).
- The two extra config requirements the guide lists for Infinispan 16 (`legacy metrics` ConfigMap, `indexing.startupMode=NONE`) are for **external** Infinispan servers — **not our case** (we use embedded).
- Source: upgrading guide (above) + `cache-ispn-jdbc-ping.xml:21-22`.

### F4 — Breaking changes to check against our setup

- **26.6.3 — redirect URIs no longer accept wildcards in the hostname** (e.g. `https://example.com*`). Our `account`-client redirect URIs are **path** wildcards (`https://<env>001.app4shark.com/*`), not hostname wildcards → expected to be fine, but **verify** no hostname-wildcard redirect URI exists in any realm.
- **26.6.0 — IdP issuer must be unique for JWT authorization grant / client assertions.** Our SSO is standard **auth-code OIDC brokering** (not JWT-assertion grants), so this is expected not to apply — **note as a check**, not a blocker.
- **Other 26.x opt-in breaking changes** (token-introspection audience validation, HTTP client not following redirects by default, JS-based policies requiring the `scripts` feature, stricter FAPI client-URI validation) — none map to our brokering-login flow, but the upgrade PR should skim the per-version migration notes to confirm.
- Source: WebSearch + upgrading guide (above).

## Proposed process (reuses the existing machinery)

1. **Determine target tag + digest** — latest `26.6.x` tag from `quay.io/keycloak/keycloak`, resolve its digest (`docker manifest inspect` / skopeo / the quay UI). Keep tag + digest (Renovate convention).
2. **Upgrade PR to `develop`** (feature branch, worktree):
   - Bump the `Dockerfile` `FROM` tag + digest.
   - Bump `cache-ispn-jdbc-ping.xml` namespace `15.0 → 16.0` (and any Infinispan-16 element changes).
   - CHANGELOG `[Unreleased]` entry.
   - Merge → `develop` build pushes `auth-001-staging:latest`.
3. **Deploy staging** — `deploy.yaml environment=auth-001-staging`. Keycloak boots, Liquibase auto-migrates `keycloak_staging` to the 26.6 schema.
4. **Validate on staging (the gate)** — the checklist in the next section. This is where the Infinispan-16/cache risk and the DB migration are proven.
5. **Release to prod** — `git hf release start X.Y.Z` (repo version bump — a base-image upgrade is at least a minor of the keycloak repo, e.g. `1.1.0`) → CHANGELOG dated section → `finish` → `master` build pushes `auth-001:latest`. No task-def repoint needed (prod already on `auth-001:latest`).
6. **Snapshot the prod DB**, then **deploy prod** — `deploy.yaml environment=auth-001`. Rolling swap (zero-downtime infra) + Liquibase auto-migrates the prod `keycloak` schema on the new tasks.
7. **Validate prod** — openid-config 200, admin console, a real SSO login.

## Staging validation checklist (the load-bearing gate)

- [ ] Server **boots** on the new image (no Infinispan config parse error).
- [ ] The **2-node JDBC_PING cluster forms** (startup log shows the cluster view with both members).
- [ ] Admin console loads; **all realms intact** (`beta-001`, `demo-001`, `shared-001`, `atento-001`).
- [ ] The **Google IdP** config survived the migration on each realm.
- [ ] **SSO end-to-end** on beta (the "consigo autenticar" flow) still works.
- [ ] No redirect-URI validation error at login (the 26.6.3 hostname-wildcard change).
- [ ] Liquibase log shows the migration **completed** (no failed changeset).

## Risks

1. **Infinispan 16 vs our 15.0 cache config** (F3) — highest. Mitigation: bump the namespace in the same PR; staging boot + cluster-formation is the proof.
2. **One-way DB migration** (F2) — a bad prod migration can't be rolled back by redeploying the old image. Mitigation: staging validation + a prod DB snapshot immediately before step 6.
3. **A breaking change we didn't map** (F4) — mitigation: skim the per-version migration notes in the upgrade PR; staging catches behavioral breaks.

## Staging trial — RESULTS (live evidence, 26.1.5 → 26.6.3)

The first upgrade was validated on staging. **Process note (correcting a mistake this session):** the 4Shark flow is **merge the upgrade PR to `develop` → the automatic push-triggered build produces `auth-001-staging:latest` → a manual `deploy.yaml` dispatch (or `upgrade-deploy.sh`) rolls it → validate**. The runs this session wrongly built the staging image from the still-open PR branch via `workflow_dispatch --ref` before merging — that is NOT the intended flow; the build is automatic post-merge. The evidence below is still valid (same image content), but the sequencing was wrong. Evidenced from the boot logs + ECS events:

- ✅ **Infinispan 16 parsed our config** — the `15.0 → 16.0` namespace bump was sufficient; no other XML change needed (`ISPN000974` container start, Keycloak 26.6.3 started in 19s).
- ✅ **Liquibase migrated 26.1 → 26.6 clean** (`Migrating older model to 26.2.0`, no failed changeset); node healthy in the ALB; openid-config 200; **all 4 realms survived**; **SSO on beta confirmed by the engineer**.
- ⚠️ **Cross-version JGroups cannot cluster** — during the rolling window the new node (JGroups 16.0.8) and the draining old node (JGroups 5.3.15) spam `SSLHandshakeException` (mTLS), `cookie does not match`, `packet has different version; discarded`. No data loss (sessions are DB-backed), but it destabilizes readiness.
- ⚠️ **The new node FLAPPED to 503 and was killed** by the ALB health check during that window; ECS started a replacement that only stabilized after the old node was fully gone (~13 min total to steady state). On prod (`desired 2`, rolling) this is a real crash-loop / circuit-breaker-rollback risk.
- ⚠️ **The Deploy workflow FALSE-FAILED** — `aws ecs wait services-stable` (fixed 10-min ceiling) timed out at 17:42 while the service stabilized at 17:45. The deploy itself succeeded. Fixed by **keycloak PR #8** (`ci(deploy)`): replaced the waiter with a 20-min describe-services poll that also exits fast on a circuit-breaker rollback.
- ℹ️ Non-fatal: a `Hostname v1 options [hostname-admin-url, hostname-url] deprecated` WARNING (a future `KC_HOSTNAME_*` v2 cleanup, unrelated to the upgrade).

## Decision — runbook IS warranted, with a dedicated Infinispan section (engineer direction)

The process is not a plain "bump the tag": a config-file schema bump (Infinispan 16), a one-way DB migration needing a snapshot, a breaking-change checklist, and — proven live — a cross-version cluster window that flaps readiness and false-fails the deploy. **Next deliverable**: a runbook under `~/.claude/docs/runbooks/` (catalogued in `runbooks/INDEX.md`), authored as a dot-claude PR — the generic "upgrade the Keycloak version" procedure, parameterized by target version.

**Engineer direction for the runbook (this session):**
- A **dedicated section on "upgrades that affect Infinispan"**, with a hard **REQUIREMENT to check whether the Infinispan version changes** as part of every Keycloak upgrade — because an Infinispan major bump affects the **whole deploy** (the cross-version cluster window), not just the config file.
- Once an Infinispan bump is confirmed, the deploy strategy must be designed under a firm constraint: **do NOT reduce the instance count** (scaling to 1/0 loses redundancy and can affect clients). So option "A" (scale down before the crossing) is **rejected**. The runbook must land a strategy that crosses the Infinispan major while keeping ≥2 healthy instances the whole time.
- **RESOLVED — the crossing is a planned maintenance window** (see "Design resolution" below). Zero-downtime-without-reducing-instances is not achievable for a schema-migrating Infinispan-crossing upgrade; the community/official convergence is recreate in an announced window.

## Design resolution — the Infinispan-crossing deploy strategy (community/official convergence)

Researched against the authoritative Keycloak docs (sources below). The answer, and the engineer's runbook direction (this session):

**1. The gate — the FIRST step of every Keycloak upgrade is to check whether it is rolling-safe.** Keycloak ships the official tool `kc.sh update-compatibility`:
- Generate metadata from the CURRENT running version (with all config): `kc.sh update-compatibility metadata --file=/tmp/kc-compat.json`
- Check it against the NEW version (same config): `kc.sh update-compatibility check --file=/tmp/kc-compat.json`
- **Exit 0** → `[OK] Rolling Update is available` — a normal rolling deploy is safe (zero-downtime, keeps ≥2). **Exit 3** → `Rolling Update is not available` — recreate required (shut down all old nodes before starting the new ones).
- It detects cache/Infinispan incompatibility (`--cache-stack`, `--cache-embedded-mtls-enabled`, `--cache-config-file` change), BUT **"does not verify changes to the content of the cache configuration file"** — so our `cache-ispn-jdbc-ping.xml` (Infinispan namespace bump) still needs a manual JGroups-compat review. This command supersedes the weaker "did the Infinispan version change?" heuristic — it is the official, config-aware gate. This is the runbook's mandatory first step.

**2. When the check says NOT rolling-safe (the Infinispan crossing — our 26.1→26.6 case, exit 3): it is a planned maintenance window, NOT an on-the-spot deploy.** The engineer's direction: the deploy **cannot be done in the moment** — the runbook must say "plan a window" and carry the MAXIMUM detail for it (the exact commands, the flow/process, how to validate, how to guarantee it works after). Why no zero-downtime alternative:
- Keycloak's own docs: *"major and minor upgrades of both Keycloak and Infinispan require downtime... performed during the same maintenance window"*; the operator falls back to **Recreate** (scales the StatefulSet down before the new image); update-compatibility exit 3 = *"Shut down all nodes of the cluster running the old version before starting the nodes with the new version."*
- **Blue-green on one DB does NOT work here** (correcting an earlier suggestion): the DB migration is one-way (F2) — once the new version migrates the schema, the OLD version can no longer read the DB, so old + new cannot coexist on the same database. True zero-downtime would need separate-DB blue-green with data sync — impractical for Keycloak, nobody does it.
- The window is SHORT (~30–60s, the new node's boot+migrate+health time) and redundancy is restored immediately after (back to `desired 2`). It is not the long "scale to 1" the engineer rejected — it is a brief, announced, controlled outage.

**3. Patches within a major.minor (e.g. 26.6.3 → 26.6.4) return exit 0 → clean rolling, zero-downtime, no window.** So the maintenance-window pain is rare — only when an Infinispan major bumps. The second staging run will prove the clean-rolling path.

**Runbook structure the engineer wants** (deliverable = a dot-claude PR under `~/.claude/docs/runbooks/`, later):
- Step 1 (mandatory gate): run `kc.sh update-compatibility check`. Branch on the result.
- Rolling branch (exit 0): normal `deploy.yaml` dispatch, zero-downtime.
- **Maintenance-window branch (exit 3 / Infinispan crossing): a dedicated section with the full window procedure** — pre-window prep (announce, snapshot the RDS, stage the new image), the exact recreate commands/flow, post-migration validation (boot log: Infinispan parses + cluster forms + Liquibase completes; then admin console + realms + SSO), the "how do we guarantee it works after" checklist, and the rollback (restore snapshot + repoint to the old image).

## Open questions for the engineer

1. **Trial the upgrade on staging now** (do a real 26.6.x bump + staging deploy to prove the Infinispan-16/cache assumption before writing the runbook), or **write the runbook first** from this research and run the real upgrade later?
2. **Repo version** for the upgrade release — a base-image bump as `1.1.0` (minor) vs something else. (Decide at release time.)
3. Confirm there is **no hostname-wildcard redirect URI** in any realm (I set the `account` clients to path wildcards `https://<env>001.app4shark.com/*`, so expected clean).

## Sources

- Keycloak Upgrading Guide — https://www.keycloak.org/docs/latest/upgrading/index.html
- Keycloak releases — https://github.com/keycloak/keycloak/releases
- Keycloak 26.6.2 release note — https://www.keycloak.org/2026/05/keycloak-2662-released
- Keycloak — Checking if rolling updates are possible (`update-compatibility` command, exit codes) — https://www.keycloak.org/server/update-compatibility
- Keycloak Operator — Avoiding downtime with rolling updates (Auto vs RecreateOnImageChange) — https://www.keycloak.org/operator/rolling-updates
- Keycloak — Managing upgrades / multi-cluster ("major and minor upgrades... require downtime... same maintenance window") — https://www.keycloak.org/high-availability/multi-cluster/upgrades
- `~/Projects/4Shark/keycloak/Dockerfile` (current pin `26.1.5@sha256:be6a862...`)
- `~/Projects/4Shark/keycloak/cache-ispn-jdbc-ping.xml:21-22` (Infinispan config schema `15.0`)
