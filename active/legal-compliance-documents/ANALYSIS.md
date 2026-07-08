# ANALYSIS — LGPD Compliance & Client-Requirement Gap Analysis (4Shark)

**Date:** 2026-06-28 · **Last update:** 2026-06-29 · **Owner:** Paulo Ribeiro (DPO) · **Status:** working analysis for prioritization

**Progress (2026-06-29):** T5 (cross-region backup) DONE. P6 (BCP/DRP) unblocked but parked pending the restore test (P7), which waits on the first scheduled DR recovery point (2026-06-30 05:00 UTC). Moving on to the next attendable document while P6/P7 wait.

This is a consolidated gap analysis crossing three sources:

1. **What 4Shark has today** — the documents and controls in place.
2. **What LGPD requires** — from the `lgpd-policy-gap-analysis` spike (Tier A legal / Tier B best-practice / Tier C situational), plus the operational/evidence layer (training, audits, records) that documents alone don't cover.
3. **What clients asked for in vendor assessments / RFPs** — Positivo (7 required mitigations) and Grupo Barigui (security questionnaire, items answered NÃO).

The goal: one complete list of everything still missing — document, process, evidence, technical, certification — to decide what we resolve and how.

---

## Part 1 — What we have today (the baseline)

Strong foundation. Do not re-do these.

**Documents (compliance repo, versioned, source of truth):**
- Public Privacy Policy (live, with analytics/cookie disclosure)
- Terms of Use
- RoPA — Record of Processing Operations (incl. analytics activity, subprocessors, international transfer)
- DPA — Data Processing Agreement (template, per client)
- Applicability Matrix (who signs what)
- Group Entities record (entity-per-document rule)
- 15 internal policies: information security (umbrella), identity & access, passwords, e-mail, IT assets/network, secure development, backup, storage/anonymization/disposal, awareness program, incident response, privacy by design, personal data treatment, sensitive data declaration, NDA, + DPA

**Runbooks (dot-claude):**
- LGPD Data Subject Request (intake/routing)
- LGPD Data Erasure (technical execution)
- Generate Compliance Documents (fill → render → sign/publish/per-client)

**Technical controls (evidenced in the client assessments):**
- Encryption in transit (TLS 1.2+) and at rest (AES-256 / AWS KMS)
- MFA on the corporate IdP (Google Workspace), VPN for prod/DB, least-privilege + JIT elevation, YubiKey break-glass
- IAM as code (Terraform), full git audit trail, CloudTrail
- 1Password vault + AWS Parameter Store (KMS) for secrets
- Dependabot (SCA, daily merges), RuboCop/ESLint (SAST), CloudFlare WAF (OWASP)
- Multi-AZ Aurora + ECS auto-recovery, PITR + daily snapshots, CloudFlare anti-DDoS
- Pentest done by an independent firm (findings remediated + retested)
- Observability 24x7 (CloudWatch, Datadog, New Relic, Rollbar, CloudFlare)
- Automatic irreversible anonymization (5y1m), 48h extraction-file disposal
- SLA grade documented; incident channel `security@4shark.com.br`; 72h breach notification commitment

---

## Part 2 — LGPD requirement gaps (from the spike)

Most document-level LGPD gaps were **closed this session**. Remaining:

| # | Item | Type | LGPD anchor | Status | Priority |
|---|---|---|---|---|---|
| L1 | International transfer — confirm AWS DPA/SCCs accepted (Res. ANPD 19/2024, grace period ended Aug 2025) | Evidence | Art. 33 | Documented in RoPA/DPA; AWS DPA acceptance to confirm | Medium |
| L2 | DPO formal designation — publication / ANPD communication | Process | Art. 41, Res. 18/2024 | Named in the public policy; formal ANPD comm. to confirm | Low-Med |
| — | DPA, RoPA, cookie disclosure, DSR channel visibility, consent record (analytics) | Document | Arts. 37/39/18/41/9 | **DONE this session** | — |

Deferred LGPD best-practice (create on client/audit demand): standalone supplier-management policy, information-classification policy, BCP/DRP, RIPD, consent-record templates (covered below where a client also asked).

---

## Part 3 — Client-requirement gaps (Positivo + Barigui)

These are the asks where 4Shark answered NÃO / partial, or committed to deliver. Several overlap with LGPD best-practice and with each other.

### Documents / processes (the "treinamentos e essas coisas" layer)

| # | Item | Type | Asked by | Status | Priority |
|---|---|---|---|---|---|
| P1 | Identity Lifecycle Procedure — onboarding/offboarding checklist with **execution records** | Process + Evidence | Positivo (Item 2, ALTO, deadline 2026-06-07 PASSED) | Controls exist (R69 SIM); the **documented procedure + records** is the deliverable | **HIGH** |
| P2 | SOC alert-triage / response procedure (for GuardDuty + Security Hub findings) | Process | Positivo (Item 6, deadline 2026-07-07) | Missing — depends on the AWS tooling being live | High |
| P3 | Internal Audit Procedure + **first audit report** | Process + Evidence | Positivo (Item 7, deadline 2026-08-06) | Missing | High |
| P4 | Formal Risk Management program (methodology, risk register, review cycle — ISO 31000 shape) | Document + Process | Barigui (R51) | Missing (risk handled ad hoc by tech lead) | Medium |
| P5 | Periodic Access Recertification (fixed cadence — semestral/annual — with records) | Process + Evidence | Barigui (R70) | Missing (compensated by least-privilege + IaC; no fixed cadence) | Medium |
| P6 | DRP / BCP document (RTO/RPO stated, tested annually) | Document | Barigui (R93), LGPD best-practice | **UNBLOCKED (T5 done) — PARKED pending P7.** Engineer chose restore-test-first (2026-06-29) so the BCP cites a *measured* RTO, not a paper target. The restore test is blocked on a DR recovery point — first scheduled backup is 2026-06-30 05:00 UTC + cross-region copy. Decision: **wait for the scheduled backup** (no on-demand trigger). Return to write the BCP once P7 produces a measured RTO. | Medium |
| T5 | **Cross-region RDS backup** (AWS Backup → 2nd region; prereq for P6/BCP) | Technical | LGPD availability + Barigui R91/R93 + the BCP | **DONE (2026-06-29).** AWS Backup live on `app-shared-001` + `app-atento-001` + `auth-001` → us-west-2; daily 05:00 UTC, 7d local + 7d DR, copy + failure alarms; applied and drift-verified (3 stacks `No changes`, config = state = real AWS). Module `cross_region_backup` (terraform PRs #562 + rename #564, both merged). Real volumes: shared ~339GB, atento ~34GB, auth ~5GB; cost ~$45-55/mo. **Follow-up:** auth-001 SNS → AWS Chatbot Slack subscription (manual, pending). | DONE |
| P7 | Restore-test procedure + documented results (≥ semestral, RTO achieved) | Process + Evidence | Barigui (R92) | **APPROACH DECIDED (2026-07-07), implementation pending.** DR recovery points now exist (T5 live + second wave applied). Fidelity resolved by spike `dr-restore-test-fidelity` (NIST 800-34, AWS WAF, Google SRE): the test must hit **real RDS/Aurora, never production, on a non-prod stack (beta/demo)** — a local-Postgres restore is not valid evidence. **It must be the CROSS-REGION restore — the us-west-2 DR recovery point restored into a NEW us-west-2 RDS** (AWS WAF: recover "in the recovery Region"); restoring the same-region local copy back into us-east-1 only tests same-region recovery, which native RDS backups already cover and does NOT validate the regional-DR claim the BCP makes (that claim is the whole reason T5 exists). Chosen approach = **AWS Backup Restore Testing (automated, dated Audit-Manager evidence) + an annual game-day** that does the real cutover (restore → repoint app → measured end-to-end RTO), because restore-job duration alone ≠ RTO (RTO includes the cutover). Both run **in us-west-2 against the DR vaults** (the RestoreTestingPlan is regional). Same-infra is NOT required (instance class is overridable), but a smaller target under-measures RTO. **Two BCP scenarios to state separately (different RTO):** (a) RDS-only corruption, us-east-1 compute survives → app repoints to the us-west-2 restored DB (cross-region latency); (b) full us-east-1 region loss → rebuild compute in us-west-2 via IaC + restore data (larger RTO). Implementation = a Terraform `RestoreTestingPlan` + a documented annual game-day runbook. **Follow-up before the game-day:** investigate how fast the app's DB-endpoint repoint/cutover is (parameterized secret vs manual) — a 4Shark-codebase question the spike flagged. | Medium |
| P8 | Incident tabletop / simulation exercise | Process | Barigui (R102) | Missing (post-mortems exist; no tabletop) | Low-Med |
| P9 | **Formal training & awareness program** — documented program + **completion tracking/records** | Document + Evidence | Engineer-flagged + Barigui (R50) | Partial — onboarding + annual happen informally; no program doc or completion records | Medium |
| P10 | Supplier / sub-processor management + due-diligence process | Document + Process | Barigui (R108), LGPD Finding 4 | Substance in DPA + RoPA; no standalone process/record | Low-Med |
| P11 | Information Classification policy (formal, with labelling/handling) | Document | Barigui (R49 — answered SIM via per-type rules) | Partial — classified by type across policies; no standalone policy | Low |
| P12 | Vulnerability Management policy with formal CVSS-based SLA | Document | Barigui (R81) | Partial — Dependabot does it in practice; no formal SLA document | Low |

### Technical (Positivo-required — code / Terraform)

| # | Item | Type | Asked by | Status | Priority |
|---|---|---|---|---|---|
| T1 | Security Events Platform — auth/security events persisted (retention ≥ 6–12 mo) + in-platform audit/Excel export + client SIEM export | Technical | **Three clients**: Positivo (Item 1, SIEM, deadline 2026-08-06) + Atento México (SOW §2.1, signed 70h, in-platform audit + Excel) + Barigui (R55, R88) | **In progress** (`security-events-platform` PLAN active; "fase final" per Barigui) — confirm shipped | **HIGH** |
| T2 | GuardDuty (SIEM / event correlation), us-east-1 + sa-east-1 | Technical | Positivo (Item 5) + Barigui (R97) | Status to confirm (Terraform net-new per the PLAN) | Medium |
| T3 | Security Hub + CIS AWS Foundations hardening | Technical | Positivo (Item 3) | Status to confirm | Medium |
| T4 | Macie (S3 sensitive-data detection / DLP) + Google Workspace DLP | Technical | Positivo (Item 4) | Status to confirm | Medium |

### Certifications / org maturity (strategic, long-term)

| # | Item | Type | Asked by | Status | Priority |
|---|---|---|---|---|---|
| C1 | ISO 27001 / SOC 2 Type II (or equivalent) | Certification | Barigui (R45) | None (aligned to ISO 27001/27002 in practice) | Low / strategic — enterprise-sales driver |
| C2 | Formal InfoSec area (structure, budget, hierarchical reporting) | Org | Barigui (R46) | None (tech lead + DPO) — likely "won't change" at current size | Low / accept |

---

## Completeness sweep (2026-06-28)

Navigated every plan folder (active + completed + content + spike) to confirm no client requirement was left out:
- **Only two formal client security assessments exist** in the plans: **Positivo** (`vendor-assessment-positivo` + `positivo-risk-mitigation`) and **Grupo Barigui** (`vendor-assessment-barigui`). Both are fully reflected above.
- **Atento México** is a third requirement driver, via its commercial SOW (`atento-mexico-improvements/STATEMENT-OF-WORK-v2.md` §2.1) — it asks for the access-events audit + Excel export, which is the **same Security Events Platform** (T1). Folded into T1.
- **No PagBank assessment exists** in the plans (searched by name — empty). If PagBank ran a questionnaire, it is not captured here; confirm with the engineer whether one exists outside the plans.
- Pentest (Barigui R82 / `pentest-vendor-selection`) is **done** — independent firm, findings remediated + retested.
- Numerous LGPD/security spikes exist (`lgpd-policy-gap-analysis`, `secure-pii-file-intake`, `signature-pdf-export`, `keycloak-saml-idp-federation`, etc.) — none introduce a client document/process ask beyond what is listed above.

## Notes / honest caveats

- **The Positivo deadlines (2026-04-08 assessment) have passed or are imminent** — Item 2 (60d) was due 2026-06-07; Items 3/4/5/6 (90d) 2026-07-07; Items 1/7 (120d) 2026-08-06. Confirm what was actually delivered vs the `positivo-risk-mitigation` PLAN (it was "READY FOR TASK CREATION" — completion not verified here).
- **T1–T4 status is unverified** in this analysis — they may be partially or fully done since the PLAN was written. First action: confirm current state.
- Items P1/P2/P3 are **client-contractual commitments with deadlines**, not just LGPD best-practice — they should rank above the generic LGPD best-practice items.
- Several "NÃO" answers (R64 SCIM, R68 PAM, R104 remote access, R46 formal SI area) are **deliberate architectural/size choices**, not gaps to close — they are documented as compensating-control explanations and can stay NÃO.
- The DPO contact in the Barigui answer shows `paulo@forcheck.com.br` — confirm/normalize to the 4Shark domain.
- **1Password access governance — evaluated and PARKED (2026-06-29).** Goal was to bring the password-manager (the "Layer C" control plane) under IdP/IaC governance. Findings: (a) **SSO unlock** with Google Workspace requires the **Business** plan; 4Shark is on **Teams Starter** (8 members), so SSO would cost ~$52/mo more (9 × $7.99 vs ~$20 flat) — the SSO-tax pattern, declined. (b) The `onepassword` Terraform provider manages **vault structure + items only, NOT membership**, so per-user access cannot be governed by IaC on any plan (that is SCIM's job). Decision: **stay on Teams Starter; 1Password membership remains admin/UI-governed**, documented as Layer C with manual revocation (remove from vault + rotate) — a sound compensating control at this size. **Revisit trigger:** an upgrade to Business (then enable Unlock-with-SSO + SCIM provisioning from Google Workspace) or hitting the Teams 10-user ceiling, which forces Business anyway. Supersedes the prior identity-stack spike note ("provider manages vault items only").

---

## Suggested resolution buckets (for discussion)

1. **Close the client-contractual commitments first** (deadlines + signed assessments): P1 (identity lifecycle proc), P2 (SOC proc), P3 (internal audit + first run), T1 (security events API), and confirm T2–T4.
2. **Operational evidence layer** (LGPD maturity + recurring client asks): P9 (training program + records), P5 (access recertification cadence), P7 (restore-test cadence + records), P6 (BCP/DRP doc), P4 (risk management program).
3. **Low-effort documentation** rounding out the set: P10 (supplier mgmt), P11 (classification), P12 (vuln-mgmt SLA), P8 (tabletop), L1/L2 (AWS DPA + DPO publication confirmation).
4. **Strategic / deferred**: C1 (ISO 27001 / SOC 2), C2 (formal SI area) — only when enterprise sales or a client contract forces it.
