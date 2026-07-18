# Auxiliary — script-shape convention excerpts: ~/.claude/scripts/ruby.sh and
# ~/.claude/scripts/terraform.sh, read in full this revision as Pattern Priming
# input for whoever eventually writes the queue-check script. This spike does
# NOT write that script — this file documents the convention only.
#
# Superseded content note: a prior revision of this spike's excerpt_4.sh cited
# app/bin/ecs (the ECS-exec path). That path is moot now that direct Redis
# access is confirmed feasible (see SPIKE.md) — this file replaces it entirely.

# =============================================================================
# ruby.sh — the "resolve+exec, secret read INSIDE the script" pattern
# =============================================================================
# Full file: ~/.claude/scripts/ruby.sh (111 lines)
#
# Key shape (comments, lines 1-13):
#   #!/usr/bin/env bash
#   # Run a Ruby/Bundler command through the correct version manager, with no
#   # command substitution and no env-var prefix in the invocation — so a single
#   # allow-list entry auto-approves every Ruby command.
#   #
#   # Why this exists: a command containing $(...) or a leading VAR=value prefix
#   # never matches the Claude Code permission allow-list (command substitution is
#   # an independent security layer; an env prefix shifts the start of the command
#   # past the prefix match). The canonical Ruby invocations hit both shapes —
#   # RAILS_MASTER_KEY=$(cat config/master.key) ~/.rvm/wrappers/.../bundle exec ...
#   # This wrapper absorbs the version-manager resolution and the master-key read
#   # INTERNALLY, leaving the invocation as a single clean line.
#
# The secret-read line itself (line 64):
#   export RAILS_MASTER_KEY="$(< config/master.key)"
#
# This is the exact pattern a Redis-check script needs, generalized: read the
# credential (there: a file; for Redis: an `aws ssm get-parameter
# --with-decryption` call) INSIDE the script body, export/use it internally,
# and never let the value appear in the invocation line the permission matcher
# (or the agent's own visible command) evaluates.
#
# Argument shape: `ruby.sh [--dir <project-dir>] <tool> [args...]` — an
# optional flag, then the tool name, then its own args passed through via `"$@"`.
#
# CAVEAT flagged by terraform.sh's own header comment (see below): ruby.sh
# `exec`s `$TOOL`, a caller-supplied argument — this is the "environment runner
# execs its arguments" shape terraform.sh's comment calls out as a risk it
# deliberately avoids by hardcoding `terraform` instead.

# =============================================================================
# terraform.sh — the "read-only by construction" pattern (the safer template
# to copy for a NEW single-purpose script)
# =============================================================================
# Full file: ~/.claude/scripts/terraform.sh (206 lines)
#
# The safety-property comment (lines 21-33), verbatim:
#   # READ-ONLY BY CONSTRUCTION — the safety property that makes a single broad
#   # `Bash(bash ~/.claude/scripts/terraform.sh:*)` allow entry safe: this wrapper
#   # REFUSES every write subcommand (apply/destroy/import/taint/untaint/refresh,
#   # `state` other than list/show, and any unrecognized subcommand). It cannot run
#   # a write, so the allow entry can only ever approve a read. Write operations
#   # keep going through the raw `direnv exec ... terraform ... apply` path, where
#   # `validate-bash-command.sh`'s emit_ask gate + MFA still fire. Do NOT relax this
#   # without also adding per-write-subcommand `ask` entries (see the terraform PR
#   # #527 incident class in CLAUDE.md § Git Safety).
#   #
#   # The `terraform` binary is HARDCODED here (never taken from an argument and
#   # exec'd, unlike ruby.sh) — closing the "environment runner execs its arguments"
#   # risk that the Claude Code permission docs warn about.
#
# The refusal mechanism (lines 59-87), the shape a Redis-check script would
# mirror by hardcoding an allowlist of read-only Redis commands and refusing
# anything else:
#   reject_write() {
#     cat >&2 <<EOF
#   Refused: `terraform $subcommand` is a WRITE operation — terraform.sh is read-only by construction.
#   ...
#   EOF
#     exit 2
#   }
#   case "$subcommand" in
#     init|plan|validate|fmt|show|output|version|state) ;;
#     *) reject_write ;;
#   esac
#
# Argument shape: `terraform.sh <stack-dir> <subcommand> [args...]` — the
# FIRST positional argument identifies WHICH target (the stack), exactly the
# shape a Redis-check script needs (`<stack>` ∈ beta-001/demo-001/shared-001/
# atento-001), rather than relying on cwd (which does not carry over to
# subagents/one-offs anyway — see CLAUDE.md § Working Directory Behavior).
#
# Output shape (lines 158-173): stdout streamed live; stderr captured to a
# temp file (`stderr_file`) so blocking/init signals can be grepped, then
# always echoed to real stderr afterward via `cat "$stderr_file" >&2` — the
# caller sees normal output, nothing is silently swallowed.
#
# `set -euo pipefail` at the top of both scripts (ruby.sh:35, terraform.sh:43).

# =============================================================================
# Allow-list entry shape (confirmed this revision, ~/.claude/settings.json)
# =============================================================================
#   settings.json:79   "Bash(bash ~/.claude/scripts/ecs-scale.sh:*)",
#   settings.json:90   "Bash(bash ~/.claude/scripts/ruby.sh:*)",
#   settings.json:97   "Bash(bash ~/.claude/scripts/terraform.sh:*)",
#
# A new script earns the same one-entry shape:
#   "Bash(bash ~/.claude/scripts/<new-script-name>.sh:*)"

# =============================================================================
# redis-cli 8.0.3 --help (relevant flags only; full dump preserved in
# sidekiq-queue-check-binary_log_1.txt) — the constraint on what redis-cli
# alone can and cannot do for this binary
# =============================================================================
#   -u <uri>           Server URI on format redis://user:password@host:port/dbnum
#                      ... For TLS, use the scheme 'rediss'.
#   --tls              Establish a secure TLS connection.
#   --insecure         Allow insecure TLS connection by skipping cert validation.
#   -a <password>      Password to use when connecting to the server.
#                      You can also use the REDISCLI_AUTH environment
#                      variable to pass this password more safely
#   --eval <file>      Send an EVAL command using the Lua script at <file>.
#   --scan             List all keys using the SCAN command.
#
# `-u rediss://...` auto-enables TLS from the URI scheme (no separate --tls
# needed). `REDISCLI_AUTH` exists specifically so a password need not appear
# in argv when NOT using the `-u` combined-URL form — but the SSM parameter
# for this binary already IS a combined URL (REDIS_SIDEKIQ_URL / REDIS_URL),
# so using `-u "$url"` puts the whole credential, password included, into the
# process's own argv (visible to `ps`, though not into the agent's own
# printed stdout/stderr unless the script itself echoes it).
