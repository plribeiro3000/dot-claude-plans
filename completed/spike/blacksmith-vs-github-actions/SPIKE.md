# SPIKE — Migrating GitHub Actions to Blacksmith for 4shark

**Conducted by:** Paulo Ribeiro (with Claude)
**Date:** 2026-05-12
**Status:** Closed — see conclusions

---

## Goal

Triggered by the TanStack npm supply chain compromise (postmortem published 2026-05-12, malicious versions published 2026-05-11). Two questions:

1. **Were we affected?** Sweep all 4shark repositories for the 84 compromised `@tanstack/*` versions listed in [GHSA-g7cv-rxg3-hmpx](https://github.com/advisories/GHSA-g7cv-rxg3-hmpx).
2. **Should we migrate to Blacksmith?** Evaluate [blacksmith.sh](https://www.blacksmith.sh) as a replacement for GitHub-hosted runners. Quantify effort and cost, and check whether the migration would have prevented the TanStack-class incident.

---

## Method

- `gh search code` across the 4shark org for `@tanstack` and `tanstack` references
- Direct inspection of `package.json` in the only TypeScript repo (`app-webclient`) and other JS/HTML candidates (`keycloak`, `onboarding`)
- `gh search code` for `pull_request_target` (the workflow pattern exploited in the TanStack attack)
- Enumerated all `.github/workflows/` files across 14 repos in the 4shark org
- Sampled `runs-on` directives and workflow shape (services, Docker builds, caching) in 3 representative workflows
- Fetched Blacksmith landing page, pricing page, and `docs.blacksmith.sh/llms-full.txt` for feature/pricing/migration details
- Cross-referenced TanStack detection timeline against the 4shark Renovate `minimumReleaseAge: 7d` window

---

## Evidence

### 1. TanStack exposure in 4shark — none

| Check | Result |
|---|---|
| `gh search code "@tanstack" --owner 4shark` | 0 results |
| `gh search code "tanstack" --owner 4shark` | 0 results |
| `app-webclient/package.json` grep `tanstack` | 0 results |
| `keycloak`, `onboarding` package.json | not present at repo root |
| `gh search code "pull_request_target" --owner 4shark` | 0 results — we don't have the workflow pattern that was exploited |

### 2. Workflow inventory (4shark)

All CI/CD workflows run on `ubuntu-latest` (GitHub-hosted, no self-hosted runners).

| Repo | CI/CD workflows | Renovate | Notes |
|---|---|---|---|
| app | 9 (ci, build-image[×4 build jobs], deploy×4, stop-service) | yes | Heavy: RSpec + postgres/redis/mongo services + 4 parallel Docker builds |
| integrator | 5 (build, deploy, test, startup, shutdown) | yes | Medium: RSpec + redis/mongo |
| onboarding | 3 (build, ci, deploy) | yes | Medium |
| setup | 2 (ci, deploy) | yes | Light |
| terraform | 1 (terraform-ci) | yes | Light |
| lambda | 1 (ci) | yes | Light |
| app-sdk-advpl | 3 (ci, dco, single-commit) | — | Very light |
| app-sdk-dotnet | 3 (ci, dco, single-commit) | — | Very light |
| ansible | 0 | yes | Renovate only |
| simplex-harvester, dot-claude, app-mobileclient, keycloak | 0 | — | No workflows directory |

**Total: 27 workflow files, ~50–70 `runs-on:` directives across the org.**

`renovate.yml` workflows trigger a self-hosted Renovate Bot — they consume negligible Actions minutes.

### 3. Blacksmith — what it is and what it costs

Drop-in replacement for GitHub-hosted runners. Same YAML, only `runs-on` changes.

**Compatibility:**
- `actions/cache@v5`, `setup-node/ruby/go/python/java` → no changes; Blacksmith intercepts and uses colocated cache (~4× faster downloads)
- Docker builds → swap `docker/build-push-action` for `useblacksmith/build-push-action@v2` + `useblacksmith/setup-docker-builder@v1` to get 40× Docker layer cache
- Docker service containers (postgres, redis, mongo) → identical behavior
- OIDC → no changes
- Known limitations: Rust `sccache` still hits GitHub backend; DNT not supported

**Pricing (Ubuntu x64 2-core, primary candidate for our workload):**

| Item | GitHub Actions | Blacksmith |
|---|---|---|
| Per-minute | $0.008 | $0.004 |
| Free tier | 3,000 min/month (Team) | 3,000 min/month |
| Runtime claim | baseline | "2× faster" |
| Add-ons | — | Docker layer cache $0.50/GB/mo; sticky disks $0.50/GB/mo; static IP $100/IP/mo |

SOC2 attested. No supply-chain-specific security features (and Blacksmith doesn't claim any — it's a runner provider).

### 4. Effort estimate to migrate

| Phase | Hours |
|---|---|
| Blacksmith account setup, GitHub App install, billing | 1–2 |
| Swap `runs-on` in light workflows (lambda, terraform, setup, sdk-advpl, sdk-dotnet) | 2–3 |
| Medium workflows (integrator, onboarding) — 1 PR per repo, validate against real CI | 3–4 |
| Heavy workflow (app) — 9 workflows, 4 parallel Docker builds, validate cache + Docker layer cache | 5–7 |
| Cross-repo validation (observe regressions across real runs) | 3–4 |
| Rollback plan, internal communication, runbook update | 2–3 |
| **Total** | **16–23 hours (2–3 working days)** |

### 5. Cost estimate (no real billing data — endpoint returned HTTP 410)

| Usage scenario | Min/month | GitHub cost ($0.008/min, 3k free) | Blacksmith cost ($0.004/min, 2× faster, 3k free) | Monthly delta |
|---|---|---|---|---|
| Low (likely ours) | 5,000 | $16 | $5 | $11 |
| Medium | 15,000 | $96 | $15 | $81 |
| High | 40,000 | $296 | $74 | $222 |

**Critical reframe from the discussion with the engineer:** The "savings" calculation is misleading at low usage. GitHub's 3,000 free minutes are bundled with seats already paid. If actual consumption is below 3,000 min/month — likely our case — GitHub Actions overage is **already $0**. Migrating to Blacksmith doesn't replace GitHub's cost (seats remain), it **adds a new vendor on top**. Real delta at low usage is *negative* (operational overhead of a second billing surface, second account, second status page to monitor) for at most an $11/month nominal saving that doesn't actually materialize.

Payback against 20h migration effort (≈R$6,000 internal cost): never at low usage; ~12–15 months at medium; ~5 months at high.

### 6. Security analysis — would Blacksmith have prevented TanStack?

**No.** The TanStack incident exploited:
- `pull_request_target` allowing fork code execution with secrets
- GitHub Actions cache poisoning across trust boundaries
- OIDC token extraction from runner memory

These are properties of the workflow YAML and the GitHub trust model, not the runner VM. Running the same YAML on Blacksmith VMs reproduces the same exploit chain — Blacksmith doesn't change the trust boundary.

**Our existing defense-in-depth already mitigates the malicious-publish vector:**

| Layer | What it does | Catches TanStack? |
|---|---|---|
| Dependabot | Immediate PR on confirmed CVE | Yes, once CVE is filed |
| Renovate (self-hosted, daily) | Continuous updates including transitive deps | Yes |
| `minimumReleaseAge: 7d` | Quarantines every new version for 7 days | **Yes — primary filter** |
| No `pull_request_target` in workflows | We lack the execution vector the attack used | Yes (vector not present) |
| Self-hosted Renovate | Dependency metadata never leaves 4shark infra | Defense in depth |

**TanStack timeline vs our 7-day window:**
- Malicious versions published: 2026-05-11 19:20–19:26 UTC
- Postmortem published by TanStack: 2026-05-12 (within ~24h)
- Earliest a Renovate PR with malicious versions could be merged: 2026-05-18

The malicious versions were yanked from the registry days before the quarantine window expired. **Renovate would never have been able to open a mergeable PR with the compromised versions.** Same mechanism that protected us from the Axios incident (documented in `~/.claude/CLAUDE.md`).

Extending the window to 14d or 30d was considered. Trade-off: doubles the latency of all legitimate updates. Both observed incidents (Axios, TanStack) were detected in hours — 7d already has ~7× margin over observed detection time. **Not worth extending.**

---

## Conclusions

1. **We were not affected by the TanStack incident.** Zero `@tanstack/*` usage across all 14 repos in the 4shark org. No `pull_request_target` in any workflow (we don't have the exploit vector).

2. **Blacksmith migration does not make financial sense at our usage level.** GitHub's 3,000 free minutes are bundled with seats we already pay; below 3,000 min/month, GitHub Actions overage is $0. Migrating adds a second vendor on top of GitHub without removing GitHub's cost. The "67% savings" only materializes at high overage volumes we don't have.

3. **Blacksmith does not improve our security posture for this class of incident.** The runner VM is not where the TanStack attack happened — the workflow trust model is. Our current stack (Dependabot + self-hosted Renovate + 7d `minimumReleaseAge` + no `pull_request_target`) already prevents the TanStack-class incident from reaching production.

4. **7-day quarantine window is sufficient.** TanStack was detected within ~24h, well inside the window. Extending to 14d or 30d adds latency to every legitimate update for no proportional gain.

---

## Decision

**Do not migrate to Blacksmith. Keep current stack.**

Rationale: no cost savings at our usage, no security gain over what we already have, 20–25h of engineering effort with negative ROI. The TanStack postmortem is a validation that our current setup works as designed, not a signal to change it.

No follow-up actions required. This spike does not generate a PLAN.md.

---

## Next Steps

- Move this folder from `active/spike/` to `completed/spike/`
- Reference this spike if the runner-migration question comes up again (e.g., if usage profile changes significantly or a stronger security feature gap is identified)
