# Vendor Assessment — Grupo Barigui

## Context

Grupo Barigui (4Shark customer for 1–2 years) started a cybersecurity maturity assessment of strategic suppliers. They sent a Google Sheets questionnaire to fill, deadline **2026-05-29**.

- **Requester**: Andréia Santos — Digital Products Manager (andreia.santos@grupobarigui.com.br)
- **Technical contact (Cybersecurity)**: Maicon Leite (maicon.leite@grupobarigui.com.br) — must be copied on every technical reply
- **Other recipients**: Matheus Simione (matheus.simione@grupobarigui.com.br), Danilo Assis (4Shark), Sergio Ajimura (4Shark)
- **Format**: editable Google Sheets (link in email). Strategy: fill everything locally in `COMPLIANCE.md`, copy-paste into the Drive at the end
- **Drive link**: https://docs.google.com/spreadsheets/d/1f97DiXq-Zbb31AZM1z90mIvDBjRGEVhyeIFt868WKe0/edit
- **Local reference**: `~/Downloads/FORMULÁRIO DE AVALIAÇÃO DE SEGURANÇA PARA FORNECEDORES _ 4SHARK.xlsx`

### Questionnaire structure

| Block | Content | Rows |
|------|---------|------|
| Header | Title and instructions | 1–9 |
| Company data | Legal name, tax ID, address, contact, email, site | 10–19 |
| Activities | Start date, in-house/outsourced headcount, headcount by department | 21–35 |
| Financials | Gross revenue 2025, 2026, 2027 forecast | 37–41 |
| Section 1 | Governance and Organizational Security [Maturity] (7 questions) | 45–51 |
| Section 2 | Privacy and Data Protection (6 questions) | 53–58 |
| Section 3 | IAM — Authentication (4 questions) | 61–64 |
| Section 4 | IAM — Identity and Access Lifecycle (4 questions) | 67–70 |
| Section 5 | IAM — API Integration (4 questions) | 73–76 |
| Section 6 | Solution Security and Architecture (11 questions) | 78–88 |
| Section 7 | Resilience, Continuity and Disaster Recovery (5 questions) | 90–94 |
| Section 8 | Monitoring and Incident Response (7 questions) | 96–102 |
| Section 9 | Support, Operations and Third-Party Management (5 questions) | 104–108 |

**Answer format**: three columns — `SIM` (col K), `NÃO` (col L), `OBS` (col M). Mark "X" in SIM or NÃO and fill the OBS with the justification.

---

## Strategic context — MUST READ before answering

### 4Shark profile (same as used for Positivo)
4Shark is a **small startup mature in security**, not an enterprise with separate IS/compliance/audit departments. The Barigui questionnaire was designed to assess enterprise suppliers (ISO 27001, SOC 2 Type II, PCI-DSS, SIEM, PAM, SCIM, SAST/DAST, 24x7 SOC — all standard at large companies). 4Shark operates with **substance without the badge**: practices exist, policies are documented, but the company does not have (and does not need) expensive enterprise structures.

### Key difference vs Positivo
Barigui **is already a customer** for 1–2 years. The assessment is not "go/no-go for contracting", it is "trust renewal". The tone can be more direct and confident (no need to prove so hard that we are a decent supplier) — we are a **long-term partner**.

### Status post-Positivo (April 2026)
4Shark committed to 7 mitigations in `DISPOSITION-v2.md` of the Positivo assessment:

| # | Item | Deadline | Current status |
|---|------|----------|----------------|
| 1 | SIEM Integration API (product) | 120 days | In progress (`security-events-platform` plan active) |
| 2 | Formalized HR integration | 60 days | Not implemented yet |
| 3 | Hardening framework (CIS) | 90 days | Not implemented yet |
| 4 | Dedicated DLP | 90 days | Not implemented yet |
| 5 | SIEM with correlation | 90 days | Not implemented yet |
| 6 | Formal SOC | 90 days | Not implemented yet |
| 7 | Formal internal audit | 120 days | Not implemented yet |

**Decision (Paulo, 2026-05-27)**: keep same answers as Positivo — "Nothing changed — keep same answers". All answers involving SOC, SIEM, DLP, PAM, formal internal audit, hardening framework, HR integration follow the same line as Positivo: **NÃO** with substantial OBS about compensatory controls and roadmap.

### Answer principle for SIM/NÃO format

The binary format of Barigui does not allow "Partially Compliant". Adaptation:

- **SIM** when the control exists substantially (even without the specific tool that the question name suggests), and the OBS details how
- **NÃO** when the specific control does not exist even as an equivalent practice — OBS always cites the real compensatory control + roadmap when applicable
- **Never leave OBS empty** even on SIM. The OBS is the substance — the "X" alone does not sell maturity

**When the question lists multiple criteria** (e.g., both TLS 1.2+ AND AES-256), mark SIM only if all are met. If partial, mark NÃO + OBS explaining what exists.

---

## Available documents (4Documents) — reuse from Positivo

Same documentation base used for Positivo. 16 formalized policies:

| # | Document | Barigui questions covered |
|---|----------|---------------------------|
| 1 | Information Security and Cybersecurity Policy v2 | R46, R48, R51, R86, R96 |
| 2 | Identity and Access Management Policy | R67, R69, R70, R76 |
| 3 | Password Policy | R63, R67 |
| 4 | Secure Software Development Policy | R78, R79, R80, R81, R84, R85, R87 |
| 5 | Information Security Incident Response Policy | R96, R98, R99, R100, R101 |
| 6 | Data Storage, Anonymization and Disposal Policy | R56 |
| 7 | Backup and Restoration Policy | R91, R92, R93 |
| 8 | Information Security Awareness Program | R50 |
| 9 | Privacy Policy | R47, R53 |
| 10 | Privacy by Design Policy | R53, R78 |
| 11 | Personal Data Processing Policy | R53, R54, R58 |
| 12 | Sensitive Personal Data Processing Policy | R53, R54 |
| 13 | IT Assets and Network Access Usage Policy | R104 |
| 14 | Corporate Email Usage Policy | General support |
| 15 | Confidentiality Agreement (NDA) | R57 (DPA-adjacent) |

### Architecture diagram
Attach `architecture-diagram.png` (already exists in `vendor-assessment-positivo/`) on answer R107.

---

## Mapping Barigui questions → Positivo equivalents

### Section 1 — Governance and Organizational Security

| Row | Question | Positivo equivalent | Suggested answer |
|-----|----------|--------------------|--------------------|
| R45 | Formal certifications (ISO 27001, SOC 2 II, PCI-DSS) | Q2.28 | **NÃO** — ISO 27001/27002 practices without formal certification |
| R46 | Formal IS area with structure/budget/reporting | Q2.1 | **NÃO** — No separate "formal area"; IS is responsibility of technical leadership + DPO. Structure documented in policies |
| R47 | CISO/DPO/LGPD officer | Q2.7 | **SIM** — Paulo Ribeiro (DPO), paulo@forcheck.com.br |
| R48 | Policies approved + review ≤12 months | Q2.3 | **SIM** — 16 formalized policies, annual review planned |
| R49 | Information classification policy | New (indirect via Sensitive Data Policy) | **SIM** — Coverage via Personal Data and Sensitive Data Processing Policies |
| R50 | Training and awareness (frequency, topics, completion rate) | Q2.31 | **SIM** — Formalized Awareness Program |
| R51 | Risk management with methodology | Q2.34 | **NÃO** — Informal assessment by technical leadership; formal methodology in roadmap |

### Section 2 — Privacy and Data Protection

| Row | Question | Positivo equivalent | Suggested answer |
|-----|----------|--------------------|--------------------|
| R53 | LGPD + ROPA + legal bases + data subject rights | Q2.6 | **SIM** — Privacy Policy + Personal Data Processing |
| R54 | Encryption in transit (TLS 1.2+) and at rest (AES-256) | Q1.6 + Q2.9 | **SIM** — TLS 1.2+ via CloudFlare; AES-256 via AWS KMS on Aurora |
| R55 | Logs ≥6 months (Marco Civil Art. 13/15) | New | **SIM** — CloudWatch retains logs >6 months |
| R56 | Retention, anonymization, disposal with evidence | Q2.14 | **SIM** — Storage, Anonymization and Disposal Policy |
| R57 | Accept signing DPA | New (coverage via NDA) | **SIM** — We accept DPA on contractor's terms |
| R58 | International transfers (mechanism) | Q1.8 | **SIM** — us-east-1 (USA) with VCDPA + AWS contractual clauses |

### Section 3 — IAM Authentication

| Row | Question | Positivo equivalent | Suggested answer |
|-----|----------|--------------------|--------------------|
| R61 | Federated SSO (SAML 2.0, OAuth 2.0, OIDC) | Q1.24-Q1.31 | **SIM** — Keycloak supports SAML 2.0, OAuth 2.0, OIDC |
| R62 | Google Workspace SSO respects MFA from IDP | New | **SIM** — Keycloak delegates MFA to the IDP |
| R63 | Without SSO: MFA TOTP (RFC 6238) or FIDO2 | Q2.23 | **SIM** — Keycloak supports TOTP and FIDO2 |
| R64 | SCIM 2.0 or AD groups for automated provisioning | New | **NÃO** — Provisioning currently manual; SCIM in roadmap |

### Section 4 — IAM Identity and Lifecycle (4Shark environment)

| Row | Question | Positivo equivalent | Suggested answer |
|-----|----------|--------------------|--------------------|
| R67 | MFA mandatory in production/critical data | Q2.19 + Q2.21 | **SIM** — VPN mandatory + YubiKey on AWS master account |
| R68 | PAM (Privileged Access Management) | New | **NÃO** — No dedicated PAM; compensatory controls: VPN + YubiKey + 1Password + least privilege |
| R69 | Lifecycle with documented SLA (revocation ≤24h) | Q2.24 | **SIM** — Immediate deactivation via JWT; offboarding in Identity Policy |
| R70 | Periodic access recertification (semi-annual critical / annual others) | New | **NÃO** — Periodic review is in policies but no formal semi-annual cadence |

### Section 5 — IAM API Integration

| Row | Question | Positivo equivalent | Suggested answer |
|-----|----------|--------------------|--------------------|
| R73 | APIs (REST/GraphQL/SOAP) with documentation and versioning | Q1.32 + Q2.30-adjacent | **SIM** — REST documented and versioned |
| R74 | Native IAM integration | New | **SIM** — Keycloak/SSO (SAML, OAuth, OIDC); SCIM in roadmap |
| R75 | User lifecycle via API with audit | Q1.32 | **SIM** — REST endpoints with audit logs |
| R76 | LDAP with profiles via AD groups | New | **SIM** — Keycloak supports LDAP/AD with group mapping |

### Section 6 — Solution Security and Architecture

| Row | Question | Positivo equivalent | Suggested answer |
|-----|----------|--------------------|--------------------|
| R78 | S-SDLC + Security by Design + threat modeling | Q2.25 + Q1.20 | **SIM** — Secure Development Policy + security review in workflow |
| R79 | SAST + DAST + pentest (frequency, executor) | Q1.22 + Q1.42 | **SIM** — RuboCop/ESLint (static) + Dependabot + annual pentest |
| R80 | SCA (Snyk, OWASP Dependency-Check) | Q2.32 | **SIM** — Dependabot (GitHub) with daily merges |
| R81 | Vuln management with SLA by criticality (CVSS) | Q2.32 | **NÃO** — Formal CVSS SLAs not documented; treatment by priority in practice |
| R82 | Annual pentest by independent third party | Q1.22 | **SIM** — Pentest performed by Positivo (customer); reports can be requested |
| R83 | TLS 1.2+ (no SSL 3.0, TLS 1.0/1.1) + monitored certificates | Q1.18 + Q2.9 | **SIM** — CloudFlare enforces TLS 1.2+; certificates managed |
| R84 | Patch management with SLA, full stack coverage | Q2.32 | **SIM** — ECS/RDS managed by AWS + daily Dependabot |
| R85 | DEV/QA/PRD segregation + no real data in dev/hom | Q2.26 | **SIM** — Segregated environments; policy forbids real data in non-prod |
| R86 | Data storage location (country, region, datacenter, provider) | Q1.7 | **SIM** — AWS us-east-1 (N. Virginia, USA) |
| R87 | APIs: OAuth 2.0, short tokens, rotation, rate limiting, OWASP API Top 10 | Q1.32 + Q1.18 | **SIM** — JWT + CloudFlare rate limiting + OWASP WAF |
| R88 | Audit log export to contractor's SIEM (≥12 months) | Q1.17 | **NÃO** — Security Events API under construction (item 1 of Positivo disposition); internal logs in CloudWatch |

### Section 7 — Resilience, Continuity and DR

| Row | Question | Positivo equivalent | Suggested answer |
|-----|----------|--------------------|--------------------|
| R90 | HA + fault tolerance documented + SLA + uptime 12 months | Q2.4 | **SIM** — Aurora Multi-AZ + ECS auto-recovery + CloudFlare; uptime >99% |
| R91 | Geo-separated backups + encrypted + retention | Q2.4 | **SIM** — Aurora PITR + cross-region AWS backups (KMS encrypted) |
| R92 | Restoration tests ≥semi-annual with documented results | New | **NÃO** — Restoration validated on actual incidents; formal semi-annual tests not documented |
| R93 | DRP/BCP with RTO/RPO + annual test + post-incident review | Q2.4 | **NÃO** — RTO 4h / RPO 1h stated in Backup Policy; formal DRP/BCP not documented as a single artifact |
| R94 | WAF + IDS/IPS + Anti-DDoS | Q1.18 + Q2.17 | **SIM** — CloudFlare WAF + DDoS protection (Anti-DDoS L3/L4/L7) |

### Section 8 — Monitoring and Incident Response

| Row | Question | Positivo equivalent | Suggested answer |
|-----|----------|--------------------|--------------------|
| R96 | Formal incident response policy | Q2.35 | **SIM** — Formalized Incident Response Policy |
| R97 | 24x7 SOC + SIEM with correlation | Q2.10 + Q2.11 | **NÃO** — No dedicated SOC and SIEM with correlation; CloudWatch + Datadog + New Relic + Slack alerts 24x7 |
| R98 | Incidents logged, RCA, lessons learned | Q2.35 | **SIM** — Policy covers full RCA and lessons-learned flow |
| R99 | Notification ≤72h LGPD/GDPR | Q2.35 | **SIM** — Policy provides for notification within LGPD Art. 48 deadlines |
| R100 | Mitigation SLA by criticality | Q2.35 + support | **SIM** — Sev1 4h / Sev2 6h / Sev3 8h (support SLA grid) |
| R101 | Dedicated 24x7 channel with receipt confirmation | Support | **SIM** — Zendesk + 24x7 Slack monitoring |
| R102 | Tabletop post-significant-incidents | New | **NÃO** — No formal tabletop program; post-incident reviews are informal |

### Section 9 — Support, Operations and Third Parties

| Row | Question | Positivo equivalent | Suggested answer |
|-----|----------|--------------------|--------------------|
| R104 | Remote access via secure channel (VPN/PAM) + recorded sessions + time limited | Q2.19 | **NÃO** — VPN mandatory + least privilege; session recording and PAM not implemented |
| R105 | Outsourced support in other countries (legal mechanisms) | New | **NÃO** — Support is internal and domestic (Brazil); no international outsourcing |
| R106 | Segregation between internal, outsourced and customer support + audit | New | **SIM** — Support is exclusively internal; access control by role |
| R107 | Up-to-date architecture documentation + data flow + asset inventory | Q1.3 | **SIM** — `architecture-diagram.png` (attached) + Ansible inventory + internal diagrams |
| R108 | Equivalent fourth-party due diligence | Q2.30 | **NÃO** — Supplier vetting performed in practice; formal due diligence process not documented |

---

## Points requiring engineer decision

### Decision 1 — Tone on controversial SIM vs NÃO

Some questions where SIM with strong OBS could be justified, but I chose NÃO with strong OBS (more honest):

| Row | Question | Alternative option |
|-----|----------|-------------------|
| R46 | Formal IS area | Could mark **SIM** arguing that technical leadership + DPO = formal area. Chose NÃO because "documented structure/budget/hierarchical reporting" does not formally exist |
| R51 | Risk management with methodology | Could mark **SIM** citing informal assessment. Chose NÃO because "defined methodology" does not exist |
| R81 | Vuln management SLA by CVSS | Could mark **SIM** citing priority treatment. Chose NÃO because "SLAs by criticality based on CVSS" not formally documented |
| R88 | Audit log export to SIEM | Could mark **SIM** with "under construction" OBS. Chose NÃO to stay consistent with Positivo disposition (mitigation in progress there) |
| R102 | Post-incident tabletop | Marking NÃO. Could mark SIM if we consider "informal reviews" as tabletop |
| R104 | Recorded sessions | Marking NÃO. Sessions are NOT recorded. Keeping NÃO |
| R108 | Formal due diligence | Marking NÃO. Could mark SIM if we consider informal vetting as due diligence |

→ **Paulo to decide**: review and tell me if you prefer SIM on any of these

### Decision 2 — Attachments needed

| File | Where to attach | Status |
|------|----------------|--------|
| `architecture-diagram.png` | R107 (architecture documentation) | Already exists in `vendor-assessment-positivo/` — copy |
| `si-organogram.png` | Not explicitly requested by Barigui | Do not use |
| 16 IS policies | Eventually requested (R48) | Available in 4Documents |
| Pentest report | R82 | Make available under NDA |

### Decision 3 — Company data (placeholders left in COMPLIANCE.md)

Engineer prefers to fill manually:
- Legal name, tax ID, address, email
- Headcount by department
- Revenue 2025/2026/2027 forecast
- Company email, phone, site

→ COMPLIANCE.md leaves `<preencher>` in all these fields

### Decision 4 — Answer about item 1 of Positivo disposition (Security Events API)

Marking R88 as **NÃO** because the feature is not yet available. But the `security-events-platform` plan exists in `active/`. If delivery is expected before the Barigui deadline or if there is already an MVP, we could change to SIM with "controlled rollout" OBS.

→ **Paulo to decide**: what is the real status of `security-events-platform`?

---

## Pending actions

### Completed during walkthrough session (2026-05-27)

- [x] Walk through all 53 questions one-by-one with Paulo, each answer reviewed and approved
- [x] Copy `architecture-diagram.png` from `vendor-assessment-positivo/` to this folder
- [x] Delete orphaned AWS Backup plan `ec2-Daily-BackupPlan-Virginia` (created by Elven contractor in Aug/2025, pointing to terminated EC2 instances, vault empty)
- [x] Convert `privacidade-dados@4shark.com.br` from individual mailbox to distribution group in Google Workspace
- [x] Validate that `security@4shark.com.br` already exists as a group with Paulo + Émerson as members, configured to accept external posts — adopted as the incident reporting channel for R101
- [x] AWS infrastructure analysis: verified uptime metrics, Aurora backup configuration, KMS encryption, AWS Backup plans, EC2 inventory — all evidence-based answers grounded in CLI verification (not guesses)
- [x] Cross-reference market benchmarks for SLA times (R100) and RTO/RPO (R93) — confirmed 4Shark numbers are within Tier 3 (Important/Business Support) industry standard

### Pre-submission tasks (before pasting to Drive)

- [ ] **Paulo to fill** company data (legal name, tax ID, address, contact, headcount by department, revenue 2025/2026/2027)
- [ ] **Request from Avant Services a properly revised Executive Summary of the retest** — the current report (`~/Downloads/4shark reteste.pdf`) is the original pentest with a "Status" column appended to the findings table; the Executive Summary section still cites "11 falhas encontradas" without distinguishing remediated vs open, and the "Observações Adicionais" describe vulnerabilities in present tense as if still active. Request: a 1–2 page Executive Summary of the retest reflecting 10/11 remediated + 1 still open (F-4 CSP inline styles) with clear remediation status
- [ ] **F-4 (CSP Permite Estilos Inline Não Confiáveis, severity Medium)** — still marked "Vulnerável" in the retest. Decide: remediate now (likely a small change to remove `'unsafe-inline'` from CSP) or document as in active remediation in the assessment response
- [ ] **Verify NDA status with Grupo Barigui** before sending the pentest executive report (R82 commits to attaching the report; if no NDA exists, draft a short one or check existing contract for confidentiality clause)
- [ ] **Attach the latest pentest executive report** alongside the assessment response (committed in R82) — pending Avant's revised Executive Summary
- [ ] **Verify whether the contract with Grupo Barigui includes a quantitative availability SLA** (e.g., 99.5%, 99.9%) — R90 uses neutral phrasing ("conforme termos do acordo vigente"); if a specific number exists, the answer can be strengthened. If asked, prepared reply: SLA tratado conforme níveis de criticidade do incidente conforme cláusulas operacionais
- [ ] **Adjust R82 OBS depending on pentest status at submission time**: if remediation of F-4 is confirmed + Avant sends revised Executive Summary → keep current OBS; if F-4 still open at submission → change OBS to "10 of 11 findings remediated and validated in retest; 1 finding of Medium severity in active remediation"
- [ ] After approval: copy `COMPLIANCE.md` contents into the Google Drive sheet
- [ ] After submission: notify Andréia and Maicon (with Sergio copied)

---

## Strategic context captured during the walkthrough

Throughout the session, Paulo established and reinforced answer principles that should be respected by any future session continuing or revising this work:

- **Don't claim what we don't have** — every "está em roadmap" / "está em desenvolvimento" / "está em avaliação" phrase was removed because it sounds like compliance theater
- **Focus on what exists, don't confess gaps** — even when marking NÃO, the OBS should describe the capability that does exist and avoid explicit acknowledgment of the absence
- **No invented specifics** — no policy names cited unless verified in 4Documents, no fabricated frequencies, no fabricated retention numbers, no fabricated metrics
- **No "small/lean team" framing** — replaced everywhere with arguments grounded in architecture or in the 10-years-zero-incident track record
- **Honest NÃO with strong OBS beats SIM with verifiable lie** — when criteria genuinely don't apply or aren't met, mark NÃO and let the OBS sell the substance of what exists
- **Equivalence arguments only when defensible** — when claiming "we cover this requirement another way" (e.g., R81 vuln management), the equivalence must be technically real (Dependabot really patches faster than enterprise SLA). Stretching to SOC/SIEM equivalence (R97) was rejected as forcing the argument
- **Answer only what was asked** — every "volunteer" detail removed (extra capabilities, extra logs, extra mechanisms) because each one opens new questions

---

## Status

**✅ ASSESSMENT COMPLETE — all 53 questions walked through and approved with Paulo on 2026-05-27.**

`COMPLIANCE.md` (sibling file) contains the 53 final answers in Portuguese, ready for copy-paste to the Google Drive sheet at https://docs.google.com/spreadsheets/d/1f97DiXq-Zbb31AZM1z90mIvDBjRGEVhyeIFt868WKe0/edit. Pre-submission tasks above must be completed (or decisions made) before the actual submission to Andréia and Maicon.
