# SPIKE — `numactl` "No package matching" on Ubuntu focal 20.04 golden AMI build

## Investigation question

While baking a golden AMI with Packer + Ansible on top of Canonical's official Ubuntu 20.04 (focal) `hvm-ssd` amd64 server cloud AMI (owner `099720109477`, sa-east-1), the `apt` task `Install MongoDB prerequisites` (`name: [gnupg, numactl]`) fails on `numactl` only with `"No package matching 'numactl' is available"`, even though `apt update` genuinely runs (~18s of fetch) and the same role succeeds unmodified on Ubuntu 24.04 (noble).

Four sub-questions were posed:
1. Which repository component is `numactl` in on focal — `main` or `universe`?
2. Do Canonical's focal `hvm-ssd` server cloud AMIs ship with `universe` enabled or disabled by default?
3. Are there community reports of this exact symptom, and how was it resolved?
4. What is the canonical, idempotent Ansible-native way to enable `universe` before an apt install, if that turns out to be the cause?

## Sources consulted

- [Launchpad API — `getPublishedBinaries` for `numactl` in focal](https://api.launchpad.net/1.0/ubuntu/+archive/primary?ws.op=getPublishedBinaries&binary_name=numactl&distro_series=https://api.launchpad.net/1.0/ubuntu/focal&exact_match=true&status=Published) — authoritative, machine-readable confirmation of the package's component for every focal architecture, including amd64.
- [`launchpad.net/ubuntu/+source/numactl`](https://launchpad.net/ubuntu/+source/numactl) — human-readable publishing history, corroborates the API result.
- [`canonical/cloud-init` — `templates/sources.list.ubuntu.tmpl`](https://github.com/canonical/cloud-init/blob/main/templates/sources.list.ubuntu.tmpl) — the upstream Canonical template cloud-init uses to render `/etc/apt/sources.list` on first boot.
- [Launchpad bug #317432 — "Add multiverse to /etc/apt/sources.list" (Ubuntu on EC2, beta2)](https://bugs.launchpad.net/ubuntu-on-ec2/beta2/+bug/317432) — historical-only data point (2008/2009, predates focal by over a decade).
- [Ubuntu tutorial — "How to build your own AMI from Ubuntu Pro using Packer"](https://ubuntu.com/tutorials/how-to-build-your-own-ami-from-ubuntu-pro-using-packer) — documents a known Packer + Ubuntu cloud-image race condition around `cloud-init status --wait`.
- [`ansible/ansible` issue #58237 — "No package matching 'docker-ce' is available"](https://github.com/ansible/ansible/issues/58237) — analogous (not identical) Ansible `apt` module symptom report.
- [`ansible/ansible` issue #73156 — "No package matching 'nginx' is available"](https://github.com/ansible/ansible/issues/73156) — analogous flaky/first-boot report.
- [`ansible/ansible` issue #48714 — "apt_repository module does not allow enabling 'universe' repository"](https://github.com/ansible/ansible/issues/48714) — documents a real limitation of the Ansible-native repository-enablement path.
- [`ansible.builtin.apt_repository` module docs](https://docs.ansible.com/ansible/latest/collections/ansible/builtin/apt_repository_module.html) — module reference, no direct "universe" example found (see Finding 4).
- Attempted and inaccessible (dropped per Citation Discipline UNVERIFIED rule): `dannyda.com` (HTTP 403), `canonical-aws.readthedocs-hosted.com` (redirected to a login wall), `repost.aws` thread on IPv6-only apt updating (HTTP 403). None of these are used to sustain any Finding below.

## Findings

### Finding 1: `numactl` is published in the `main` component on focal, for every architecture including amd64 — NOT `universe`

**Evidence:** Direct JSON from the Launchpad API, re-fetched verbatim as a self-check:

```json
{"display_name": "numactl 2.0.12-1 in focal riscv64", "component_name": "main", "section_name": "admin", "source_package_name": "numactl", "source_package_version": "2.0.12-1", "distro_arch_series_link": "https://api.launchpad.net/1.0/ubuntu/focal/riscv64", "date_published": "2020-04-02T16:48:33.204445+00:00", "status": "Published", "pocket": "Release", "binary_package_name": "numactl", "binary_package_version": "2.0.12-1"}
```

A second query against the same endpoint enumerated all seven focal architecture entries; every one carries `component_name: "main"`, including the amd64 entry (`distro_arch_series_link: ubuntu/focal/amd64`, `component: main`, `pocket: Release`, published `2019-10-18T09:15:30.173940+00:00`, version `2.0.12-1`). The publishing history view on [`launchpad.net/ubuntu/+source/numactl`](https://launchpad.net/ubuntu/+source/numactl) shows the same version/date for the focal release row, labeled `(main)`.

**Source:** [Launchpad API — `getPublishedBinaries`](https://api.launchpad.net/1.0/ubuntu/+archive/primary?ws.op=getPublishedBinaries&binary_name=numactl&distro_series=https://api.launchpad.net/1.0/ubuntu/focal&exact_match=true&status=Published)

**Significance:** This directly answers Q1 and contradicts the working hypothesis in the investigation brief. `numactl` has been in `main` (not `universe`) since focal's initial release (2019-10-18 for amd64/i386/armhf/arm64/ppc64el/s390x; 2020-04-02 for riscv64), at the `Release` pocket, and has never been superseded to a different component. The `section_name: "admin"` field in the same JSON record is almost certainly the source of the earlier ambiguity described in the brief — Ubuntu package listings often display "Section: universe/admin"-style composite labels where "admin" is the *section* (a topical grouping) and is independent of the *component* (`main`/`restricted`/`universe`/`multiverse`, the field that actually gates repository enablement). Reading "admin" as evidence of "universe" conflates the two axes.

**Verification block:** URL fetched: `https://api.launchpad.net/1.0/ubuntu/+archive/primary?ws.op=getPublishedBinaries&binary_name=numactl&distro_series=https://api.launchpad.net/1.0/ubuntu/focal&exact_match=true&status=Published` / Verbatim quote checked: yes, re-fetched a second time as a self-check and the `component_name: "main"` field was confirmed present in every one of the 7 architecture entries / Quote substring confirmed at: the raw JSON `entries` array element for `distro_arch_series_link` ending in `.../focal/amd64` (and the other 6 arches).

### Finding 2: Canonical's own cloud-init template ships `universe` and `multiverse` as active (uncommented) `deb` lines by default — but this is the generic upstream template, not a confirmed dump of the specific focal server AMI's live `/etc/apt/sources.list`

**Evidence:** The `sources.list.ubuntu.tmpl` maintained in the `canonical/cloud-init` repository — the template cloud-init renders into `/etc/apt/sources.list` on first boot for Ubuntu unless overridden — contains active lines for all four components:

- `deb {{mirror}} {{codename}} main restricted`
- `deb {{mirror}} {{codename}} universe` and `deb {{mirror}} {{codename}}-updates universe`
- `deb {{mirror}} {{codename}} multiverse` and `deb {{mirror}} {{codename}}-updates multiverse`
- `deb {{mirror}} {{codename}}-backports main restricted universe multiverse`

Only the `# deb-src` lines are commented out; the `deb` lines for every component are active.

**Source:** [`canonical/cloud-init` — `templates/sources.list.ubuntu.tmpl`](https://github.com/canonical/cloud-init/blob/main/templates/sources.list.ubuntu.tmpl)

**Significance:** This is evidence *against* the "universe disabled by default on EC2" hypothesis (already made moot by Finding 1, since `numactl` doesn't live in `universe` anyway), but it does not fully answer Q2 as posed. I could not obtain an authoritative, reproducible dump of the *actual* `/etc/apt/sources.list` on a freshly-booted focal `hvm-ssd server` AMI in `sa-east-1` — the two most promising leads (`canonical-aws.readthedocs-hosted.com`, an AWS re:Post thread on Ubuntu EC2 + apt behavior) were inaccessible (login wall / HTTP 403) and are excluded from evidence per Citation Discipline. **UNVERIFIED: whether the specific `hvm-ssd` server AMI in sa-east-1 renders this exact template unmodified, or whether Canonical bakes a different/pre-rendered `sources.list` directly into the image at build time** (e.g. via `livecd-rootfs`) that could, in principle, diverge from the generic cloud-init template. The one historical data point found (Launchpad bug #317432, 2008/2009) concerned `multiverse` being absent on an EC2 *beta* image and was resolved by preinstalling the needed tool rather than enabling the repo — it predates focal by over a decade and is not evidence about focal's default.

**Verification block:** URL fetched: `https://github.com/canonical/cloud-init/blob/main/templates/sources.list.ubuntu.tmpl` / Verbatim quote checked: yes / Quote substring confirmed at: the `deb {{mirror}} {{codename}} universe` and `deb {{mirror}} {{codename}} multiverse` lines in the template body.

### Finding 3: No community report of the exact `numactl` + focal + EC2/Packer symptom was found; analogous (not identical) Ansible `apt` module "No package matching" reports exist and skew toward transient/first-boot flakiness

**Evidence:** Targeted searches combining `numactl`, `focal`/`20.04`, `EC2`, `packer`, and `ansible` returned no report of this exact combination — this sub-question is **not found / UNVERIFIED as an exact match**. Two analogous reports on the Ansible `apt` module exist for *other* packages:

- Issue #58237: a user reports `"No package matching 'docker-ce' is available"` on armv7/Armbian even though `apt-cache show docker-ce` and manual `apt install docker-ce` both succeed — i.e., the package is visibly present via the CLI tooling but the Ansible module's own package-lookup path reports it missing. No maintainer root-cause explanation is present in the issue.
- Issue #73156: a user reports `"No package matching 'nginx' is available"` occurring **randomly on newly created machines**, with the playbook already running `update_cache` before the install, and **re-running the same playbook typically succeeds**. No maintainer root-cause explanation is present in the issue.

Separately, a related but distinct Packer+Ubuntu-cloud-image gotcha is documented by Canonical directly: a shell provisioner running `cloud-init status --wait` before any `apt`/Ansible provisioner, because — per the tutorial — *"If you skip this line, you may have errors during the build process, since the Ubuntu Advantage client needs to change configurations and repositories right after booting."* The example shell provisioner in that tutorial is:

```json
{
  "type": "shell",
  "inline": [
    "cloud-init status --wait",
    "sudo apt-get update && sudo apt-get upgrade -y"
  ]
}
```

**Source:** [ansible/ansible#58237](https://github.com/ansible/ansible/issues/58237), [ansible/ansible#73156](https://github.com/ansible/ansible/issues/73156), [Ubuntu tutorial — Packer AMI from Ubuntu Pro](https://ubuntu.com/tutorials/how-to-build-your-own-ami-from-ubuntu-pro-using-packer)

**Significance:** None of these three sources reproduces the exact `numactl`/focal/EC2 symptom, so Q3 cannot be answered with a matching report — this is stated as an explicit gap, not filled with a guess. What they establish, as a pattern rather than a proof, is that (a) the Ansible `apt` module's own package-lookup path has multiple independent, unexplained reports of reporting a package as unavailable when other tooling on the same machine sees it fine, and (b) a **freshly booted Ubuntu cloud image running cloud-init** is a documented context where package-manager state can still be in flux immediately after boot, specifically because cloud-init itself performs apt/repository-related work on first boot (Ubuntu Advantage/Pro client, in the cited case) that can race with a provisioner connecting too early. This second point is directly relevant to a Packer build, since Packer connects and starts provisioning as soon as SSH is reachable, which can be before cloud-init's own first-boot work has finished.

**Verification block:** URL fetched: all three / Verbatim quotes checked: yes for all three / Quote substrings confirmed at: the issue body / title text for #58237 and #73156, and the shell provisioner block + explanatory sentence in the Ubuntu tutorial page.

### Finding 4: The Ansible-native `apt_repository` module cannot enable `universe` by its short name — it requires the full `deb` line, and a plain `repo: universe` value is a documented failure mode

**Evidence:** GitHub issue #48714 against `ansible/ansible` reports: *"apt_repository does not support enabling built-in repositories, like 'universe'"*, with the module raising `"Invalid repository string: universe"` (an `InvalidSource` exception from the module's `_parse` method) when given the bare component name. No maintainer resolution or built-in shortcut is recorded on that issue as fetched. The corroborating pattern found via web search (community blog/tutorial content, not independently re-fetched and therefore not cited as a Finding on its own) is that the module is used with a full repository line instead, of the shape `repo: deb http://archive.ubuntu.com/ubuntu focal universe`, `state: present`.

**Source:** [ansible/ansible#48714](https://github.com/ansible/ansible/issues/48714)

**Significance:** Answers Q4's gotcha half directly: if `universe` enablement were ever needed as a belt-and-suspenders measure (notwithstanding Finding 1), the idiomatic `ansible.builtin.apt_repository` task must pass the **full `deb` line** (mirror + codename + component), not the bare word `universe` — the bare form is a confirmed, reproducible module error, not a hypothetical. The module reference page itself does not carry a "how to enable universe" example, so this specific gotcha is not obvious from the docs alone.

**Verification block:** URL fetched: `https://github.com/ansible/ansible/issues/48714` / Verbatim quote checked: yes / Quote substring confirmed at: the issue's reported error text `"Invalid repository string: universe"` and description text `"apt_repository does not support enabling built-in repositories, like 'universe'"`.

## Analysis (inference from the engineer-supplied facts, not externally sourced)

The following is a deduction from facts already established in the investigation brief, not a cited external claim — flagged separately per Citation Discipline (claims must be either quote-backed or explicitly marked as the spike's own reasoning):

Given Finding 1 (`numactl` is `main`, same as `gnupg`), the fact that `gnupg` resolves while `numactl` does not is not explained by component/repository enablement — both are in the same component. A structural asymmetry between the two packages that the brief itself supplies is: `gnupg` is preinstalled on the base image (present in `dpkg`'s status database) while `numactl` is not. `python-apt`'s `Cache` object (which the Ansible `apt` module's lookup path relies on) can resolve an already-installed package's identity from the local `dpkg` status database even when the downloaded `Packages` index for that component is incomplete, partial, or not yet fully parsed — whereas a **not-yet-installed** package like `numactl` can only be found via the downloaded index. If the apt index fetch that "genuinely runs (~18s)" completed on the wire but the specific in-memory `Cache` object the Ansible module opened was built from an inconsistent or partially-written `/var/lib/apt/lists` snapshot (the kind of window a concurrent cloud-init-driven apt operation on first boot could produce), a package already known to `dpkg` would still resolve while a package that depends entirely on the index would not. This is offered as one candidate mechanism consistent with the observed asymmetry, not a proven root cause — it has not been confirmed against this specific build's logs or instance state.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| Diagnose live on a fresh instance from the exact same AMI (`cloud-init status`, `cat /etc/apt/sources.list`, `apt-cache policy numactl`, `apt list -a numactl`, check `/etc/apt/preferences.d`) before changing anything | Confirms or refutes every hypothesis above with direct evidence from the actual environment; costs one instance-boot | Takes a diagnostic cycle before any fix lands | Not sourced — general diagnostic practice, consistent with Findings 1–3 pointing away from a repository-enablement cause |
| Add a `cloud-init status --wait` step before the Ansible provisioner runs | Directly targets the documented Packer+Ubuntu-cloud-image race condition (Finding 3); Canonical's own recommended pattern | Adds boot-time latency to every build; does not fix the issue if the root cause is unrelated to cloud-init timing | [Ubuntu tutorial — Packer AMI from Ubuntu Pro](https://ubuntu.com/tutorials/how-to-build-your-own-ami-from-ubuntu-pro-using-packer) |
| Add `retries`/`until` around the `apt` task (or a second `apt: update_cache: true` retry) to survive a transient/partial cache state | Cheap, idempotent, does not require root-causing the exact mechanism | Papers over the underlying cause instead of explaining it; if the cause is deterministic (not transient) it will not help | Not sourced — general Ansible resilience pattern |
| Explicitly enable `universe` via `ansible.builtin.apt_repository` with a full `deb` line, as insurance | Cheap; removes the`universe`-disabled hypothesis from consideration entirely regardless of what the actual AMI ships | Finding 1 shows this is very unlikely to be the actual cause for `numactl` specifically, so this would not explain or necessarily fix the observed failure; the module requires the full line, not the bare word (Finding 4) | [Launchpad API](https://api.launchpad.net/1.0/ubuntu/+archive/primary?ws.op=getPublishedBinaries&binary_name=numactl&distro_series=https://api.launchpad.net/1.0/ubuntu/focal&exact_match=true&status=Published) (Finding 1), [ansible/ansible#48714](https://github.com/ansible/ansible/issues/48714) (Finding 4) |

## What remains uncertain

- Whether the specific `hvm-ssd` server focal AMI in sa-east-1 renders `/etc/apt/sources.list` from the unmodified upstream cloud-init template (Finding 2) — not directly confirmed; the two most relevant sources were inaccessible.
- The exact mechanism causing `numactl` (and only `numactl`) to be reported unavailable — no source reproduces this exact symptom (Finding 3); the "Analysis" section above is this spike's own inference from the given facts, not an externally verified root cause.
- Whether this build's Packer template already includes (or omits) a `cloud-init status --wait`-equivalent step before the Ansible provisioner connects — this was not inspected as part of this spike (no repository path was provided) and would need to be checked in the actual Packer/Ansible source to know whether Finding 3's race-condition hypothesis is even applicable.
- Whether the failure is fully deterministic (happens on every build) or intermittent — the brief states the noble build succeeds and the focal build fails, but does not state whether the focal failure has been observed more than once, which bears on whether "transient race condition" or "deterministic misconfiguration" is the more likely category.

## Suggested options for main and the engineer

- Option A: Before changing any code, SSH into (or Packer-shell into) a fresh instance of the exact same AMI and run the direct diagnostics listed in the trade-off table — this converts every "UNVERIFIED" and "uncertain" item above into a confirmed fact specific to this build, and is the only path that can confirm the actual root cause rather than a plausible candidate.
- Option B: Add a `cloud-init status --wait` shell provisioner ahead of the Ansible provisioner, on the strength of Finding 3's documented Packer+Ubuntu race condition, without waiting for Option A's diagnostic.
- Option C: Add retry/backoff around the failing `apt` task as a resilience measure, independent of root-causing the mechanism.
- Option D: Add explicit `universe` enablement via `apt_repository` (full `deb` line per Finding 4) as low-cost insurance, while treating Finding 1 as strong evidence this alone will not explain or fix the `numactl`-specific failure.

These options are not mutually exclusive and are not ranked — the choice of which to pursue first (or in combination) is the engineer's.
