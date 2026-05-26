# Vendor Assessment Positivo — Risk Mitigation Response

**Date**: 08/04/2026
**Source**: Email from AB (Positivo) with attached risk table (Tabela de Riscos - 4Shark.xlsx)
**Context**: After assessment review, Positivo identified 7 risks requiring mitigation plans and compensatory controls

## Response format

For each item:
- **Agreed timeline**: Accept or propose adjustment
- **Mitigation**: What will be implemented to resolve the risk
- **Compensatory**: Current controls that reduce risk while mitigation is in progress

---

## Item 1 — SIEM Integration (Product)

**Category**: Produto
**Risk level**: BAIXO
**Mitigation deadline**: 120 days

**Original question (Q1.17)**: Establish connectivity with corporate SIEM systems for detection, prevention and vulnerability monitoring.

**Our original response**: Partially Compliant — The platform has centralized security monitoring with automated alerts. Authentication and user activity events are logged internally. The platform does not have native integration with external SIEM tools.

**Risk identified**: The platform must expose security events so the client's SIEM can consume them.

**Agreed timeline**: 120 days — accepted

**Mitigation**: Implementation of a Security Events REST API (read-only endpoint, authenticated by API token) that exposes authentication, authorization and user management events in JSON format, enabling integration with any SIEM platform. Opt-in per client.

**Compensatory**: Centralized security monitoring with automated alerts integrated with the operations team. Authentication and user activity events are logged internally.

---

## Item 2 — User Identifier and HR Integration

**Category**: Ambiente do Parceiro
**Risk level**: ALTO
**Mitigation deadline**: 60 days

**Original question (Q2.21)**: Unique nominal user identifier integrated with the company's HR system.

**Our original response**: Partially Compliant — Every employee has a unique, personal and non-transferable identifier. Access management for engineering and infrastructure is centralized via infrastructure as code, with provisioning and revocation in a single operation. There is no automated integration between the HR system and identity management — the process is initiated manually by the manager.

**Risk identified**: Missing automated integration between HR and identity management. HIGH risk.

**Agreed timeline**: 60 days — accepted

**Mitigation**: Formalization of identity management procedure integrated with the employee lifecycle, with documented onboarding/offboarding checklists, defined responsibilities and execution records.

**Compensatory**: All employees have a unique and personal identifier. Access management is centralized with provisioning and revocation in a single operation. Offboarding includes immediate revocation of all access via administrative account protected by physical device.

---

## Item 3 — Hardening Methodology

**Category**: Ambiente do Parceiro
**Risk level**: MEDIO
**Mitigation deadline**: 90 days

**Original question (Q2.33)**: Hardening methodology for assets. Must indicate the framework used.

**Our original response**: Partially Compliant — Hardening practices are applied across all layers under responsibility: dedicated network segmentation per application and environment, private subnets for databases, access restricted via VPN, identity management with tiered privileges, firewall rules with least privilege, infrastructure managed as code. No formal hardening framework (CIS, NIST) adopted.

**Risk identified**: Must indicate a formal hardening framework.

**Agreed timeline**: 90 days — accepted

**Mitigation**: Formal adoption of CIS Benchmarks as hardening reference, with automated and continuous verification enabled in the cloud environment.

**Compensatory**: Hardening practices applied across all layers: network segmentation, internal access exclusively via VPN, least privilege access control, administrative account protected by physical device, and infrastructure managed as code with full change traceability.

---

## Item 4 — DLP (Data Loss Prevention)

**Category**: Ambiente do Parceiro
**Risk level**: MEDIO
**Mitigation deadline**: 90 days

**Original question (Q2.12)**: Data loss and leakage prevention technology (DLP) with monitoring and active response to deviations.

**Our original response**: Partially Compliant — Information protection controls implemented including encryption in transit and at rest, restrictive access control (RBAC, least privilege), mandatory VPN for internal access and information classification policies. No dedicated DLP solution.

**Risk identified**: Must have DLP technology with monitoring and active response.

**Agreed timeline**: 90 days — accepted

**Mitigation**: Implementation of data loss prevention technology with automated monitoring for sensitive data detection and active response to deviations.

**Compensatory**: Information protection controls implemented: encryption in transit and at rest, restrictive access control with least privilege, internal access exclusively via VPN, credentials managed via corporate vault, and formal information classification and handling policies.

---

## Item 5 — SIEM / Event Correlation (Partner Environment)

**Category**: Ambiente do Parceiro
**Risk level**: MEDIO
**Mitigation deadline**: 90 days

**Original question (Q2.11)**: Security event correlation system to analyze and identify patterns or relationships between security events in real time.

**Our original response**: Partially Compliant — Centralized logs and automated alerts configured. No dedicated SIEM solution with event correlation across multiple sources.

**Risk identified**: Must have a system that correlates security events in real time, identifying patterns across multiple sources.

**Agreed timeline**: 90 days — accepted

**Mitigation**: Implementation of security event correlation system with automated threat detection across multiple log sources.

**Compensatory**: Security logs centralized across multiple layers (application, infrastructure and web traffic) with automated alerts integrated with the operations team for anomalous event detection.

---

## Item 6 — SOC (Security Operations Center)

**Category**: Ambiente do Parceiro
**Risk level**: MEDIO
**Mitigation deadline**: 90 days

**Original question (Q2.10)**: Security Operations Center (SOC) to monitor, detect and respond to security incidents.

**Our original response**: Partially Compliant — Security monitoring performed by the IT team with support from observability tools and automated alerts.

**Risk identified**: Must have a SOC to monitor, detect and respond to security incidents.

**Agreed timeline**: 90 days — accepted

**Mitigation**: Implementation of Security Operations Center (SOC).

**Compensatory**: Automated monitoring with security alerts integrated with the operations team. Formalized Information Security Incident Response Policy.

---

## Item 7 — Internal Audit

**Category**: Ambiente do Parceiro
**Risk level**: BAIXO
**Mitigation deadline**: 120 days

**Original question (Q2.29)**: Internal audit process that evaluates compliance with security policies, guidelines and controls. Including sanctions for deviations.

**Our original response**: Partially Compliant — Security policies include periodic review. The IT team performs regular checks on implemented controls. Formalization of a structured internal audit process is in development.

**Risk identified**: Must have established internal audit process with compliance evaluation and sanctions.

**Agreed timeline**: 120 days — accepted

**Mitigation**: Implementation of internal security audit process with defined frequency, covering all current policies.

**Compensatory**: Information security policies include periodic review and disciplinary measures clauses for deviations. Infrastructure managed as code with full change traceability via version control.

---

## Summary

| Item | Risk | Deadline | Timeline decision |
|------|------|----------|-------------------|
| 1 | BAIXO | 120 days | Accepted |
| 2 | ALTO | 60 days | Accepted |
| 3 | MEDIO | 90 days | Accepted |
| 4 | MEDIO | 90 days | Accepted |
| 5 | MEDIO | 90 days | Accepted |
| 6 | MEDIO | 90 days | Accepted |
| 7 | BAIXO | 120 days | Accepted |

## Technical actions (internal — not shared with Positivo)

### Items 3 + 5 + 6 resolve together
- Activate GuardDuty (automated threat detection from CloudTrail + VPC Flow Logs + DNS)
- Activate Security Hub with CIS AWS Foundations Benchmark (continuous compliance checks)
- Formalize SOC procedures (alert triage, response, escalation)
- One implementation covers hardening framework (CIS), SIEM (correlation), and SOC (detection + response)

### Item 4 (DLP)
- Activate AWS Macie for S3 sensitive data detection
- Configure DLP rules in Google Workspace (Gmail + Drive)

### Item 1 (SIEM Product)
- Implement Security Events API (REST, JSON, per-company token auth)
- Capture auth events from all 3 login flows (password, SSO, Devise web)
- Feature flag per company
- Estimated effort: 7-8 dev days

### Item 2 (HR Integration)
- Document onboarding/offboarding procedure with checklist
- Formalize identity lifecycle tied to Google Workspace as identity hub

### Item 7 (Internal Audit)
- Create Internal Audit Procedure document
- Perform first audit and generate report

## Pending actions

- [ ] Confirm response deadline with Danilo/Positivo (email does not specify)
- [ ] Fill Excel compensatory column with approved texts
- [ ] Return filled Excel to Positivo
- [ ] After approval: risks and timelines go to legal for contract inclusion
- [ ] After each mitigation deadline: Positivo will request evidence of implementation
