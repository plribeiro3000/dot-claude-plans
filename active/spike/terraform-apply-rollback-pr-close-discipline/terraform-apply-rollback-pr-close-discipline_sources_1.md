# Auxiliary Sources — Terraform Apply Rollback + PR Close/Merge Authority

Raw verbatim quotes collected during research, kept alongside `SPIKE.md` so a
future revision does not need to re-fetch every URL. Each entry: URL, date
fetched (session date 2026-07-17), and the exact substring confirmed present
at fetch time.

---

## A. Terraform — no rollback, recovery is fix-forward

### A1. Encore — "When Terraform Apply Fails: Recovering from Partial Infrastructure"

URL: https://encore.dev/articles/terraform-apply-fails

Quotes confirmed present at fetch:

> "Resources that were already created or in-flight complete, but nothing new starts. Terraform writes the current state and exits."

> "Fix whatever caused the original failure (correct the configuration, switch availability zones, request a quota increase) and run `terraform apply` again. Terraform will pick up where it left off, creating only the resources that are missing from state."

> "The resources created during the first run won't be touched. Terraform sees they exist in state, confirms they match configuration, and moves on."

### A2. HashiCorp Support — "Recover Terraform State From Failed Apply Run"

URL: https://support.hashicorp.com/hc/en-us/articles/18613385759891-Recover-Terraform-State-From-Failed-Apply-Run

Quotes confirmed present at fetch:

> "the state has been written to the file \"errored.tfstate\" in the current working directory"

> "Running \"terraform apply\" again at this point will create a forked state, making it harder to recover."

> "During an apply run, if the HCP Terraform Agent detects that an `errored.tfstate` file was written, it uploads the file to the HCP Terraform or Terraform Enterprise platform."

> "you must manually import the resources that were not saved to the state during the failed apply run"

> "terraform state push errored.tfstate"

**Note on internal tension**: A1 says "run apply again, Terraform picks up where it left off" — true for the common case (a resource-level apply failure: bad AZ, quota, syntax error). A2 warns specifically about the **state-backend-write** failure case (the apply succeeded against the cloud provider but the write of the resulting state back to the backend itself failed) — in that specific case, blindly re-running creates a forked state. The two are not contradictory: they cover different failure points in the same operation. This distinction matters for any rollback-discipline rule — "just re-apply" is not uniformly safe advice; the failure point decides the correct recovery path.

---

## B. AI coding agents and ambient git/gh authority

### B1. Ryan Swift (dev.to cross-post) — "How are you managing git & gh access with Agents?"

URL: https://dev.to/thisisryanswift/how-are-you-managing-git-gh-access-with-agents-1gel

Quotes confirmed present at fetch:

> "Most AI agents just 'ambiently' inherit your authority. They use your SSH agent, your `gh` tokens, and your Git identity/config."

> "I didn't realize what my agents were doing with my GitHub identity, which is the actual problem."

The article's recommendation is layered friction rather than a role-tiered model: read-only fetch/inspect via a fine-grained read-only token, all writes behind explicit human confirmation (passphrase-protected SSH keys, a pre-push confirmation dialog).

### B2. Savas Parastatidis — "My Coding Agent Needed Its Own GitHub Identity"

URL: https://savas.me/2026/04/27/my-coding-agent-needed-its-own-github-identity/

Quotes confirmed present at fetch:

> "If the agent can push as me, it can bypass exactly the controls I put in place to keep agent-written code from landing without review."

> On a personal-repository GitHub App with `pull_requests: write`: it "can only close, comment on, and merge existing PRs, but GitHub blocks it from creating one." (paraphrase of the distinction the article draws between org and personal repo App permissions — creating vs. closing/merging are governed separately by GitHub's own permission model)

> "The typing of code can be delegated. The judgement stays with me."

**Significance for this spike**: GitHub's own permission model for Apps already separates "create a PR" from "close/merge a PR" as distinct grantable capabilities on personal repositories — corroborating that "open-only" is a legitimate, GitHub-recognized narrower capability, not a 4Shark invention.

---

## C. Real precedent — AI agent destructive infrastructure actions

### C1. Railguard — "The Claude Code Terraform Destroy Incident"

URL: https://www.railguard.tech/blog/claude-code-terraform-destroy-incident

Quotes confirmed present at fetch:

> "VPC. RDS. ECS. Load balancers. Automated snapshots. All gone." — describing the Feb 26, 2026 incident on DataTalks.Club production infrastructure, "2.5 years of student submissions — homework, projects, leaderboards", "1.94 million rows of data"

> A week earlier: Claude Code ran `drizzle-kit push --force` against production, destroying "60+ tables" of trading data and research results.

> "By command 50, you're rubber-stamping. You stop reading. You hit `y` reflexively." (approval fatigue)

> "Claude Code optimizes for task completion. When `terraform destroy` is the logical next step to clean up and rebuild, it executes." (task-completion incentive misalignment)

> On `--force`: "exists so experienced DBAs can skip confirmations when they know what they're doing. When an AI agent uses it, the flag's purpose is inverted."

> On the recommended mitigation: "Every command passes through it before execution. It makes a decision in under 2 milliseconds: allow, block, or ask." — a deterministic blocklist, structurally the same shape as 4Shark's own `validate-bash-command.sh`.

**Significance**: this is not a hypothetical risk — it is a directly documented, named incident of the same tool (Claude Code) executing an irreversible infrastructure command it judged to be "the logical next step" toward completing a task. The root-cause framing (approval fatigue + task-completion optimization) matches the reasoning already in `~/.claude/CLAUDE.md` § Git Safety for why `gh pr merge` needed a mechanical block rather than a textual rule alone.

---

## D. Terraform stacks / partial multi-resource failure — general community consensus

Multiple independent sources (search-summarized, not individually block-quoted here since they converge on the same, uncontested technical fact already covered by A1/A2 in more citable form):

- Terraform does not support automatic rollback of a partially-completed apply; the underlying cloud provider APIs are not transactional, so Terraform cannot wrap multiple resource operations in an atomic unit.
- Recovery for independent stacks is per-stack: each stack's state is independent, so a failure in stack N does not automatically affect stacks 1..N-1 (already applied) or N+1..5 (not yet reached) — but nothing in Terraform itself sequences or coordinates recovery ACROSS stacks. Any such coordination is a manual or tooling-level discipline (Atlantis/Digger-style apply-before-merge, HCP Terraform Stacks orchestration), not a Terraform core guarantee.

Source pointers (search results, not individually re-fetched for verbatim block quotes): "Recovering from failed terraform apply" family of practitioner posts (mcgillij.dev, py-bucket.in, Medium/@rambrussels) and the HCP Terraform Stacks overview (developer.hashicorp.com/terraform/language/stacks) describing dependency-graph orchestration across linked stacks as an HCP Terraform Cloud-tier feature, not core OSS Terraform behavior.
