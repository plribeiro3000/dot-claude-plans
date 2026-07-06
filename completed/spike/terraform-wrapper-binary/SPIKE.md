# SPIKE — Terraform Wrapper Binary + Redirect Hook

## Investigation question

Can 4Shark introduce a single **terraform wrapper script** (analogous to `~/.claude/scripts/ruby.sh`) plus a **PreToolUse redirect hook** (analogous to `~/.claude/scripts/redirect-ecs-scale.sh`) that:

1. Skips `terraform init` when it is not actually needed (init runs on every plan/apply today, and is slow)?
2. Deterministically rejects/strips `--target` (a documented-but-not-enforced 4Shark rule)?
3. Applies a **try-first** flow for `direnv` — run the command; only run `direnv allow` when direnv actually reports the `.envrc` as blocked; never pre-emptively re-allow?
4. Injects the correct env (`-chdir`, `AWS_PROFILE`) deterministically, the way `ruby.sh` injects the master key and version-manager path?

— **while structurally preserving** the existing approval gate for `terraform apply/destroy/import/taint/untaint` and `state rm/mv` (MFA profile + explicit human approval), so the wrapper cannot become a silent bypass of that gate?

## Sources consulted

- `~/.claude/docs/TERRAFORM-POLICY.md` (full read)
- `~/.claude/docs/TERRAFORM-CONVENTIONS.md` (full read)
- `~/.claude/docs/IDENTITY-STACK.md` (full read)
- `~/.claude/docs/adr/ADR-002-permission-resolver-precedence.md` (full read) — the deny→ask→allow precedence rule and its citation
- `~/.claude/scripts/inject-terraform-context.sh` — current Tier 2+ injection hook
- `~/.claude/scripts/ruby.sh` — the wrapper-binary template
- `~/.claude/scripts/redirect-ecs-scale.sh` — the redirect/`updatedInput` template
- `~/.claude/scripts/validate-bash-command.sh` (relevant sections) — the terraform write-op `emit_ask` block and command-normalization logic
- `~/.claude/settings.json` — full `permissions.allow`/`permissions.ask` terraform/direnv entries, and the `PreToolUse` hook wiring/ordering
- `~/Projects/4Shark/terraform/` — repo root listing, `terramate.tm.hcl`, a sample stack `.envrc` (`app-shared-001`), the `identity` stack `.envrc`, `.gitignore`, `stack.tm.hcl`, `.github/workflows/terraform-ci.yml`, presence/tracking of `.terraform.lock.hcl` and `.terraform/`
- [Configure permissions — Claude Code Docs](https://code.claude.com/docs/en/permissions) — official precedence rule, hook/permission interaction, and the "environment runner" wildcard-matching warning
- [Dependency Lock File — Terraform Docs](https://developer.hashicorp.com/terraform/language/files/dependency-lock)
- [Initialize Terraform configuration — Terraform Tutorial](https://developer.hashicorp.com/terraform/tutorials/cli/init)
- [terraform plan — Terraform CLI Docs](https://developer.hashicorp.com/terraform/cli/commands/plan) (`-target` guidance)
- [direnv(1) man page](https://direnv.net/man/direnv.1.html)
- [direnv-stdlib(1) man page](https://direnv.net/man/direnv-stdlib.1.html)
- `direnv/direnv` GitHub issues [#812](https://github.com/direnv/direnv/issues/812), [#581](https://github.com/direnv/direnv/issues/581), [#1463](https://github.com/direnv/direnv/issues/1463) — the exact blocked-`.envrc` error text and behavior
- `direnv/direnv` source: `internal/cmd/cmd_exec.go` and `internal/cmd/rc.go` (fetched via WebFetch) — the exact `notAllowed` constant and the exec-abort behavior
- [terramate run — Terramate CLI Docs](https://terramate.io/docs/cli/reference/cmdline/run) and [Terramate orchestration search results](https://terramate.io/docs/concepts/orchestration) — what `terramate run` actually does and its lack of built-in secret/env loading

## Current-state grounding

### 1. The terraform rules as written today

`~/.claude/docs/TERRAFORM-CONVENTIONS.md:111-116` on `init`:

> "### `terraform init`
> Run with **no flags**. Plain `terraform init`.
> - Never `-reconfigure`, `-upgrade`, `-migrate-state`
> - Extra flags hide problems or reset state in ways that bypass review"

No conditional-skip language exists in the doc today — the convention as written assumes `init` runs every time, unconditionally, with no flags.

`~/.claude/docs/TERRAFORM-CONVENTIONS.md:118-120` on `plan`/`--target`:

> "### `terraform plan`
> - Always **without `-target`** — plan the full stack. `-target` is a debugging tool that hides drift in non-targeted resources; using it routinely creates blind spots"

Note the wording: "using it **routinely** creates blind spots" — softer than an absolute ban, and in tension with the section header's "Always without". This ambiguity is a genuine open question (see § What remains uncertain).

`~/.claude/docs/TERRAFORM-CONVENTIONS.md:68-105` establishes the canonical invocation shape:

> "`direnv exec <dir> <cmd>` loads the `.envrc` for `<dir>` (if any) and runs `<cmd>` with that environment, without permanently mutating the shell. ... **`-chdir` needs the absolute stack path, not `~`.**"

and:

> "Because of this, `permissions.allow` in `settings.json` carries the `direnv exec ...` form explicitly, mirroring the bare `terraform <subcommand>:*` rules one-for-one... When adding a new terraform subcommand to the allow-list, add both the bare and the `direnv exec` form."

This is the precedent the wrapper design must respect: 4Shark's allow-list is already **per-subcommand granular**, not a blanket `terraform:*`/`direnv exec ...:*` wildcard. Any wrapper-form permission entries must follow the same granularity (see § Findings 5 and 6).

`~/.claude/docs/IDENTITY-STACK.md:6`:

> "Identity stack uses the `ivo` profile, not `4shark-mfa` — `terraform -chdir=identity ...` requires `AWS_PROFILE=ivo` (the break-glass account). The `identity/guard.tf` postcondition fails any other caller by design."

The `identity` and `audit` stacks set `AWS_PROFILE=ivo` **inside their own `.envrc`** (confirmed directly — see § Finding 7) rather than via an inline `env AWS_PROFILE=...` prefix on the command line. This matters for the wrapper's profile-injection logic (see § Finding 6).

### 2. Is `terraform init` allowed today? — Yes, unconditionally, in both invocation shapes

Direct quotes from `~/.claude/settings.json`:

```
481:      "Bash(terraform init:*)",
...
492:      "Bash(direnv exec ~/Projects/4Shark/terraform/* terraform -chdir=* init*)",
```

Both the bare form and the canonical `direnv exec` form of `terraform init` sit in `permissions.allow` with no conditions attached — every `init` invocation auto-approves, every time, regardless of whether the `.terraform/` directory or lock file already reflect the current configuration. There is **no permission-level throttle** on `init` today; the slowness the engineer describes is not a permission-prompt cost, it is the actual wall-clock cost of `terraform init` re-running provider/module resolution on every plan/apply cycle because the agent (or the convention) issues it unconditionally. This confirms the pain point precisely: `init` is not blocked or gated — it is just always executed.

### 3. The wrapper-binary template — `ruby.sh`

`~/.claude/scripts/ruby.sh:1-13` states its own rationale:

> "Run a Ruby/Bundler command through the correct version manager, with no command substitution and no env-var prefix in the invocation — so a single allow-list entry auto-approves every Ruby command.
> ... a command containing `$(...)` or a leading `VAR=value` prefix never matches the Claude Code permission allow-list ... This wrapper absorbs the version-manager resolution and the master-key read INTERNALLY, leaving the invocation as a single clean line."

Mechanically, `ruby.sh:63-65` shows the internal secret injection pattern to mirror:

```bash
if [[ -f config/master.key ]]; then
  export RAILS_MASTER_KEY="$(< config/master.key)"
fi
```

— the secret is read and exported **inside** the wrapper, never on the command line the permission matcher sees. And critically, `ruby.sh:88-91,110` shows the wrapper ultimately does `exec "$TOOL" "$@"` / `exec "$WRAPPER_DIR/$TOOL" "$@"` — the first positional argument passed to the wrapper becomes the exec'd binary with **no allow-list distinction between subcommands** (there is no Ruby-side equivalent of "apply requires approval"). This is safe for Ruby because there is no write/read split Ruby commands need gated the way terraform apply/destroy needs gating — **this is exactly the structural difference the terraform wrapper cannot copy verbatim** (see § Finding 6).

### 4. The redirect-hook template — `redirect-ecs-scale.sh`

`~/.claude/scripts/redirect-ecs-scale.sh:27-32` states the mechanism:

> "Returns `permissionDecision` `\"allow\"` together with `updatedInput`, which replaces the tool's `command` with the wrapper invocation before it runs. The rewritten `bash .../ecs-scale.sh ...` is itself auto-approved in `permissions.allow`, so the approval holds **even if the harness re-validates the rewritten input**."

The phrase "even if the harness re-validates the rewritten input" is the load-bearing design note: the hook's author did not assume re-validation happens, but engineered the rewrite target to be safe *regardless* — the rewritten command form (`bash ~/.claude/scripts/ecs-scale.sh ...`) is itself present in `permissions.allow` (`settings.json:455-456`). The hook also defers conservatively — `redirect-ecs-scale.sh:39-57` lists exhaustive conditions (compound commands, quoted args, unrecognized flags) under which it does nothing and lets the normal prompt flow proceed unchanged. This conservative-defer posture, plus "make the rewrite target safe on its own merits," are the two transferable design properties for a terraform redirect hook.

Critically, `ecs-scale.sh` has **no write/read distinction to preserve** — every ECS scale action is already homogeneous (there is no "ask"-gated ECS scale shape it must avoid bypassing). This precedent, by itself, does **not** demonstrate that a redirect hook can safely rewrite a *gated* write operation (terraform apply) — see § Finding 6, which is the crux of the safety analysis the engineer asked for.

### 5. The existing write-op safety gate — `validate-bash-command.sh`

`~/.claude/scripts/validate-bash-command.sh:556-562`:

```bash
if printf '%s' "$normalized_command" | grep -qE '^terraform([[:space:]]+-chdir=[^[:space:]]+)?[[:space:]]+(apply|destroy|import|taint|untaint)([[:space:]]|$)'; then
  emit_ask "terraform write operation (apply/destroy/import/taint/untaint) — approval required regardless of env-var, path, or -chdir prefix."
fi

if printf '%s' "$normalized_command" | grep -qE '^terraform([[:space:]]+-chdir=[^[:space:]]+)?[[:space:]]+state[[:space:]]+(rm|mv)([[:space:]]|$)'; then
  emit_ask "terraform state surgery (rm/mv) — approval required regardless of env-var, path, or -chdir prefix."
fi
```

This regex fires only when the *normalized* command's first token, after stripping a leading `VAR=`/`env` prefix and a leading absolute path, is literally `terraform`. **A command beginning with `direnv exec ...` or `bash ~/.claude/scripts/terraform.sh ...` never matches this regex** — the normalization logic (`validate-bash-command.sh:515-536`) strips only env-var assignments and absolute-path binaries, not a leading `direnv exec DIR` or `bash SCRIPT` prefix. This means: **`validate-bash-command.sh`'s bypass-detection is not the backstop for a wrapper-rewritten write command.** The only backstop for a wrapper form is whatever explicit entries exist in `settings.json`'s `ask` array for that exact wrapper-command shape (see § Finding 6).

### 6. Permission precedence — the mechanism that decides whether the safety gate survives

`~/.claude/docs/adr/ADR-002-permission-resolver-precedence.md:27` (quoting the official docs):

> "Rules are evaluated in order: deny → ask → allow. The first matching rule wins, so deny rules always take precedence."

and (`ADR-002:39`, also quoting the official docs):

> "Hook decisions do not bypass permission rules. Deny and ask rules are evaluated regardless of what a PreToolUse hook returns, so a matching deny rule blocks the call and a matching ask rule still prompts even when the hook returned 'allow' or 'ask'. This preserves the deny-first precedence."

I re-fetched the primary source directly (not just the ADR's quote) to confirm this is still accurate as of today. From [Configure permissions — Claude Code Docs](https://code.claude.com/docs/en/permissions), § "Extend permissions with hooks":

> "Hook decisions don't bypass permission rules. Deny and ask rules are evaluated regardless of what a PreToolUse hook returns, so a matching deny rule blocks the call and a matching ask rule still prompts even when the hook returned `"allow"` or `"ask"`. This preserves the deny-first precedence described in [Manage permissions], including deny rules set in managed settings."

**Verification**: URL fetched `https://code.claude.com/docs/en/permissions`; verbatim quote confirmed present at § "Extend permissions with hooks" (both fetches, same session).

The same official page also contains a directly on-point warning about wrapper/runner scripts, § "Process wrappers":

> "Development environment runners such as `direnv exec`, `devbox run`, `mise exec`, `npx`, and `docker exec` are not in the [process-wrapper stripping] list. Because these tools execute their arguments as a command, a rule like `Bash(devbox run *)` matches whatever comes after `run`, including `devbox run rm -rf .`. To approve work inside an environment runner, write a specific rule that includes both the runner and the inner command, such as `Bash(devbox run npm test)`. Add one rule per inner command you want to allow."

**Verification**: URL fetched `https://code.claude.com/docs/en/permissions`; verbatim quote confirmed present at § "Process wrappers" (same fetch as above).

**This is the exact rationale already baked into 4Shark's current terraform permission entries** — `settings.json` does not have one blanket `Bash(direnv exec ~/Projects/4Shark/terraform/*:*)` allow rule; it has one rule *per subcommand* (`... terraform -chdir=* init*`, `... plan*`, `... apply*`, etc., each independently placed in `allow` or `ask`). The official guidance — "add one rule per inner command you want to allow" — is precisely why that granularity exists, and it directly generalizes to a `bash ~/.claude/scripts/terraform.sh ...` wrapper: **a single broad `Bash(bash ~/.claude/scripts/terraform.sh:*)` allow entry would be exactly the anti-pattern this warning names**, because the wrapper (like `direnv exec` and `devbox run`) ultimately execs whatever subcommand is passed to it. A wrapper allow entry must be split per-subcommand, exactly mirroring today's `terraform`/`direnv exec` split between `allow` (init/plan/validate/fmt/show/output/workspace/providers/version/state list/state show) and `ask` (apply/destroy/import/taint/untaint/state rm/mv).

Consequence for the redirect-hook design: whether or not the harness re-validates `updatedInput` against the permission lists (the `ecs-scale.sh` author engineered around this exact uncertainty — see § Finding 4), the **only mechanically-guaranteed way to preserve the apply/destroy gate** is:

1. **Never let the redirect hook rewrite a write subcommand into a form covered only by a broad allow rule.** Concretely: the redirect hook should either (a) not rewrite apply/destroy/import/taint/untaint/state-rm/state-mv at all — deferring to today's existing `ask` entries for the raw/`direnv exec` forms — or (b) rewrite them into the wrapper form **only if** the wrapper's write-subcommand shape is *also* explicitly registered in `permissions.ask` (mirroring the granularity above), so the rewritten command still matches an `ask` rule regardless of how the harness re-validates it.
2. Given the official doc's explicit "add one rule per inner command" guidance, option (b) is achievable but adds six new `ask` entries (`Bash(bash ~/.claude/scripts/terraform.sh apply:*)`, `destroy`, `import`, `taint`, `untaint`, `state rm`/`state mv`) with the identical shape/intent as the six that already exist for the raw and `direnv exec` forms.
3. Additionally, `terraform.sh` itself must **never** do a blind `exec "$1" "$@"` the way `ruby.sh` does (`ruby.sh:88-91,110`) — it must hardcode `exec terraform "$@"` (the binary is fixed, never taken from the caller), and treat the subcommand only as a string to branch on for env/profile decisions, never as an arbitrary exec target. This closes the "environment runner executes its arguments as a command" risk the official docs warn about, at the wrapper-script layer itself (defense in depth alongside the permission-list granularity in point 2).

### 7. The terraform repo reality — Terramate is orchestration-only, not a run-wrapper

`~/Projects/4Shark/terraform/terramate.tm.hcl` (full contents):

```hcl
terramate {
  required_version = ">= 0.12.0"

  config {
    git {
      default_remote = "origin"
      default_branch = "develop"
    }
  }
}
```

Every stack directory carries its own `stack.tm.hcl` (confirmed for 22 stacks via `find`), e.g. `~/Projects/4Shark/terraform/app-shared-001/stack.tm.hcl:1-7`:

```hcl
stack {
  name        = "app-shared-001"
  description = "App Shared 001 ECS application environment"
  id          = "app-shared-001"
  tags        = ["aws", "us-east-1", "app"]
  after       = ["/shared-resources", "/dns"]
}
```

— this defines stack **ordering metadata** (`after`), not a run/env wrapper. Confirming this, `~/Projects/4Shark/terraform/.github/workflows/terraform-ci.yml:27-34` shows Terramate's actual role in the one place it is invoked in this repo:

```yaml
- name: Install Terramate
  uses: terramate-io/terramate-action@1cc78a548efefaab7762f4d06f51aa6de06ce201 # v3
- name: Detect changed stacks
  id: detect
  run: |
    STACKS=$(terramate list --changed --output json 2>/dev/null || echo "[]")
```

Every subsequent CI step (`terraform-ci.yml:67-125`) then runs **plain `terraform init` / `validate` / `fmt` / `plan`** per matched stack directory — CI never invokes `terramate run`. Terramate's only job in this repo is `terramate list --changed`, i.e., change detection for the CI matrix — never command execution or env injection.

`.envrc` presence: every stack that needs third-party secrets has its own `.envrc` (confirmed: `app-demo-001`, `identity`, `integrator-almaviva`, `integrator-redebrasil`, `setup`, `integrator-atento`, `integrator-maqnelson`, `audit`, `app-shared-001`, `integrator-commcenter`, `app-beta-001`, `app-atento-001`, `monitoring`, `dns`, `auth-001`, `onboarding` — 16 stacks). Stacks like `networking`, `analytics-access`, `vpn`, `workspace-access` have none, consistent with `TERRAFORM-CONVENTIONS.md:66`'s "Stacks that need no third-party secret ... have no `.envrc`."

`~/Projects/4Shark/terraform/identity/.envrc:4` confirms the profile is set **inside** the stack's own `.envrc`, not via an inline `env` prefix on the command line:

```bash
export AWS_PROFILE=ivo
```

`~/Projects/4Shark/terraform/.gitignore:2` confirms `.terraform/` is git-ignored (so its presence/absence is a local, machine-specific signal, not a repo-tracked one):

```
.terraform/
```

Directly confirmed for `app-shared-001` (already-initialized locally on this machine):

```
$ find ~/Projects/4Shark/terraform/app-shared-001 -maxdepth 1 -name ".terraform.lock.hcl" -o -maxdepth 1 -name ".terraform"
/Users/plribeiro3000/Projects/4Shark/terraform/app-shared-001/.terraform
/Users/plribeiro3000/Projects/4Shark/terraform/app-shared-001/.terraform.lock.hcl
$ git -C ~/Projects/4Shark/terraform ls-files app-shared-001/.terraform.lock.hcl
app-shared-001/.terraform.lock.hcl
```

`.terraform.lock.hcl` **is git-tracked** (the `git ls-files` output confirms it), matching HashiCorp's own guidance to commit the lock file (see § Finding: conditional init below). `.terraform/` exists locally but is git-ignored — so a fresh `git clone` or fresh worktree has no `.terraform/` and genuinely needs `init`, while a machine that already ran `init` for that stack has it cached locally.

---

## Findings

### Finding 1: The trustworthy conditional-init signal is the combination of "does `.terraform/` exist" and "is the lock file unchanged since last init" — not a single file check

**Evidence:** [Dependency Lock File — Terraform Docs](https://developer.hashicorp.com/terraform/language/files/dependency-lock):

> "Terraform automatically creates or updates the dependency lock file each time you run the `terraform init` command."

And when init updates it because the resolved providers changed:

> "Terraform has made some changes to the provider dependency selections recorded in the .terraform.lock.hcl file. Review those changes and commit them to your version control system if they represent changes you intended to make."

From [Initialize Terraform configuration — Terraform Tutorial](https://developer.hashicorp.com/terraform/tutorials/cli/init), the tutorial enumerates exactly when re-init is required:

> "You add, remove, or change the version of a module or provider in an existing workspace" ... "You add, remove, or change the `backend` or `cloud` blocks within the `terraform` block of an existing workspace"

and, critically, the built-in safety net if a session forgets to re-init:

> "If you forget to re-initialize after changes, other commands will detect it and remind you to do so if necessary." For example: "Run `terraform init` to install all modules required by this configuration."

**Significance:** There is no single authoritative "init is needed" boolean file Terraform exposes for a wrapper to check directly — the two *reliable local signals* are: (a) **`.terraform/` does not exist at all** in the stack directory (fresh checkout/worktree — unconditionally needs init), and (b) **`.terraform/` exists, but `terraform validate` or `terraform plan` itself errors out demanding `init`** (Terraform's own built-in detection, quoted above, is the authoritative check — not a heuristic the wrapper re-implements). A wrapper can safely treat "run the read command first; if the specific `... init required...` error text or exit behavior appears, run init and retry" as the trustworthy signal, mirroring the direnv try-first shape (Finding 3) rather than trying to independently diff provider blocks or module sources against the lock file (fragile, config-parsing heuristic). Provider/module changes are exactly what `.terraform.lock.hcl`'s own content-hash mechanism is for (HashiCorp: "each time you run `terraform init`"), but the wrapper does not need to parse the lock file itself — Terraform already refuses to proceed and says so when it is out of date. **Not found**: an official HashiCorp statement of the exact error string or exit code `terraform plan`/`validate` emits when init is required (the tutorial paraphrases it as "Run `terraform init`..." but I could not verify the literal string via a primary source in the time available — flagged under § What remains uncertain).

**Verification**: URL fetched `https://developer.hashicorp.com/terraform/language/files/dependency-lock`; quote on lock-file update behavior confirmed present. URL fetched `https://developer.hashicorp.com/terraform/tutorials/cli/init`; quotes on re-init triggers and automatic detection confirmed present.

### Finding 2: `terraform init -backend=false` is already 4Shark's own validated "cheap init" shape — but only for CI, and it explicitly skips backend/state wiring

**Evidence:** `~/Projects/4Shark/terraform/.github/workflows/terraform-ci.yml:67-69`:

```yaml
- name: Terraform Init
  working-directory: ${{ matrix.stack }}
  run: terraform init -backend=false
```

used only in the `validate` job (before `terraform validate` / `terraform fmt -check`), while the `plan` job (`terraform-ci.yml:105-114`) runs full `terraform init` (no `-backend=false`) before `terraform plan`.

**Significance:** 4Shark's own CI already draws the same distinction the engineer is asking the wrapper to draw locally: a cheap, backend-skipping init is good enough for `validate`/`fmt` (no state access needed), but `plan`/`apply` need the full init (backend configured, state accessible). This is directly reusable evidence that "no single init cost fits every subcommand" — the wrapper's conditional logic should treat `validate`/`fmt` as tolerating a lighter init path if a distinction is wanted, though this is a refinement, not the primary conditional-init mechanism (Finding 1).

### Finding 3: direnv's `exec` aborts the command entirely when `.envrc` is blocked — the abort is the trustworthy try-first signal, not a heuristic

**Evidence:** [direnv-stdlib(1) man page](https://direnv.net/man/direnv-stdlib.1.html) confirms `direnv allow` semantics only at a high level (`"Grants direnv permission to load the given .envrc or .env file"`), so I went to the actual Go source for the precise mechanics. I fetched `direnv/direnv`'s `internal/cmd/rc.go` directly:

> `const notAllowed = "%s is blocked. Run \`direnv allow\` to approve its content"` (line 243, per the fetched file), used via `err = fmt.Errorf(notAllowed, rc.Path())` in the `Load()` function.

And `internal/cmd/cmd_exec.go` (fetched directly):

```go
if toLoad := findEnvUp(rcPath, config.LoadDotenv); toLoad != "" {
    if newEnv, err = config.EnvFromRC(toLoad, previousEnv); err != nil {
        return
    }
} else {
    newEnv = previousEnv
}
```

`EnvFromRC` internally calls the same `Load()` path that produces the `notAllowed` error above when the `.envrc`'s content hash is not in the allow-list. When it returns an error, `cmd_exec.go` **returns immediately** — the wrapped command is never executed.

Corroborating this from the user-facing side, GitHub issue [#812](https://github.com/direnv/direnv/issues/812) and [#581](https://github.com/direnv/direnv/issues/581) both show the literal terminal error:

> "direnv: error $PWD/.envrc is blocked. Run `direnv allow` to approve its content"

**Significance:** This is exactly the deterministic signal the try-first flow needs. `direnv exec <stack-dir> terraform ...` either (a) succeeds and runs terraform with the loaded env, or (b) **fails without running terraform at all**, printing `<path> is blocked. Run \`direnv allow\` to approve its content` to stderr with a non-zero exit. A wrapper can safely: run the command once; if it exits non-zero AND stderr contains the substring `is blocked. Run` (or `direnv: error`), run `direnv allow <stack-dir>` exactly once, then retry the original command exactly once. There is no risk of terraform silently running with a stale/absent env — direnv's own abort-on-block behavior *is* the safety net. Re-allowing on every invocation (today's likely habit) is therefore pure waste: the hash-based allow-list (confirmed indirectly via the `notAllowed` message format and the community reports of hash-mismatch-driven re-blocks) only invalidates when the `.envrc` content actually changes or a path was never allowed — an unchanged `.envrc` stays allowed indefinitely, so "try first, allow only on the specific blocked-error" costs nothing and never mutates the shell.

**Verification**: URLs fetched — `https://direnv.net/man/direnv-stdlib.1.html`, `https://github.com/direnv/direnv/issues/812`, `https://github.com/direnv/direnv/issues/581`, and the two source files `internal/cmd/rc.go` / `internal/cmd/cmd_exec.go` on `github.com/direnv/direnv`. Verbatim `notAllowed` constant and the abort-before-exec code path both confirmed present in the fetched source; the terminal error text corroborated independently across two separate GitHub issues.

### Finding 4: HashiCorp itself discourages `-target` for routine use — reinforcing, not contradicting, the 4Shark rule, but explicitly reserving it for "exceptional circumstances"

**Evidence:** [terraform plan — Terraform CLI Docs](https://developer.hashicorp.com/terraform/cli/commands/plan):

> "It is _not recommended_ to use `-target` for routine operations, since this can lead to undetected configuration drift and confusion about how the true state of resources relates to configuration."

and:

> "\[`-target`] is provided for exceptional circumstances, such as recovering from mistakes or working around Terraform limitations."

with the alternative HashiCorp recommends instead of routine targeting:

> "breaking large configurations into several smaller configurations that can each be independently applied."

**Significance:** This directly confirms 4Shark's own rationale (`TERRAFORM-CONVENTIONS.md:120`: "`-target` is a debugging tool that hides drift in non-targeted resources") is aligned with the authoritative source, closing the loop the engineer asked for. It also surfaces the open question precisely: HashiCorp does **not** say "never" — it carves out "exceptional circumstances, such as recovering from mistakes." 4Shark's own doc says "Always without `-target`" in its section header but then qualifies the *reason* as being about *routine* use. **I did not find a 4Shark-authored statement of what an "exceptional circumstance" override procedure looks like today** (there is no escape hatch documented) — this is the fact the engineer must resolve: should the wrapper (a) hard-reject `--target` with a corrective message pointing at "ask the engineer, then run the raw command deliberately" as the override path, or (b) silently strip it? Given the "digest" of HashiCorp's own guidance (recovering from mistakes is a legitimate, if rare, use), a silent strip would remove a legitimate escape hatch without the engineer ever knowing it was requested — this argues for reject-with-message over silent-strip, but this is a design choice for the engineer to confirm (§ Suggested options).

**Verification**: URL fetched `https://developer.hashicorp.com/terraform/cli/commands/plan`; both quotes ("not recommended for routine operations" and "exceptional circumstances, such as recovering from mistakes") confirmed present in the fetched page content.

### Finding 5: Terramate is not a viable local single-stack wrapper target — it delegates env/secrets to the shell layer and 4Shark only uses it for CI change-detection

**Evidence:** [terramate run — Terramate CLI Docs](https://terramate.io/docs/cli/reference/cmdline/run):

> "The `terramate run` command executes any command in all or a subset of stacks honoring the defined order of execution." Primary use case per the fetched page: multi-stack CI/CD orchestration (filtering changed stacks, parallel execution, syncing to Terramate Cloud). On environment/secret handling: "The documentation makes no mention of built-in direnv integration or per-stack secret loading mechanisms... responsibility for per-stack environment variables and secrets appears to be delegated to the shell layer."

Corroborated by 4Shark's own repo: `terraform-ci.yml:27-34` shows the **only** Terramate invocation in the repo is `terramate list --changed --output json` for CI change-detection; every actual `terraform init`/`validate`/`fmt`/`plan` in that same workflow (`terraform-ci.yml:67-125`) runs as **plain `terraform`**, never `terramate run`.

**Significance:** Wrapping `terramate run` instead of raw `terraform` would not remove the direnv problem — Terramate still needs the shell (direnv) layer underneath it for secrets, so a `terramate`-wrapping design would still need the exact same `direnv exec`/try-first logic this spike is solving, just at one more layer of indirection, with no offsetting benefit for a **single-stack** local operation (`terramate run`'s value is multi-stack ordering/parallelism, which 4Shark's engineer-driven, one-stack-at-a-time apply-before-merge workflow does not use — confirmed no `terramate run` anywhere in `TERRAFORM-CONVENTIONS.md`). The wrapper should target raw `terraform` (via `direnv exec`), matching what the repo actually does today for individual stack operations.

**Verification**: URL fetched `https://terramate.io/docs/cli/reference/cmdline/run`; quote on `terramate run`'s function and the absence-of-secret-loading conclusion both confirmed present in the fetched content. Codebase citation `terraform-ci.yml:27-34,67-125` read directly.

### Finding 6: A single broad wrapper-allow entry would repeat the exact anti-pattern the official docs warn about — the write/read split must be preserved at the same granularity as today

(Fully argued in § Current-state grounding, Finding 6 above — restated here as a Finding per the citation-discipline structure.)

**Evidence:** [Configure permissions — Claude Code Docs](https://code.claude.com/docs/en/permissions), § "Process wrappers":

> "Development environment runners such as `direnv exec`, `devbox run`, `mise exec`, `npx`, and `docker exec` are not in the [process-wrapper stripping] list. Because these tools execute their arguments as a command, a rule like `Bash(devbox run *)` matches whatever comes after `run`, including `devbox run rm -rf .`. To approve work inside an environment runner, write a specific rule that includes both the runner and the inner command... Add one rule per inner command you want to allow."

and § "Extend permissions with hooks":

> "Hook decisions don't bypass permission rules. Deny and ask rules are evaluated regardless of what a PreToolUse hook returns, so a matching deny rule blocks the call and a matching ask rule still prompts even when the hook returned `"allow"` or `"ask"`."

**Significance:** These two passages together are the entire safety argument for the wrapper+redirect design. They confirm: (1) a wrapper script that execs its argument is architecturally identical to `devbox run`/`direnv exec` for permission-matching purposes — one blanket allow rule for the wrapper binary would auto-approve every subcommand including `apply`/`destroy`, which is exactly the failure mode 4Shark's Git-Safety and Terraform-Policy rules exist to prevent (the terraform PR #527 incident cited in `CLAUDE.md` § Git Safety is the same class of failure: an auto-approved path where a gated one was intended); (2) even granting the redirect hook returns `permissionDecision: "allow"`, that does not override a matching `ask` rule elsewhere in the settings — so the fix is structural (split the wrapper's own allow-list entries per-subcommand, exactly mirroring today's raw/`direnv exec` split) rather than behavioral (trusting the hook's own decision).

**Verification**: URL fetched `https://code.claude.com/docs/en/permissions`; both quotes confirmed present at their respective sections in the same fetch used for Finding in § Current-state grounding #6.

### Finding 7: The `identity`/`audit` stacks' profile is invisible to the command line today — the wrapper can either preserve or eliminate this invisibility, and that is a design choice, not a bug to silently fix

**Evidence:** `~/Projects/4Shark/terraform/identity/.envrc:4`: `export AWS_PROFILE=ivo` — set inside the stack's own `.envrc`, never passed as an inline `env AWS_PROFILE=...` argument. Consequently, an `identity`-stack apply command today would be shaped `direnv exec ~/Projects/4Shark/terraform/identity terraform -chdir=<path> apply <planfile>` — **with no ` env AWS_PROFILE=... ` segment at all**. Cross-referencing `settings.json:601-606`, the only `ask`-listed `direnv exec` write-op forms require the literal substring ` env AWS_PROFILE=4shark-mfa ` — so the `identity`/`audit` apply shape does not match any of the six explicit `ask` entries, nor any `allow` entry (write subcommands are absent from the `direnv exec` `allow` block, `settings.json:492-502`).

**Significance:** This is not a bypass today — an unmatched Bash command falls through to Claude Code's default interactive prompt (confirmed structurally by the precedence rule in Finding 6: "the first matching rule wins" implies an *unmatched* command is neither auto-allowed nor auto-denied, so it hits the standard confirmation flow), which is the safe default, just an *undocumented* one (no `emit_ask` custom message explains why `identity`/`audit` applies prompt). If the wrapper is built to resolve `AWS_PROFILE` **internally** (4shark-mfa for ordinary stacks, deferring to whatever `identity`/`audit`'s own `.envrc` sets for those two), the command line the model would type becomes uniform across every stack — `bash ~/.claude/scripts/terraform.sh <stack> apply <planfile>` with no profile visible at all — which actually *simplifies* the ask-list requirement (one set of six wrapper-subcommand `ask` entries covers every stack, `identity`/`audit` included, rather than needing a parallel `ivo`-specific set). This is a genuine simplification the wrapper enables, but it must be a deliberate, documented design choice (the six wrapper `ask` entries must exist before the wrapper ships), not an accidental side effect.

**Verification**: Codebase-only finding; both citations (`identity/.envrc:4`, `settings.json:601-606,492-502`) read directly in this session.

---

## Documentation & rationale discoverability

The coordinator flagged that mechanical enforcement (block/redirect) is not enough on its own — a future session that hits the block or gets silently redirected needs to be able to **find and re-derive the reasoning**, the same way `~/.claude/scripts/validate-bash-command.sh:538-554`'s EC2-instance block explains itself inline and points to the wrapper + `CLAUDE.md`, and the way `redirect-ecs-scale.sh:1-57`'s own header explains its own rationale before any code runs.

Applying that same shape to the terraform wrapper, three places need to carry the rule, each doing a different job:

**1. The corrective message at the point of friction** (the wrapper script's own stderr, and/or the redirect hook's `permissionDecisionReason`). Modeled directly on the EC2 block's shape (`validate-bash-command.sh:539-552`, which the wrapper's design should mirror almost verbatim):

```
Raw `terraform ...` / hand-built `direnv exec ... terraform ...` — routed through the terraform.sh wrapper.

Why:
  - `terraform init` re-runs provider/module resolution on every invocation unless something gates it — the wrapper only runs init when `.terraform/` is missing or Terraform itself reports init is required.
  - `--target` hides drift in non-targeted resources (HashiCorp: "not recommended ... routine operations") — the wrapper rejects it rather than silently stripping it, so a genuinely exceptional need surfaces to the engineer instead of disappearing.
  - Pre-emptively re-running `direnv allow` on every invocation wastes a round-trip when the `.envrc` content has not changed — the wrapper runs the command first and only allows once, on the specific "is blocked" signal direnv itself emits.
  - See ~/.claude/docs/TERRAFORM-CONVENTIONS.md and ~/.claude/docs/TERRAFORM-POLICY.md for the full policy this wrapper implements.

Fix: bash ~/.claude/scripts/terraform.sh <stack> <subcommand> [args...]
```

This is the layer an erring session actually *sees* first — same principle as the EC2 block's `Why:` / `Fix:` shape, which the engineer already validated works (it is in production).

**2. The policy docs — `TERRAFORM-POLICY.md` / `TERRAFORM-CONVENTIONS.md`.** These are the canonical "why" a session reads when it wants the full reasoning, not just the corrective one-liner. If the wrapper ships, both docs need a new bullet stating: (a) the wrapper is the **only** sanctioned invocation path — raw `terraform`/hand-built `direnv exec` is forbidden even though the underlying commands are technically unchanged; (b) each of the three problems the wrapper solves (init-every-time, `--target` drift, direnv re-allow waste) gets one sentence of "why this was a problem" so the rule is never just an assertion. This mirrors how `TERRAFORM-CONVENTIONS.md:96-105` today already explains *why* the `direnv exec` allow-list entries are shaped the way they are ("the matcher does string-prefix matching...") rather than just stating the shape.

**3. A short `CLAUDE.md` rule**, mirroring the existing "Ruby Version Manager in Bash" section's shape (`CLAUDE.md` § "Ruby Version Manager in Bash": *"Run every Ruby/Bundler command through `~/.claude/scripts/ruby.sh`... Do NOT hand-build ... Do NOT prefix with ..."*). A parallel "Terraform Command Execution" section would state, tersely, in the always-loaded Tier-1/critical-rules surface: run every terraform command through `terraform.sh`; never hand-build `direnv exec`/`AWS_PROFILE=...` invocations; the wrapper handles conditional init, `--target` rejection, and direnv try-first internally; the write-op approval gate (`apply`/`destroy`/etc.) is unchanged and still prompts. This is the layer that survives context compaction and reaches every session (main and subagent) without the session needing to have hit the block first — same role `CLAUDE.md`'s Ruby section plays for `ruby.sh` today.

**Why all three, not just one:** the EC2 wrapper precedent (`validate-bash-command.sh:538-554`) already demonstrates that a corrective message *alone*, without a standing `CLAUDE.md` rule, still gets rediscovered every time the block fires — that is acceptable for a rare operation (starting/stopping an instance), but terraform commands run far more often, so relying only on "hit the block, read the message" would cost a wasted turn on every session's first terraform command. Conversely, a `CLAUDE.md` rule alone (no corrective message) fails the moment a session's context is compacted and the rule scrolls out of active memory — which is exactly why the Ruby rule is reinforced by `ruby.sh` refusing malformed invocations with its own `Usage:` stderr, and why `inject-working-dir-reminder.sh` exists as a *second*, mechanically-triggered reinforcement layer alongside the prose rule. The three layers (corrective message, canonical doc, `CLAUDE.md` bullet) are not redundant — each is the answer for a different moment: mid-command friction, deliberate lookup, and standing memory, respectively.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| **Thin wrapper (`terraform.sh`) + redirect hook (read-ops only), write-ops NEVER rewritten** | Read-ops (init/plan/validate/fmt/show/output/etc.) get conditional-init, direnv try-first, and env injection for free with zero extra `ask`-list entries; write-ops keep today's exact, already-in-production gate untouched (zero regression risk) | Apply/destroy do not get the wrapper's smoothing (direnv try-first, deterministic profile) unless the engineer types the wrapper form directly, which requires new `ask` entries anyway if that convenience is wanted later | Findings 3, 6; `redirect-ecs-scale.sh:39-57` conservative-defer precedent |
| **Full wrapper (all subcommands) + redirect hook that rewrites everything, with new granular `ask` entries mirroring today's split** | Uniform invocation shape for every subcommand including apply/destroy; `identity`/`audit` profile handling becomes internal and consistent (Finding 7); one coherent mental model | Requires adding and carefully maintaining 6 new `ask`-list entries (`bash .../terraform.sh apply\|destroy\|import\|taint\|untaint\|state rm/mv`) — a maintenance surface that must never regress to a blanket allow; higher blast radius if the split is ever done wrong | Findings 6, 7; ADR-002; official docs § "Process wrappers" |
| **Wrapper only, no redirect hook** (model must remember to call `bash terraform.sh ...` itself) | Zero interaction risk with the permission engine's re-validation-of-`updatedInput` ambiguity — the model's own invocation is what gets matched, nothing rewritten | Reintroduces exactly the problem the engineer is trying to solve: the model still has to *remember* to use the wrapper every time; no mechanical guarantee, same failure mode as "list the rule in `CLAUDE.md` and hope" | Documentation & rationale discoverability section above; `CLAUDE.md` § Ruby Version Manager precedent shows a wrapper alone is not self-enforcing — hooks are what make it mechanical |
| **Extend `inject-terraform-context.sh` only (status quo + more context), no wrapper/redirect** | Zero new code, zero new permission-list entries, zero new failure surface | Does not solve any of the four pain points — injection only adds *documentation* to context, it cannot skip `init`, strip `--target`, or avoid a direnv re-allow; the engineer explicitly asked for mechanical smoothing, not more prose | Direct reading of `inject-terraform-context.sh` — it is allow-only (`permissionDecision: "allow"`), has no logic to change what actually runs |
| **Adopt `terramate run` as the wrap target instead of raw `terraform`** | Terramate is already in the repo (not a new dependency); could unify local + CI invocation shape | Terramate has no built-in secret/env-loading — the direnv problem does not go away, it just moves one layer deeper; 4Shark's own CI never uses `terramate run` for actual command execution, only `terramate list --changed`; no local single-stack workflow uses it today (would be new scope, not a fix) | Finding 5 |

---

## What remains uncertain

- **Whether Claude Code's harness re-validates a hook's `updatedInput` against the full `permissions.allow`/`ask`/`deny` lists, or only executes it after the *original* command already cleared the gate.** The `redirect-ecs-scale.sh` author explicitly engineered around not knowing this ("even if the harness re-validates the rewritten input") rather than asserting it as fact, and I could not find an authoritative statement of this specific mechanic in the fetched official docs (the docs describe hook-vs-rule precedence for the *original* tool call, not explicitly for a rewritten one). This spike's recommended designs are safe under **either** interpretation (per Finding 6's granular-entries argument), but the underlying platform behavior itself is not confirmed from a primary source.
- **The exact error string / exit code Terraform emits when a command needs `init`.** The HashiCorp tutorial paraphrases it ("Run `terraform init`...") but I did not verify the literal, version-stable string from a primary source in the time available (Finding 1). A wrapper implementation would need to empirically capture this against the 4Shark-pinned Terraform version (`~1.5`, per `terraform-ci.yml:65`) before relying on string-matching it.
- **Whether "Always without `-target`" in `TERRAFORM-CONVENTIONS.md:120` is meant as an absolute ban or tolerates HashiCorp's "exceptional circumstances" carve-out** (Finding 4). The doc's own wording is internally in tension (section header says "Always", the rationale sentence says "routinely"). This affects whether the wrapper should hard-reject `--target` with no override path, or reject-with-message-and-documented-manual-override.
- **Whether 4Shark wants the wrapper to also resolve `AWS_PROFILE` internally for write ops** (Finding 7), which would newly require six `ask`-list entries for the wrapper's own write-subcommand forms — a design/scope decision, not a research gap.

## Suggested options for main and the engineer

- **Option A — Read-ops-only wrapper + redirect; write-ops untouched.** Ship `terraform.sh` covering `init` (conditional), `plan`, `validate`, `fmt`, `show`, `output`, `workspace`, `providers`, `version`, `state list`, `state show` — with direnv try-first and `--target` rejection built in. `redirect-terraform.sh` rewrites only these subcommands (raw or `direnv exec` shape) into the wrapper form, mirroring `redirect-ecs-scale.sh`'s conservative-defer posture for anything it doesn't recognize. Apply/destroy/import/taint/untaint/state-rm/state-mv are explicitly out of the redirect hook's scope — they keep exactly today's already-in-production gate, zero new `ask`-list entries needed, zero regression risk. This is the minimal-blast-radius option; it solves 3 of 4 pain points (init, direnv, env-injection) fully and leaves `--target`-on-write moot (write ops rarely use `-target` in 4Shark's workflow per `TERRAFORM-CONVENTIONS.md`'s framing as a `plan`-time concern).
- **Option B — Full wrapper (every subcommand) + redirect, with six new mirrored `ask` entries for the wrapper's write forms.** Solves all four pain points uniformly, including `identity`/`audit` profile handling (Finding 7). Requires the engineer to explicitly approve and add the new `ask` entries as part of the same change — per Finding 6, this is the one place a mistake would silently reopen the exact incident class `CLAUDE.md` § Git Safety already names (terraform PR #527). This is the maximal-value, maximal-care option.
- **Option C — Wrapper only, no redirect hook; model is instructed (via the new `CLAUDE.md` rule + doc updates from § Documentation & rationale discoverability) to call it directly.** Removes the "does the redirect correctly leave write-ops alone" risk category entirely, at the cost of relying on the model to remember to invoke the wrapper — the same non-mechanical reliability gap the engineer is trying to close by asking for a redirect hook in the first place.
- **Option D — Do nothing to `--target` beyond documentation** (leave enforcement as an unenforced convention) **while still shipping conditional-init + direnv try-first** in the wrapper. Splits the three original pain points: ships the two that have a clean, low-risk mechanical fix (init, direnv) now, defers the `--target` decision (which needs the engineer's resolution of the "exceptional circumstances" ambiguity in Finding 4) to a follow-up.

No recommendation is made here — Options A–D trade blast radius against completeness, and the `--target` reject-vs-strip question in Finding 4 is a genuine policy decision, not a technical one.

## Resolution — decided and implemented (2026-07-05)

**Decision: Option A (read-ops-only wrapper + redirect; writes untouched), with `--target` rejected-with-message.** Both scripts shipped:

- **`scripts/terraform.sh`** — the wrapper, **read-only by construction**. Covers `init`/`plan`/`validate`/`fmt`/`show`/`output`/`version` and `state list`/`state show`; refuses every write subcommand with a corrective message. Conditional init (runs `init` only when `.terraform/` is absent, or when the subcommand fails reporting init is required — Finding 1's trustworthy signal). direnv try-first (runs first; runs `direnv allow` once only on direnv's own `is blocked. Run` abort, then retries — Finding 3). `--target` rejected with a message rather than silently stripped (Finding 4). The `terraform` binary is hardcoded (never exec'd from an argument — Finding 6, point 3).
- **`scripts/redirect-terraform.sh`** — PreToolUse hook that rewrites raw read-terraform (`terraform -chdir=… <read>` and `direnv exec … terraform … <read>`) into the wrapper form via `updatedInput`; **defers write subcommands untouched** so they keep hitting the existing `emit_ask` gate.

**How the crux (Finding 6) was resolved:** rather than add six new granular `ask` entries (Option B), the wrapper is **read-only by construction** — it cannot run a write — which makes a single broad `Bash(bash ~/.claude/scripts/terraform.sh:*)` allow entry safe. Writes were left entirely out of the wrapper/redirect scope, so the apply/destroy/state-surgery gate + MFA (`4shark-mfa` / `ivo`) is untouched. No new `ask` entries were needed, and the PR #527 incident class stays closed.

**Open questions from the spike, now resolved:**
- *Is `terraform init` allowed today?* — Yes, confirmed unconditionally (`settings.json`), so the slowness was wall-clock (unconditional re-init), never a permission prompt. The wrapper's conditional init is the fix.
- *Trustworthy init signal* — `.terraform/` absent, plus terraform's own init-required error as the fallback; the wrapper does not re-implement lock-file diffing.
- *direnv try-first shape* — the `is blocked. Run` abort is the deterministic signal; allow-once-and-retry, never pre-emptive.
- *Terramate* — not the wrap target (CI-only change-detection, no env/secret loading); the wrapper targets raw `terraform` via `direnv exec`.

**Deferred / not adopted:** Option B (full wrapper + six `ask` entries) — not built; the read-only-by-construction approach achieves safety without it. Option C (wrapper without redirect) and Option D (defer the `--target` decision) — not adopted; the redirect ships and `--target` is handled (reject-with-message).

**Documentation & rationale discoverability** — implemented in all three layers as the § above specified: the wrapper/redirect corrective messages, a "The Wrapper" section in `TERRAFORM-CONVENTIONS.md` + a top bullet in `TERRAFORM-POLICY.md`, and a "Terraform Command Execution" rule in `CLAUDE.md` (mirroring the Ruby Version Manager section).

**Implementation note:** a real bug was caught in smoke-testing — expanding an empty array under `set -u` on macOS bash 3.2 (`"${empty[@]}"`) throws "unbound variable"; fixed with the `${arr[@]+"${arr[@]}"}` idiom in both scripts.

**Delivered:** PR #342 — `feat(hooks): route read terraform commands through a wrapper with conditional init` — merged into `develop` on 2026-07-05.
