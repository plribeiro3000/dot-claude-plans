# SPIKE — Mechanical Enforcement of the 4Shark Commit Message Scope Requirement

## Investigation question

Two parts:

1. **Confirm and pin the exact 4Shark commit standard.** Is the Angular-style scope (`<type>(<scope>): <subject>`) mandatory at 4Shark, and how does that diverge from the upstream Angular / Conventional Commits specification (where scope is documented as optional)? How consistently is the scope actually used across real 4Shark repository history, and what scope vocabulary is in use?
2. **Find a mechanical enforcement mechanism** that makes a non-conforming commit message impossible to slip through, rather than advisory — comparing a 4Shark PreToolUse hook, commitlint + a `commit-msg` git hook, and the existing lighter reminder-injection pattern already in use for commit-time policy — and sketch the matching/parsing logic a PreToolUse hook would need.

Trigger: the agent repeatedly wrote commit subjects without the parenthesized scope this session (`feat: scaffold the containerized Pritunl VPN image`, `feat: scaffold the MongoDB golden-AMI build pipeline`), both of which are present, unmerged into `develop` at time of writing, in the `pritunl` and `mongodb` repositories.

## Sources consulted

- `~/.claude/CLAUDE.md:176` — the exact 4Shark commit-format rule text
- `~/.claude/docs/PULL-REQUEST-CONVENTIONS.md:42` — a second, independent 4Shark citation of the same mandatory-scope shape
- `~/.claude/scripts/validate-bash-command.sh` (full read) — the existing PreToolUse block pattern (structure, block-vs-ask decision, quote-stripping technique, and three separate "textual rule was not enough" precedents)
- `~/.claude/scripts/inject-pr-commit-data-policy.sh` (full read) — the existing lighter reminder-only hook fired at `git commit`, and its explicit design rationale for why it does NOT block
- `~/.claude/scripts/inject-commit-policy-reminder.sh` (full read) — a second reminder-only hook fired at `git commit`, confirming the pattern is deliberate and repeated
- `~/.claude/settings.json:524-652` — how PreToolUse hooks are wired (`matcher`, optional `if` conditional matcher used by the terraform-context hook, ordering)
- `~/.claude/settings.json:19-20,290-291` — the existing `permissions.allow` entries covering `git commit` (`Bash(git:*)`, `Bash(git -C *)`)
- Local git history samples across nine 4Shark repositories (`app`, `terraform`, `keycloak`, `integrator`, `dot-claude`, `pritunl`, `mongodb`, `pgbouncer`, `app-webclient`, `onboarding`, `setup`) — see auxiliary `commit-enforcement_log_1.txt`
- [Conventional Commits v1.0.0 specification](https://www.conventionalcommits.org/en/v1.0.0/) — "OPTIONAL scope" / "A scope MAY be provided"
- [Angular `commit-message-guidelines.md`](https://github.com/angular/angular/blob/main/contributing-docs/commit-message-guidelines.md) — "The `<type>` and `<summary>` fields are mandatory, the `(<scope>)` field is optional"
- [commitlint rules reference](https://commitlint.js.org/reference/rules.html) — the `scope-empty` rule and its `[2, 'never']` configuration
- [claudedirectory.org — Commit Message Linter Hook for Claude Code](https://www.claudedirectory.org/hooks/commit-lint) — a third-party PreToolUse commit-lint hook implementation, cited for its message-extraction limitations
- See auxiliary: `commit-enforcement_log_1.txt` — raw `git log` output and scope-usage ratios that ground Finding 3
- See auxiliary: `commit-enforcement_hook-sketch_1.sh` — an illustrative (non-installed) sketch of the matching/parsing logic a `validate-commit-message.sh` PreToolUse hook would need, referenced by Findings 7 and 8

## Findings

### Finding 1: 4Shark's own text writes the scope as mandatory; the upstream spec writes it as optional

**Evidence (4Shark, CLAUDE.md):**
```
176	- Use Angular Commit Guidelines: `<type>(<scope>): <subject>`
```
**Source:** `~/.claude/CLAUDE.md:176`

**Evidence (4Shark, PULL-REQUEST-CONVENTIONS.md — independent second citation):**
```
40	**Title**: The commit message subject
41	```
42	feat(Scope): Description of the feature
43	```
```
**Source:** `~/.claude/docs/PULL-REQUEST-CONVENTIONS.md:40-43`

Neither 4Shark document ever writes the scope in brackets, with a qualifier like "optional", or with any conditional language — in both places it appears as a plain, always-present component of the format string.

**Evidence (upstream, Conventional Commits v1.0.0):**
> "Commits MUST be prefixed with a type, which consists of a noun, `feat`, `fix`, etc., followed by the OPTIONAL scope, OPTIONAL `!`, and REQUIRED terminal colon and space."
> "A scope MAY be provided after a type. A scope MUST consist of a noun describing a section of the codebase surrounded by parenthesis, e.g., `fix(parser):`"

**Source:** [conventionalcommits.org/en/v1.0.0](https://www.conventionalcommits.org/en/v1.0.0/)

**Evidence (upstream, Angular's own current commit guidelines):**
> "The `<type>` and `<summary>` fields are mandatory, the `(<scope>)` field is optional."

**Source:** [github.com/angular/angular — commit-message-guidelines.md](https://github.com/angular/angular/blob/main/contributing-docs/commit-message-guidelines.md)

**Significance:** the divergence is real and explicit, not a misreading. 4Shark's format string `<type>(<scope>): <subject>` is textually identical to Angular's `<type>(<scope>): <subject>`, but 4Shark's CLAUDE.md carries none of the "optional" qualifying language that both the Conventional Commits spec and Angular's own guidelines carry for the scope. Whether this was a deliberate 4Shark tightening or an unstated assumption is not resolvable from the text alone — the wording is silent on why the qualifier was dropped, not on what the resulting rule is. The rule, as written, has no escape hatch for scope-less commits.

### Finding 2: `~/.claude/docs/CHANGELOG.md` links to the Angular guidelines but does not itself state the scope-mandatory divergence

**Evidence:**
```
9:- **[Angular Commit Guidelines](https://github.com/angular/angular.js/blob/master/DEVELOPERS.md#commits)** - Commit message format
```
**Source:** `~/.claude/docs/CHANGELOG.md:9`

**Significance:** this is the one place in 4Shark's docs that points an engineer at the *external* spec by reference, without repeating the mandatory-scope wording found in CLAUDE.md. Read in isolation, this line could suggest the Angular optional-scope rule applies; only CLAUDE.md:176 and PULL-REQUEST-CONVENTIONS.md:40-43 make the 4Shark-specific tightening explicit. There is no single 4Shark document that states outright "unlike upstream Angular, 4Shark requires the scope" — the divergence has to be inferred by comparing the two sources, which is exactly what this spike does in Finding 1.

### Finding 3: scope usage is near-universal in 4Shark's established repos, and the two commits the engineer flagged are drop-in examples of the failure — both currently sitting, un-merged, in local history

**Evidence — scope-usage ratio, last 60 non-merge commit subjects per repo** (see auxiliary `commit-enforcement_log_1.txt` for the full raw sampling and the exact grep commands used):

| Repo | Scoped / Total | % |
|---|---|---|
| `app` | 30/30 | 100% |
| `app-webclient` | 30/31 | 97% |
| `terraform` | 28/30 | 93% |
| `integrator` | 25/27 | 93% |
| `dot-claude` | 27/30 | 90% |
| `onboarding` | 25/28 | 89% |
| `setup` | 25/28 | 89% |
| `keycloak` | 10/16 | 62% |
| `pgbouncer` | 5/18 | 28% |

**Evidence — the two flagged commits, verified in local history:**
```
$ git -C ~/Projects/4Shark/pritunl log --format='%s'
Merge pull request #1 from 4shark/feature/repo-scaffold
feat: scaffold the containerized Pritunl VPN image
Initial commit
```
```
$ git -C ~/Projects/4Shark/mongodb log --all --format='%s (%D)'
feat: scaffold the MongoDB golden-AMI build pipeline (origin/feature/repo-scaffold, feature/repo-scaffold)
Initial commit (HEAD -> main, origin/main, origin/HEAD)
```
**Source:** direct `git log` output, `~/Projects/4Shark/pritunl` and `~/Projects/4Shark/mongodb` (see auxiliary `commit-enforcement_log_1.txt` for the full transcript, including the `git worktree list` confirming the `mongodb` commit lives on an active `feature/repo-scaffold` worktree, not yet merged)

**Significance:** the sampled repos with a long, mature commit history (`app`, `app-webclient`, `terraform`, `integrator`, `dot-claude`, `onboarding`, `setup`) sit at 89–100% scope usage — the convention is real and the vast majority of commits already comply without a mechanical gate. The two lowest-compliance repos in the sample (`keycloak` 62%, `pgbouncer` 28%) are both young "Docker-image-tool-repository" scaffolds (per `~/.claude/docs/DOCKER-IMAGE-TOOL-REPOSITORIES.md`), and their earliest commits are disproportionately the un-scoped ones — see the `pgbouncer` reversed-order sample in the auxiliary file, where the first four feature commits (`feat: thin PgBouncer image...`, `feat: render multi-database config...`, `feat: write static userlist...`, `fix: restore CMD...`) are all scope-less, before scope usage becomes consistent later in the same repo's history. This matches the shape of the two commits that triggered this spike — both are the FIRST substantive commit of a brand-new repo scaffold, a category that appears structurally more prone to omitting scope, plausibly because there is no obviously "correct" single scope for a change that touches the entire new repository at once (see "What remains uncertain" below).

### Finding 4: 4Shark commit messages are observed to be single-line, single `-m` invocations with no body — this bounds what a hook's message-extraction needs to handle

**Evidence:**
```
$ git -C ~/Projects/4Shark/dot-claude log -n 3 --format='%B---END---'
Merge pull request #364 from 4shark/feature/output-policy-no-artifacts

docs(output-policy): document Artifacts as a non-sanctioned output surface---END---
docs(output-policy): document Artifacts as a non-sanctioned output surface
---END---
Merge pull request #363 from 4shark/feature/output-policy-native-first

docs(output-policy): make native-app-first with terminal caveats inline---END---
```
**Source:** `git -C ~/Projects/4Shark/dot-claude log -n 3 --format='%B---END---'` (see auxiliary `commit-enforcement_log_1.txt`)

Cross-referenced against the standing rule:
```
175	- **ALWAYS one commit per pull request** — unless the engineer explicitly requests otherwise. Squash mid-branch iterations before pushing; `--force-with-lease` is acceptable on your own feature branch
```
**Source:** `~/.claude/CLAUDE.md:175`

**Significance:** every sampled non-merge commit body is exactly one subject line — no second paragraph, no footer. Combined with the "one commit per PR" / "succinct" changelog conventions, this means the realistic 4Shark `git commit` invocation shape is a single `-m "type(scope): subject"`, not the `-m "subject" -m "body"` pair the CLAUDE.md investigation question anticipated as a possible edge case. This narrows — but does not eliminate — what a hook's message extractor must parse: `-m`, `--amend`, `-c`/`-C`, and `-F` remain open shapes (see Finding 8), but multi-`-m` body composition is not a shape observed in current 4Shark practice.

### Finding 5: the existing `permissions.allow` list already auto-approves every `git commit` shape — a hook must actively block, not just downgrade to "ask"

**Evidence:**
```
19:      "Bash(git:*)",
20:      "Bash(git -C *)",
```
**Source:** `~/.claude/settings.json:19-20`

**Significance:** `Bash(git:*)` string-prefix-matches and auto-approves any `git commit ...` invocation today, with no human in the loop. This is directly relevant to the enforcement-mechanism comparison in Finding 6/7: a hook that only reclassifies the permission decision to `"ask"` (the mechanism `validate-bash-command.sh` uses for `terraform apply`, `aws ecs run-task`, `git tag`, `git rm` — see `~/.claude/scripts/validate-bash-command.sh:556-578`) would still let a malformed message through the moment the engineer rubber-stamps the prompt, which does not solve "the engineer must not have to manually check every commit message" (the stated problem). The stronger mechanism already used elsewhere in `validate-bash-command.sh` for git-safety violations (`git reset --hard`, `git branch -D`, `git checkout .`, `git checkout -b release/*`, `gh pr merge`) is a hard block: `exit 2` with a corrective message on stderr, which Claude Code cannot silently route around.

### Finding 6: 4Shark already has two hooks that fire at `git commit` but are deliberately advisory, not blocking — and both name why

**Evidence (`inject-pr-commit-data-policy.sh`):**
```
1	#!/bin/bash
2	#
3	# PR/Commit Client-Data Policy Reinjection Hook (PreToolUse / Bash)
4	#
5	# Fires before a Bash tool invocation and reinjects the "No Client/Infra Data
6	# in PR Descriptions and Commit Messages" rule into Claude's context at the
7	# exact moment the data could leak — when a PR is being opened or a commit is
8	# being authored. It NEVER blocks and NEVER matches values: it only keeps the
9	# rule fresh in context so the model applies it while composing the body.
...
11	# Why reinjection and not value-matching: a value list (customer names,
12	# hostnames) would be unmaintainable AND would itself version client/infra data
13	# into this repo — the very leak the rule exists to prevent. So the rule is
14	# semantic (the model interprets it) and this hook only re-surfaces it.
```
**Source:** `~/.claude/scripts/inject-pr-commit-data-policy.sh:1-14`

**Evidence (`inject-commit-policy-reminder.sh`):**
```
10	# Why a reminder and not a block: a hook is fast bash and cannot run an LLM
11	# inline. The policy check is judgment work (the 3 structural rules —
12	# IDs-only, index awareness, code anti-patterns) ... So this hook only
13	# re-surfaces the instruction at the commit boundary; main spawns the
14	# verifier and decides.
```
**Source:** `~/.claude/scripts/inject-commit-policy-reminder.sh:10-14`

**Significance:** both existing commit-time hooks are advisory by design, and both name the specific reason: the No-Client-Data rule is advisory because the alternative (a matchable value list) would itself leak the data it protects, and the code-policy reminder is advisory because judging code-pattern conformance is LLM-scale reasoning a bash hook cannot perform inline (it hands off to a spawned verifier agent instead). **Neither reason applies to commit-message format.** Checking `^<type>(<scope>): <subject>$` against a literal string is a plain regex match — no semantic judgment, no risk of leaking the thing being protected, no need for an LLM in the loop. This is exactly the shape `validate-bash-command.sh`'s existing blocking checks already handle (branch-name prefixes, force-push targets, `gh pr merge` detection) — none of those are semantic either. The advisory pattern used for the two existing commit-time hooks is a considered choice for problems that need judgment; a commit-format regex is not that kind of problem.

### Finding 7: 4Shark's own hooks repeatedly document that a prose rule alone did not hold up in practice, independent of this investigation

**Evidence (general rationale, header of `validate-bash-command.sh`):**
```
84	# Why a hook instead of a CLAUDE.md rule:
85	#   These patterns appeared repeatedly across one session even with the rule
86	#   "never prepend cd to git" present in the Claude Code system prompt. Textual
87	#   rules are probabilistic; hooks are deterministic. A blocked command with
88	#   stderr feedback lets the model self-correct without engineer approval.
```
**Source:** `~/.claude/scripts/validate-bash-command.sh:84-88`

**Evidence (specific precedent 1 — AWS instance wrapper scripts):**
```
545	  - Listing the scripts in CLAUDE.md was not enough — the rule got lost in long sessions and the agent fell back to the raw command. Hook is the deterministic fix.
```
**Source:** `~/.claude/scripts/validate-bash-command.sh:545`; corroborated in `~/.claude/CLAUDE.md:898` — "the textual rule alone was not enough (the scripts were listed in the repository tree but the agent fell back to the raw command in long sessions)"

**Evidence (specific precedent 2 — local database OS-level management):**
```
486	  - Listing this in CLAUDE.md was not enough — the rule got lost in long sessions and the agent went straight to `brew`. Hook is the deterministic fix.
```
**Source:** `~/.claude/scripts/validate-bash-command.sh:486`

**Evidence (specific precedent 3 — compound infra commands):**
```
951:- **Mechanically enforced**: ... The prose rule alone was insufficient — the agent chained an `aws` read with `jq` anyway, hitting a permission prompt the hook now prevents
```
**Source:** `~/.claude/CLAUDE.md:951`

**Significance:** the commit-scope failure fits the exact structural shape of these three precedents — a rule stated once in CLAUDE.md prose (line 176), with no mechanical gate anywhere in the hook set, that the model failed to apply consistently across a session (this session, twice). Unlike migration creation, bang-methods-in-web-flow, bulk-delete, worker-topology-naming, and concurrent-index migrations — each of which DOES have a `validate-*.sh` / `check-*.sh` hook — commit-message format currently has zero mechanical gate. The two existing commit-time hooks (Finding 6) fire at the right moment but check different things (client-data leakage, code-pattern policy), not message format. This is the gap, not a moral failing of the model: a rule that lives only in prose is consulted probabilistically, and the moment of composing a `-m` string is not guaranteed to re-surface CLAUDE.md:176 into the model's active attention.

### Finding 8: a real third-party PreToolUse commit-lint hook exists, and its published limitation is exactly the extraction problem a 4Shark implementation must solve for

**Evidence:**
> "The hook uses a limited extraction approach: `MSG=$(echo "$COMMAND" | grep -oP '(?<=-m\s["\''])[^"\'']+')`. However, the script only handles the `-m` flag—it does not process `-F` (file input), `--amend` (reusing previous messages), or heredocs. If none of these formats match, the `MSG` variable remains empty and the script exits without validation."
> "**Limitation**: The script's minimal extraction logic means many valid commit syntaxes bypass validation entirely rather than being properly validated."

**Source:** [claudedirectory.org — Commit Message Linter Hook for Claude Code](https://www.claudedirectory.org/hooks/commit-lint)

**Significance:** this is independent, external confirmation that the extraction problem sketched in Finding 4 and in the auxiliary hook sketch is a real, previously-hit limitation, not a hypothetical this spike invented. The third-party hook's failure mode is instructive: it fails OPEN (skips validation silently) rather than failing closed on unparseable shapes — the same design choice the auxiliary sketch (`commit-enforcement_hook-sketch_1.sh`) makes deliberately, for the same reason (a false block is worse friction than a message that slips through unchecked on a rare shape). The third-party example also confirms the validation regex itself is the easy half of the problem — `^(feat|fix|...)(\(.+\))?!?:\s.+` is a one-line pattern; the extraction of the message text from an arbitrary shell command is where an implementation's correctness actually lives.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| **PreToolUse `validate-commit-message.sh` hook (blocking, `exit 2`)** | Deterministic — cannot be rubber-stamped past like an "ask" prompt (Finding 5); matches the exact mechanism (`exit 2` + stderr) already used for every other git-safety block in `validate-bash-command.sh`; fires for every 4Shark repo without per-repo installation, since it is wired once in the shared `~/.claude/settings.json`; only gates the AGENT's commits — a human running `git commit` directly in a terminal outside Claude Code is unaffected (matches "the engineer must not have to check the AGENT's messages" framing) | Message extraction from a raw shell string is inherently fragile — must correctly handle `-m`, `-F <file>`, `--amend` (with/without a new `-m`), `-c`/`-C <commit>`, and (in principle) heredoc bodies; a third-party implementation surveyed in this spike only handles a single quoted `-m` and silently fails open on every other shape (Finding 8); a bug in the regex either false-blocks a valid commit (friction) or false-allows an invalid one (silently reopens the gap) | This spike, Findings 5–8; `~/.claude/scripts/validate-bash-command.sh` (pattern precedent) |
| **commitlint + `.git/hooks/commit-msg`** (`@commitlint/config-conventional`, `scope-empty: [2, 'never']`) | Community-standard, widely documented tool purpose-built for exactly this check ([commitlint rules reference](https://commitlint.js.org/reference/rules.html)); enforces on EVERY commit to the repo, human or agent — closes the gap for engineers typing commits by hand too, which a Claude-Code-only hook does not | Per-repo installation and maintenance (a `commit-msg` git hook is not versioned/shared centrally the way `~/.claude/settings.json` is across all 4Shark work); requires Node/npm tooling present in every repo including non-JS repos (`terraform`, `pritunl`, `mongodb`, `keycloak` are not npm projects) or the standalone commitlint CLI installed separately; Husky-style git hooks live in `.git/hooks/` which is not itself version-controlled — needs a setup step (Husky or manual symlink) that runs on every clone/worktree, which interacts with 4Shark's per-repo worktree flow (`~/.claude/scripts/setup-worktree.sh`) in a way not currently modeled | [commitlint rules reference](https://commitlint.js.org/reference/rules.html); `~/.claude/CLAUDE.md` § Worktree Policy (setup-worktree.sh symlink pattern, for context on the added-per-repo-setup cost) |
| **Reminder-injection hook** (mirrors `inject-pr-commit-data-policy.sh` / `inject-commit-policy-reminder.sh`) | Trivial to build — the two existing commit-time hooks are the exact template; zero false-block risk since it never blocks | Does not solve the stated problem: the engineer explicitly wants to stop manually checking every message, and an injected reminder is exactly the "prose rule" category Finding 7 shows repeatedly fails to hold under a long session; the two existing commit-time hooks are advisory for reasons (semantic judgment, anti-value-leak) that do not apply to a plain format regex — using the same shape here would be applying the wrong tool for a different kind of problem (Finding 6) | `~/.claude/scripts/inject-pr-commit-data-policy.sh`, `~/.claude/scripts/inject-commit-policy-reminder.sh` |

## What remains uncertain

- **Why 4Shark's CLAUDE.md dropped the "optional" qualifier from the Angular format string** — whether this was a deliberate policy tightening or an unstated assumption carried over when the Angular guidelines were adapted. Not found in any 4Shark doc; CLAUDE.md:176 and PULL-REQUEST-CONVENTIONS.md:40-43 state the mandatory shape without explaining the divergence from upstream.
- **What scope a whole-repo scaffold commit should carry.** The two flagged commits (`pritunl`, `mongodb`) are each the first substantive commit of a brand-new repository, touching the entire tree at once — there is no established single "area of the codebase" the way `feat(user-history): ...` or `fix(atento-001): ...` name one in a mature repo. The sampled data shows this exact category (new "Docker-image-tool-repository" scaffolds) has the lowest scope-compliance in the sample (`keycloak` 62%, `pgbouncer` 28%, both concentrated in their earliest commits — Finding 3). No 4Shark doc states what scope, if any, a scaffold commit should use (`repo`? `scaffold`? the repo's own name, e.g. `pritunl`? no scope, as a documented exception?). This is a scope-vocabulary decision, not something this spike can resolve from evidence alone.
- **Whether a blocking PreToolUse hook or commitlint (or both) is the direction 4Shark wants**, and if the hook route is chosen, whether it lives as a new case inside the existing `validate-bash-command.sh` or as its own script following the `inject-pr-commit-data-policy.sh` self-filtering pattern (command-text inspection rather than the `if:` conditional matcher used by `inject-terraform-context.sh` — see `~/.claude/settings.json:586-606` for that alternate wiring style). Either wiring choice is engineer-facing and out of this spike's scope.
- **How `-F <file>`-based and heredoc-based commit messages would be extracted**, if that shape is ever adopted at 4Shark — not observed in the sampled history (Finding 4), confirmed as an unsolved gap even in the third-party reference implementation (Finding 8), so left as a documented gap in the sketch (auxiliary `commit-enforcement_hook-sketch_1.sh`) rather than solved.

## Suggested options for main and the engineer

- **Option A — Blocking PreToolUse hook (`validate-commit-message.sh`), modeled on `validate-bash-command.sh`'s existing `exit 2` block pattern.** Extracts the first `-m` value from a `git commit` invocation, validates it against `^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)\([a-z0-9._-]+\):[[:space:]].+`, blocks with a corrective stderr message on mismatch, and fails OPEN (allows) on any invocation shape it cannot confidently parse (`-F`, bare `--amend`, `-c`/`-C`) rather than guess-block. See auxiliary `commit-enforcement_hook-sketch_1.sh` for the full sketch, including the itemized parsing gaps to size before building. Implementing this is a dot-claude config-change PR per `~/.claude/CLAUDE.md` § Configuration Changes Policy — not something written directly into the live `~/.claude/` tree.
- **Option B — commitlint + `commit-msg` git hook per repo**, `@commitlint/config-conventional` with `scope-empty: [2, 'never']`. Closes the gap for human-typed commits too, at the cost of per-repo setup and Node tooling in non-JS repos.
- **Option C — Both A and B together**, treating the PreToolUse hook as the fast, zero-install, agent-scoped gate and commitlint as the belt-and-suspenders check that also covers human-authored commits — accepting the double-maintenance cost.
- **Option D — Do nothing mechanical; keep it a documented prose rule**, accepting that Finding 7's three prior precedents (AWS wrapper scripts, OS-level DB management, compound infra commands) predict this will keep recurring in long sessions.

(No recommendation — the four options and their trade-offs are surfaced above for the engineer to choose from.)
