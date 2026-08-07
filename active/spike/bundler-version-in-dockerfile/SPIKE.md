# SPIKE — Bundler Version Pinning in Ruby Application Dockerfiles

## Investigation question

In a Ruby application Docker image, should the Bundler version be pinned explicitly (`RUN gem install bundler -v X.Y.Z`), or should the image rely on the Bundler that the official `ruby:X.Y.Z` base image already ships as its default? Is there an established way to make the Dockerfile derive the Bundler version from the `BUNDLED WITH` section of `Gemfile.lock`, so the two can never disagree?

Context that framed the research (established by the engineer, not re-derived here): four 4Shark Rails repositories run Ruby 4.0.6 via `ARG RUBY_VERSION=4.0.6` / `FROM ruby:${RUBY_VERSION}` (Renovate-tracked), each followed by a hardcoded `RUN gem install bundler -v 2.7.1` (or `2.6.3`) that nothing tracks. Three of the four repos' `Gemfile.lock` now carry `BUNDLED WITH 4.0.x` (rewritten by engineers on machines where Ruby 4.0.6's default Bundler is 4.0.16) while the image installs 2.x — a divergence that entered through unrelated commits.

## Sources consulted

- [rails/rails `Dockerfile.tt` generator template](https://raw.githubusercontent.com/rails/rails/main/railties/lib/rails/generators/rails/app/templates/Dockerfile.tt) — the actual Dockerfile `rails new` generates since Rails 7.1; fetched raw, no summarization risk. See auxiliary `bundler-version-in-dockerfile_excerpt_1.dockerfile`.
- [docker-library/ruby `4.0/bookworm/Dockerfile`](https://raw.githubusercontent.com/docker-library/ruby/master/4.0/bookworm/Dockerfile) — the current official image build recipe for the exact Ruby 4.0.6/bookworm family 4Shark uses; fetched raw. See auxiliary `bundler-version-in-dockerfile_excerpt_2.dockerfile`.
- [docker-library/ruby PR #255](https://github.com/docker-library/ruby/pull/255) — the PR that removed `BUNDLER_VERSION` from the official images (merged 2019-01-04), with maintainer reasoning.
- [docker-library/ruby issue #246](https://github.com/docker-library/ruby/issues/246) — the original bug report that led to PR #255.
- [rubygems/bundler issue #6782](https://github.com/rubygems/bundler/issues/6782) — corroborating report of the same `BUNDLER_VERSION` problem, filed against the Bundler repo.
- [ruby/rubygems PR #4076](https://github.com/ruby/rubygems/pull/4076) — implementation of the `BUNDLED WITH` auto-install/re-exec feature.
- [RubyGems blog — "Bundler v2.3: Locking the version of Bundler itself"](https://blog.rubygems.org/2022/01/23/bundler-v2-3.html) — the official announcement of the feature, with exact mechanics and version requirements.
- [Heroku Dev Center — "Bundler Version Considerations"](https://devcenter.heroku.com/articles/bundler-version) — a major Ruby deployment platform's documented policy on which Bundler version it installs and why.
- [GitLab `gitlab-build-images` MR !819](https://gitlab.com/gitlab-org/gitlab-build-images/-/merge_requests/819) — GitLab dropping its own explicit Bundler-version install step from its build images.
- [Netlify community forum — "Builds: Bundler version from Gemfile.lock now installed and used"](https://answers.netlify.com/t/builds-bundler-version-from-gemfile-lock-now-installed-and-used/5561) — a third platform's announcement of the same lockfile-driven behavior.
- [ruby/ruby commit `59c8d50`](https://github.com/ruby/ruby/commit/59c8d50653480bef3f24517296e6ddf937fdf6bc) — the commit that made Bundler a default gem of Ruby itself.
- [guides.rubygems.org — "Default gems and bundled gems"](https://guides.rubygems.org/default-gems-and-bundled-gems/) — the definitional distinction between the two gem categories.
- [Josh McArthur — "Docker: You must use Bundler 2 or greater with this lockfile"](https://www.joshmcarthur.com/til/2021/01/27/docker-you-must-use-bundler-2-or-greater-with-this-lockfile.html) — a documented, hand-rolled recipe for deriving the Bundler version from `Gemfile.lock` inside a Dockerfile, with its own reported caveat.
- [DEV Community — "How to add a specific version of bundler to your Ruby Dockerfile"](https://dev.to/seedyrom/how-to-add-a-specific-version-of-bundler-to-your-ruby-dockerfile-5chl) — representative "pin it by hand" recipe.
- [Medium — "Docker Rails Fix Bundler 2 problem"](https://nrogap.medium.com/docker-rails-fix-bundler-2-problem-e49a961cbd9d) — a second representative "pin it by hand" recipe.
- [ruby/rubygems issue #8265](https://github.com/ruby/rubygems/issues/8265) — request to expose `--local`/`--prefer-local` install options as config; cited in "What remains uncertain" as adjacent evidence that the offline-install problem space exists. Does not itself confirm or deny the `BUNDLED WITH` auto-install's network behavior — no claim in this spike is sustained by it beyond naming the open question.
- See auxiliary `bundler-version-in-dockerfile_excerpt_1.dockerfile` and `bundler-version-in-dockerfile_excerpt_2.dockerfile` — full raw Dockerfile text preserved for re-derivation without a re-fetch.

## Findings

### Finding 1: Rails' own generated Dockerfile does not pin Bundler at all

**Evidence:**
```dockerfile
ARG RUBY_VERSION=<%= Gem.ruby_version %>
FROM docker.io/library/ruby:$RUBY_VERSION-slim AS base
...
COPY vendor/* ./vendor/
COPY Gemfile Gemfile.lock ./

RUN bundle install && \
```
No `ARG BUNDLER_VERSION`, `ENV BUNDLER_VERSION`, or `gem install bundler -v ...` line exists anywhere in the template that precedes or follows this `bundle install` call. A direct substring search confirms neither `ARG BUNDLER_VERSION` nor `gem install bundler` appears anywhere in the full file.

**Source:** `railties/lib/rails/generators/rails/app/templates/Dockerfile.tt` in `rails/rails`, fetched raw at `https://raw.githubusercontent.com/rails/rails/main/railties/lib/rails/generators/rails/app/templates/Dockerfile.tt` on 2026-08-06, fetched twice.

**Significance:** This is the Dockerfile every `rails new` invocation has produced since Rails 7.1 shipped Docker support by default. It pins `RUBY_VERSION` the same way 4Shark's repos do, but carries no equivalent mechanism for Bundler — the framework's own reference implementation relies on whatever the base image ships plus `bundle install`'s own version-reconciliation behavior (Finding 4).

**Verification:** URL fetched directly as raw file content (not HTML-rendered), twice / quote is the literal file text on both fetches / confirmed present at the `ARG RUBY_VERSION` through `RUN bundle install &&` span of the file, full text preserved in `bundler-version-in-dockerfile_excerpt_1.dockerfile`.

### Finding 2: The current official Ruby 4.0/bookworm image sets no `BUNDLER_VERSION` and installs no explicit Bundler version

**Evidence:** the full current Dockerfile for the `4.0/bookworm` tag family builds Ruby from source (`./configure`, `make`, `make install`) and its only Bundler-related line is a smoke test with no version argument:
```
	ruby --version; \
	gem --version; \
	bundle --version
```
No `ENV BUNDLER_VERSION` line and no `RUN gem install bundler` line appear anywhere in the file. A direct substring search confirms both "BUNDLER_VERSION" and "gem install bundler" are absent from the file.

**Source:** `4.0/bookworm/Dockerfile` in `docker-library/ruby`, fetched raw at `https://raw.githubusercontent.com/docker-library/ruby/master/4.0/bookworm/Dockerfile` on 2026-08-06, fetched twice.

**Significance:** whatever Bundler ends up in the image is exactly whatever Ruby 4.0.6's source tree bundles as its own default gem — the image build performs no independent Bundler installation step. This matches the engineer's own observation (`gem list bundler` reporting `bundler (default: 4.0.16, 2.7.1)`) — `4.0.16` is what the base image itself would contain absent the repos' extra `RUN gem install bundler -v 2.x` line; `2.7.1` is the extra line's product.

**Verification:** URL fetched twice, directly as raw file content / quote is the literal file text / confirmed absent on both fetches via direct substring search, full text preserved in `bundler-version-in-dockerfile_excerpt_2.dockerfile`.

### Finding 3: `BUNDLER_VERSION` was deliberately removed from docker-library/ruby in 2019, and a maintainer's stated reason was to make the base image track "whatever comes with the Ruby release"

**Evidence:** commenting on the PR that removed the `BUNDLER_VERSION` environment variable from the official images, GitHub user `indirect` wrote:

> "As a RubyGems and Bundler maintainer, I think having the base Ruby image ship with just Ruby (and the RubyGems+Bundler that came with that Ruby) definitely seems like the solid conservative/compatible choice to me."

and, on why an application should not expect the base image to carry an independently-updated Bundler:

> "I feel like people who want specific RubyGems or Bundler versions are probably better off adding their own `RUN` commands to their own Dockerfiles anyway, probably?"

**Source:** `https://github.com/docker-library/ruby/pull/255`, fetched three times (2026-08-06) with consistent results each time.

**Significance:** this is the design rationale from inside the project that maintains the base image 4Shark's Dockerfiles start from, from a commenter who identifies themselves in the same comment as "a RubyGems and Bundler maintainer" — a self-identification present in the fetched source itself, not inferred. It frames the base image's own philosophy as "ship whatever Ruby ships" — silent on whether an *application's* Dockerfile should add its own Bundler-pinning `RUN` line, but explicit that doing so is a decision left to the application, not something the base image should pre-empt or that an application should assume the base image handles for it.

**Verification:** URL fetched three times / verbatim quotes checked on each fetch / quote substrings "solid conservative/compatible choice to me" and "adding their own `RUN` commands to their own Dockerfiles" confirmed present in the PR discussion content on all fetches.

### Finding 4: Since Bundler 2.3 (with RubyGems ≥ 3.3), `bundle install` auto-installs and re-execs into the exact `BUNDLED WITH` version from `Gemfile.lock`, independent of what Bundler version is already present

**Evidence:**

> "In Bundler 2.3 and up (if you also have RubyGems 3.3 or higher), running `bundle install` will use the exact version from the BUNDLED WITH section of the lockfile."

and, on what happens when that version is not yet installed:

> "the running version of Bundler will install the locked version, and then run your original command using the newly-installed locked version."

**Source:** RubyGems Blog, "Bundler v2.3: Locking the version of Bundler itself", `https://blog.rubygems.org/2022/01/23/bundler-v2-3.html`, fetched twice with consistent results.

**Significance:** this is the official, primary-source description of the mechanism the investigation question asked about directly ("is there an established way to derive the Bundler version from `BUNDLED WITH`"). The mechanism already exists inside Bundler/RubyGems itself, is not a Dockerfile-authored recipe, and is unconditional once the two version prerequisites (Bundler ≥ 2.3, RubyGems ≥ 3.3) are met — both of which are satisfied by a Ruby 4.0.6 install carrying Bundler 4.0.16 as default, and satisfied for the pinned 2.7.1 as well (2.7.1 > 2.3, and it ships with a RubyGems ≥ 3.3-compatible release line).

**Verification:** URL fetched twice / verbatim quote checked on both fetches / quote substring "will use the exact version from the BUNDLED WITH section" confirmed present at the section of the post describing the Bundler 2.3 feature on both fetches.

### Finding 5: Bundler is a Ruby "default gem" — its version is synced from the `bundler/bundler` project into the Ruby core tree at Ruby release time, not decided by the Docker image maintainers

**Evidence:** the commit that established this classification, quoted verbatim from its commit message:

> "Added bundler as default gems. Revisit [Feature #12733]"

with the change further described, in the same commit message, as:

> "Merge from latest stable branch of bundler/bundler repository and added workaround patches. I will backport them into upstream."

and, naming the sync mechanism between the two projects:

> "tool/sync_default_gems.rb: Added sync task for bundler."

Definitionally, per RubyGems' own guide (a different source, cited separately):

> "Gems that are part of Ruby and you can always require them directly"

**Source:** `https://github.com/ruby/ruby/commit/59c8d50653480bef3f24517296e6ddf937fdf6bc` (commit message, fetched twice) and `https://guides.rubygems.org/default-gems-and-bundled-gems/` (default-gem definition, fetched twice). The guides.rubygems.org page mentions "Bundler" repeatedly elsewhere on the page — in guide titles such as "How to use Bundler with Docker", and in a comparison-table row reading "When using Bundler, you need to declare them in your Gemfile" — but nowhere on the page does it itself state that Bundler is a default gem; that specific classification rests on the ruby/ruby commit alone, and the guide page supplies only the general default-vs-bundled vocabulary the commit's classification is measured against.

**Significance:** the default Bundler version that ships with a given Ruby release (e.g. 4.0.16 for Ruby 4.0.6) is not something `docker-library/ruby` selects or that changes independently of a Ruby version bump — it travels with the Ruby source tree itself, following Finding 2's confirmation that the image build performs no separate Bundler installation step.

**Verification:** URLs fetched twice each / verbatim quotes checked / quote substrings "Added bundler as default gems", "Merge from latest stable branch of bundler/bundler repository", and "tool/sync_default_gems.rb: Added sync task for bundler" all confirmed present in the commit message on both fetches; quote substring "part of Ruby and you can always require them directly" confirmed present on the guides.rubygems.org page on both fetches.

### Finding 6: Three independent deployment/build platforms (Heroku, GitLab, Netlify) install exactly the `BUNDLED WITH` version from the lockfile as their platform behavior — none of them ship a platform-level pinned Bundler that an application's lockfile must match

**Evidence (Heroku):**

> "The same bundler version found in your `Gemfile.lock` under the `BUNDLED WITH` key will be installed and used."

**Source:** `https://devcenter.heroku.com/articles/bundler-version`, fetched twice with consistent results.

**Evidence (GitLab, explaining why its build-images repo dropped its own hardcoded Bundler install step):**

> "Starting with Bundler v2.3, Bundler automatically installs the version needed in `Gemfile.lock` if it's not installed already"

**Source:** `https://gitlab.com/gitlab-org/gitlab-build-images/-/merge_requests/819`, fetched twice with consistent results.

**Evidence (Netlify):**

> "The Bundler version specified in the `BUNDLED_WITH` section of your `Gemfile.lock` file is now automatically installed and used to install the gems from your Gemfile."

**Source:** `https://answers.netlify.com/t/builds-bundler-version-from-gemfile-lock-now-installed-and-used/5561`, fetched twice with consistent results.

**Significance:** these are three separate, independently-operated platforms (a PaaS, a CI/build-image maintainer, a static-site/JAMstack build platform) converging on the same policy — trust `Gemfile.lock`'s `BUNDLED WITH` as the single source of truth for which Bundler runs, rather than maintaining their own pinned version that the lockfile must be kept in sync with by hand. Each is a separate Finding-sustaining source (per the one-source-per-claim rule), not a composite citation.

**Verification (all three):** URLs fetched twice each / verbatim quotes checked / quote substrings confirmed present at each source on every fetch: "will be installed and used" (Heroku), "automatically installs the version needed in `Gemfile.lock`" (GitLab MR), "automatically installed and used to install the gems" (Netlify).

### Finding 7: A hand-rolled Dockerfile recipe for deriving the Bundler version from `Gemfile.lock` exists and is documented, with a specific caveat that the fix only holds at build time and reverts afterward

**Evidence:**
```
RUN unset BUNDLER_VERSION &&\
    gem install bundler -v "$(grep -A 1 "BUNDLED WITH" Gemfile.lock | tail -n 1)" &&\
    echo $(bundle --version) &&\
    bundle install
```
and, on why the fix needs a second, runtime-side piece:

> "this works when building the image, but not when using bundle after that (it reverts to trying to use the old version)."

with the author's follow-up being a `docker-entrypoint.sh` that re-exports `BUNDLER_VERSION` from `Gemfile.lock` at container start, because otherwise the image's baked-in `BUNDLER_VERSION` environment variable overrides the freshly-installed one on every subsequent `bundle` invocation. The author states directly that they "ended up not being able to find a solution for this in the Dockerfile" itself, hence the separate entrypoint script.

**Source:** `https://www.joshmcarthur.com/til/2021/01/27/docker-you-must-use-bundler-2-or-greater-with-this-lockfile.html`, fetched twice (2026-08-06) — once for the article's full raw text, once confirming the code snippet independently. Both the `grep -A 1 "BUNDLED WITH" Gemfile.lock | tail -n 1` snippet and the entrypoint script text are confirmed present in the article as fetched; a line-wrap in the rendered fetch output (the `tail -n` / `1)` split across two lines) is a rendering artifact of the fetch tool, not a claim about the article's own formatting.

**Significance:** this is an actual `grep`-from-`Gemfile.lock` recipe of the shape the investigation question asked about, and it is a real, documented practice — but it is a workaround for a problem (the base image setting `BUNDLER_VERSION`) that Finding 2 and Finding 3 show no longer exists in the current official image for the Ruby line 4Shark runs. The recipe's own caveat (the `unset` only holding for the build stage, requiring an entrypoint-level re-export because the image's `BUNDLER_VERSION` reverts the effective version afterward) was specifically a consequence of that now-removed `BUNDLER_VERSION` default. This dated recipe (2021) predates confirmation of the 2019 removal reaching wide awareness; it targets exactly the failure mode Finding 3 documents as fixed at the image level.

**Verification:** URL fetched twice / verbatim quote checked on both fetches / quote substring "this works when building the image, but not when using bundle after that (it reverts to trying to use the old version)" confirmed present in the article's follow-up section on both fetches; the `grep -A 1 "BUNDLED WITH" Gemfile.lock | tail -n 1` code snippet independently re-confirmed present in the same fetch.

### Finding 8: The "pin it explicitly" recipes found do not carry a stated rationale beyond "this made the error go away"

**Evidence:** a representative recipe:
```
ENV BUNDLER_VERSION=2.1.4
RUN gem install bundler:2.1.4
```
with no accompanying explanation of why this approach was chosen over deriving the version from the lockfile or relying on the base image's default.

**Source:** `https://nrogap.medium.com/docker-rails-fix-bundler-2-problem-e49a961cbd9d`, fetched twice with consistent results.

A second, structurally identical recipe:
```
ENV BUNDLER_VERSION='X.X.X'
RUN gem install bundler --no-document -v 'X.X.X'
```
with the only caveat given being to "replace `X.X.X` with whatever version you're expecting" — again with no rationale for hardcoding over deriving.

**Source:** `https://dev.to/seedyrom/how-to-add-a-specific-version-of-bundler-to-your-ruby-dockerfile-5chl`, fetched twice with consistent results.

**Significance:** both are individual-blog-post-level "here is what fixed my build" recipes, not platform or maintainer guidance. They are two separate sources, cited separately per the one-source-per-claim rule; neither argues against the lockfile-derivation or default-reliance approaches — they simply do not consider them. Weighed against Findings 1, 4, 6, and 7 (Rails' own generator, the built-in Bundler mechanism, three independent platforms, and a lockfile-derivation recipe that exists specifically to avoid this hardcoding), this is the weaker-evidenced side of the comparison — its prevalence in search results reflects how often people hit the error and blog the first fix that worked, not an argued position.

**Verification:** both URLs fetched twice each / verbatim quotes checked / quote substrings "gem install bundler:2.1.4" and "gem install bundler --no-document -v" confirmed present at their respective sources on every fetch.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Hardcode `RUN gem install bundler -v X.Y.Z` (4Shark's current shape) | Explicit, visible in the Dockerfile; build does not depend on network access to `rubygems.org` for a *different* Bundler at deploy time beyond this one line | Nothing ties `X.Y.Z` to `Gemfile.lock`'s `BUNDLED WITH` — the exact divergence 4Shark hit; every unrelated commit that runs `bundle update --bundler` or bumps Rails on a machine with a newer default Bundler silently drifts the lockfile away from the pin, and nothing detects it until an engineer notices or a build breaks | Finding 8 (recipes with no stated rationale); the 4Shark-observed incident described in the investigation question |
| Rely on the base image's default Bundler, no Dockerfile-side pin at all | Zero maintenance surface for Bundler specifically; matches Rails' own generated Dockerfile (Finding 1); matches the base-image maintainers' stated philosophy (Finding 3); the running Bundler auto-reconciles against `Gemfile.lock`'s `BUNDLED WITH` on every `bundle install` via the built-in mechanism (Finding 4), which is the same mechanism Heroku, GitLab, and Netlify's platform behavior already delegates to (Finding 6) | If `Gemfile.lock`'s `BUNDLED WITH` and the base image's default Bundler ever disagree, `bundle install` auto-installs the locked version at build time — which Finding 4's own wording confirms happens via installing the missing version, an operation whose network-access requirement was not independently verified in this spike (see "What remains uncertain") | Findings 1, 3, 4, 6 |
| Derive the pinned version from `Gemfile.lock`'s `BUNDLED WITH` inside the Dockerfile (`grep`/`sed`-based extraction into `gem install bundler -v "$(...)"`) | Keeps an explicit `RUN` line (some teams may want the image to name the version it is building, e.g. for build-log legibility or layer-cache reasoning) while never letting it disagree with the lockfile, because it reads the lockfile at build time | Requires `Gemfile.lock` to be `COPY`'d into the build context *before* this line, which constrains Dockerfile layer ordering; the one documented real-world recipe found (Finding 7) needed a second, runtime-side fix (`docker-entrypoint.sh`) for a problem specific to the (now-removed, per Finding 3) `BUNDLER_VERSION` default in older base images — whether that runtime-side complication still applies to the current base image was not established in this spike | Finding 7 |

## What remains uncertain

- **Whether the built-in `BUNDLED WITH` auto-install (Finding 4) requires network access to `rubygems.org` during a Docker build**, and whether that would fail in a network-restricted build stage. A `gem install` of any kind ordinarily reaches out to a configured gem source unless a local cache is pre-populated, and the auto-install described in Finding 4 is described as "install the locked version" with no documented offline-only mode found in this research. This spike found adjacent material (`ruby/rubygems` issue #8265, on exposing `--local`/`--prefer-local` as config options for offline installs) that shows the general problem space exists, but did not find a source directly confirming or denying that the `BUNDLED WITH` auto-install path specifically respects `BUNDLE_DEPLOYMENT` or offline-only settings — so this is marked UNVERIFIED and not used to sustain any option above. Not found: a direct, quotable confirmation either way.
- **Whether the recipe in Finding 7 (grep-based extraction from `Gemfile.lock`) still needs its documented `docker-entrypoint.sh` runtime workaround against the current (2026) official Ruby images**, now that Finding 3 shows `BUNDLER_VERSION` was removed from the image in 2019. The 2021-dated article predates independent confirmation that this problem class was already fixed at the image level; nothing in this research re-tested the recipe against a current `ruby:4.0.6` image build.
- **Whether 4Shark's own build pipeline (CI runners, ECR build stage) enforces `BUNDLE_DEPLOYMENT`/`--frozen` in a way that would reject an auto-install-triggered Bundler switch mid-build**, or whether it would simply proceed. This spike did not read the four repos' actual Dockerfiles or CI workflow files — it answered the question as posed (community/authoritative-source research), not as a codebase audit of the four repos' current build configuration.
- **Whether the pinned-2.x recipe currently in place ever produces a hard failure versus a silent auto-upgrade** in the observed divergence (lockfile says 4.0.x, image installs 2.x). Reasoning from Findings 2 and 4 together suggests that a plain `bundle install` in that state would trigger the auto-install-and-re-exec described in Finding 4 (making the pinned `gem install bundler -v 2.7.1` step moot rather than fatal), but this is an inference from the two Findings, not something a single source stated directly about this exact scenario — flagged here rather than presented as a Finding.

## Suggested options for main and the engineer

- **Option A — remove the explicit `RUN gem install bundler -v X.Y.Z` line entirely** and let `bundle install` run against whatever Bundler the base image ships, trusting the built-in `BUNDLED WITH` auto-install/re-exec (Finding 4) to reconcile any difference against `Gemfile.lock` on every build. This is the shape of Rails' own generated Dockerfile (Finding 1) and matches the stated design philosophy of the base-image maintainers (Finding 3) and the observed platform behavior of Heroku, GitLab, and Netlify (Finding 6).
- **Option B — replace the hardcoded version with a `Gemfile.lock`-derived one**, e.g. `RUN gem install bundler -v "$(grep -A 1 'BUNDLED WITH' Gemfile.lock | tail -n 1)"` (Finding 7's shape), ensuring `Gemfile.lock` is `COPY`'d before this line runs. This keeps an explicit, logged `gem install bundler` step in the build output while making it structurally impossible for the pin to disagree with the lockfile — at the cost of a layer-ordering constraint and an unverified question about whether the reported runtime `BUNDLER_VERSION`-persistence caveat (Finding 7) still applies to current base images (see "What remains uncertain"). Finding 7's evidence — a documented recipe whose build-time fix needed a separate runtime workaround for a since-removed base-image default — is a verified quote from a re-fetched source, so this option stands on that evidence; the open question limiting it is scoped narrowly to whether the runtime workaround still applies to current base images, not to whether the recipe itself exists or works at build time.
- **Option C — keep the current hardcoded-pin shape but add a build-time or CI check that fails when the pinned version and `Gemfile.lock`'s `BUNDLED WITH` disagree**, functioning as a guard rather than a derivation. No source in this research described this specific pattern; it is offered as a structurally distinct alternative that keeps today's Dockerfile shape while closing the drift gap the investigation question is about — it was not found as an established community practice and is not sustained by any Finding above.
