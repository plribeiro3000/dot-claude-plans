# SPIKE — GitHub SSO with Keycloak as Identity Provider

**Conducted by:** Paulo Ribeiro
**Date:** 2026-04-13
**Status:** Research complete — pending decisions

---

## Goal

Determine whether and how 4Shark can configure Single Sign-On (SSO) for GitHub using the existing Keycloak identity provider. Specifically:

1. Which GitHub plans support SSO?
2. What SSO protocols does GitHub support?
3. Can Keycloak be used as an IdP for GitHub SSO?
4. What are the steps to configure GitHub SAML SSO?
5. What happens to existing users and repositories when SSO is enabled?
6. What is SCIM provisioning and does GitHub support it with Keycloak?
7. Are there any limitations or gotchas?
8. What is the cost difference between plans that support SSO?

---

## Method

- Researched GitHub's official documentation (docs.github.com)
- Searched for community experience with Keycloak + GitHub SAML SSO
- Reviewed GitHub pricing pages and third-party pricing analysis
- Reviewed Keycloak's SCIM roadmap and current release notes (Keycloak 26.6)
- Fetched full content from relevant documentation pages

---

## Evidence

### 1. Which GitHub Plans Support SSO?

SAML SSO is exclusively available on **GitHub Enterprise Cloud**. It is not available on Free or Team plans.

Source: [About identity and access management with SAML SSO](https://docs.github.com/en/enterprise-cloud@latest/organizations/managing-saml-single-sign-on-for-your-organization/about-identity-and-access-management-with-saml-single-sign-on)

| Plan | Price | SAML SSO |
|------|-------|----------|
| Free | $0/user/month | No |
| Team | $4/user/month | No |
| Enterprise Cloud | $21/user/month | Yes |

Source: [GitHub Pricing 2026](https://costbench.com/software/developer-tools/github/)

---

### 2. What SSO Protocols Does GitHub Support?

GitHub supports **SAML 2.0** as the primary SSO protocol. Any IdP that implements the SAML 2.0 standard can be used, not just the officially tested ones.

**OIDC** is also supported, but **only for Enterprise Managed Users (EMU) and only with Microsoft Entra ID**. OIDC is not available for standard organization-level SSO.

The officially supported and tested IdPs for SAML are:
- Microsoft Active Directory Federation Services (AD FS)
- Microsoft Entra ID (formerly Azure AD)
- Okta
- OneLogin
- PingOne
- Shibboleth

Source: [About identity and access management with SAML SSO](https://docs.github.com/en/enterprise-cloud@latest/organizations/managing-saml-single-sign-on-for-your-organization/about-identity-and-access-management-with-saml-single-sign-on)

---

### 3. Can Keycloak Be Used as an IdP for GitHub SSO?

**Yes — Keycloak can be configured as a SAML 2.0 IdP for GitHub.** Keycloak is not on GitHub's officially supported IdP list, but GitHub states that any IdP implementing SAML 2.0 can be used. GitHub support may not be able to assist with Keycloak-specific configuration issues.

There is documented community experience with Keycloak + GitHub Enterprise Server, and the same SAML fundamentals apply to GitHub Enterprise Cloud. The integration works at the protocol level.

Source: [GitHub Enterprise Server SSO with Keycloak (Medium)](https://medium.com/@guillem.riera/github-enterprise-server-sso-with-keycloak-5337652ac621)

---

### 4. Configuration Steps for GitHub SAML SSO with Keycloak

#### In Keycloak

1. Create a dedicated realm (e.g., `github`) or reuse an existing realm.
2. Create a new SAML client in Keycloak:
   - Import GitHub's SAML metadata (available at `https://github.com/orgs/{org}/saml/metadata` for org-level or from the enterprise settings page).
   - Set **Signature Method**: RSA-SHA256
   - Set **Digest Method**: SHA256
   - Set **Name Identifier Format**: Persistent (or email — must match what GitHub expects)
   - **Disable "Client Signature Required"** — this is a known Keycloak issue where it rejects GitHub's signature digest size. Disabling this resolves the error.
3. Add attribute mappers for the following:
   - `givenName` — built-in user property
   - `email` — built-in user property (this is what GitHub uses to link accounts)
   - `full_name` — script-generated or composite attribute
4. Remove full scope to avoid sending unnecessary attributes.
5. Export the Keycloak signing certificate (PEM format, 64-char line wraps, with `-----BEGIN CERTIFICATE-----` headers).

#### In GitHub (Organization level)

1. Navigate to **Organization Settings → Authentication security**.
2. Enable SAML SSO.
3. Fill in:
   - **Sign-on URL**: `https://{keycloak-host}/auth/realms/{realm}/protocol/saml`
   - **Issuer**: `https://{keycloak-host}/auth/realms/{realm}`
   - **Public certificate**: The PEM certificate extracted from Keycloak.
4. Click **Test SAML configuration** — this must succeed before saving.
5. Enable the configuration (do not enforce yet).
6. After testing with a subset of users, enforce SAML SSO.

#### In GitHub (Enterprise level)

The same settings apply but are configured under **Enterprise Settings → Authentication security**. Enterprise-level configuration overrides any existing organization-level SAML configurations.

Sources:
- [Enabling and testing SAML SSO for your organization](https://docs.github.com/en/enterprise-cloud@latest/organizations/managing-saml-single-sign-on-for-your-organization/enabling-and-testing-saml-single-sign-on-for-your-organization)
- [Configuring SAML SSO for your enterprise](https://docs.github.com/en/enterprise-cloud@latest/admin/managing-iam/using-saml-for-enterprise-iam/configuring-saml-single-sign-on-for-your-enterprise)
- [GitHub Enterprise Server SSO with Keycloak (Medium)](https://medium.com/@guillem.riera/github-enterprise-server-sso-with-keycloak-5337652ac621)

---

### 5. What Happens to Existing Users and Repositories When SSO Is Enabled?

**Enable (not enforce) — gradual phase:**
- Existing members keep their GitHub accounts and access.
- GitHub creates a linked record between the member's GitHub account and their IdP identity the first time they authenticate via SSO.
- Members who have not yet authenticated via SSO can still access the organization.
- Outside collaborators are exempt from SSO requirements entirely.

**Enforce — hard cutoff:**
- All members who have NOT authenticated via SSO are **removed from the organization**.
- GitHub sends an email notification to each removed user.
- Bots and service accounts without a linked IdP identity are also removed.
- **Recovery window**: Removed users can rejoin within **3 months** by authenticating via SAML. Their access privileges and settings are restored if they rejoin within that window.
- Repositories are not deleted — only membership is revoked.

**Best practice**: Enable without enforcing first, allow all members to link their accounts, then enforce.

Source: [Enforcing SAML SSO for your organization](https://docs.github.com/en/enterprise-cloud@latest/organizations/managing-saml-single-sign-on-for-your-organization/enforcing-saml-single-sign-on-for-your-organization)

---

### 6. SCIM Provisioning and Keycloak Support

**What is SCIM?**
SCIM (System for Cross-domain Identity Management) automates user provisioning and deprovisioning. When a user is added or removed from a group in the IdP, SCIM propagates that change to GitHub automatically — no manual invitation or removal needed.

**Does GitHub support SCIM?**
Yes, but with significant restrictions:

- SCIM for **organizations** is supported with: **Microsoft Entra ID, Okta, and OneLogin only**.
- SCIM for **Enterprise Managed Users (EMU)** supports: **Okta, PingFederate, and Entra ID**.
- **Keycloak is not an officially supported SCIM provider for GitHub.**

**What about Keycloak's own SCIM support?**
Keycloak added SCIM as an experimental feature in **version 26.6** (released in early 2026). However:
- The implementation is focused on Entra ID compatibility.
- Custom schemas are not yet supported.
- Group resource mapping is limited to `displayName` and `members` only.
- Even if Keycloak exposes a SCIM endpoint, GitHub's SCIM API for organizations expects specific supported providers.

**Workaround**: GitHub exposes a SCIM REST API that can be called directly. A custom integration could be built to bridge Keycloak events (user created/deleted/group changed) to GitHub's SCIM API calls. This is a non-trivial engineering effort.

Sources:
- [About SCIM for organizations](https://docs.github.com/en/enterprise-cloud@latest/organizations/managing-saml-single-sign-on-for-your-organization/about-scim-for-organizations)
- [Keycloak SCIM as experimental feature (April 2026)](https://www.keycloak.org/2026/04/scim-as-experimental-feature)
- [REST API endpoints for SCIM](https://docs.github.com/en/enterprise-cloud@latest/rest/scim/scim)

---

### 7. Limitations and Gotchas

| Issue | Detail |
|-------|--------|
| **No SAML Single Logout** | GitHub does not support SAML SLO. Logging out of GitHub does not log users out of Keycloak, and vice versa. Sessions expire independently. |
| **PAT and SSH key authorization** | After SSO is enabled, existing Personal Access Tokens (classic) and SSH keys must be individually authorized for each SSO-protected organization. Fine-grained PATs are authorized during creation. |
| **GitHub CLI** | `gh` CLI requires an authorized token. If SAML enforcement is active and the token is not authorized, `gh status` and other commands fail. |
| **API access** | REST and GraphQL API calls using PATs will get 401/403 errors if the token is not authorized for SSO. |
| **Bot/service accounts** | Bots using PATs must have those PATs authorized. Bots without linked IdP identities are removed on enforcement. |
| **Re-authentication cadence** | Members must re-authenticate via the IdP periodically (typically every 24 hours) to access organization resources. |
| **Keycloak "Client Signature Required"** | Must be disabled in Keycloak. Keycloak rejects GitHub's SAML authentication requests due to digest size mismatch when this is enabled. |
| **Performance at scale** | Organizations exceeding 100,000 members may experience degraded UI and API performance. |
| **Outside collaborators** | External collaborators are exempt from SSO requirements by default. |
| **Keycloak not officially supported** | GitHub support cannot assist with Keycloak-specific issues. Community resources are the primary reference. |
| **SCIM not available with Keycloak** | Automated user provisioning/deprovisioning requires Entra ID, Okta, or OneLogin. Keycloak requires a custom bridge. |

Sources:
- [About authentication with SSO](https://docs.github.com/en/enterprise-cloud@latest/authentication/authenticating-with-single-sign-on/about-authentication-with-single-sign-on)
- [Authorizing a PAT for use with SSO](https://docs.github.com/en/enterprise-cloud@latest/authentication/authenticating-with-single-sign-on/authorizing-a-personal-access-token-for-use-with-single-sign-on)
- [GitHub Enterprise Server SSO with Keycloak (Medium)](https://medium.com/@guillem.riera/github-enterprise-server-sso-with-keycloak-5337652ac621)

---

### 8. Cost Analysis

| Plan | Price | SSO | SCIM | Notes |
|------|-------|-----|------|-------|
| Free | $0/user/month | No | No | |
| Team | $4/user/month | No | No | |
| Enterprise Cloud | $21/user/month | Yes (SAML 2.0) | Yes (Entra ID, Okta, OneLogin only) | Volume discounts available for 25+ seats (10–20%) |

**Current 4Shark situation**: If 4Shark is on Team or Free, upgrading to Enterprise Cloud is required for SSO. The cost delta is **$17/user/month** ($21 vs $4) or **$21/user/month** (from Free).

For reference, with 10 engineers: $210/month or $2,520/year. Volume discounts require direct sales engagement.

Sources:
- [GitHub Pricing](https://github.com/pricing)
- [GitHub Pricing 2026](https://costbench.com/software/developer-tools/github/)

---

## Conclusions

1. **SSO requires Enterprise Cloud** — there is no path to SSO on Free or Team plans.

2. **Keycloak works as a SAML 2.0 IdP for GitHub** — the integration is technically feasible because GitHub supports any SAML 2.0-compliant IdP, not just the officially listed ones. Community documentation confirms the setup works, with one known workaround (disable "Client Signature Required" in Keycloak).

3. **SCIM with Keycloak is not officially supported** — Keycloak is not on GitHub's supported SCIM provider list for organizations. Automated user provisioning would require either (a) switching to Okta or Entra ID for SCIM, or (b) building a custom bridge from Keycloak events to GitHub's SCIM REST API.

4. **SSO enforcement has a real impact on existing users** — members who have not authenticated via the IdP are removed from the organization on enforcement. A careful rollout (enable first, enforce later) mitigates this risk.

5. **PATs and SSH keys need manual reauthorization** — every developer and every service account must authorize their tokens for SSO after the feature is enabled. This is a one-time action per token, but must be communicated to the team.

6. **No SAML Single Logout** — this is a GitHub limitation, not a Keycloak limitation. Sessions will not propagate logout state across systems.

---

## Next Steps

Three decisions are needed before implementation can proceed:

1. **Plan upgrade**: Confirm whether 4Shark is willing to upgrade to GitHub Enterprise Cloud ($21/user/month) to unlock SSO. Without this, no further configuration is possible.

2. **SCIM strategy**: Decide whether automated user provisioning is required:
   - If yes: evaluate switching SCIM to Okta or Entra ID (alongside Keycloak), or invest in a custom Keycloak-to-GitHub SCIM bridge.
   - If no: manage GitHub membership manually (invite/remove members manually when they join or leave the company).

3. **Rollout plan**: If the upgrade is approved, a PLAN.md should be created covering: plan upgrade, Keycloak client configuration, GitHub SSO configuration, team communication (PAT reauthorization), and enforcement timeline.

Use `@agent-planner` to create a PLAN.md once the decisions above are made.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
