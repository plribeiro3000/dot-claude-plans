# External search log — fix-space research

Per the citation discipline, a search-result summary (not a fetched page with a quote) cannot sustain a claim on its own — it is recorded here as a negative/inconclusive result, not cited as a Finding in `SPIKE.md`.

## Search 1 — expand/contract naming for this specific case

Query: `expand contract pattern remove terraform managed secret before destroying still referenced resource`

No fetched primary source was opened (the search tool returned a synthesized summary, not a page-level quote I re-fetched myself). The summary surfaced generic Terraform lifecycle material — `developer.hashicorp.com/terraform/language/meta-arguments/lifecycle`, the `removed` block, and an AWS Secrets Manager recovery-window caveat — none of which names a pattern specific to "a launch-time-resolved resource (SSM parameter/secret) referenced by a live ECS task definition, where the reference is removed from config before the resource is destroyed." **Not found**: a community-named pattern matching 4Shark's exact shape. This is consistent with, and does not contradict, the prior spike's own Finding 5 (`terraform-ignore-changes-task-definition-drift/SPIKE.md`), which reached the same "not named" conclusion via a different, more targeted search.

## Search 2 — `track_latest` and the `command` argument interaction

Query: `terraform aws_ecs_task_definition track_latest command argument null default CMD problem`

No fetched primary source with a quote — the search tool's own synthesis explicitly states: *"the search results don't contain specific information about a problem related to the `command` argument being null with a default CMD or specific details about this particular issue."* This is a genuine, searched-for negative result: **no issue, blog post, or provider documentation was found addressing whether `track_latest` (or any other Terraform-side revision-tracking mechanism) has any bearing on a task definition's `command` field being `null`.** `track_latest` (per the prior spike's F17) only changes which revision a `data`/resource considers "latest ACTIVE" — it does not touch what `command` value the Terraform-authored revision itself carries, since that is downstream of `var.command`'s value in 4Shark's own module (§ `pointer-lag_cloudtrail_1.md` finding 7), a concern `track_latest` was never designed to address.
