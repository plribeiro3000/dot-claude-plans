<!-- Fetched excerpt — https://blakecrosley.com/blog/claude-code-hooks-explained — retrieved 2026-07-16 -->
<!-- THIRD-PARTY / COMMUNITY SOURCE — not Anthropic-authored, not found in the
     official docs after four direct targeted queries (see doc_2). Included
     because it is the only source found that states a precedence rule and a
     multiple-updatedInput resolution rule in specific terms. Treat as
     community secondary evidence, not an official guarantee. Re-fetched once
     to confirm the quote is stable (citation discipline self-check, both
     fetches returned identical substrings on 2026-07-16). -->

# Claude Code Hooks Explained (excerpt)

On precedence when multiple PreToolUse hooks disagree:

> "when multiple `PreToolUse` hooks disagree, precedence is `deny` > `defer` > `ask` > `allow`."

On parallel updatedInput rewriting:

> "When several PreToolUse hooks rewrite the same tool's arguments, the last to finish wins."

The page was also asked directly whether a command rewritten via `updatedInput` is re-checked against `permissions.allow`/`ask`/`deny` before running. Result: not found on this page either — the same gap as the official docs.
