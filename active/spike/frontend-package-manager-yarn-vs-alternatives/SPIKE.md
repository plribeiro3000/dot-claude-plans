# SPIKE — Frontend package manager: keep Yarn or migrate?

**Investigation date:** 2026-09-11
**Trigger:** A "Four Line Friday" newsletter recommended `aube` ("still typing npm, but running aube") as a drop-in package manager. This prompted the question of whether 4Shark's frontend (`app-webclient`) should stay on Yarn or move to one of the newer tools (aube / bun / pnpm), especially framed around supply-chain security.

## Investigation question

On 2026-09-11, is it safer to keep `app-webclient` on Yarn, or to migrate to another JavaScript dependency manager (pnpm, bun, or the newly released aube)? And are these tools even the same category of thing?

## Context

4Shark's history with frontend dependency managers: Bower (Twitter, ~2013, now dead) → npm → Yarn. The team adopted Yarn around 2017 (when npm had not yet reached feature parity) and has stayed on it. The newsletter reintroduced the question because `aube` markets security and performance as differentiators, and 2026 has been dominated by npm-registry supply-chain attacks.

## Sources consulted

- [aube.sh](https://aube.sh/) — official site; what aube is, its claims (fetched directly).
- [github.com/jdx/aube](https://github.com/jdx/aube) / [crates.io/crates/aube](https://crates.io/crates/aube) — author (jdx, creator of mise), Rust implementation, MIT, active development (via search).
- [Hacker News: Aube](https://news.ycombinator.com/item?id=47948568) — community reception; production-readiness concerns (fetched directly).
- [Reintech: npm vs Yarn vs pnpm vs Bun 2026](https://reintech.io/blog/npm-vs-yarn-vs-pnpm-vs-bun-2026-comparison) — category comparison (via search).
- [Socket: npm introduces minimumReleaseAge](https://socket.dev/blog/npm-introduces-minimumreleaseage-and-bulk-oidc-configuration) — npm 11 min-release-age (via search).
- [pnpm: supply-chain security](https://pnpm.io/supply-chain-security) — pnpm `minimumReleaseAge` (via search).
- [Microsoft Security: Shai-Hulud 2.0](https://www.microsoft.com/en-us/security/blog/2025/12/09/shai-hulud-2-0-guidance-for-detecting-investigating-and-defending-against-the-supply-chain-attack/) — Nov/2025 wave (via search).
- [Unit 42: Shai-Hulud npm supply-chain attack](https://unit42.paloaltonetworks.com/npm-supply-chain-attack/) — attack timeline (via search).
- Local state: `~/Projects/4Shark/app-webclient/package.json`, `.yarnrc.yml`, `renovate.json` (read directly).

> Note on sourcing: `aube.sh` and the Hacker News thread were fetched verbatim. The remaining external claims come from aggregated web-search summaries rather than a verbatim re-fetch of each page; they are directional and should be re-verified against the linked page before being quoted as exact wording.

## Findings

### Finding 1: The five tools are not one category

Four of them are package managers (install/manage dependencies): **npm**, **Yarn**, **pnpm**, **aube**. **bun** is a full JavaScript *runtime* (runs JS, bundles, tests) written in Zig that *also* ships a package manager — adopting bun as a package manager pulls in the runtime commitment. **Bower** is a dead package manager (deprecated years ago). The newsletter's item #1 ("Executor") is not a package manager at all — it is an "MCP-of-MCPs" for AI agents, unrelated to this question.

**Significance:** "Should we switch package managers?" and "should we adopt bun?" are different-sized decisions. bun is a runtime migration, not a like-for-like swap.

### Finding 2: The 2026 security story is the npm registry, not any one tool

The dominant JS security event of 2025–2026 is the **Shai-Hulud** self-replicating worm on the npm registry, in multiple waves: Sept/2025 (1,300+ package versions, ~2B downloads/month), Nov/2025 "V2" (700+ packages, ~14,000 secrets exposed), May/2026 "Mini", Aug/2026 (1,280+ packages, stealing GitHub/npm/AWS/SSH/VPN secrets during `install`).

Because every one of these managers installs from the same npm registry, a compromised published package affects them equally. The threat is not "which manager", it is "which published versions land in `node_modules`".

**Source:** Microsoft Security (Shai-Hulud 2.0), Unit 42.

**Significance:** This corrects the premise that bun "is a security package that had problems." bun had no such incident; the incidents are registry-wide and manager-agnostic.

### Finding 3: The industry mitigation is minimum-release-age, now everywhere

The community converged on two manager-independent defenses: **blocking post-install scripts** (the worm's execution vector) and a **minimum-release-age quarantine** (refuse to install a version published less than N days ago, so the community can catch a compromised release first). Time-based release gating is now available across npm (CLI 11, Feb/2026 `min-release-age`), pnpm (v10.16, Sept/2025 `minimumReleaseAge`), Yarn, and bun. aube ships it on by default plus script "jails".

**Source:** Socket (npm), pnpm docs.

**Significance:** aube's headline security features are not unique; they are the 2026 baseline, available on the mature managers too.

### Finding 4: `app-webclient` already runs every one of those defenses, on Yarn

Local state read directly:
- `package.json` → `"packageManager": "yarn@4.18.0"` (the current, maintained Yarn Berry line; latest point release is 4.18.0, Jul/2026 — this is not the 2020-era Yarn 1).
- `.yarnrc.yml` → `enableScripts: false` (post-install scripts OFF — the primary Shai-Hulud vector, blocked) and a comment documenting that the native Yarn age-gate is set via CI (`YARN_NPM_MINIMAL_AGE_GATE` from the org variable, same source as Renovate).
- `renovate.json` present → Renovate with `minimumReleaseAge` (7 days), consistent with the 4Shark dependency-update policy (Dependabot + Renovate + CI age check).

**Significance:** 4Shark's supply-chain protection lives at the Yarn config + Renovate/CI layer, which is package-manager-independent. Switching managers would add no security that is not already in place.

### Finding 5: aube is credible but immature

aube is by **jdx** (creator of `mise`, widely adopted), written in Rust, MIT, v2.2.x, drops in by reading/writing the existing lockfile without migration, pnpm-like content-addressable store. Fast on warm installs. But it is a 2026 release: the Hacker News reception is "promising, not yet recommended for production" — testers report filing pnpm-compatibility bugs against it daily (fixed quickly, but gaps remain) and ~30% slower than pnpm on large monorepos.

**Source:** aube.sh, github.com/jdx/aube, Hacker News thread.

**Significance:** Interesting to track (the "uv for Node" pattern), but too new for a client-facing whitelabel frontend built on Angular + Netlify.

## Trade-offs surfaced

| Option | Pros | Cons |
|--------|------|------|
| **Keep Yarn 4.18** | Current + maintained; already integrated (Angular, Netlify); all supply-chain defenses already on; zero migration risk | No disk-dedup like pnpm |
| **pnpm** | Mature; ~70% less disk; native `minimumReleaseAge` | Real migration; marginal gain over the current hardened Yarn |
| **bun** | Fastest installs | Adopting the runtime is a much larger commitment than a manager swap |
| **aube** | Fast; ~90% less disk multi-project; security-by-default; reputable author; drop-in | 3 months old; "not yet for production" per community; zero net security gain for 4Shark |

## Decision reached

**Keep Yarn 4.18 on `app-webclient`.** The team asked, researched, and decided to stay. Rationale, in order:

1. The security motivation dissolves on inspection: 4Shark's protection is at the Yarn-config + Renovate/CI layer (`enableScripts: false`, native age-gate, `minimumReleaseAge`, committed lockfile), which is manager-independent and already state-of-the-art. A manager swap buys no security.
2. They are on the current, actively-maintained Yarn line, integrated with the Angular + Netlify build.
3. aube — the tool that triggered the question — is too new for a client frontend, with no offsetting benefit.

If disk/speed (not security) ever becomes the pain, the lowest-risk higher-maturity option is **pnpm**, not aube or bun — but that is a "nice to have", not urgent.

## What remains uncertain / revisit triggers

- **Revisit aube in ~6–12 months.** If it matures the way `uv` did for Python, the maturity objection weakens and the decision is worth re-running.
- The external comparison figures (install speeds, disk percentages) came from aggregated search summaries; treat them as directional, not benchmarked in-house.

## Auxiliary

- [`frontend-package-manager_report_1.html`](./frontend-package-manager_report_1.html) — the engineer-facing pt-BR comparison report produced for this investigation (taxonomy, comparison table, Shai-Hulud timeline, recommendation). Preserved as source material.

---

> **Authoring:** research spike carrying a `Decision reached` section — a deliberate deviation from the pure-spike template (which surfaces options without picking) because the engineer settled the question at the end and asked for the decision to be on record. Findings cite their sources; external figures drawn from search aggregation are flagged as directional rather than verbatim-verified.
