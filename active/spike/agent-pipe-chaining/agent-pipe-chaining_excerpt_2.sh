# Source: ~/.claude/scripts/inject-output-preservation-reminder.sh
# Key sections showing the "reminder-only / always exits 0" design.
#
# Three sections reproduced below:
#   (A) Lines 1-44  — header / rationale for advisory-only design
#   (B) Lines 92-99 — existing false-positive exclusion logic
#   (C) Lines 101-111 — per-session rate-limiting
#   (D) Lines 140-147 — always exits 0

# ─── SECTION A: Lines 1-44 (header / rationale) ──────────────────────────────

#!/bin/bash
#
# Output-Preservation Reminder Injector (PreToolUse / Bash)
#
# Fires before a Bash tool invocation and injects a reminder when the command
# TRUNCATES a work command's output to fit context — i.e. it pipes the output
# of a command that executes work (runs a script, hits infra/network, mutates,
# is slow or non-deterministic) into `head`, `tail`, or `sed -n`.
#
# Why this exists: the dominant failure mode is the agent reaching for
# `cmd 2>&1 | tail -3` / `... | head -40` to keep context small, deciding to
# discard output BEFORE seeing it. If the answer (an error, the line that
# matters) sits in the discarded region, the only recovery is re-running the
# command — and a work command is not guaranteed to reproduce the same output
# (non-idempotent / side-effecting / non-deterministic). This is documented as
# a model bug in anthropics/claude-code#39945 ("Claude pipes Bash output
# through tail/head, discarding errors before reading them"): a `| tail -3`
# hid a script crash and the agent reported success. The harness already does
# better than the manual clip — it middle-truncates (keeps BOTH ends) at 30k
# chars and auto-persists oversized output to a Read-able file — so the manual
# `head`/`tail` is strictly worse, throwing away the end the harness kept.
#
# ...
#
# Emits additionalContext ONLY — never a permissionDecision. The command
# continues through the normal permission flow; this hook only adds context.
#
# Always exits 0. A failing hook must NEVER block a Bash command.
#

# ─── SECTION B: Lines 92-99 (false-positive exclusion logic) ─────────────────
#
# Pure-local idempotent reads — truncating these is low-risk, so NO nudge.
# `git` is treated as a read here: git diff|log|show|status are the commonly
# piped subcommands and all reproduce the same output on re-run.
case "$first_program" in
    grep|rg|cat|ls|find|fd|wc|sort|uniq|head|tail|echo|printf|awk|sed|cut \
        |tr|jq|yq|column|tac|nl|od|xxd|diff|comm|paste|cut|git)
        emit_empty ;;
esac

# NOTE (spike analysis): When the first token is `bash` or `sh`, this case
# statement does NOT match — so the reminder fires. This is the correct
# behavior for the reminder path. For a hard-block path, the same logic
# would apply: `bash script.sh` cannot be classified as idempotent or
# non-idempotent from the command text alone — the script's content determines
# that. This is the false-positive challenge documented in SPIKE.md Finding 4.

# ─── SECTION C: Lines 101-111 (per-session rate-limiting) ───────────────────

# Per-session marker. Falls back to a stable name if session_id is absent.
marker_dir="/tmp/claude_output_preservation_reminder_${session_id:-shared}"
marker_file="${marker_dir}/injected"

[[ -f "$marker_file" ]] && emit_empty

# Persist the marker so subsequent commands in the same session do not
# re-inject. Failure to create the marker is non-fatal — at worst the
# reminder is injected twice.
mkdir -p "$marker_dir" 2>/dev/null && touch "$marker_file" 2>/dev/null || true

# NOTE (spike analysis): The rate-limiting means the reminder fires at most
# ONCE per session, regardless of how many pipe-truncation commands are
# issued. The first occurrence always passes through before the marker is set.
# Upgrading to a hard block (Option B in SPIKE.md) would require removing or
# rethinking this rate-limiting.

# ─── SECTION D: Lines 140-147 (always exits 0) ───────────────────────────────

jq -n --arg ctx "$message" '{
    hookSpecificOutput: {
        hookEventName: "PreToolUse",
        additionalContext: $ctx
    }
}'

exit 0

# NOTE (spike analysis): The script unconditionally exits 0 after injecting
# the additionalContext. There is no exit 2 path. The design comment at line
# 44 ("A failing hook must NEVER block a Bash command") reflects the intent
# that this hook is advisory-only. Changing this to exit 2 (Option B) would
# violate that stated design intent — the spike documents this as an open
# question for the engineer.
