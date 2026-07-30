# SPIKE — macOS Bash Version, the sh Premise, and Whether 4Shark Scripts Should Move Off bash 3.2

## Investigation question

The engineer (macOS, latest OS, interactive shell = zsh) keeps hitting bash 3.2
limitations when this session writes hook/wrapper scripts under
`~/.claude/scripts/`. Three questions:

1. Why is macOS bash so old — an Apple decision, or is bash simply unused now?
2. Should 4Shark switch its scripts to zsh, which is current on macOS, to stop
   paying the bash-3.2 tax?
3. Verify or correct the premise "maybe we should use `/bin/sh` instead of
   `bash`" — the engineer's working assumption was that `/bin/sh` on macOS is
   bash itself running in POSIX mode, so switching to it would be strictly
   fewer features, not more.

## Sources consulted

- `bash --version`, `/bin/sh --version`, `/opt/homebrew/bin/bash --version`,
  `zsh --version` on the engineer's machine — direct version evidence, see
  `macos-shell-version_data_1.txt`.
- `strings /bin/sh` + `stat` on `/private/var/select/sh` — direct binary
  inspection revealing `/bin/sh` is a dispatcher, not bash itself. See
  `macos-shell-version_log_2.txt`.
- A reproducer script executed under both bash 3.2.57 and bash 5.3.9 —
  see `macos-shell-version_reproducer_1.sh` and `macos-shell-version_log_1.txt`.
- [scriptingosx.com — About bash, zsh, sh, and dash in macOS Catalina and
  beyond](https://scriptingosx.com/2020/06/about-bash-zsh-sh-and-dash-in-macos-catalina-and-beyond/)
  — the `/var/select/sh` selector mechanism, documented since Catalina.
- [Wikipedia — Bash (Unix shell)](https://en.wikipedia.org/wiki/Bash_(Unix_shell))
  — bash license-per-version table.
- [The Register — Dissed Bash boshed: Apple makes fancy zsh default in
  forthcoming macOS 'Catalina' 10.15](https://www.theregister.com/2019/06/04/apple_zsh_macos_catalina_default/)
  — Apple's own quoted statement on zsh/bash compatibility, plus the
  publication's own (not Apple's) licensing inference.
- itnext.io / Medium — "Upgrading Bash on macOS" — a community explanation of
  the GPLv3 licensing story, explicitly self-labeled as inference, not an
  Apple statement.
- [GitHub rstudio/rstudio#6182](https://github.com/rstudio/rstudio/issues/6182)
  — the exact text of macOS's own bash-deprecation warning message and the
  `BASH_SILENCE_DEPRECATION_WARNING` variable.
- [GitHub Actions — Workflow syntax, `shell:` defaults](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions)
  — bash is the documented default shell for `run:` steps on Linux/macOS
  runners.
- [Debian Policy Manual §10.4 — Scripts](https://www.debian.org/doc/debian-policy/ch-files.html)
  — `/bin/sh` on Debian/Ubuntu is POSIX-only by policy, and bash is called out
  as an `Essential` package.
- [zsh FAQ — 2.1: Differences from sh and ksh](https://zsh.sourceforge.io/FAQ/zshfaq02.html)
  — zsh's own documentation stating it is not bash-script-compatible.
- [zsh.sourceforge.io/News/](https://zsh.sourceforge.io/News/) — current
  upstream zsh release (5.9.2, 2026-07-12).
- `~/.claude/scripts/validate-bash-command.sh:249` and CLAUDE.md § Command
  Safety Policy (the live, injected copy of this repo's own rules) — the
  actual reason `$(...)` needs rewriting in 4Shark hook scripts, independent
  of bash version.
- See auxiliary: `macos-shell-version_data_1.txt` — the full machine-state
  inventory (versions, PATH, script/shebang counts, settings.json wiring,
  scheduler installers) that backs Findings 4 and 6.

## Findings

### Finding 1: The GPLv3 story is a widely-repeated, well-corroborated community inference — not a sourced Apple statement

**Evidence:** Bash's own license history: v.1.11–3.2 are GPL-2.0-or-later,
v.4.0+ are GPL-3.0-or-later (per Wikipedia's bash article, license-per-version
table). Bash 3.2.57 is exactly the version installed on the engineer's
machine (`bash --version` → `GNU bash, version 3.2.57(1)-release
(arm64-apple-darwin25) / Copyright (C) 2007`), matching the last GPLv2
release.

The Register, reporting on Apple's June 2019 WWDC zsh announcement, frames
the causal story as its own analysis, not a quoted Apple admission: *"For
approximately a decade, Apple avoided updating bash due to the iGiant's
distaste for the GPLv3 license attached to the command interpreter"* and
notes Apple *"has been reducing its use of GPL-covered code for years"*
(citing the Samba and GCC precedents). The itnext.io piece on the same topic
is even more explicit about the inference boundary: *"Since version 4.0
(successor of 3.2), Bash uses the GNU General Public License v3 (GPLv3),
which Apple does not (want to) support"* and *"Version 3.2 of GNU Bash is the
last version with GPLv2, which Apple accepts, and so it sticks with it"* —
both framed by the author as their own explanation, sourced to community
discussion (Reddit, forums), not to any Apple statement.

**Source:** [Wikipedia — Bash (Unix shell)](https://en.wikipedia.org/wiki/Bash_(Unix_shell));
[The Register, 2019-06-04](https://www.theregister.com/2019/06/04/apple_zsh_macos_catalina_default/);
itnext.io "Upgrading Bash on macOS"; `bash --version` output,
`macos-shell-version_data_1.txt`.

**Significance:** Not found: an Apple-authored statement giving a licensing
reason for staying on bash 3.2. The GPLv3 explanation is consistent across
every independent source consulted and lines up exactly with bash's own
license-version boundary, so it is a well-corroborated inference — but every
source that states it frames it as inference or community understanding, not
as something Apple itself said. Apple's own quoted words (via the same
Register piece) address only the zsh-compatibility side: *"zsh is highly
compatible with the Bourne shell (sh) and mostly compatible with bash, with
some differences."*

### Finding 2: Bash is functionally frozen on macOS, and Apple's own tooling calls it "deprecated" (as an interactive default) — but the binary still ships

**Evidence:** macOS 26.5.2 (this machine, current as of this spike) still
ships `/bin/bash` at version 3.2.57 — nineteen years after that release
(`Copyright (C) 2007`). Apple's own interactive-shell warning, printed by
Terminal when bash is used as the login shell, reads verbatim: *"The default
interactive shell is now zsh. To update your account to use zsh, please run
`chsh -s /bin/zsh`. For more details, please visit
https://support.apple.com/kb/HT208050."* Apple ships a documented escape
hatch that names the state explicitly: setting `BASH_SILENCE_DEPRECATION_WARNING=1`
suppresses that warning.

**Source:** [GitHub rstudio/rstudio#6182](https://github.com/rstudio/rstudio/issues/6182);
`sw_vers` / `bash --version` output, `macos-shell-version_data_1.txt`.

**Significance:** "Frozen" and "deprecated" are two different claims. The
*interactive default* is deprecated by Apple's own naming (the env var is
literally called `BASH_SILENCE_DEPRECATION_WARNING`) and has been since
Catalina (2019). The *binary* is not removed and is not versioned forward —
it still ships, unchanged, as of the current OS release. Not found: any Apple
statement that bash *scripting* (as opposed to bash as a login shell) is
deprecated or scheduled for removal.

### Finding 3: "Nobody uses bash anymore" is true for interactive shells and false for scripting/CI

**Evidence:** GitHub Actions' own documentation states plainly that on
non-Windows runners, a `run:` step with no `shell:` specified runs as
*"The default shell on non-Windows platforms... If `bash` is not found in the
path, this is treated as `sh`"*, executed as `bash -e {0}` (or
`bash --noprofile --norc -eo pipefail {0}` when `shell: bash` is explicit).
Separately, the Debian Policy Manual makes bash's presence a guarantee, not a
convenience: a script needing non-POSIX features must declare `#!/bin/bash`
*"and the package must depend on the package providing the shell (unless the
shell package is marked 'Essential', as in the case of `bash`)"* — bash is
literally exempted from needing a declared dependency because Debian
guarantees it is always present.

**Source:** [GitHub Actions workflow syntax docs](https://docs.github.com/en/actions/using-workflows/workflow-syntax-for-github-actions);
[Debian Policy Manual §10.4](https://www.debian.org/doc/debian-policy/ch-files.html).

**Significance:** The macOS *interactive* shell default moved to zsh in 2019
(Finding 2). That is a genuinely different question from what *scripting*
environments assume as their default interpreter — CI (GitHub Actions) and
Debian/Ubuntu (the WSL2 target CLAUDE.md documents for other 4Shark
engineers) both treat bash as the guaranteed, always-present scripting shell.

### Finding 4: zsh is current and Apple-default on macOS, but is NOT guaranteed present on 4Shark's other target platform (WSL2/Debian/Ubuntu)

**Evidence:** This machine's zsh is `5.9 (arm64-apple-darwin25.0)`. Current
upstream zsh, per the project's own release feed, is `5.9.2`, released
`2026-07-12` — a gap of roughly one year and two minor releases, not the
19-year gap between bash 3.2 (2007) and bash 5.3 (2025). On the other side,
zsh is *not* installed by default on Ubuntu/Debian and is not an `Essential`
package the way bash is (Finding 3's Debian Policy quote); a fresh Debian
minbase Docker image only guarantees bash and dash, per Docker Hub's own
description of the official debian image build: *"they're built from [the
'minbase' variant], which only installs 'required' packages."* zsh must be
`apt install`ed explicitly on Debian/Ubuntu/WSL2 and on minimal Docker base
images.

**Source:** [zsh.sourceforge.io/News/](https://zsh.sourceforge.io/News/);
[Debian Policy Manual §10.4](https://www.debian.org/doc/debian-policy/ch-files.html);
[Docker Hub — debian official image](https://hub.docker.com/_/debian);
`zsh --version` output, `macos-shell-version_data_1.txt`.

**Significance:** CLAUDE.md documents 4Shark engineers on both macOS and
WSL2/Linux (the plans-autocommit and config-self-heal installers have
launchd / systemd / Task Scheduler branches specifically because of this —
see Finding 6). zsh being current and default on macOS does not transfer to
the WSL2/Linux side of that split: there, zsh is an opt-in install, not a
guarantee, while bash is guaranteed.

### Finding 5: The reported heredoc failure is very likely NOT a bash-3.2 language limitation — it reproduces identically on bash 5.3

**Evidence:** Three plausible reproductions of "heredoc inside `$( )` with
multiple occurrences" were written and executed under both the system bash
3.2.57 and Homebrew bash 5.3.9 on this machine: (A) two independent
`$(...)` command substitutions, each containing its own heredoc; (B) two
heredocs sequential inside one single `$(...)` group; (C) a function
containing a heredoc, invoked twice via `$(...)`. All three produced
byte-identical, correct output under both bash versions — see
`macos-shell-version_log_1.txt` for the full transcript.

Independently, this repository's own `validate-bash-command.sh` states the
actual, documented reason a `$(...)`-shaped command needs rewriting in a
4Shark session, and it has nothing to do with bash version: *"`$(...)`
command substitution already requires manual approval in Claude Code
regardless of any allow-list rule (an independent security layer — see
~/.claude/docs/RUBY-COMMAND-EXECUTION.md)"* (`validate-bash-command.sh:249`).
The live CLAUDE.md § Command Safety Policy states the same constraint from
the auto-approve side: the read-only-compound auto-approver and its blocking
counterpart *"Both refuse on `$(...)`/backticks (command substitution is an
independent security layer)"*.

**Source:** `macos-shell-version_reproducer_1.sh` +
`macos-shell-version_log_1.txt` (direct empirical test, this machine);
`~/.claude/scripts/validate-bash-command.sh:249`; CLAUDE.md § Command Safety
Policy (as injected into this session).

**Significance:** If the specific failure the engineer hit was one of these
three shapes (or a close variant), the rewrite to `read -r -d ''` likely
fixed a permission-matcher/approval-gate problem, not a shell-parser problem
— `$(...)` triggers Claude Code's own mandatory-approval path independent of
which bash executes the command. Not found: the exact original command that
failed, so this finding cannot rule out that a *different*, not-yet-tested
bash-3.2-specific construct was also involved — only that the specific
heredoc-in-`$()` shape named in the question is not one of them, on this
machine, for the three shapes tested.

### Finding 6: Migrating scripts off bash touches more than the script bodies — shebangs, 33 allow-list entries, and three scheduler-installer code paths

**Evidence:** `~/.claude/scripts/` and `~/.claude/skills/*/scripts/` contain
89 `.sh` files: 58 use `#!/bin/bash`, 31 use `#!/usr/bin/env bash`; zero use
`#!/bin/sh` or a zsh shebang. `~/.claude/settings.json` wires 66 hook
`"command"` entries, none of which prefix the script path with a literal
`bash` verb — the harness invokes the path directly, relying on the
shebang + executable bit (sample in `macos-shell-version_data_1.txt`).
Separately, 33 `permissions.allow` entries are of the shape
`Bash(bash ~/.claude/scripts/<name>.sh:*)` — because 4Shark's documented
Command Safety Policy explains the permission matcher does a plain
string-prefix match against the literal command text, every one of these
entries is tied to the literal verb `bash`. Finally, both
`setup-plans-autocommit.sh` and `setup-config-self-heal.sh` hardcode the
interpreter across all three scheduler mechanisms they generate: `/bin/bash`
in the macOS launchd plist, `/bin/bash` in the Linux systemd unit, and a
literal `bash -lc '...'` in the WSL2 Task Scheduler branch.

**Source:** `macos-shell-version_data_1.txt` (full inventory, all commands
reproducible); `~/.claude/scripts/setup-plans-autocommit.sh`,
`~/.claude/scripts/setup-config-self-heal.sh` (grep output included in the
aux file).

**Significance:** A shell migration is not shebang-only. The `settings.json`
hook wiring would follow the shebang automatically (no `"command"` edits
needed), but the 33 `Bash(bash ...)` permission-allow entries and the two
scheduler installers' hardcoded `/bin/bash` / `bash -lc` strings would all
need a coordinated edit or the affected invocations would silently fall back
to manual approval prompts (for the allow-list) or fail outright (for a
scheduler unit invoking a script whose shebang no longer matches `bash`,
depending on whether `/bin/bash <script>` or a bare `<script>` execution is
used at each of those three call sites).

### Finding 7: zsh is not a drop-in bash replacement — the incompatibilities are documented by the zsh project itself

**Evidence:** zsh's own FAQ states unambiguously: *"bash and zsh are
different programming languages. They are not interchangeable; programs
written for either of these languages will, in general, not run under the
other."* and *"Don't run bash scripts under zsh. If the scripts were written
for bash, run them in bash."* Concretely, the same FAQ documents array
indexing starting at 1 rather than 0 (*"subscripts start at 1, not 0;
`array[0]` refers to `array[1]`"*) and default word-splitting behavior that
diverges from bash (*"The classic difference is word splitting... this
catches out very many beginning zsh users"*).

**Source:** [zsh FAQ 2.1](https://zsh.sourceforge.io/FAQ/zshfaq02.html).

**Significance:** Switching the 89 scripts' shebangs to zsh would not be a
version bump — every array index, every unquoted-expansion word-splitting
assumption, and any other bash-specific idiom in those 89 files would need
per-file review, not just a shebang line change.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| (a) Stay on bash-3.2-compatible code | Zero migration cost; bash is guaranteed present on every documented 4Shark platform (macOS ships it, Debian/Ubuntu/WSL2 marks it `Essential` — Finding 3) | Recurring rewrite tax on any genuinely bash-4/5-only construct; Finding 5 shows at least one instance of this "tax" was likely a misdiagnosis, not a real language gap | Findings 3, 5, 6 |
| (b) Require a modern bash (Homebrew 5.3.9 + explicit version guard) | Unlocks bash4/5 features when a real gap exists; Homebrew bash is already installed on this machine | On THIS machine, `#!/usr/bin/env bash` still resolves to the OLD system bash 3.2.57 because `/bin` precedes `/opt/homebrew/bin` in `$PATH` — an `env bash` shebang alone would silently keep picking up 3.2.57; would need either a hardcoded `/opt/homebrew/bin/bash` path (breaks on WSL2/Linux, where Homebrew is not standard) or a runtime version check with a loud failure; not verified whether other engineers' machines even have Homebrew bash installed | `macos-shell-version_data_1.txt` (this machine only) |
| (c) Switch scripts to zsh | zsh is current upstream (5.9 vs 5.9.2) and is Apple's own interactive default on macOS | Not installed by default on Debian/Ubuntu/minimal Docker images, unlike bash which is `Essential` (Finding 4); documented incompatibilities in array indexing and word splitting mean this is a per-file rewrite, not a shebang swap (Finding 7); touches 89 script shebangs, 33 `permissions.allow` entries, and 2 scheduler installers across 3 platforms (Finding 6) | Findings 4, 6, 7 |
| (d) Write non-trivial scripts in Ruby instead of shell | 4Shark is a Ruby shop; CLAUDE.md documents `ruby.sh`, RVM, four Rails backends; RVM-managed ruby on this machine is a current 4.0.2 | A hook must run fast with no Gemfile/version-manager dependency, so this only works with a system/managed Ruby and zero gems; this machine's Apple system Ruby (`/usr/bin/ruby`) is 2.6.10 (2022, itself old and unmaintained by Apple) — which Ruby a hook would actually invoke is undecided; not evaluated for WSL2/Linux Ruby availability | `macos-shell-version_data_1.txt` |

## What remains uncertain

- Whether other 4Shark engineers' machines have Homebrew bash installed, and
  where `/opt/homebrew/bin` sits relative to `/bin` in their `$PATH` — this
  spike only measured one machine.
- Whether the specific WSL2 Linux distribution 4Shark engineers use ships zsh
  by default — the Debian/Ubuntu-general finding (zsh not default) was
  verified against Debian Policy and Docker Hub, not against a specific WSL2
  distro image.
- Whether Apple has ever stated the GPLv3-avoidance motive anywhere in an
  official capacity — every source found frames it as inference; a direct
  Apple statement was searched for and not found.
- Whether any of the ~9 candidate bash-4/5-only features (associative
  arrays, `mapfile`/`readarray`, `${var^^}`/`${var,,}`, `globstar`, `&>>`,
  `|&`, negative array indices, `${!prefix@}`, `wait -n`, `coproc`) are
  actually used or worked around anywhere across the 89 existing scripts —
  not enumerated file-by-file within this spike's scope; only the reported
  heredoc case was reproduced and tested.
- The exact original command that triggered the "heredoc inside `$( )` with
  multiple occurrences" rewrite — not available for direct replay, so
  Finding 5's conclusion is based on the three most plausible reproductions
  of that description, not the literal failing command.

## Suggested options for main and the engineer

- Option A: Keep bash 3.2 as the compatibility floor for `~/.claude/scripts/`
  and `~/.claude/skills/*/scripts/`, and when a future rewrite is proposed,
  first check whether the actual blocker is a `$(...)`/backtick approval-gate
  issue (Finding 5) rather than a genuine bash-3.2 language gap, before
  reaching for a simpler-but-different construct.
- Option B: Adopt Homebrew bash as a documented, version-guarded requirement
  for `~/.claude/scripts/` specifically (not for WSL2/Linux targets, where
  bash 5.x may already be the system default) — this needs verifying across
  more than the one machine measured here, and an explicit absolute path or
  version check rather than bare `env bash`.
- Option C: Migrate to zsh — viable only with a deliberate per-file audit
  against Finding 7's documented incompatibilities, a plan for the 33
  `permissions.allow` entries and 2 scheduler installers (Finding 6), and an
  answer for the WSL2/Linux zsh-availability gap (Finding 4) — e.g.,
  bundling a zsh install step into the WSL2 setup docs, or keeping bash for
  the Linux/WSL2 branch and zsh for macOS as a split standard.
- Option D: Move non-trivial script logic to Ruby, keeping only thin bash
  entry points for hook wiring — contingent on deciding which Ruby a hook
  invokes (system Ruby vs. a pinned Homebrew/rbenv Ruby) and confirming
  startup latency is acceptable for a `PreToolUse` hook that must return
  quickly on every tool call.

(No recommendation — the four options and their trade-offs are laid out
above; the engineer decides.)
