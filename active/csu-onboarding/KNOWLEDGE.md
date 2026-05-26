# KNOWLEDGE — CSU Onboarding

CSU is a new 4Shark client currently being onboarded. This document captures the domain knowledge needed for any conversation involving CSU's integration, SSO matching, or user provisioning while onboarding is in progress.

## Identity provider

CSU's user data and SSO go through their **Microsoft Entra** tenant. There is no plan to use any other IdP for this client.

## Unique identifier — matrícula → `employeeId`

The unique identifier correlating Entra users to 4Shark users is the **matrícula** (CSU's internal HR-system employee number). In Microsoft Graph, this attribute is `employeeId`.

- The 4Shark side uses `AuthenticatorConfiguration.identity_provider_user_uuid` to hold this value
- The Microsoft Graph attribute requested for synchronization is `employeeId` — **not** `id`, **not** `userPrincipalName`, **not** `mail`

This decision was made explicitly by CSU's IT team during the onboarding alignment. The reason is that matrícula is the same identifier used by their internal HR system of record; using anything else would break the link between 4Shark cadastro and HR.

## How to apply

When discussing CSU's user provisioning, SSO matching, or required Microsoft Graph attributes:

- **List `employeeId` as a non-negotiable attribute** in any required-permissions document or email to CSU
- **Do not** offer alternatives like "`id` or `employeeId`" — only `employeeId` works for this client
- When implementing or testing the SSO matcher for CSU, the test fixture must use `employeeId`, not the generic Entra `id`

## Open items

(Track open items here as onboarding progresses — Graph permissions approval, first sync test, production cutover.)
