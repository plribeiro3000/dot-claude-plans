#!/bin/bash
# ILLUSTRATIVE SKETCH ONLY — produced by the `spike` agent as research output.
# NOT wired into settings.json, NOT installed under ~/.claude/scripts/.
# Implementing this for real is a separate dot-claude config-change PR
# (per CLAUDE.md § Configuration Changes Policy) — a design decision the
# engineer makes, not something the spike agent may write into ~/.claude/.
#
# Working name: validate-commit-message.sh
# Proposed wiring (for the engineer's future PR):
#   settings.json -> hooks.PreToolUse -> matcher "Bash"
#   Same tier as validate-bash-command.sh (see file:line citations in SPIKE.md);
#   could live as a new block INSIDE validate-bash-command.sh's Bash case, or
#   as a standalone script following the inject-pr-commit-data-policy.sh /
#   inject-commit-policy-reminder.sh self-filtering pattern (command-text
#   inspection, not the `if:` matcher — see SPIKE.md Finding 5 for why).
#
# Goal: block (exit 2) a `git commit` invocation whose message does not match
#   ^<type>(<scope>): <subject>
# with the scope REQUIRED — closing the gap left by the Angular/Conventional
# Commits spec, where scope is OPTIONAL, and 4Shark's own CLAUDE.md, which
# writes `<type>(<scope>): <subject>` with no "optional" qualifier.

set -euo pipefail

hook_input="$(cat)"
tool_name="$(printf '%s' "$hook_input" | jq -r '.tool_name // empty')"

[ "$tool_name" = "Bash" ] || exit 0

command="$(printf '%s' "$hook_input" | jq -r '.tool_input.command // empty')"

# --- Step 1: is this a `git commit` invocation? -----------------------------
# Mirrors the normalization already used by inject-pr-commit-data-policy.sh
# and inject-commit-policy-reminder.sh: strip a leading env-var prefix or
# `env` wrapper, then match `git commit` / `git -C <path> commit`.
working_command="$command"
while :; do
  read -r first_word rest_of_command < <(printf '%s\n' "$working_command") || true
  case "$first_word" in
    [A-Za-z_]*=*|env) working_command="$rest_of_command" ;;
    *) break ;;
  esac
done

printf '%s' "$working_command" | grep -qE '^git([[:space:]]+-C[[:space:]]+[^[:space:]]+)?[[:space:]]+commit([[:space:]]|$)' || exit 0

# --- Step 2: extract the SUBJECT line ---------------------------------------
# 4Shark commits are observed to be single `-m "type(scope): subject"` with no
# body (see commit-enforcement_log_1.txt — dot-claude body-shape check: every
# sampled non-merge commit is a single subject line). This sketch therefore
# targets the FIRST `-m` value as the subject. Known gaps, to size before
# building for real:
#   - Multiple `-m` flags (`-m subject -m body`) — take the FIRST -m only;
#     4Shark convention does not currently produce a second -m, but a future
#     commit with a body would need this handled explicitly (skip validation
#     on later -m values, do not treat the body as the subject).
#   - `-F <file>` / `--file=<file>` — message comes from a file, not the
#     command line. The hook would need to `cat` the referenced file. A
#     relative path requires resolving against the command's implied cwd,
#     which the hook does not otherwise track (an edge case validate-*.sh
#     hooks elsewhere accept as "engineer runs manually" rather than solve).
#   - `--amend` with NO `-m` — reuses the previous commit's message unchanged;
#     nothing to validate, should short-circuit to allow.
#   - `--amend -m "..."` — replaces the message; validate the new `-m` as
#     normal.
#   - `-c <commit>` / `-C <commit>` (reuse another commit's message, with or
#     without allowing edit) — same shape as amend: no new text was typed
#     this call, allow.
#   - Heredoc / multi-line body passed via `$(cat <<'EOF' ... EOF)` — not
#     observed in the sampled 4Shark history (single-subject convention) but
#     technically possible; the naive `-m` grep would not extract this
#     correctly. A third-party implementation surveyed in this spike
#     (see SPIKE.md Finding 6) has this exact limitation and silently skips
#     validation when the shape does not match — a fail-open gap.
#   - Message contains an escaped quote or the type/scope colon appears inside
#     a quoted body — quote-stripping must be careful not to eat the message
#     content itself (contrast with validate-bash-command.sh's
#     `command_without_quotes`, which is fine to fully discard quoted spans
#     because it never needs to READ their content — this hook does).
#
# Minimal, more robust extraction than a bare grep: use the shell's own
# tokenizer via a `eval`-free array split, OR restrict validation to the
# common case and fail OPEN (allow) on any unrecognized shape rather than
# fail closed — false negatives (an unchecked message slips through) are
# preferable to false positives (a legitimate command is blocked because the
# extractor could not parse it). This mirrors validate-bash-command.sh's own
# philosophy: block only what is confidently matched, never guess-block.

subject="$(printf '%s' "$command" | grep -oE -- "-m[[:space:]]+'[^']*'" | head -n1 | sed -E "s/^-m[[:space:]]+'//; s/'\$//")"
if [ -z "$subject" ]; then
  subject="$(printf '%s' "$command" | grep -oE -- '-m[[:space:]]+"[^"]*"' | head -n1 | sed -E 's/^-m[[:space:]]+"//; s/"$//')"
fi

# No -m found (amend/-c/-C/-F/interactive editor) — nothing to validate here,
# allow. (A -F file-based message is a KNOWN gap, not handled by this sketch.)
[ -z "$subject" ] && exit 0

# --- Step 3: validate against 4Shark's Angular-with-mandatory-scope format --
# 4Shark's own CLAUDE.md (Git Commit Policy) and PULL-REQUEST-CONVENTIONS.md
# (feature-branch PR title example) both write the scope with no "optional"
# marker: `<type>(<scope>): <subject>`. This diverges from the upstream
# Angular/Conventional Commits spec, where scope is OPTIONAL — see SPIKE.md
# Finding 1 for both citations.
commit_type_scope_pattern='^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)\([a-z0-9._-]+\):[[:space:]].+'

if printf '%s' "$subject" | grep -qE "$commit_type_scope_pattern"; then
  exit 0
fi

# Special-case: Angular/HubFlow machine-generated subjects that are exempt by
# existing 4Shark convention and observed in every repo's history — these are
# NOT authored by the agent and should never be blocked:
#   chore(release): X.Y.Z          <- has scope, matches above; listed for clarity
#   Merge pull request #N from ... <- not produced via `-m`, N/A here
#   Merge tag 'X.Y.Z' into develop <- not produced via `-m`, N/A here
# No extra exemption needed — both machine subjects above already carry a
# parenthesized scope or are not authored via -m.

cat >&2 <<EOF
Commit message does not match 4Shark's mandatory Angular format
'<type>(<scope>): <subject>' — blocked.

Message seen:
  ${subject}

Why:
  - CLAUDE.md § Git Commit Policy: "Use Angular Commit Guidelines:
    \`<type>(<scope>): <subject>\`" — no "optional" qualifier on the scope.
  - PULL-REQUEST-CONVENTIONS.md's feature-branch PR title example is
    \`feat(Scope): Description of the feature\` — same mandatory shape.
  - This diverges from the upstream Angular/Conventional Commits spec, where
    the scope is explicitly OPTIONAL — 4Shark's convention is stricter by
    deliberate local choice, not an upstream requirement.

Fix:
  Rewrite the -m message as: <type>(<scope>): <subject>
  Valid types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert
  Scope: the affected package/module/area (see SPIKE.md Finding 3 for the
  scope vocabulary actually in use across 4Shark repos).
EOF
exit 2
