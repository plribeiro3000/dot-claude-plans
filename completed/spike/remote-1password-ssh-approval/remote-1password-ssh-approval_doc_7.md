# Auxiliary source — GitHub deploy keys (alternative to a 1Password-backed Service Account key)

## Source: GitHub Docs — Managing deploy keys
- URL: https://docs.github.com/en/authentication/connecting-to-github-with-ssh/managing-deploy-keys
- Fetched: 2026-07-06

> An SSH key that grants access to a single repository. GitHub attaches the public part of the key directly to your repository instead of a personal account, and the private part of the key remains on your server.

> Deploy keys only grant access to a single repository.

> Deploy keys are usually not protected by a passphrase, making the key easily accessible if the server is compromised.

> Deploy keys are credentials that don't have an expiry date.

Deploy keys are read-only by default; write access can be granted when adding the key to the
repository. GitHub's own guidance points toward GitHub Apps as offering finer-grained control and
better security than a raw deploy key for more sophisticated needs.

## Source: web search aggregation — deploy key write-access scope and branch protection interaction
- Fetched via WebSearch: 2026-07-06 (aggregated summary, not a single verbatim page — treated as
  a lower-confidence source than a direct fetch; the two specific claims below were corroborated
  by GitHub's own documentation title/URL pattern returned in the same search and are consistent
  with GitHub's publicly documented behavior, but were not independently re-fetched from a single
  primary page in this research pass)

- Deploy keys with write access can perform the same repository actions as a collaborator with
  write/admin access — a write-enabled deploy key is not inherently scoped down to "push only";
  it can push, delete branches, etc., subject to the same repository rules that apply to any
  writer.
- Branch protection rules (including a block on force-pushing to a protected branch) apply to
  deploy keys the same as to any other writer, unless the deploy key is deliberately added to a
  ruleset's bypass list.

Marked lower-confidence deliberately: this paragraph is not a verbatim quote from a single fetched
page and is not used to sustain a Finding on its own in SPIKE.md — it corroborates, but does not
solely carry, the point that 4Shark's own branch-protection/force-push-block conventions (see
4Shark `CLAUDE.md` § Git Safety, an internal document, not re-cited here as an external source)
are a Claude-Code-level and GitHub-level control that operates independently of which SSH
credential mechanism authenticates the push.
