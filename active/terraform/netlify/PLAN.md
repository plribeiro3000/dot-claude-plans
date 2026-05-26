# PLAN — Netlify Sites Management via Terraform

**Feature:** Bring all Netlify frontend sites under Terraform control
**Status:** ❌ Cancelled — 2026-03-12

**Research:** See `~/.claude/plans/active/spike/netlify/SPIKE.md`
**Community research:** See `SPIKE.md`

---

## Objective

Bring all 47 Netlify frontend sites under Terraform control, organized by the backend
application they connect to. Sites are already deployed and operational — this is an
import exercise, not a creation exercise. The Netlify provider cannot create sites,
only manages configuration of existing ones.

---

## Cancellation Reason

After analysis and community research, the decision was made **not to bring Netlify into Terraform**.

**Reasons:**
- The `netlify/netlify` provider (v0.4.1, pre-1.0) does not support site creation — the main IaC value is gone
- What IS supported (build settings, domain settings, env vars) has near-zero ROI:
  - Build settings change rarely and are trivially updated via UI
  - Domain settings are already managed via Cloudflare CNAME in `dns/` and Netlify UI — redundant
  - Env vars: the team does not manage env vars via Terraform for any system, backend or frontend
- Team members and SSO are not supported by the provider
- `app-shared-001` already has 201 resources (at the community warning threshold of 200–300)
- Separate `webclient-*` stacks would have arbitrary groupings with no natural separation in Netlify
- Operational overhead (47-site import, pre-1.0 provider drift) exceeds the value

**Revisit when:** Provider reaches v1.0 and/or adds site creation support (issue #39).
All collected site UUIDs, build commands, and domains remain documented below for future reference.

---

## Open Architectural Question (archived)

Before implementing, a structural decision must be made:

### Option A — Inside existing `app-*` stacks (original plan)

Add `netlify.tf` + (later) `rollbar.tf` directly to `app-atento-001`, `app-beta-001`,
`app-demo-001`, `app-shared-001`.

**Pros:** Fewer directories. Each stack = complete environment (backend + frontend).
**Cons:** `app-shared-001` already has 1,584 lines of backend HCL. Adding 33 Netlify
sites + 34 Rollbar projects (33 frontend + 1 backend) roughly doubles its size.
State locking: a backend infra change blocks a frontend config change.

### Option B — Separate `webclient-*` stacks (proposed revision)

Create 4 new stacks dedicated to frontend infra:

| New stack | Contains |
|---|---|
| `webclient-atento-001` | Netlify (7 sites) + Rollbar (7 frontend projects) |
| `webclient-beta-001` | Netlify (1 site) + Rollbar (1 frontend project) |
| `webclient-demo-001` | Netlify (6 sites) + Rollbar (6 frontend projects) |
| `webclient-shared-001` | Netlify (33 sites) + Rollbar (33 frontend projects) |

Backend Rollbar project stays in the corresponding `app-*` stack.

**Pros:** Backend and frontend state are isolated. `app-shared-001` stays focused on
backend infra. Frontend changes don't block backend applies. Consistent with the
`integrator-*` pattern already in the repo.
**Cons:** 4 new directories. More stacks to manage (though Terramate handles ordering).

**Decision needed:** Community research pending — see `SPIKE.md`.

---

## Decisions Already Made

| Topic | Decision |
|---|---|
| Provider | `netlify/netlify` v0.4.1 — official, maintained by Netlify |
| Team members | Not managed via Terraform — no provider support. Use Netlify Dashboard UI. |
| SSO | Not available — requires Enterprise plan. Not in use. |
| Env vars | All in `terraform.tfvars`, variable set per site (common base + optional) |
| Sensitive vars | None — Rollbar client token is `post_client_item` scope only, safe in tfvars |
| Migration approach | All sites at once, not incrementally |
| Resources to use | `netlify_site_build_settings`, `netlify_site_domain_settings` — NOT `netlify_site_metadata` (does not exist) |
| Import strategy | Terraform 1.5+ `import` blocks with `for_each`. Put in `import.tf` (temporary, remove after first apply) |
| Netlify Identity | Removed from `fourshark-app-client` on 2026-03-12 — was never used, 0 users since 2019 |

---

## Site Inventory with IDs and Build Settings

Collected via Netlify API on 2026-03-12. Saved in full at:
`/tmp/netlify_all_sites_settings_20260312_*.txt`

### AppAtento 001 (7 sites)

| Netlify Site | UUID | Production Branch | Build Command | Publish Dir | Custom Domain |
|---|---|---|---|---|---|
| `fourshark-app-client-atento-ar` | `2ea8728d-793a-4079-b38c-2af014b39837` | `atento` | `yarn build atento && rm dist/3rdpartylicenses.txt` | `dist/` | atento-ar.app4shark.com |
| `fourshark-app-client-atento-br` | `eccd4f4b-432e-446d-a11f-234d0c0650fd` | `atento` | `yarn build atento  && rm dist/3rdpartylicenses.txt` | `dist` | atentoprime-br.app4shark.com (alias: atentoprime-br.atento.com) |
| `fourshark-app-client-atento-cl` | `9455e721-556a-4c77-9d89-38ac3a48d9f1` | `atento` | `yarn build atento && rm dist/3rdpartylicenses.txt` | `dist` | atento-cl.app4shark.com |
| `fourshark-app-client-atento-co` | `037c132e-ff6d-45b0-b8d7-300bf11ec777` | `atento` | `yarn build atento && rm dist/3rdpartylicenses.txt` | `dist/` | atento-co.app4shark.com |
| `fourshark-app-client-atento-gt` | `005b4831-b9e6-442c-9265-d29ec5584e03` | `atento` | `yarn build atento && rm dist/3rdpartylicenses.txt` | `dist/` | atento-gt.app4shark.com |
| `fourshark-app-client-atento-mx` | `8e53beee-76ad-498a-b651-4373815d819a` | `atento` | `yarn build atento && rm dist/3rdpartylicenses.txt` | `dist/` | atento-mx.app4shark.com |
| `fourshark-app-client-atento-pe` | `47803ee6-1006-4226-8962-53cefa927bff` | `atento` | `yarn build atento && rm dist/3rdpartylicenses.txt` | `dist/` | atento-pe.app4shark.com |

### AppBeta 001 (1 site)

| Netlify Site | UUID | Production Branch | Build Command | Publish Dir | Custom Domain |
|---|---|---|---|---|---|
| `fourshark-app-client-beta` | `1f94c733-5bcd-470d-8d5a-4823064d6207` | `develop` | `yarn prettier:check && yarn lint:ng && yarn lint:htmlhint && yarn build 4shark` | `dist` | beta.app4shark.com |

### AppDemo 001 (6 sites)

| Netlify Site | UUID | Production Branch | Build Command | Publish Dir | Custom Domain |
|---|---|---|---|---|---|
| `fourshark-app-client-demo` | `5c3624c5-2359-4f8e-987a-b5e0926556b7` | `chore/update-brand-colors-and-assets` ⚠️ | `yarn prettier:check && yarn lint:ng && yarn lint:htmlhint && yarn build 4shark && rm dist/3rdpartylicenses.txt` | `dist` | demo.app4shark.com |
| `fourshark-app-client-next` | `b533bd7d-c390-491d-8a39-c002d4f15093` | `master` | `yarn lint:ng && yarn lint:htmlhint && yarn build 4shark` | `dist` | next.app4shark.com |
| `fourshark-app-client-next-cl` | `428ca161-3d77-4ac6-b3fd-116743f7c928` | `master` | `yarn lint:ng && yarn lint:htmlhint && yarn build 4shark` | `dist` | next-cl.app4shark.com |
| `fourshark-app-client-next-co` | `2e28e9bf-4d7f-465d-85d8-d701042dfac9` | `master` | `yarn lint:ng && yarn lint:htmlhint && yarn build 4shark` | `dist` | next-co.app4shark.com |
| `fourshark-app-client-next-en` | `226fd4cd-6394-42fd-a825-26c3cf055e4b` | `master` | `yarn lint:ng && yarn lint:htmlhint && yarn build 4shark` | `dist` | next-en.app4shark.com |
| `fourshark-app-client-next-mx` | `d92b531e-d2a1-4c59-a115-4b48265e1a6a` | `master` | `yarn lint:ng && yarn lint:htmlhint && yarn build 4shark` | `dist` | next-mx.app4shark.com |

⚠️ `fourshark-app-client-demo` has a feature branch (`chore/update-brand-colors-and-assets`) as
production branch — likely left over from a deploy. Needs to be corrected before or during import.

### AppShared 001 (33 sites)

| Netlify Site | UUID | Production Branch | Build Command | Publish Dir | Custom Domain |
|---|---|---|---|---|---|
| `fourshark-app-client` | `64d9ad28-b49f-4cc8-bdb3-cca0a74bb812` | `master` | `yarn build 4shark` | `dist` | operador.app4shark.com (aliases: vendedor.app4shark.com, www.app4shark.com) |
| `fourshark-app-client-almaviva` | `ff1c86d9-31e7-4d83-89d8-1b44007baca7` | `old-front` | `yarn build almaviva` | `dist` | almaviva.app4shark.com |
| `fourshark-app-client-atlas-schindler` | `48cc3b77-9f7e-4809-a84d-fcd64a37e30b` | `master` | `yarn build atlas_schindler` | `dist` | atlas-schindler.app4shark.com |
| `fourshark-app-client-bostonscientific` | `2981949c-4554-440a-b616-52641e1bdcd1` | `master` | `yarn build boston_scientific` | `dist/` | bostonscientific.app4shark.com |
| `fourshark-app-client-brisanet` | `740b4ecb-0da3-4215-8cf0-d8d2911b85cf` | `master` | `yarn build brisanet` | `dist` | brisanet.app4shark.com |
| `fourshark-app-client-cabralesousa` | `9f20c29c-c596-4b3b-a1e9-4cb92cdc577f` | `master` | `yarn build cabralesousa` | `dist` | cabralesousa.app4shark.com |
| `fourshark-app-client-castropil` | `d324f1e5-136e-4873-96aa-78bb8cced053` | `master` | `yarn build castropil` | `dist` | castropil.app4shark.com |
| `fourshark-app-client-cmaacanapolis` | `27862ea7-0d57-476c-bd71-f9dd123d2be1` | `master` | `yarn build cmaa-canapolis` | `dist` | cmaacanapolis.app4shark.com |
| `fourshark-app-client-cmaavaledopontal` | `86f171c8-288b-4e92-aa70-ac09ab349d93` | `master` | `yarn build cmaa-pontal` | `dist` | cmaavaledopontal.app4shark.com |
| `fourshark-app-client-cmaavaledotijuco` | `c293bc6b-78c0-4317-a765-0038a243ccc6` | `master` | `yarn build cmaa-tijuco` | `dist` | cmaavaledotijuco.app4shark.com |
| `fourshark-app-client-dpaschoal` | `b9df9a3a-1c79-472d-83d7-87da07b3c440` | `master` | `yarn run build dpaschoal` | `dist/` | dpaschoal.app4shark.com |
| `fourshark-app-client-easy` | `e6506ead-df68-45c8-8de2-92978ac705af` | `master` | `yarn build 4shark_easy` | `dist` | easy.app4shark.com |
| `fourshark-app-client-ecom` | `a7f75e32-3175-4e18-b712-664f2e1fd428` | `master` | `yarn build ecom` | `dist/` | ecomenergia.app4shark.com |
| `fourshark-app-client-goodyear` | `c22ddcdd-2937-4797-b86b-86b229f0e89d` | `master` | `yarn build goodyear` | `dist` | goodyear.app4shark.com |
| `fourshark-app-client-grupobarigui` | `b61bc493-6ffe-40d3-b4f8-054529eba3ca` | `master` | `yarn build grupo_barigui` | `dist/` | grupobarigui.app4shark.com |
| `fourshark-app-client-grupoelfa` | `a25679a3-a214-4520-9de9-a87a8df21fde` | `master` | `yarn build grupo_elfa` | `dist` | grupoelfa.app4shark.com |
| `fourshark-app-client-grupoveneza` | `4d290f6a-6a67-46d5-978d-e59374454260` | `master` | `yarn build grupo_veneza` | `dist/` | grupoveneza.app4shark.com |
| `fourshark-app-client-hapvida` | `c13a6bcd-aec9-47ca-bf02-2c666a70c5ae` | `master` | `yarn build hapvida` | `dist` | hapvida.app4shark.com |
| `fourshark-app-client-inova-maquinas` | `9e998f59-8342-43fc-8953-9c465e20b675` | `master` | `yarn run build inova_maquinas` | `dist/` | inovamaquinas.app4shark.com |
| `fourshark-app-client-lavronorte` | `b70d48ba-87e6-414f-a3d7-af34697cf7b4` | `master` | `yarn build lavronorte` | `dist/` | lavronorte.app4shark.com |
| `fourshark-app-client-liberta` | `1a642caf-abb8-41ba-a010-def401cad455` | `master` | `yarn build liberta` | `dist/` | liberta.app4shark.com |
| `fourshark-app-client-lugardegente` | `005f552e-7115-42f1-9f4c-f643c71deccc` | `master` | `yarn build lugardegente` | `dist` | lugardegente.app4shark.com |
| `fourshark-app-client-maislaser` | `8bdb5068-bb69-4919-a8f9-b3d94d1d332f` | `mais-laser` | `yarn build mais_laser && rm dist/3rdpartylicenses.txt` | `dist` | maislaser.app4shark.com |
| `fourshark-app-client-maqnelson` | `d5c56e4c-2ffc-4bc9-8a04-4a10777ec467` | `old-front` | `yarn build maqnelson` | `dist` | maqnelson.app4shark.com |
| `fourshark-app-client-mill-energia` | `b58910ed-fb5a-474d-b40e-574f35106efc` | `master` | `yarn build mill_energia` | `dist/` | millenergia.app4shark.com |
| `fourshark-app-client-pierrefabre` | `48f06ca4-85ab-442f-9d63-cb0187966cc2` | `master` | `yarn build pierre_fabre` | `dist/` | pierrefabre.app4shark.com |
| `fourshark-app-client-redebrasil` | `5d504b96-d921-4398-b41e-4c9d2f89f67f` | `old-front` | `yarn build rede_brasil` | `dist` | redebrasil.app4shark.com |
| `fourshark-app-client-self-telefonia` | `1eda5eb7-d539-4af3-8cd8-06bc4f8ca4b8` | `master` | `yarn build self_telefonia` | `dist` | self-telefonia.app4shark.com |
| `fourshark-app-client-tools4change` | `e2063bf3-5b2b-4ee4-b7f6-f44d2e8d12f9` | `master` | `yarn build tools_4_change` | `dist/` | tools4change.app4shark.com |
| `fourshark-app-client-totvs` | `774214ee-ec8d-4880-8bf9-748a2f28a224` | `master` | `yarn build totvs` | `dist` | totvs.app4shark.com |
| `fourshark-app-client-unimaq` | `652d95cb-0b24-4c23-8e8d-20162e93f752` | `master` | `yarn build unimaq` | `dist/` | unimaq.app4shark.com |
| `fourshark-app-client-valecard` | `f100ffa8-1e2f-459a-9814-581098e27e72` | `master` | `yarn build valecard` | `dist/` | valecard.app4shark.com |
| `fourshark-app-client-wolfmexico` | `99e8443e-2385-4499-84d9-aa65bfe6e08a` | `master` | `yarn build wolfmexico` | `dist/` | wolfmexico.app4shark.com |

### Excluded from Terraform management

| Netlify Site | UUID | Reason |
|---|---|---|
| `redesign-menu-temp` | `930f21f7-4e01-4c73-87f1-42124af348a3` | Temporary site, no custom domain |

---

## Notes on Build Settings

- `production_branch` in the API field `build_settings.branch` is null for all sites.
  The `allowed_branches` field shows the actual branch currently deployed to production.
  In Terraform, `production_branch` is optional — omit it to avoid drift on import.
- Publish directory inconsistency: some sites use `dist/` (with trailing slash), others `dist`.
  Use exact values from the API table above to avoid unintended changes on first apply.
- `fourshark-app-client-demo` has a feature branch as production branch — should be fixed to `master`
  before or during import. Confirm with team.
- `fourshark-app-client-atento-br` has an alias on a different domain: `atentoprime-br.atento.com`.
  This needs to be included in `domain_aliases` when managing domain settings.

---

## Pending Items

### Architectural decision (BLOCKING)
- [ ] Review `SPIKE.md` when ready
- [ ] Decide: Option A (in `app-*` stacks) or Option B (separate `webclient-*` stacks)
- [ ] Update this PLAN.md accordingly before implementation

### Netlify — Team Members (manual)
- [ ] Add Paulo and Emerson as team members via Netlify Dashboard
- [ ] Store credentials in 1Password

### Netlify — Sites via Terraform
(Tasks below apply to whichever stack structure is chosen)

- [ ] Add `netlify/netlify` provider to `providers.tf` of each target stack
- [ ] Create `netlify.tf` in each target stack (47 sites across 4 stacks)
- [ ] Create `import.tf` in each target stack (temporary — remove after first apply)
- [ ] Confirm `fourshark-app-client-demo` production branch with team before importing
- [ ] Run `terraform init` in each stack
- [ ] Run `terraform plan` to verify import produces no unintended changes
- [ ] Run `terraform apply` to complete import
- [ ] Remove `import.tf` files after successful apply
- [ ] Update Terramate dependency graph in `dns/stack.tm.hcl` to add `after` entries for the Netlify stacks

---

## Rollbar — Scope Note

Rollbar management is out of scope for this feature but must be considered in the
architectural decision above. Each frontend site will need a Rollbar project. If
Option A is chosen, that means `app-shared-001` would manage 33+ Rollbar frontend
projects on top of existing backend resources. If Option B is chosen, each
`webclient-*` stack manages its own Rollbar projects.
