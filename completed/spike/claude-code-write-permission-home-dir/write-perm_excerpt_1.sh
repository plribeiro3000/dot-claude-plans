#!/bin/bash
# EXCERPT — auto-approve-local-skills.sh (full file as reference)
# Source: /Users/plribeiro3000/.claude/scripts/auto-approve-local-skills.sh
# Copied: 2026-06-30
# Purpose: Reference pattern for a new auto-approve-claude-dir-writes.sh hook
#
# Key elements to replicate:
#   1. Read hook_input via "$(cat)" — stdin is the hook JSON payload
#   2. Extract tool_name with jq -r '.tool_name // empty'
#   3. Guard: exit 0 if tool_name doesn't match — defers to normal flow
#   4. Extract the relevant field (skill_name here; file_path for Write/Edit)
#   5. Guard: exit 0 if field is empty
#   6. Business logic check (file existence here; path prefix for Write/Edit)
#   7. Print the JSON allow decision on stdout
#   8. exit 0

set -euo pipefail

hook_input="$(cat)"
tool_name="$(printf '%s' "$hook_input" | jq -r '.tool_name // empty')"

if [ "$tool_name" != "Skill" ]; then
  exit 0
fi

skill_name="$(printf '%s' "$hook_input" | jq -r '
  .tool_input.skill
  // .tool_input.name
  // .tool_input.skill_name
  // .tool_input.command
  // empty
')"

if [ -z "$skill_name" ]; then
  exit 0
fi

claude_root="${HOME}/.claude"

if [ -f "${claude_root}/commands/${skill_name}.md" ] \
   || [ -f "${claude_root}/skills/${skill_name}/SKILL.md" ]; then
  printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow","permissionDecisionReason":"local skill %s defined in ~/.claude/"}}\n' "$skill_name"
  exit 0
fi

exit 0
