# Auxiliary — the Rollbar token-label convention, extracted verbatim

Source: `~/.claude/docs/runbooks/terraform-operations/ADD-ROLLBAR-PROJECT.md:29-57`.
Referenced by `PLAN-SPIKE.md` findings F1–F3 and by the naming options.

---

## The convention, as written (lines 29–44)

> ## Token label naming convention
>
> Each token is a concealed field in the `Rollbar ENV` 1Password item (Employee
> vault). The label is also the key used in `var.rollbar_project_tokens`. Build it
> from the project's canonical Rollbar Name (the value side of the
> `local.rollbar_projects` map), not the lowercase key:
>
> - Prefix `ROLLBAR_`, then the **entity/client first**, then the type.
> - Split multi-word names at camelCase and letter→digit boundaries:
>   `InovaMaquinas` → `INOVA_MAQUINAS`, `RedeBrasil` → `REDE_BRASIL`,
>   `Atento001` → `ATENTO_001`. Single-cap names stay joined (`Maqnelson` →
>   `MAQNELSON`).
> - Type tokens: backend/API = bare `_APP`; webclient = `_APP_WEBCLIENT`;
>   integrator = `_INTEGRATOR`; harvester = `_SIMPLEX_HARVESTER`.
> - Atento per-country: `ATENTO_<CC>` (e.g. `ATENTO_MX`).
> - Environment suffix last: `_STAGING`, `_DEVELOPMENT`.

## The worked examples (lines 46–53)

| Project key | Token label |
|---|---|
| `app-almaviva-webclient` | `ROLLBAR_ALMAVIVA_APP_WEBCLIENT` |
| `app-shared001-api` | `ROLLBAR_SHARED_001_APP` |
| `integrator-atento-mx` | `ROLLBAR_ATENTO_MX_INTEGRATOR` |
| `simplex-harvester-atento-co-staging` | `ROLLBAR_ATENTO_CO_SIMPLEX_HARVESTER_STAGING` |

## The uniqueness rule (lines 55–57)

> The label must be unique. Since it derives 1:1 from the project key, a collision
> only happens if two keys map to the same label — pick a distinguishing form and
> record it here if a new shape appears.

---

## Decomposed grammar

Reading the rules above, the label is a positional grammar:

```
<SERVICE>_<ENTITY>_<TYPE>[_<ENVIRONMENT>]
```

| Segment | Rollbar instantiation | Rule |
|---|---|---|
| `<SERVICE>` | `ROLLBAR_` | Fixed prefix naming the third-party service |
| `<ENTITY>` | `ALMAVIVA`, `SHARED_001`, `ATENTO_MX` | Client/stack, entity-first; camelCase and letter→digit split |
| `<TYPE>` | `APP`, `APP_WEBCLIENT`, `INTEGRATOR`, `SIMPLEX_HARVESTER` | What kind of thing consumes the token |
| `<ENVIRONMENT>` | `STAGING`, `DEVELOPMENT` | Suffix last; absent = production |

**Note on scope of the convention.** As written, this convention governs a **1Password
field label**, which doubles as the map key in `var.rollbar_project_tokens`. It is not
stated to govern the name of a resource *inside the third-party service*. Whether it
extends to a Datadog key's `name` argument is an extrapolation, not a citation — see the
open decision in `PLAN-SPIKE.md`.

---

## Why Rollbar tokens are created out of band (lines 15–25)

> `rollbar_integration` and `rollbar_notification` bind to the provider's
> `project_api_key` and take no project argument, and Terraform cannot `for_each` a
> provider block. Each project therefore needs its own `provider "rollbar"` alias
> fed by a write-scoped token, plus one module call. The token cannot be created by
> the provider (it only mints legacy unencrypted tokens, which the account
> disables) — it is created out of band and stored in the `Rollbar ENV` 1Password
> item, injected as `var.rollbar_project_tokens` via the stack `.envrc`.

Corroborated in code at `~/Projects/4Shark/terraform/monitoring/rollbar_notifications.tf:9-13`:

> ```
> # The per-project write tokens are NOT created here: the Rollbar provider can
> # only mint legacy (unencrypted) tokens, which this account disables. They are
> # created out of band, stored in the 'Rollbar ENV' 1Password
> # item, and injected as var.rollbar_project_tokens (keyed by the token's
> # 1Password label) via the stack .envrc.
> ```

**Reading:** Rollbar tokens are created out of band because the provider *cannot* create
usable ones — a provider limitation, not a 4Shark policy preference. The Datadog provider
does not have this limitation (`datadog_api_key` creates real keys), so the precedent's
out-of-band half does not transfer. The naming and 1Password-storage halves do.
