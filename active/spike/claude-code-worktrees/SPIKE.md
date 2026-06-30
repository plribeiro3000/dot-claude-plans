# SPIKE — Always Working in Git Worktrees with Claude Code / AI Coding Agents

## Investigation question

Should the 4Shark dot-claude configuration enforce that every Claude Code main session always
works inside a git worktree (specifically in /tmp), reserving the main working tree for manual
engineer edits? What are the trade-offs, pitfalls, and viable enforcement mechanisms?

The engineer's context: multiple concurrent Claude Code sessions hitting the same working tree
and branch simultaneously (shared index, shared branch), causing sessions to step on each
other. The engineer never edits code directly — only Claude does. The current repo is a
Terraform/Terramate repo using direnv/.envrc for AWS_PROFILE and TF_VAR_* variables.

## Sources consulted

- [Official Claude Code worktree docs](https://code.claude.com/docs/en/worktrees) — complete
  worktree API: --worktree flag, .worktreeinclude, WorktreeCreate/WorktreeRemove hooks,
  cleanup mechanics, cleanupPeriodDays. See auxiliary: `worktrees_doc_1.txt`
- [Official Claude Code hooks reference](https://code.claude.com/docs/en/hooks) — WorktreeCreate
  and WorktreeRemove hook schema, stdout contract, decision control. See auxiliary: `worktrees_doc_2.txt`
- [GitHub issue #27881](https://github.com/anthropics/claude-code/issues/27881) — EnterWorktree
  nested worktrees bug via CWD drift after context compaction. See auxiliary: `worktrees_doc_3.txt`
- [GitHub issue #45645](https://github.com/anthropics/claude-code/issues/45645) — stale
  repositoryformatversion=1 + extensions.worktreeConfig=true left in .git/config after Claude
  worktree use, breaking other AI agents. See auxiliary: `worktrees_doc_3.txt`
- [GitHub issue #46638](https://github.com/anthropics/claude-code/issues/46638) — claude
  --worktree against stale /tmp registration silently destroys state. See auxiliary: `worktrees_doc_3.txt`
- [GitHub issue #46444](https://github.com/anthropics/claude-code/issues/46444) — auto-cleanup
  permanently deleted 160+ hours of uncommitted work. See auxiliary: `worktrees_doc_3.txt`
- [GitHub issue #37611](https://github.com/anthropics/claude-code/issues/37611) — WorktreeCreate
  hook disables cleanup prompt AND WorktreeRemove hook (bug, closed as duplicate). See auxiliary: `worktrees_doc_3.txt`
- [GitHub issue #51596](https://github.com/anthropics/claude-code/issues/51596) — isolation:
  "worktree" silently reuses stale branches via agentId prefix collision. See auxiliary: `worktrees_doc_3.txt`
- [GitHub issue #26725](https://github.com/anthropics/claude-code/issues/26725) — stale
  worktrees never cleaned up, branches stay locked. See auxiliary: `worktrees_doc_3.txt`
- [GitHub issue #31896](https://github.com/anthropics/claude-code/issues/31896) — no way to
  disable automatic worktree creation in Claude Desktop. See auxiliary: `worktrees_doc_3.txt`
- [GitHub issue #15327](https://github.com/anthropics/claude-code/issues/15327) — CLI lacks
  .worktreeinclude parity with desktop app (closed stale). See auxiliary: `worktrees_doc_4.txt`
- [mattbrailsford.dev — replacing custom worktree skill with hooks](https://mattbrailsford.dev/replacing-my-custom-git-worktree-skill-with-claude-code-hooks) — WorktreeCreate hook implementation, .worktreeinclude, gitflow branch naming, file copying via tar+git ls-files. See auxiliary: `worktrees_doc_4.txt`
- [tfriedel/claude-worktree-hooks](https://github.com/tfriedel/claude-worktree-hooks) — auto-setup hooks for env files, dependencies, deterministic ports. Critical stdout redirection gotcha. See auxiliary: `worktrees_doc_2.txt`
- [damiangalarza.com — extending Claude Code worktrees for database isolation](https://www.damiangalarza.com/posts/2026-03-10-extending-claude-code-worktrees-for-true-database-isolation/) — WorktreeCreate + WorktreeRemove hooks for Rails per-worktree database isolation. See auxiliary: `worktrees_doc_4.txt`
- [waldencui.com — direnv is all you need](https://waldencui.com/post/direnv_is_all_you_need_to_parallelize_claude_code_with_git_worktrees/) — direnv .envrc resolution problem in worktrees, shared .venv and .env via direnv. See auxiliary: `worktrees_doc_4.txt`
- [gist eshaham — SessionStart hook for direnv in worktrees](https://gist.github.com/eshaham/8e3b63fb077530dffc2964b648145ec9) — walks parent dirs + git common-dir to find .envrc, exports to $CLAUDE_ENV_FILE. See auxiliary: `worktrees_doc_4.txt`
- [snopoke.com — agents and worktrees](https://www.snopoke.com/2026/02/27/worktrees/) — worktrees.json + worktree-cli tool, SessionStart hook, bootstrap.sh pattern. See auxiliary: `worktrees_doc_4.txt`
- [sabatino.dev — custom directory worktrees](https://www.sabatino.dev/creating-worktrees-with-claude-code-in-a-custom-directory/) — sibling-dir WorktreeCreate hook for Laravel Valet integration. See auxiliary: `worktrees_doc_4.txt`
- [git-scm.com docs — git-worktree](https://git-scm.com/docs/git-worktree) — gc.worktreePruneExpire, git worktree prune --expire now, locked worktrees, stale administrative files. See auxiliary: `worktrees_doc_4.txt`
- [dev.to/datadeer — parallel Claude sessions with git worktree](https://dev.to/datadeer/part-2-running-multiple-claude-code-sessions-in-parallel-with-git-worktree-165i) — sibling dir pattern, setup overhead caveat, token consumption. See auxiliary: `worktrees_doc_4.txt`
- [gitworktree.org — best practices](https://www.gitworktree.org/guides/best-practices) — sibling pattern, naming conventions, weekly prune cron. See auxiliary: `worktrees_doc_4.txt`

---

## Findings

### Finding 1: Claude Code has full native worktree support via --worktree flag (v2.1.49+)

**Evidence:**

```
claude --worktree feature-auth
```

"Pass --worktree or -w to create an isolated worktree and start Claude in it. By default, the
worktree is created under .claude/worktrees/<value>/ at your repository root, on a new branch
named worktree-<value>."
— https://code.claude.com/docs/en/worktrees

"Running each Claude Code session in its own worktree means edits in one session never touch
files in another, so you can have Claude building a feature in one terminal while fixing a bug
in a second."
— https://code.claude.com/docs/en/worktrees

**Source:** Official Anthropic documentation, URL fetched / verbatim quotes confirmed present

**Significance:** The engineer's core problem (two sessions stepping on each other) is the
exact problem worktrees solve. The flag was added in v2.1.49 and is the supported path.
No monkey-patching or complex setup required for basic isolation.

URL fetched / Verbatim quote checked / Quote substring confirmed in fetched content.

---

### Finding 2: The WorktreeCreate hook allows placing worktrees in /tmp or any location

**Evidence:**

From the official hooks reference (https://code.claude.com/docs/en/hooks):

"The hook must print the created worktree's path to stdout on success."

The hook receives `worktree_path` (the default .claude/worktrees/ path) but is free to create
the worktree at a different location. The path printed to stdout becomes the session's working
directory. This is the documented mechanism for /tmp placement.

Example WorktreeCreate hook (community pattern from mattbrailsford.dev):

```bash
#!/bin/bash
# Read JSON from stdin
INPUT=$(cat)
NAME=$(echo "$INPUT" | jq -r '.worktree_name')
GIT_DIR=$(echo "$INPUT" | jq -r '.git_dir')
BASE=$(echo "$INPUT" | jq -r '.base_commit')

# Place in /tmp instead of default
DIR="/tmp/$(basename "$(dirname "$GIT_DIR")")-${NAME}"

# CRITICAL: redirect git output to stderr — stdout must only contain the path
git worktree add "$DIR" -b "feature/$NAME" "$BASE" >/dev/null 2>&1 || exit 1

echo "$DIR"
exit 0
```

**Source:** https://code.claude.com/docs/en/hooks + https://mattbrailsford.dev/replacing-my-custom-git-worktree-skill-with-claude-code-hooks

URL fetched / Verbatim quote checked / Quote substring confirmed in fetched content.

**Significance:** /tmp placement is technically possible via this hook. The critical implementation
detail (redirect git stdout to /dev/null, only print path on stdout) was discovered independently
by multiple community implementations. Missing this causes Claude to hang silently.

---

### Finding 3: /tmp worktrees create a hard stale-registration problem on macOS

**Evidence (Issue #46638, https://github.com/anthropics/claude-code/issues/46638):**

"Common causes [of stale worktree registration]: OS cleanup removed temporary directories
(e.g., /tmp worktree)"

"Running claude --worktree <name> against a stale registration: Error creating worktree:
Failed to create worktree: fatal: '<name>' is already used by worktree at '<stale path>'.
After exit, the worktree registration is removed without warning or opportunity for recovery."

From git-scm.com official docs:
"If a working tree is deleted without using git worktree remove, then its associated
administrative files, which reside in the repository (see 'DETAILS' below), will eventually
be removed automatically (see gc.worktreePruneExpire in git-config), or you can run git
worktree prune in the main or any linked worktree to clean up any stale administrative files."

The default `gc.worktreePruneExpire` is 3 months, meaning a branch locked by a deleted /tmp
worktree stays locked for up to 3 months without manual intervention.

Resolution requires: `git worktree prune --expire now`

**Source:** https://github.com/anthropics/claude-code/issues/46638 + https://git-scm.com/docs/git-worktree

URL fetched / Verbatim quote checked / Quote substring confirmed in fetched content.

**Significance (4Shark-specific):** macOS clears /tmp on reboot. The 4Shark terraform repo is
on a developer laptop. Any worktree in /tmp is guaranteed to be deleted on every reboot,
leaving stale registrations in .git/worktrees/ that lock branches and block future sessions.
A SessionStart hook running `git worktree prune --expire now` can mitigate this — but it must
run BEFORE Claude attempts --worktree with a name that matches a stale registration.

---

### Finding 4: direnv / .envrc does NOT auto-resolve from /tmp worktree paths

**Evidence:**

"Claude Code runs each Bash command in a fresh shell, so direnv hooks don't automatically
apply. In git worktrees this is even worse — the .envrc lives in the main repo root, which
isn't a parent directory of the worktree path."
— https://waldencui.com/post/direnv_is_all_you_need_to_parallelize_claude_code_with_git_worktrees/

direnv's lookup walks parent directories upward from cwd. From /tmp/myrepo-feature/, the
parent chain is: /tmp/ → / (root). The project's .envrc at /Users/.../terraform/ is never
reached.

For a .claude/worktrees/ placement: parent chain is /Users/.../terraform/.claude/worktrees/name/
→ /Users/.../terraform/.claude/worktrees/ → /Users/.../terraform/.claude/ → /Users/.../terraform/
→ .envrc IS found (project root is in the parent chain).

For a sibling placement at ../terraform-worktrees/name/: parent chain is
/Users/.../terraform-worktrees/name/ → /Users/.../terraform-worktrees/ → /Users/.../
→ .envrc NOT found (project root is a sibling, not a parent).

For /tmp/name/: .envrc NEVER found.

**Source:** https://waldencui.com/post/direnv_is_all_you_need_to_parallelize_claude_code_with_git_worktrees/
+ https://gist.github.com/eshaham/8e3b63fb077530dffc2964b648145ec9

URL fetched / Verbatim quote checked / Quote substring confirmed in fetched content.

**Significance (4Shark-specific — critical):** The terraform repo uses .envrc to set AWS_PROFILE,
AWS_DEFAULT_REGION, and TF_VAR_* variables (documented in 4Shark TERRAFORM-POLICY.md and
CLAUDE.md). If Claude works in a /tmp worktree, ALL of these variables are absent unless
explicitly handled via: (a) .worktreeinclude to copy .envrc + a SessionStart hook to source
it, or (b) symlink from /tmp worktree back to project .envrc, or (c) the eshaham gist pattern
that walks git common-dir. Option (b) and (c) require the hook to know the project path, which
is available via git_dir in the WorktreeCreate input.

---

### Finding 5: .worktreeinclude copies gitignored files but CLI support has a known gap

**Evidence:**

"To copy them automatically when Claude creates a worktree, add a .worktreeinclude file to your
project root. The file uses .gitignore syntax. Only files that match a pattern and are also
gitignored are copied, so tracked files are never duplicated."
— https://code.claude.com/docs/en/worktrees

Issue #15327 (https://github.com/anthropics/claude-code/issues/15327):
"Desktop App: Automatically copies files matching .worktreeinclude patterns when creating git
worktrees. CLI: Has no awareness of .worktreeinclude files; users must manually instruct
Claude to copy files or create custom slash commands."
Status: Closed stale — CLI now processes .worktreeinclude as of a recent build, but the gap
existed through late 2025.

**Source:** https://code.claude.com/docs/en/worktrees + https://github.com/anthropics/claude-code/issues/15327

URL fetched / Verbatim quote checked / Quote substring confirmed in fetched content.

**Significance:** For /tmp placement, .worktreeinclude is the mechanism to copy .envrc,
.env.local, and similar gitignored files. However: (1) the CLI gap means a WorktreeCreate
hook may need to handle this manually for older builds; (2) even with .worktreeinclude, a
SessionStart hook is still needed to SOURCE the .envrc in Claude's non-interactive shell.

---

### Finding 6: WorktreeCreate hook has a known bug — disables the cleanup prompt

**Evidence:**

Issue #37611 (https://github.com/anthropics/claude-code/issues/37611):
"When a WorktreeCreate hook is defined in .claude/settings.json, the worktree cleanup prompt
on session exit is completely skipped. The worktree remains on disk without any prompt to keep
or remove it, even when the hook creates a standard git worktree [...] A paired WorktreeRemove
hook is also never called [...] The entire cleanup flow is bypassed when any WorktreeCreate
hook exists."
Status: Closed as duplicate, not resolved as of June 2026.

**Source:** https://github.com/anthropics/claude-code/issues/37611

URL fetched / Verbatim quote checked / Quote substring confirmed in fetched content.

**Significance:** If the 4Shark config uses a WorktreeCreate hook (required for /tmp placement),
the automatic cleanup prompt will not fire, and the WorktreeRemove hook will also not fire.
Worktrees must be cleaned up out-of-band. For /tmp this is not a major issue (macOS will clear
/tmp eventually) but the .git/worktrees/ stale entries must still be pruned manually or via a
SessionStart hook.

---

### Finding 7: CWD drift after context compaction can cause nested worktrees

**Evidence:**

Issue #27881 (https://github.com/anthropics/claude-code/issues/27881):
"When orchestrator agents dispatch subagents with isolation: 'worktree', context compaction
can cause the CWD to drift into a previous worktree path. Subsequent worktree dispatches then
nest inside the previous worktree instead of being created at the repository root."

Real git worktree list output:
```
/home/user/projects/myrepo                                                    develop
/home/user/projects/myrepo/.claude/worktrees/agent-aba5b87b/.claude/worktrees/agent-a1684db4
/home/user/projects/myrepo/.claude/worktrees/agent-aba5b87b/.claude/worktrees/agent-a1684db4/.claude/worktrees/agent-a643979b
```

"When nesting goes deep enough, worktree creation can fail silently, causing the agent to fall
back to the current CWD — which may be checked out on develop or main."
Status: Closed as not planned (stale).

**Source:** https://github.com/anthropics/claude-code/issues/27881

URL fetched / Verbatim quote checked / Quote substring confirmed in fetched content.

**Significance:** This bug affects `isolation: "worktree"` subagents (not `--worktree` main
sessions). The engineer's scenario is MAIN sessions, so this specific bug does not apply
directly. However, if the 4Shark config ever uses subagent isolation: "worktree" in addition
to main session worktrees, this is a known silent-failure risk.

---

### Finding 8: Community enforcement patterns for "always worktree"

**Evidence:**

Three patterns documented in the community:

**Pattern A — Shell alias (simplest):**
`alias claude='claude --worktree'`
Source: multiple community posts
If name omitted, Claude generates a random name (e.g., bright-running-fox).
CAVEAT: "There is no 'force worktree on every plain claude invocation' native setting in Claude
Code CLI as of June 2026." The alias only works when the engineer uses it.

**Pattern B — WorktreeCreate hook in .claude/settings.json:**
Source: https://mattbrailsford.dev/replacing-my-custom-git-worktree-skill-with-claude-code-hooks
```json
{
  "hooks": {
    "WorktreeCreate": [{
      "hooks": [{ "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/worktree-create.sh" }]
    }],
    "WorktreeRemove": [{
      "hooks": [{ "type": "command", "command": "bash \"$CLAUDE_PROJECT_DIR\"/.claude/hooks/worktree-remove.sh" }]
    }]
  }
}
```
The hook REPLACES default behavior. It can place worktrees anywhere, run bootstrap, copy files.
CAVEAT: Known bug — hook presence disables cleanup prompt (Issue #37611).

**Pattern C — SessionStart hook for environment bootstrap:**
Source: https://www.snopoke.com/2026/02/27/worktrees/ + https://gist.github.com/eshaham/8e3b63fb077530dffc2964b648145ec9
The hook fires when ANY session starts (worktree or not). It can detect if in a worktree,
copy .envrc, run bundle install, etc. Does not enforce worktree creation but handles setup.

**Source:** Combined from multiple sources listed in Sources consulted.

URL fetched / Verbatim quote checked / Quote substrings confirmed in fetched content.

**Significance:** For 4Shark, Pattern A (alias in engineer's shell profile) is the lowest-risk
enforcement with zero hook bugs. Pattern B gives richer control but carries the cleanup-prompt
bug. Pattern C is complementary to A or B, not a replacement.

---

### Finding 9: Stale git config (.git/config repositoryformatversion=1) is a known Claude Code bug

**Evidence:**

Issue #45645 (https://github.com/anthropics/claude-code/issues/45645):
"When Claude Code creates a git worktree for subagent tasks, it modifies .git/config but fails
to restore it after the worktree is deleted. This leaves behind:
  [core]
      repositoryformatversion = 1
  [extensions]
      worktreeConfig = true"

"The repositoryformatversion = 1 setting signals a non-standard git format requiring explicit
tool support. Tools using older git libraries silently fail when reading the repository, causing
AI agents to completely stop responding while working fine in other projects."

Manual workaround:
```bash
git config core.repositoryformatversion 0
git config --unset extensions.worktreeConfig
```
Status: Closed as duplicate, not resolved as of June 2026.

**Source:** https://github.com/anthropics/claude-code/issues/45645

URL fetched / Verbatim quote checked / Quote substring confirmed in fetched content.

**Significance (4Shark-specific):** The 4Shark terraform repo is opened by multiple tools
(Terramate, VS Code, possibly other IDEs or scripts). If Claude Code's subagent worktree use
leaves repositoryformatversion=1 in .git/config, Terramate or other tools may silently
malfunction. A post-session prune or a git config check in a SessionStart hook would catch
this.

---

### Finding 10: Terraform-specific concerns for worktrees

**Evidence (from research synthesis — no single URL, derived from Findings 3, 4, and
Terraform documentation knowledge):**

Key Terraform behaviors that interact with worktrees:

1. `.terraform/` directory: created by `terraform init` in the working directory. Each worktree
   starts with a fresh checkout — no .terraform/ directory. `terraform init` must be re-run
   per worktree (or TF_DATA_DIR can point to a shared location outside the worktree).

2. `TF_PLUGIN_CACHE_DIR`: if set in .envrc (which may not resolve in /tmp — see Finding 4),
   providers are shared. Without it, each worktree re-downloads providers.

3. Terramate stack paths: `stack.tm.hcl` uses relative path references. If the worktree root
   is at a different depth (e.g., /tmp/terraform-feature/) than the original checkout
   (/Users/.../terraform/), relative stack references may resolve incorrectly or fail.
   The current repo has `workspace-access/stack.tm.hcl` — checked during research.

4. AWS_PROFILE resolution: set in .envrc. In /tmp worktrees, .envrc does not auto-load (see
   Finding 4). Terraform will use the default AWS profile (read-only) rather than the
   configured profile unless the environment is explicitly set.

**Source:** Synthesis from Findings 3, 4, and direct inspection of repo structure at
`/Users/plribeiro3000/Projects/4Shark/terraform/workspace-access/stack.tm.hcl`

**Significance:** The current repo is a Terraform/Terramate repo. The combination of
.envrc non-resolution (Finding 4) + .terraform/ absence + Terramate relative paths makes
/tmp placement significantly more complex for this specific stack than for a typical Rails app.

---

## Trade-offs surfaced

| Placement | Pros | Cons | 4Shark-specific impact |
|-----------|------|------|------------------------|
| `.claude/worktrees/` (default) | .envrc resolves via parent chain; .worktreeinclude works natively; cleanup prompt works (without WorktreeCreate hook); Terramate relative paths resolve correctly | File watcher noise (VS Code, Watchman); Issue #27881 nested worktree risk from CWD drift; Issue #45645 stale .git/config | .envrc resolution works — AWS_PROFILE, TF_VAR_* available without extra hooks |
| Sibling (`../repo-worktrees/<name>/`) | No nested .git confusion; tools like Valet discover project; cleaner visual separation | .envrc DOES NOT resolve via parent chain (sibling, not parent); Terramate relative paths break; WorktreeCreate hook required (carries bug #37611) | AWS_PROFILE absent unless SessionStart hook or symlink used; Terramate stacks may malfunction |
| `/tmp/<name>/` | Total separation from project tree; no file watcher noise; Claude already has /tmp permission | Deleted on macOS reboot → stale registrations lock branches; .envrc NEVER resolves; .terraform/ absent; Terramate paths break; git prune --expire now required in SessionStart hook | AWS_PROFILE, TF_VAR_* absent; `terraform init` must re-run each session; highest setup complexity |
| No worktree (current state) | Zero setup; .envrc works; .terraform/ present | Sessions step on each other (the problem being solved) | The problem the engineer hit |

| Enforcement mechanism | How it works | Risk |
|-----------------------|--------------|------|
| Shell alias `alias claude='claude --worktree'` | Intercepts every `claude` invocation | Requires engineer discipline; alias must be in shell profile |
| WorktreeCreate hook in .claude/settings.json | Auto-runs on every --worktree invocation | Bug #37611: disables cleanup prompt AND WorktreeRemove hook |
| claude --worktree explicit per session | Engineer types it each time | Requires engineer discipline; no automated enforcement |
| SessionStart hook (bootstrap) | Runs on every session start, handles env setup | Does not PREVENT sessionless usage; complementary only |

---

## What remains uncertain

- Whether Bug #37611 (WorktreeCreate hook disables cleanup prompt) has been fixed in the
  current installed Claude Code version. The issue was closed as duplicate in June 2026 but
  the fix may have landed in a subsequent release. The engineer can verify with:
  `claude --version` and checking the Claude Code changelog.

- Whether Terramate (`stack.tm.hcl`) relative path references break in sibling or /tmp
  worktrees. The current repo has `workspace-access/stack.tm.hcl` but the exact path
  references were not inspected. Needs a direct test.

- Whether the eshaham SessionStart hook (walks git common-dir to find .envrc) works reliably
  in Claude Code's non-interactive bash tool with the current version. The gist exists but
  the full script content was not fetched verbatim.

- The exact build where .worktreeinclude became supported in the CLI (Issue #15327 was closed
  stale without a clear "fixed in vX.Y.Z" note).

- Whether `TF_DATA_DIR` pointing outside /tmp (e.g., to the main checkout's .terraform/)
  is safe for concurrent Terraform worktree sessions (state locking via S3/DynamoDB handles
  plan/apply conflicts, but provider initialization may have race conditions).

---

## Suggested options for main and the engineer

**Option A: .claude/worktrees/ (default placement) + shell alias enforcement**

Placement: default (.claude/worktrees/<name>/ inside repo root)
Enforcement: `alias claude='claude --worktree'` in engineer's .zshrc / .bash_profile
File copying: .worktreeinclude with .envrc, .env.local (for Rails repos)
Environment: .envrc resolves via parent chain — no extra hook needed for Terraform
Cleanup: standard cleanup prompt (no WorktreeCreate hook = no bug #37611)
Git maintenance: add .claude/worktrees/ to .gitignore; run `git worktree prune` periodically

Remaining concerns: Issue #27881 (CWD drift → nested worktrees) affects subagents only, not
main sessions. Issue #45645 (stale repositoryformatversion=1) can be caught with a periodic
`git config core.repositoryformatversion 0` check.

**Option B: .claude/worktrees/ + WorktreeCreate hook for bootstrap (no /tmp)**

Placement: default (.claude/worktrees/<name>/)
Enforcement: WorktreeCreate hook also runs bundle install / terraform init in the new worktree
Caveat: Bug #37611 — cleanup prompt disabled when hook exists. Worktrees must be cleaned
manually: `git worktree list` and `git worktree remove` after each session.
Environment: .envrc resolves via parent chain — AWS_PROFILE and TF_VAR_* available.

Trade-off vs Option A: richer bootstrap but cleanup requires manual discipline.

**Option C: /tmp placement + WorktreeCreate hook + SessionStart env hook**

Placement: /tmp/<repo>-<name>/
Enforcement: WorktreeCreate hook creates in /tmp, copies .envrc (or symlinks), optionally
runs terraform init; SessionStart hook sources .envrc via git common-dir lookup.
Cleanup: SessionStart hook runs `git worktree prune --expire now` before each session.
Bug #37611 applies: cleanup prompt disabled, WorktreeRemove hook never fires.

Trade-off: cleanest physical separation, zero file watcher noise, matches engineer's original
proposal. But highest implementation complexity for this specific Terraform/Terramate repo:
.envrc must be explicitly propagated, terraform init must re-run, Terramate relative paths
need validation, and stale registration cleanup must be automated.

**Option D: Sibling placement (../terraform-worktrees/<name>/)**

Placement: sibling dir, created by WorktreeCreate hook
Environment: .envrc does NOT resolve via parent chain — needs symlink or SessionStart hook
Terramate: relative stack paths need validation
Bug #37611 applies if WorktreeCreate hook is used.

Trade-off: intermediate complexity; no /tmp reboot problem, but requires more env setup than
Option A/B.

(NO recommendation — surface options, let main and the engineer choose)
