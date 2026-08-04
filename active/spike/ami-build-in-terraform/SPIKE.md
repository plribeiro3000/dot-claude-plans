# SPIKE — Building the MongoDB Golden AMI Entirely Through Terraform (EC2 Image Builder)

## Investigation question

Can 4Shark build its MongoDB golden AMI entirely through Terraform-declared AWS resources (EC2 Image Builder), sourcing the provisioning content from a GitHub repository — such that the Packer definition, the Ansible role repository, and the GitHub Actions build workflow can all be retired?

The engineer's stated principle for why this matters: *"Terraform is the source of truth for infrastructure. If something exists in the infrastructure and is not in Terraform, that is a design problem, because the team can no longer trust Terraform to describe what exists."* Today the golden AMI exists in AWS and Terraform only discovers it with a `data "aws_ami"` tag lookup — Terraform does not know it exists.

## Baseline (current state, read before researching)

- `~/Projects/4Shark/mongodb/packer/mongodb.pkr.hcl` — Packer `amazon-ebs` builder: resolves Canonical's Ubuntu 24.04 (`noble`) AMI fresh at build time via `source_ami_filter` (owner `099720109477`, name pattern, `most_recent = true`), passes `mongodb_version`/`mongodb_ubuntu_codename` into the Ansible provisioner as `--extra-vars`, tags the AMI with a generated `Version` (series + timestamp).
- `~/Projects/4Shark/mongodb/ansible/playbook.yml` + `requirements.yml` — a one-role playbook; the role is pulled from a **private** repo (`git@github.com:4shark/ansible-role-mongodb.git`) over SSH at a pinned tag (`v0.2.0`), authenticated with a read-only deploy key.
- `~/Projects/4Shark/mongodb/.github/workflows/build.yaml` — triggers on `push` to `main` filtered by `paths: [packer/**, ansible/**, .github/workflows/build.yaml]`, or `workflow_dispatch`; loads the deploy key as a GitHub secret; runs `packer build`; prunes AMIs down to the 3 most recent with a hand-written `aws ec2 describe-images` + `deregister-image` + `delete-snapshot` bash loop.
- `~/Projects/4Shark/terraform/mongodb/` — owns only the build's AWS credentials: `main.tf` declares an IAM user/access key (`iam.tf`, not read in full — out of scope for this question) and `github.tf` pushes `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` into the `mongodb` GitHub Actions environment. No `aws_ami`, `aws_imagebuilder_*`, or any other AMI-shaped resource exists in this stack.
- `~/Projects/4Shark/ansible-role-mongodb/tasks/main.yml` — 101 lines: assert a required var, install two apt packages, download+dearmor a GPG key, add the MongoDB apt repo, install `mongodb-org`, `dpkg_selections` hold five packages, template a systemd unit (`disable-thp.service.j2`) and `mongod.conf` (`mongod.conf.j2`), enable/start two systemd services.
- `~/Projects/4Shark/ansible-role-mongodb/templates/mongod.conf.j2` — a Jinja2 template with one conditional block: `{% if mongodb_conf_replSetName %} replication: replSetName: ... {% endif %}`.
- `~/Projects/4Shark/ansible-role-mongodb/defaults/main.yml:46` — `mongodb_conf_replSetName: ""`, never overridden by the golden-AMI build (the packer file's `extra_arguments` pass only `mongodb_version` and `mongodb_ubuntu_codename`) — so at bake time this conditional always evaluates false.

## Sources consulted

- `hashicorp/terraform-provider-aws` raw docs (`imagebuilder_image`, `imagebuilder_image_pipeline`, `imagebuilder_image_recipe`, `imagebuilder_component`, `imagebuilder_lifecycle_policy`) — argument/attribute references, fetched directly from GitHub raw markdown (the source the rendered `registry.terraform.io` pages are built from; the rendered pages themselves returned no usable content to the fetch tool)
- AWS official EC2 Image Builder user guide (`manage-recipes.html`, `image-lifecycle-rules.html`, `integ-eventbridge.html`) and API reference (`API_DeleteImage.html`) — authoritative behavior documentation
- AWS Compute Blog, "Executing Ansible playbooks in your Amazon EC2 Image Builder pipeline" (Andrew Pearce) — the post named in the question
- `aws-samples/amazon-ec2-image-builder-samples`, `Components/Linux/ansible-playbook-execution-amazon-linux-2/cloudformation.yml` — the sample repo named in the question
- AWS "What's New" post, EC2 Image Builder SSM Parameter Store integration (April 2025)
- `aws/ec2-image-builder-roadmap` issue #54 (GitHub API) — EventBridge-as-trigger feature status
- Ubuntu AWS docs (`ubuntu.com/aws/docs/aws-how-to/instances/find-ubuntu-images/`) — SSM parameter path for the Ubuntu 24.04 AMI

## Findings

### Finding 1 — `aws_imagebuilder_image` tracks the AMI id in state; `aws_imagebuilder_image_pipeline` does not

**Evidence:**

`aws_imagebuilder_image`'s attribute reference (fetched verbatim from the provider's raw docs source):

```
* `output_resources` - List of objects with resources created by the image.
    * `amis` - Set of objects with each Amazon Machine Image (AMI) created.
        * `account_id` - Account identifier of the AMI.
        * `description` - Description of the AMI.
        * `image` - Identifier of the AMI.
        * `name` - Name of the AMI.
        * `region` - Region of the AMI.
```

`aws_imagebuilder_image_pipeline`'s full attribute reference, quoted in its entirety (no `amis` or AMI-id field appears anywhere in it):

```
* `id` - Amazon Resource Name (ARN) of the image pipeline.
* `arn` - Amazon Resource Name (ARN) of the image pipeline.
* `date_created` - Date the image pipeline was created.
* `date_last_run` - Date the image pipeline was last run.
* `date_next_run` - Date the image pipeline will run next.
* `date_updated` - Date the image pipeline was updated.
* `platform` - Platform of the image pipeline.
* `tags_all` - A map of tags...
```

**Source:** `https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/imagebuilder_image.html.markdown`, `https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/imagebuilder_image_pipeline.html.markdown`

**Significance:** this is the crux, and it is unambiguous. `aws_imagebuilder_image` is a resource whose `create` performs one build and stores the resulting AMI id in `terraform.tfstate` at `output_resources.amis[].image` — that AMI is genuinely a Terraform-managed fact from that point on, refreshable with `terraform plan`/`state show`, discoverable without a tag-based `data` lookup. `aws_imagebuilder_image_pipeline`, by contrast, configures a recurring build definition; each pipeline execution (scheduled or manually started via `StartImagePipelineExecution`, an API the Terraform resource does not expose an argument for) produces a new Image Builder image resource **outside the Terraform resource graph**. Terraform would still need a `data "aws_ami"` (or `data "aws_imagebuilder_image"`) lookup to find what a pipeline execution produced — reproducing exactly today's situation, just with EC2 Image Builder standing in for Packer/GitHub Actions as the thing Terraform does not track. Migrating to a pipeline satisfies the engineer's principle no better than the status quo; migrating to a directly-declared `aws_imagebuilder_image` does satisfy it, for image creation — with the qualification in Finding 3.

**Verification block:** URL fetched — both raw markdown URLs above. Verbatim quote checked — yes, self-checked by re-fetching the `imagebuilder_image_pipeline` doc's attribute reference a second time in a follow-up call and confirming the same nine attributes with no AMI-id field. Quote substring confirmed at the `## Attribute Reference` section of each document.

---

### Finding 2 — Recipes and components are immutable; a rebuild requires a version bump, not a re-run

**Evidence:** Image recipe versioning:

> "Recipes are immutable. After you create a recipe, you can't modify or replace it. To update components or any other configuration, you must create a new recipe or recipe version. Image Builder retains all previous versions."

Component data/uri, quoted in full including the note:

```
* `data` - (Optional) Inline YAML string with data of the component. Exactly one of `data` and `uri` can be specified. Terraform will only perform drift detection of its value when present in a configuration.
...
* `uri` - (Optional) S3 URI with data of the component. Exactly one of `data` and `uri` can be specified.

~> **NOTE:** Updating `data` or `uri` requires specifying a new `version`. This causes replacement of the resource. The `skip_destroy` argument can be used to retain the old version.
```

**Source:** `https://docs.aws.amazon.com/imagebuilder/latest/userguide/manage-recipes.html`; `https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/imagebuilder_component.html.markdown`

**Significance:** this changes the operational shape of "rebuild," compared both to Packer and to the current workflow's `workflow_dispatch` (forcing a bake with no code change, e.g. to pick up a newer patched Canonical base — see the current `build.yaml:10-27` comment on why that trigger exists). With `aws_imagebuilder_image` as a directly-declared Terraform resource, re-running `terraform apply` against an *unchanged* component/recipe produces no diff and therefore no new build — Terraform sees the same immutable inputs and does nothing. To force a rebuild you must bump the component's `version` (which forces resource replacement) and/or the recipe's `version`, which in turn forces `image_recipe_arn` to change on the `aws_imagebuilder_image` resource, which is what actually triggers a new `create`. This is a genuine behavior change: "just re-run the build" is no longer a no-argument operation, it requires a version bump somewhere in the chain on every apply that should produce a new AMI — including a bake that intentionally has zero content changes (Canonical repatch pickup).

**Verification block:** URL fetched — both above. Verbatim quote checked — yes. Quote substring confirmed at `## Recipe versioning` (manage-recipes.html) and the `~> NOTE` immediately following the `uri` argument (imagebuilder_component.html.markdown).

---

### Finding 3 — Deleting the Terraform resource does not deregister the AMI

**Evidence:**

> "Deletes an Image Builder image resource. This does not delete any EC2 AMIs or ECR container images that are created during the image build process. You must clean those up separately, using the appropriate Amazon EC2 or Amazon ECR console actions, or API or AWS CLI commands."

**Source:** `https://docs.aws.amazon.com/imagebuilder/latest/APIReference/API_DeleteImage.html` (the API that `aws_imagebuilder_image`'s Terraform `delete` lifecycle calls)

**Significance:** qualifies Finding 1. Terraform state *tracking* the AMI id is one-directional — `create` genuinely produces and records the AMI, but `terraform destroy` (or a replacement triggered by Finding 2's version-bump mechanics) does not deregister the old AMI or delete its snapshot; those become orphaned unless cleaned up by a separate mechanism (a companion `aws_ami` resource pointed at the same id, or the lifecycle policy in Finding 9's COUNT rule, which does support an explicit AMI-deregister + snapshot-delete action). "Terraform owns the AMI" is accurate for creation and for state-visibility, not for full lifecycle symmetry without additional resources.

**Verification block:** URL fetched — yes. Verbatim quote checked — yes, re-fetched and confirmed the same paragraph verbatim in the "Delete this image resource" opening line. Quote substring confirmed at the top of the page, immediately under the `# DeleteImage` heading.

---

### Finding 4 — Component content: inline `data` and S3 `uri` are both supported, mutually exclusive

**Evidence:** already quoted in full in Finding 2 — `data` (inline YAML string) and `uri` (S3 URI) are each optional, and "Exactly one of `data` and `uri` can be specified." No upload-to-S3-first requirement exists for the common case: the component YAML can be written directly as an HCL heredoc inside `data = <<-EOT ... EOT` in the Terraform repository, with no S3 bucket in the loop at all.

**Source:** same as Finding 2.

**Significance:** directly answers question 2. The component document can live in the Terraform repository as inline `data`; `uri` is available for teams that prefer to manage large or shared component bodies as versioned S3 objects outside the `.tf` file, but it is not a requirement — it is an alternative.

**Verification block:** URL fetched — yes (same as Finding 2). Verbatim quote checked — yes. Quote substring confirmed at the `data`/`uri` bullet pair in `## Argument Reference`.

---

### Finding 5 — The official Ansible guidance (AWS blog + `aws-samples`) pulls the playbook from S3, not from GitHub

**Evidence:** the full component document from the sample the question named, fetched verbatim from the raw GitHub file:

```yaml
name: 'Ansible Playbook Execution on Amazon Linux 2'
...
      - name: DownloadPlaybook
        action: S3Download
        inputs:
          - source: 's3://mybucket/playbooks/my-playbook.yml'
            destination: '/tmp/my-playbook.yml'
      - name: InvokeAnsible
        action: ExecuteBinary
        inputs:
          path: ansible-playbook
          arguments:
            - '{{ build.DownloadPlaybook.inputs[0].destination }}'
```

The AWS Compute Blog post (Andrew Pearce) that introduces this same pattern was independently checked and describes the identical mechanism: a component action named `S3Download` retrieving `s3://mybucket/playbooks/my-playbook.yml`, then `ExecuteBinary` invoking `ansible-playbook` against the downloaded file.

**Source:** `https://raw.githubusercontent.com/aws-samples/amazon-ec2-image-builder-samples/master/Components/Linux/ansible-playbook-execution-amazon-linux-2/cloudformation.yml`; `https://aws.amazon.com/blogs/compute/executing-ansible-playbooks-in-your-amazon-ec2-image-builder-pipeline/`

**Significance:** neither the official blog post nor the official sample repository pulls provisioning content from a GitHub repository at build time — both pull a pre-uploaded object from S3. "Executing an Ansible playbook via Image Builder" as AWS documents and demonstrates it is an S3-sourced pattern, not a GitHub-sourced one. A GitHub-sourced pull is not shown anywhere in either of the two sources the question named as evidence to check.

**Verification block:** URL fetched — both. Verbatim quote checked — yes, the cloudformation.yml YAML block was re-fetched in full and matches character-for-character. Quote substring confirmed at the `ComponentDocument`/inline YAML section of the CloudFormation template, and at the step-by-step description in the blog post body.

---

### Finding 6 — No Image Builder action module authenticates against a private source (S3-IAM-role is the only authenticated path documented)

**Evidence:** the full list of action modules on the AWSTOE reference page, each with its documented one-line purpose:

- `ExecuteBash` — run bash scripts with inline shell code/commands
- `ExecuteBinary` — run binary files with a list of command-line arguments
- `ExecuteDocument` — nested component documents
- `ExecutePowerShell` — run PowerShell scripts
- `S3Download` / `S3Upload` — transfer to/from Amazon S3
- `WebDownload` — download over HTTP/HTTPS
- File-system modules (`AppendFile`, `CopyFile`, `CopyFolder`, `CreateFile`, `CreateFolder`, `CreateSymlink`, `DeleteFile`, `DeleteFolder`, `ListFiles`, `MoveFile`, `MoveFolder`, `ReadFile`, `SetFileEncoding`, `SetFileOwner`, `SetFolderOwner`, `SetFilePermissions`, `SetFolderPermissions`)
- `InstallMSI` / `UninstallMSI`, `Reboot`, `SetRegistry`, `UpdateOS`

No `GitClone` or equivalent git-specific action module appears in this list.

`WebDownload`'s full input-parameter table was checked separately: it accepts `source`, `destination`, `overwrite`, `checksum`, `algorithm`, `ignoreCertificateErrors` — no header, token, or basic-auth parameter of any kind.

**Source:** `https://raw.githubusercontent.com/awsdocs/ec2-image-builder-user-guide/master/doc_source/toe-action-modules.md`; `https://docs.aws.amazon.com/imagebuilder/latest/userguide/toe-action-modules.html`

**Significance:** directly answers question 3. There is no native, documented way for an Image Builder component to authenticate a pull from a private GitHub repository. `S3Download` inherits the build instance's IAM role — authenticated, but only for S3, and only after the private content has already been uploaded there by some other process. `WebDownload` has no auth mechanism at all, so it cannot reach a private GitHub URL (raw content or API) even with a token, since GitHub requires the token as an `Authorization` header and `WebDownload` supports no headers. The only path to pulling a private git repository directly is `ExecuteBash` running an arbitrary `git clone` command — which is possible (the action module runs unrestricted shell as root) but requires the engineer to provision the credential (SSH deploy key or a GitHub token) onto the build instance through some other channel — for example an `SSM Parameter Store SecureString` read via the instance's IAM role inside the `ExecuteBash` script. This is an inference from what the action modules can do, not a documented AWS pattern for private-repo authentication — no source consulted describes it as a supported or recommended approach.

**Verification block:** URL fetched — both. Verbatim quote checked — the module list and the `WebDownload` parameter table were each independently re-verified across two separate fetches of two different pages (the `awsdocs` GitHub-hosted source and the rendered `docs.aws.amazon.com` page), with consistent results. Quote substring confirmed at the module list on the `toe-action-modules.md`/`.html` pages.

---

### Finding 7 — Base image can be resolved dynamically via an SSM parameter, comparable in spirit to Packer's `most_recent` filter

**Evidence:** the `parent_image` argument:

> "The value can be the base image ARN, an AMI ID, or an SSM Parameter referencing the AMI. For an SSM Parameter, enter the prefix `ssm:`, followed by the parameter name or ARN."

AWS's own April 2025 feature announcement:

> "Now, customers can leverage SSM Parameters as inputs for their image recipes, enabling them to dynamically retrieve the latest base image."

Canonical publishes exactly such a parameter for the Ubuntu release the current Packer build targets:

> "/aws/service/canonical/ubuntu/server/24.04/stable/{serial}/amd64/hvm/ebs-gp3/ami-id"

**Source:** `https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/imagebuilder_image_recipe.html.markdown`; `https://aws.amazon.com/about-aws/whats-new/2025/04/ec2-image-builder-integrates-ssm-parameter-store/`; `https://ubuntu.com/aws/docs/aws-how-to/instances/find-ubuntu-images/`

**Significance:** this narrows one of the "does not cover" gaps in question 4. A recipe's `parent_image` can be set to `ssm:/aws/service/canonical/ubuntu/server/24.04/stable/current/amd64/hvm/ebs-gp3/ami-id`, which — per AWS's description — dynamically retrieves the current AMI rather than the recipe being locked to a fixed AMI id at creation time. This is different in mechanism from Packer's `source_ami_filter` (an `owners` + `name` glob + `most_recent = true` describe-images query resolved by the Packer binary at build start) but arrives at a comparable practical outcome — a build baked from the current Canonical AMI without hardcoding an id. What remains unverified (see "What remains uncertain") is the precise resolution timing — whether the parameter is re-read at every pipeline execution or only at the point the recipe/image resource is created.

**Verification block:** URL fetched — all three. Verbatim quote checked — yes for all three. Quote substring confirmed: `parent_image` argument description on the recipe doc page; the "What's New" post's feature paragraph; the SSM path pattern on the Ubuntu AWS docs page.

---

### Finding 8 — Build-time variables: component `parameter` blocks are the analog to Packer's `--extra-vars`

**Evidence:**

```
* `name` - (Required) The name of the component parameter.
* `value` - (Required) The value for the named component parameter.
```

**Source:** `https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/imagebuilder_image_recipe.html.markdown`

**Significance:** answers another part of question 4. A component's steps can reference `{{ params.<name> }}`-style expansion of values passed at the recipe's `component { parameter { name = ...; value = ... } }` block — a direct, if less flexible, counterpart to Packer's `extra_arguments = ["--extra-vars", "mongodb_version=... mongodb_ubuntu_codename=..."]` (`mongodb.pkr.hcl:169-172`).

**Verification block:** URL fetched — yes. Verbatim quote checked — yes. Quote substring confirmed at the `parameter` sub-block description within the recipe doc's `component` block documentation.

---

### Finding 9 — AMI retention/pruning is natively declarable via `aws_imagebuilder_lifecycle_policy` with a COUNT filter — with one structural caveat

**Evidence:**

> "`COUNT` filter — Retains the newest N Image Builder images per recipe version. All images beyond the specified count qualify for deletion."

> "The COUNT filter counts Image Builder image resources per recipe version, not output AMIs or containers."

> "Delete rule — Deletes the image resources by age or by count. ... You can optionally deregister associated AMIs or delete the snapshots for those AMIs."

**Source:** `https://docs.aws.amazon.com/imagebuilder/latest/userguide/image-lifecycle-rules.html`

**Significance:** answers the retention/pruning part of question 4 — and, notably, this is the one Image Builder-native mechanism that can also close the Finding 3 gap: a `DELETE` rule can be configured to deregister the AMI and delete the snapshot, not just remove the Image Builder image resource. The caveat: retention is counted **per recipe version** (a wildcard version pattern like `1.x.x` is evaluated per resolved version, e.g. keep 5 of `1.0.0`, 5 of `1.1.0`, independently), which is a natural fit for a *pipeline* re-running against one recipe repeatedly, and a less natural fit for a chain of individually-declared `aws_imagebuilder_image` resources each requiring its own bumped recipe version per Finding 2 — the "3 most recent" semantics of today's `build.yaml:73-97` bash loop (which prunes by `Name=tag:mongodb` across all AMIs regardless of recipe version) would need to be re-expressed as "3 most recent per recipe-version lineage," which is a materially different retention shape if recipe versions are bumped on every apply.

**Verification block:** URL fetched — yes. Verbatim quote checked — yes, self-checked with a second fetch targeting the same page and section. Quote substring confirmed at `## How retention is calculated` and the `Delete rule` description under `## How lifecycle management rules work`.

---

### Finding 10 — Test stage can be skipped

**Evidence:**

```
* `image_tests_enabled` - (Optional) Whether image tests are enabled. Defaults to `true`.
* `timeout_minutes` - (Optional) Number of minutes before image tests time out. ...
```

**Source:** `https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/imagebuilder_image.html.markdown`

**Significance:** answers the last part of question 4. Setting `image_tests_configuration { image_tests_enabled = false }` on the `aws_imagebuilder_image` (or the pipeline) skips the `test` phase entirely — comparable to simply not defining a `validate`/`test` step in the current Packer `build` block (the current `mongodb.pkr.hcl` has no test/validate phase at all).

**Verification block:** URL fetched — yes (same page as Finding 1). Verbatim quote checked — yes. Quote substring confirmed at the `image_tests_configuration` block's argument list.

---

### Finding 11 — The Ansible role's steps map onto component actions; the one Jinja2 conditional in the config template is currently a dead branch for this specific build

**Evidence:** every step in `~/Projects/4Shark/ansible-role-mongodb/tasks/main.yml` (101 lines total) uses one of: `assert`, `apt`, `get_url`, `command` (`gpg --dearmor`), `apt_repository`, `dpkg_selections`, `template` (×2), `systemd` (×2), `file` (×2). Per Finding 6's action-module list, `ExecuteBash` covers `assert`/`apt`/`get_url`/`command`/`apt_repository`/`dpkg_selections`/`systemd`/`file` (all are shell-expressible), and `CreateFile` (or an `ExecuteBash` heredoc) covers the two `template` steps. The one piece of logic in either template that is not a flat string substitution is the conditional in `mongod.conf.j2:17-20`:

```
{% if mongodb_conf_replSetName %}
replication:
  replSetName: {{ mongodb_conf_replSetName }}
{% endif %}
```

`~/Projects/4Shark/ansible-role-mongodb/defaults/main.yml:46` sets `mongodb_conf_replSetName: ""`, and neither `mongodb.pkr.hcl`'s `extra_arguments` (`mongodb.pkr.hcl:169-172`) nor `playbook.yml` overrides it for the golden-AMI build — so for this specific build the conditional always evaluates false, and the `replication:` block is never emitted in the baked image (replica-set init is a documented post-boot step per `mongodb.pkr.hcl:6-7`).

**Source:** direct reading of the four files named above; no external citation needed for this finding (it is a comparison of two pieces of 4Shark's own code, both already read in full for the baseline).

**Significance:** answers question 5's factual half. Nothing in this specific role requires Jinja2's expressive features (loops, filters, macros) — the sole conditional it uses never fires for this build's actual usage. A component-YAML rewrite that hardcodes the "no replication block" branch would be behaviorally identical to what the current bake already produces. What would genuinely be lost is not template capability for this build, but the role's **general-purpose reusability** — the Ansible role as written could serve a different consumer that does pass a non-empty `mongodb_conf_replSetName` (its `defaults/main.yml` comments describe deliberate genericness, e.g. the Ubuntu-codename default "tracks the base image, not the fleet's MongoDB series"); a hardcoded component loses that flexibility along with the separate versioned repo, `CHANGELOG.md`, and `.ansible-lint`/`.yamllint` tooling that currently govern the role as an independent artifact.

**Verification block:** not applicable (internal code comparison, not an external source) — citations are `file:line` against files already read in full for the baseline, satisfying the code-citation format.

---

### Finding 12 — Build triggers: cron/dependency-gated scheduling is native; a GitHub-push-shaped trigger is not

**Evidence:** the pipeline `schedule` block, quoted in full:

```
* `schedule_expression` - (Required) Cron expression of how often the pipeline start condition is evaluated.
* `pipeline_execution_start_condition` - (Optional) Condition when the pipeline should trigger a new image build. Valid values are `EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE` and `EXPRESSION_MATCH_ONLY`. Defaults to `EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE`.
```

AWS's EventBridge integration doc, quoted:

> "Image Builder works with EventBridge in two independent directions. ... Run a pipeline in response to an event (Image Builder as a target). EventBridge starts a pipeline build when an event matches a rule, or when a schedule fires."

The roadmap item that shipped this capability (`aws/ec2-image-builder-roadmap#54`, "Using EventBridge events to trigger Image Pipeline builds"), per the GitHub API: `state: closed`, `state_reason: completed`, `created_at: 2020-11-10`, `closed_at: 2025-11-24`.

**Source:** `https://raw.githubusercontent.com/hashicorp/terraform-provider-aws/main/website/docs/r/imagebuilder_image_pipeline.html.markdown`; `https://docs.aws.amazon.com/imagebuilder/latest/userguide/integ-eventbridge.html`; `https://api.github.com/repos/aws/ec2-image-builder-roadmap/issues/54`

**Significance:** answers question 6. Two Terraform-declarable trigger shapes exist: (a) the pipeline's own `schedule` block, a cron cadence that can additionally gate on `EXPRESSION_MATCH_AND_DEPENDENCY_UPDATES_AVAILABLE` — "only actually build if the base image or a component changed" — which is the closest built-in analog to today's `build.yaml:10-27` path-filtered push trigger, but it is **polling** (evaluated on a cadence), not **push** (evaluated the instant a commit lands); (b) an `aws_cloudwatch_event_rule`/target pointed at Image Builder as an EventBridge target, which is a real, currently-shipped feature (closed as completed, Nov 2025) but requires *something* to put a matching event on the bus — GitHub is not a native AWS EventBridge partner source for a raw `git push`, so this path still needs either a GitHub Actions step that calls `aws imagebuilder start-image-pipeline-execution` directly (bypassing Terraform's trigger declaration entirely, and re-introducing a GitHub Actions workflow, just a much smaller one), or some other bridge (e.g. a webhook receiver publishing a custom EventBridge event) that was not researched here. No source consulted describes a documented, no-code path from "a GitHub push happened" to "an Image Builder pipeline started" that does not involve either GitHub Actions or a hand-built bridge.

**Verification block:** URL fetched — all three. Verbatim quote checked — yes for the schedule block and the EventBridge doc, both re-confirmed on a second read of the fetched text. The roadmap issue's JSON fields were checked once via the GitHub API and are treated as direct data, not a paraphrase. Quote substring confirmed at `### schedule` (pipeline doc) and the "Image Builder works with EventBridge in two independent directions" paragraph (EventBridge integration doc).

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| `aws_imagebuilder_image` (one-shot, directly declared) | AMI id genuinely lands in Terraform state (Finding 1); satisfies the "Terraform describes what exists" principle for creation | No rebuild without a version bump somewhere in the chain (Finding 2); `terraform destroy`/replacement does not deregister the old AMI on its own (Finding 3); loses the "just re-run to pick up a newer Canonical patch with zero code change" operation the current `workflow_dispatch` provides | Findings 1–3 |
| `aws_imagebuilder_image_pipeline` (recurring/scheduled) | Matches today's operational cadence (push/dispatch-triggered rebuilds) more closely; supports dependency-gated skip-if-unchanged builds (Finding 12) | Pipeline executions are NOT tracked in Terraform state at all — reproduces today's `data "aws_ami"` discovery problem with Image Builder standing in for Packer (Finding 1) | Finding 1, Finding 12 |
| Component content: inline `data` vs S3 `uri` | `data` needs no S3 bucket, lives directly in the `.tf` file (Finding 4) | Either form requires a new component `version` (forced replacement) to change content (Finding 2) | Finding 2, Finding 4 |
| Provisioning source: GitHub (private) vs S3 | GitHub keeps the existing repo/versioning/review workflow for the role | No native action module authenticates a private GitHub pull (Finding 6); the two official references named in the question (AWS blog + `aws-samples`) both use S3, not GitHub (Finding 5) | Findings 5–6 |
| AMI pruning: `aws_imagebuilder_lifecycle_policy` vs the current bash loop | Declarable in Terraform; can also deregister the AMI + delete the snapshot (closing part of the Finding 3 gap) | Retention counts per recipe version, not per AMI tag — a different shape than the current "3 most recent regardless of version" script if recipe versions are bumped on every apply (Finding 9) | Finding 9 |

## What remains uncertain

- Whether an `ssm:`-referenced `parent_image` is re-resolved at **every** pipeline execution or only once, at the point the recipe (or the directly-declared image) is created. The April 2025 AWS announcement says the capability lets customers "dynamically retrieve the latest base image" (Finding 7) but no source fetched states the exact resolution timing explicitly enough to settle this.
- Whether GitHub can be wired to an EventBridge rule as a native event source (as opposed to a GitHub Actions step calling the Image Builder API directly, or a custom webhook bridge) — not researched.
- Whether `aws_imagebuilder_infrastructure_configuration` (not directly researched in this spike) can express the current Packer build's subnet-selection logic (`subnet_filter { filters = { "tag:Name" = "management-pub-a" }, most_free = true, random = false }`, `mongodb.pkr.hcl:110-116`) or requires a fixed `subnet_id`.
- Whether the 20-components-per-recipe / 25KB-recipe-size limits (Finding 2's source page also states these, not separately verified against actual component-YAML size) would ever bind for this specific role — the role is small (101 lines of tasks), so likely not, but this was not measured against an actual drafted component document.
- Whether `skip_destroy` on the component resource (mentioned in the Finding 2 NOTE) meaningfully changes the destroy-orphan picture in Finding 3 for the recipe/image chain as a whole — only the component-level behavior was quoted, not traced through to the image resource.

## Suggested options for main and the engineer

- **Option A — Full Terraform ownership via `aws_imagebuilder_image`.** Satisfies the stated principle for AMI creation (Finding 1); changes the operational model to "bump a version to rebuild" (Finding 2) and needs a separate mechanism (lifecycle policy or companion `aws_ami`) to avoid orphaned AMIs on replacement (Finding 3).
- **Option B — `aws_imagebuilder_image_pipeline`, kept close to today's cadence.** Closer to the current push/dispatch trigger shape (Finding 12); does not close the stated gap — pipeline-produced AMIs remain outside Terraform state (Finding 1), so the `data "aws_ami"` lookup pattern would persist unchanged.
- **Option C — Hybrid: Terraform declares the provisioning-as-code (component, recipe, infrastructure configuration, lifecycle policy), the periodic bake stays orchestrated by a (much smaller) GitHub Actions workflow that calls the Image Builder API directly.** Retires Packer and the Ansible role repository (content becomes component YAML, per Finding 11), keeps a thin CI trigger layer; does not fully retire GitHub Actions.
- **Option D — Status quo.** Packer + Ansible role + GitHub Actions, AMI discovered via `data "aws_ami"`. Kept here only as the explicit baseline the other three options are compared against.
- **On sourcing provisioning content from GitHub specifically**: whichever option is chosen, Finding 5 and Finding 6 together mean that "pull the playbook/component from our private GitHub repo at build time" is not what either of the two official references the question named actually does, and no native authenticated path for it exists in any Image Builder action module — the only way to do it is an `ExecuteBash` step running `git clone` with credentials provisioned through some other AWS-native channel (e.g., an SSM `SecureString` read via the instance's IAM role), which is engineering built on top of what is documented, not a documented pattern itself.
