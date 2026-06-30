# SPIKE: Working-directory strategy — keep `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1` or adopt Claude Code's default carry-over?

**Status:** Done — engineer chose to adopt Claude Code's default carry-over; implementation tracked in `~/.claude/plans/completed/dot-claude/working-dir-cwd-strategy/PLAN.md`, executed by 2026-05-31
**Date:** 2026-05-29 (research) / by 2026-05-31 (decision executed)
**Author:** main session (research), plribeiro3000 (requester)
**Time-box:** single session

---

## Question

We set `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1` in `~/.claude/settings.json` as an anti-drift trap — originally to stop the agent from running a command (notably `terraform apply`) in the wrong stack after wandering with `cd`. It now conflicts daily with the no-`cd` rules and forces the escape-hatch patterns (`git -C`, `BUNDLE_GEMFILE=<abs>`, `ruby -C`, absolute paths) everywhere.

The engineer's proposal: **remove the variable and instead "always stay in the correct path"**, to (a) make RVM / Ruby-version-manager usage easier and (b) remove the friction with the no-`cd` rules.

This spike establishes what the variable actually does, what removing it actually buys, and what would have to change in a coordinated way.

---

## Key reframe (the single most important finding)

The proposal as phrased ("force the opposite: always stay in the correct path") is **not** a new behavior we'd have to build. **Removing the variable simply restores Claude Code's default working-directory behavior**, which already is "stay in the directory you `cd` into" — scoped, with an automatic safety reset.

So the real decision is: **keep the reset-after-every-command override, or fall back to the platform default carry-over.**

---

## Finding 1 — What the variable does (authoritative)

Claude Code docs, Bash tool behavior:

> To disable this carry-over so every Bash command starts in the project directory, set `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1`.

Env-vars doc:

> Return to the original working directory after each Bash or PowerShell command in the main session

**Verification block**
- URL fetched: https://code.claude.com/docs/en/tools-reference and https://code.claude.com/docs/en/env-vars
- Verbatim quotes checked: both substrings above
- Confirmed at: "Bash tool behavior" section and the env-vars table entry

So `=1` means: **reset cwd to the session's project directory after every command.** That is exactly the override we have.

---

## Finding 2 — What the DEFAULT (variable unset) does

Claude Code docs, Bash tool behavior:

> When Claude runs `cd` in the main session, the new working directory carries over to later Bash commands as long as it stays inside the project directory or an additional working directory you added with `--add-dir`, `/add-dir`, or `additionalDirectories` in settings. Subagent sessions never carry over working directory changes.
> - If `cd` lands outside those directories, Claude Code resets to the project directory and appends `Shell cwd was reset to <dir>` to the tool result.

**Verification block**
- URL fetched: https://code.claude.com/docs/en/tools-reference
- Verbatim quote checked: substring above
- Confirmed at: "Bash tool behavior" bullet list

Two consequences:
1. Default already gives the engineer's desired behavior in the **main session** — `cd` once into the right project, subsequent commands run there.
2. There is a **built-in safety net**: a `cd` that escapes the allowed directory tree auto-resets to the project dir with a visible note.

---

## Finding 3 — The safety net does NOT cover our Terraform anti-drift case

The reset only fires when `cd` lands **outside** the project dir and the `additionalDirectories`. Our `additionalDirectories` (from `settings.json`) are:

```
"additionalDirectories": ["~/Projects", "~/.claude", "~/Downloads", "/tmp"]
```

Every 4Shark repo — including every Terraform stack — lives under `~/Projects/4Shark/…`. Therefore:

- `cd ~/Projects/4Shark/terraform/identity` → inside `~/Projects` → **persists, no reset**
- `cd ~/Projects/4Shark/terraform/networking` → inside `~/Projects` → **persists, no reset**

The original anti-drift fear — plan in stack A, then `apply` while actually sitting in stack B — is **inside the allowed tree the whole time**, so the platform's auto-reset never triggers. **Removing the variable re-opens exactly the drift window the variable was added to close**, and the built-in default does not close it for us because of our flat-under-`~/Projects` layout.

This is the crux: the variable is doing real anti-drift work *specifically because* our layout defeats the built-in reset.

---

## Finding 4 — What removing the variable does NOT fix (the escape hatches stay)

Removing the variable does **not** retire the escape-hatch patterns:

- **Subagents never carry over `cd`** — docs: *"Subagent sessions never carry over working directory changes."* All our subagent-driven flows (spike, plan-researcher, pr-reviewer, DDD agents) still need `git -C`, `BUNDLE_GEMFILE=<abs>`, `ruby -C`, absolute paths. The variable change touches **only the main session.**
- **Env vars never persist regardless** — docs: *"Environment variables do not persist. An `export` in one command will not be available in the next."* So `BUNDLE_GEMFILE=<abs> …` inline prefixes remain mandatory; this has nothing to do with the cwd variable.

**Verification block**
- URL fetched: https://code.claude.com/docs/en/tools-reference
- Verbatim quotes checked: both substrings
- Confirmed at: "Bash tool behavior" section

So the benefit is real but **narrower than "all the friction goes away"**: it removes friction only for sequential main-session commands in one repo.

---

## Finding 5 — The RVM benefit is partial, and depends on the manager

The engineer's RVM motivation is sound but uneven:

- **rbenv / asdf** — shims read `.ruby-version` / `.tool-versions` from the **current directory**. With correct cwd carried over, shims auto-resolve the right Ruby. Clear win.
- **RVM** — auto-activation is a `cd`-hook shell function. Claude Code sources `~/.zshrc`/`~/.bashrc` at session start and *"captures the resulting aliases, functions, and shell options, and applies them to every Bash command"* (docs). Whether RVM's `chpwd`/`cd`-hook actually fires under that captured-function model is **not confirmed** by the docs and would need a live test. Our current CLAUDE.md already states the auto-activation hooks "do not fire automatically" in this shell — which is why the wrappers exist. **Correct cwd may or may not make RVM auto-activate; the wrappers remain the safe path until proven otherwise.**

**Verification block**
- URL fetched: https://code.claude.com/docs/en/tools-reference
- Verbatim quote checked: "captures the resulting aliases, functions, and shell options, and applies them to every Bash command"
- Confirmed at: "Bash tool behavior" section
- UNVERIFIED: whether RVM's cd-hook fires under the captured-function model — no source found; requires empirical test.

---

## Finding 6 — Removing the variable is a coordinated change, not a one-liner

The current setup is a tightly-coupled triad built around the reset model:

1. `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1` in `settings.json:8`.
2. `scripts/validate-bash-command.sh:111` blocks `cd <dir> && <cmd>` (compound). Standalone `cd` is currently pointless *because* of the variable.
3. `CLAUDE.md § Working Directory Behavior` + `§ Ruby Version Manager in Bash` document the escape hatches as the only sanctioned path, explicitly citing the variable as the reason.

Flipping to carry-over requires touching all three coherently:
- Remove the env var.
- Decide what to do with the `cd &&` block (a standalone `cd` in its own tool call would now persist and be the intended way to set the directory; `cd &&` chains are still discouraged for the command-safety/approval-fatigue reason, independent of cwd).
- Rewrite both CLAUDE.md sections so they stop describing the reset model as ground truth.
- **Replace the lost Terraform anti-drift guarantee** with another mechanism (see options).

Leaving any one of these stale produces contradictory rules.

---

## Finding 7 — The original anti-drift fear was calibrated to a less mature harness (engineer input)

The engineer notes that the variable was added at a time when the harness was *"not as good as it is today; it's already much more controlled, to the point this is no longer as much of a problem."* This is a material recalibration of Finding 3.

What it changes and what it does not:

- **Does not change the mechanics** — all stacks still live under `~/Projects`, so the platform's auto-reset still never fires for cross-stack moves (Finding 3 stands structurally).
- **Does change the probability** — the agent today is markedly better at tracking and stating its cwd, and the mutating terraform ops (`apply/destroy/import/taint/state rm`) are already in the `ask` list (`settings.json:432-437`), i.e. they **always** surface a human confirmation. The residual risk is "agent drifts cwd AND the engineer approves the prompt without noticing the wrong stack" — a much narrower window than the raw mechanics suggest.

**Implication for the decision:** the compensating control for Terraform can be **lighter** than mandating `-chdir` everywhere. Surfacing the resolved stack inside the existing `ask` prompt (Option B1) may be sufficient defense-in-depth on a controlled harness, rather than a hard command-shape rule (B2).

---

## Finding 8 — The acrobatics are what defeat the EXISTING allow-list (concrete, engineer-provided evidence)

The engineer demonstrated the real cost with a live rubocop run that prompted for permission every time:

```
BUNDLE_GEMFILE=/private/tmp/integrator-rcf/Gemfile ~/.rvm/wrappers/ruby-4.0.4@integrator/bundle exec ruby -C /private/tmp/integrator-rcf -S rubocop --only Layout...
```

Causal chain (this is the crux that ties the cwd question to the daily friction):

1. `CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR=1` forbids a useful `cd`, so to run anything in another repo the command must carry **two compensating artifacts**: `BUNDLE_GEMFILE=<abs>` (so bundler finds the Gemfile without cwd) and `ruby -C <dir>` (so autoload resolves without cwd).
2. The `BUNDLE_GEMFILE=` **inline env-var prefix defeats the permission matcher** (Finding: matcher does not strip env prefixes — issues [#51057](https://github.com/anthropics/claude-code/issues/51057), [#8581](https://github.com/anthropics/claude-code/issues/8581)). So the command no longer matches the allow rule `Bash(~/.rvm/wrappers/*/bundle:*)` (`settings.json:264-281`) and **prompts every single time**.
3. Without that prefix, the same wrapper command **already auto-approves** under the existing rule.

**Therefore removing the variable is not just ergonomic — it restores the existing allow-list.** With `cd` into the project, the command collapses from the line above to:

```
~/.rvm/wrappers/ruby-4.0.4@integrator/bundle exec rubocop --only Layout...
```

which matches `Bash(~/.rvm/wrappers/*/bundle:*)` and runs with no prompt. Both acrobatic artifacts (`BUNDLE_GEMFILE=` prefix and `ruby -C`) disappear because they only ever existed to compensate for the forbidden `cd`.

The engineer's framing: the change "loosens this rule, making usage easier in slightly more complex scenarios that don't fit the auto-allow rule." This finding is the mechanism behind that statement — the auto-allow rules already exist; the reset regime is what pushes commands into a shape those rules can't match.

**Rejected alternative (band-aid):** adding env-prefixed allow patterns like `Bash(BUNDLE_GEMFILE=* ~/.rvm/wrappers/*/bundle exec *)` would silence the prompt without removing the variable. It is rejected here because it treats the symptom (the prefix) instead of the cause (the forbidden `cd`), grows the allow-list with fragile arg-constraining patterns (the permissions doc explicitly warns these are fragile), and still leaves every other "complex scenario" needing its own bespoke rule. Removing the variable fixes the whole class at once.

---

## Options

### Option A — Keep the variable (status quo)
- **Pros:** anti-drift guarantee intact for Terraform; escape hatches already documented and enforced; zero migration.
- **Cons:** daily friction with no-`cd`; RVM ergonomics stay awkward; the friction the engineer is reporting persists.

### Option B — Remove the variable, adopt default carry-over, replace anti-drift separately
- **Pros:** main-session sequential commands stay in the right repo; rbenv/asdf auto-resolve; less escape-hatch overhead for main-session work; aligns with the platform default.
- **Cons:** re-opens Terraform cross-stack drift (Finding 3) → must add a compensating control; coordinated multi-file change; RVM benefit unconfirmed (Finding 5); subagents unaffected (Finding 4).
- **Required compensating control for Terraform anti-drift (pick one):**
  - B1. A PreToolUse hook that, for `terraform apply/destroy/import/taint/state rm`, prints the resolved cwd/stack and forces an explicit confirm (we already send these to the `ask` list — this would surface the stack in the prompt). Low effort, high signal.
  - B2. Require `terraform -chdir=<stack>` on every mutating terraform call (terraform's native per-stack flag — analogous to `git -C`), and block bare `terraform apply` without `-chdir`. Makes the stack explicit at the command level; survives cwd drift entirely.
  - B3. Keep `cd` reset behavior **only** when cwd is under `~/Projects/4Shark/terraform/**`, via a hook — narrow the anti-drift to where it matters and free the rest. Highest complexity.

### Option C — Hybrid: remove the variable but harden the `cd` discipline
- Adopt carry-over (Option B) **and** keep `validate-bash-command.sh` blocking `cd &&` chains (command-safety reason stands), while allowing standalone `cd`. Pair with B2 (`terraform -chdir`) as the anti-drift control since it is the most robust and mirrors the `git -C` pattern the team already follows.
- This is the closest to "always stay in the correct path" while preserving the property that made the original rule valuable.

---

## Open questions for the engineer

1. **Anti-drift appetite:** is the Terraform cross-stack drift risk (Finding 3) acceptable to trade away, or must it be replaced (B1/B2/B3) before removing the variable?
2. **Terraform `-chdir`:** are you open to standardizing `terraform -chdir=<stack>` on mutating calls (mirrors `git -C`/`gh -R`)? This is the cleanest anti-drift control and makes the cwd question moot for Terraform.
3. **RVM test:** do you want a quick empirical test of whether RVM auto-activates under correct cwd before committing to the RVM ergonomics claim, or is the rbenv/asdf win enough to justify the change on its own?
4. **Scope:** confirm this is main-session-only relief — subagents keep the escape hatches regardless (Finding 4). Acceptable?

---

## Recommendation (engineer decides)

**Option B with the lightest compensating control (B1)** — given Finding 7 (the harness is now controlled enough that raw drift is a narrow risk, and mutating terraform is already gated by `ask`):
- remove the variable, adopt the platform-default carry-over,
- keep the `cd &&`-chain block for command-safety reasons (not cwd reasons), while allowing standalone `cd` as the intended way to set the directory,
- add the lightweight anti-drift control B1 (surface the resolved stack/cwd inside the existing terraform `ask` prompt) rather than the heavier mandated `terraform -chdir` (B2). B2 remains a clean fallback if a drift incident ever recurs.

This:
- delivers the engineer's actual goal (stay in the correct path in the main session),
- gives the rbenv/asdf auto-resolution win immediately,
- keeps a proportionate anti-drift signal without re-introducing daily friction at the command level,
- and is honest about the residual: subagents and env-var inlining are unchanged.

**This change must go through the PR workflow per `CLAUDE.md § Configuration Changes Policy` — direct edits to `~/.claude/` can break active sessions.** Next step if approved: a PLAN.md covering the coordinated edits (settings.json, validate-bash-command.sh, two CLAUDE.md sections, the terraform anti-drift hook).

---

## Sources

- [Tools reference — Claude Code Docs](https://code.claude.com/docs/en/tools-reference) (Bash tool behavior: carry-over, reset, subagents, env vars, captured shell functions)
- [Environment variables — Claude Code Docs](https://code.claude.com/docs/en/env-vars) (`CLAUDE_BASH_MAINTAIN_PROJECT_WORKING_DIR` definition)
- Local: `~/.claude/settings.json:8` (env var), `:225` (additionalDirectories), `:432-437` (terraform mutating ops in `ask`)
- Local: `~/.claude/scripts/validate-bash-command.sh:111-130` (`cd &&` block + rationale)
- Local: `~/.claude/CLAUDE.md § Working Directory Behavior`, `§ Ruby Version Manager in Bash`
