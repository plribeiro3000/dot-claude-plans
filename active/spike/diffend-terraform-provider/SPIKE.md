# SPIKE — Terraform Provider for Diffend (diffend.io)

**Conducted by:** Engineering Team
**Date:** 2026-03-19
**Status:** Closed — see conclusions

---

## Goal

Determine whether a Terraform provider exists (official or community) for Diffend (diffend.io) — a software supply chain security platform for Ruby gems and npm packages.

Questions to answer:
1. Is there a Terraform provider for Diffend on the Terraform Registry?
2. Is there a community provider on GitHub?
3. Does Diffend expose a REST API suitable for Terraform-style resource management?
4. What alternatives exist for managing Diffend resources programmatically?

Context: The team wants to know if it is viable to manage Diffend resources (projects, tokens, monitoring configurations) via Terraform before deciding on an approach.

---

## Method

- Searched Terraform Registry (registry.terraform.io) for "diffend"
- Searched GitHub for "terraform-provider-diffend" repositories
- Inspected the diffend-io GitHub organization for all public repositories
- Fetched the official Diffend/Mend platform at my.diffend.io
- Researched the diffend gem RubyDoc documentation
- Searched for Diffend API documentation and programmatic management references
- Researched Mend.io (acquirer) for any Terraform provider or API offerings

---

## Evidence

### 1. Terraform Registry — No provider found

Search on registry.terraform.io for "diffend" returned zero relevant results. The only loosely-related result was `sms-system/diff-state`, an unrelated utility provider. No provider named "diffend" or "mend" exists on the public registry.

Source: registry.terraform.io/browse/providers (searched March 2026)

### 2. GitHub — No terraform-provider-diffend repository exists

Search for "terraform-provider-diffend" on GitHub returned no results. The `diffend-io` GitHub organization contains only **one public repository**:

- `diffend-io/bundler-integrity` — a Ruby gem for Bundler checksum integrity verification (27 stars, last updated May 2022)

There is no Terraform provider repository in the organization. The main `diffend-io/diffend-ruby` gem repository is referenced in documentation but does not expose or document any management API.

Source: github.com/diffend-io (fetched March 2026)

### 3. Diffend platform status — Acquired by Mend

Diffend was acquired by Mend (formerly WhiteSource). The platform at `my.diffend.io` continues to operate as "Mend Supply Chain Defender." The footer now reads "Copyright © 2026 Mend Software."

The platform remains active for RubyGems diff analysis, but all branding and strategic direction now falls under Mend.

Source: my.diffend.io (fetched March 2026), mend.io/blog/welcome-to-whitesource-diffend/

### 4. REST API — Not publicly documented

No public REST API documentation was found for Diffend or Mend Supply Chain Defender. The only API reference discovered is a deprecated setup script endpoint:

```
https://my.diffend.io/api/setup/ruby
```

This endpoint now returns HTTP 404. The `diffend.io/docs` URL timed out during fetch. No endpoints for managing projects, tokens, or configurations were found in any source.

Source: rubydoc.info/gems/diffend/0.2.35, mensfeld.pl/2020/10/diffend-ruby-security/

### 5. Mend.io — No Terraform provider

Mend.io does not offer a Terraform provider. Mend's integration model is focused on CI/CD pipeline plugins, IDE extensions, and the Bundler plugin (`bundle plugin install diffend`). No Mend or Diffend entry exists on the Terraform Registry.

Source: mend.io (searched March 2026), registry.terraform.io (searched March 2026)

### 6. Diffend configuration model

Diffend operates through:
- A Bundler plugin installed via `bundle plugin install diffend`
- Configuration via the `.diffend.yml` file in the project root
- Project tokens stored as environment variables or in CI secrets
- No documented management plane API for creating/modifying projects or tokens

The gem communicates with `my.diffend.io` during bundle operations but does not expose this as a public API.

---

## Conclusions

1. **No Terraform provider exists** for Diffend or Mend Supply Chain Defender — neither official nor community-maintained.

2. **No public REST API** is documented for managing Diffend resources (projects, tokens, monitoring configurations). The setup API endpoint is deprecated (HTTP 404).

3. **The platform has been absorbed by Mend**, which also does not offer a Terraform provider. The integration model is CI/CD-centric, not infrastructure-as-code-centric.

4. **Terraform management of Diffend is not viable** in the traditional sense. There is no resource model to manage — no projects API, no tokens API, no webhook configuration API.

5. **Closest alternatives for automation**:
   - Store Diffend project tokens in GitHub Actions secrets (already the standard pattern for similar integrations in this codebase)
   - Use the `diffend` Bundler plugin with token injected at CI runtime
   - Manage the `.diffend.yml` config file as part of the application repository (version-controlled but not Terraform-managed)
   - If Mend exposes an enterprise API in the future, a custom Terraform provider could be built — but this is not currently feasible

---

## Next Steps

- **No implementation needed**: Diffend cannot be managed via Terraform. No PLAN.md required.
- **Decision needed**: The team should decide how Diffend tokens and project configuration will be managed. The recommended path is: tokens as GitHub Actions secrets (already used for similar services) + `.diffend.yml` committed to the app repository.
- **Monitor**: If Mend releases a public REST API or Terraform provider, revisit this decision. Check mend.io developer documentation periodically.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
