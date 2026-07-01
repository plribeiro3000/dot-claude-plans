# Source: ~/.claude/scripts/validate-bash-command.sh — lines 159-200
# The infra+compound detection block.
# The gap: the infra token list is aws|terraform|kubectl|docker|ansible|gcloud|helm.
# `bash` and `sh` are NOT in this list.
# A command like `bash ~/.claude/scripts/setup-worktree.sh ~/path 2>&1 | tail -10`
# passes through this check silently.

    # An infrastructure command (aws/terraform/kubectl/docker/ansible/gcloud/helm)
    # chained into a compound command (`&&`, `||`, `;`, `|`, or `$(...)`) — blocked.
    # The Command Safety Policy requires infra commands to run ATOMICALLY, one per
    # tool call. A chained infra command also defers the read-only auto-approve hook
    # (auto-approve-aws-readonly.sh gives up on any compound operator), so it falls
    # back to a manual permission prompt every time — exactly the friction the policy
    # exists to remove. The atomic form (`aws ... > /tmp/file.json`; a `>` redirect is
    # NOT a compound operator) is auto-approved.
    #
    # Read-only pipes with NO infra command (`grep pattern file | head`) are NOT
    # blocked — the policy permits them. Two guards against false positives:
    #   - The infra-tool token is matched only at a SEGMENT START (string start, or
    #     after `;`/`&`/`|`/backtick/`$(`, past optional leading VAR=value prefixes),
    #     so an infra name used as a mere argument (`grep aws file | head`) is ignored.
    #   - Quoted spans are stripped before BOTH checks (compound operator AND infra
    #     token), so neither an operator inside a quoted argument (JMESPath
    #     `--query 'X | [0]'`) nor an infra-command example inside a quoted argument
    #     (a `gh pr create --body` / `git commit -m` documenting `aws ...` /
    #     `terraform ...`) trips the guard.
    command_without_quotes="$(printf '%s' "$command" | sed -E "s/'[^']*'//g; s/\"[^\"]*\"//g")"
    if printf '%s' "$command_without_quotes" | grep -qE '(&&|;|\||\$\()' && \
       printf '%s' "$command_without_quotes" | grep -qE '(^|[;&|`]|\$\()[[:space:]]*([A-Za-z_][A-Za-z0-9_]*=[^[:space:]]*[[:space:]]+)*(aws|terraform|kubectl|docker|ansible|gcloud|helm)([[:space:]]|$)'; then
      cat >&2 <<'EOF'
Compound shell command containing an infrastructure command (aws / terraform / kubectl / docker / ansible / gcloud / helm) — blocked.

Why:
  - Infrastructure commands must run ATOMICALLY — one command per tool call, never chained with `;`, `&&`, `||`, `|`, or wrapped in `$(...)`. Chaining defeats per-command review.
  - A chained infra command also defers the read-only auto-approve hook (it gives up on any compound operator), so the command falls back to a manual permission prompt every time — the friction you are trying to avoid.
  - Atomic commands isolate failure: a chained command fails opaquely; separate calls tell you exactly which step broke.

Fix — run each step as a SEPARATE tool call:
  1. aws cloudwatch get-metric-data ... --output json > /tmp/result.json    (atomic; a `>` redirect is NOT a compound operator and IS auto-approved)
  2. jq -r '...' /tmp/result.json                                           (separate call)

Notes:
  - Shell variables do NOT persist across tool calls (only cwd does) — inline the value instead of `VAR=...; cmd`.
  - Read-only pipes with NO infra command (e.g. `grep pattern file | head`) are NOT blocked.

See: ~/.claude/docs/COMMAND-SAFETY.md
EOF
      exit 2
    fi

# NOTE (spike analysis): The token list on line 180 is:
#   aws|terraform|kubectl|docker|ansible|gcloud|helm
#
# `bash` and `sh` are NOT in this list. This is intentional — the hook was
# designed to block infra commands specifically, not all compound commands.
# The pattern `bash work-script.sh 2>&1 | tail -10` therefore passes through
# this check silently. This is the enforcement gap the spike investigates.
