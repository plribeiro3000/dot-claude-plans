# SPIKE — MongoDB Upgrade Cadence and Automation

## Investigation question

4Shark runs 4 self-managed MongoDB PSA (Primary-Secondary-Arbiter) replica sets on EC2 (Ubuntu 20.04 focal), built from a Packer golden AMI, with the Ansible role pinned by tag in a separate repo. Renovate is self-hosted with `minimumReleaseAge: 7 days`. The fleet just reached MongoDB 8.0.26 / FCV 8.0. Sets are not sharded; arbiters carry no data.

The investigation answers six sub-questions with cited, verified external sources (MongoDB official docs first, then reputable community/vendor sources):

1. What are MongoDB's "Major" vs "Rapid"/"Minor" releases, their support lifetimes, and is there a published EOL calendar (including 8.0's EOL date)?
2. Does MongoDB/the community recommend automatic patch-version updates on a production replica set, and are `mongodb-org` apt packages pinned by default?
3. What is the community/official-sanctioned procedure for upgrading a self-managed replica set — in-place rolling binary upgrade, or replace-the-node?
4. Must major-version upgrades be sequential (no skipping), what does `setFeatureCompatibilityVersion` (FCV) do, and what is the documented binary/FCV compatibility tolerance?
5. What does the community say about immutable-infrastructure/golden-image patterns for stateful services (databases) specifically?
6. How does Renovate classify and gate updates by semver level (major/minor/patch), and what config options exist to gate majors specifically?

This spike returns findings only — no recommendation is made. Main and the engineer decide.

## Sources consulted

- [MongoDB Versioning — Database Manual](https://www.mongodb.com/docs/manual/reference/versioning/) — official definition of Major vs Minor releases, version-number format, anchors revealing internal "lts-releases" / "rapid-releases" labeling
- [MongoDB Software Lifecycle Schedules](https://www.mongodb.com/legal/support-policy/lifecycles) — EOL date table for every MongoDB Server release series
- [MongoDB Software Support Policy](https://www.mongodb.com/legal/support-policy/software) — the "5 years after Release Date" support-duration clause
- [MongoDB 8.1 Server Now Generally Available](https://www.mongodb.com/products/updates/mongodb-8-1-server-now-generally-available/) — confirms 8.1 is a Rapid Release, Atlas-only, and names 8.0 "the latest long-term supported release for self-managed environments"
- [Longer Lifecycles for MongoDB 7.0 and 8.0](https://www.mongodb.com/products/updates/longer-lifecycles-for-mongodb-7-0-and-8-0/) — Sept 2025 announcement extending EOL windows
- [Understanding the MongoDB Stable API and Rapid Release Cadence (MongoDB Blog)](https://www.mongodb.com/company/blog/product-release-announcements/understanding-mongodb-stable-api-rapid-release-cadence) — confirms Rapid Releases are Atlas-only, and are explicitly NOT for on-premises production
- [Install MongoDB Community Edition on Ubuntu (v8.0 manual)](https://www.mongodb.com/docs/v8.0/tutorial/install-mongodb-on-ubuntu/) — apt pinning is documented as "Optional"; confirms apt-get auto-upgrades unpinned packages
- [Preventing unintended upgrades on Ubuntu · Issue #364 · ansible-collections/community.mongodb](https://github.com/ansible-collections/community.mongodb/issues/364) — community-filed gap: the official Ansible collection has no built-in package-hold support
- [Unattended Upgrades, Ubuntu 18.04, and PostgreSQL 10: The Perfect Storm](https://seiler.us/2020-11-18-unattended-upgrades/) — cross-database (Postgres) real-world incident of `unattended-upgrades` restarting a production database
- [Percona Community Forum — Percona-server-server get restarted by debian unattended-upgrades](https://forums.percona.com/t/percona-server-server-get-restarted-by-debian-unattended-upgrades/29804) — cross-database (MySQL/Percona) real-world incident, same failure class
- [MongoDB Community Hub — Best way to perform system updates on replica set hosts](https://www.mongodb.com/community/forums/t/best-way-to-perform-system-updates-on-replica-set-hosts/191752) — MongoDB-specific community guidance confirming rolling, one-member-at-a-time OS maintenance
- [Upgrade to the Latest Self-Managed Patch Release of MongoDB](https://www.mongodb.com/docs/manual/tutorial/upgrade-revision/) — official rolling patch-upgrade procedure
- [Perform Maintenance on Self-Managed Replica Set Members](https://www.mongodb.com/docs/manual/tutorial/perform-maintence-on-replica-set-members/) — official OS-maintenance procedure (standalone restart pattern)
- [Replace a Self-Managed Replica Set Member](https://www.mongodb.com/docs/manual/tutorial/replace-replica-set-member/) — official doc scoped to hostname changes, not general upgrade-by-replacement
- [Upgrade a Standalone to 8.0](https://www.mongodb.com/docs/manual/release-notes/8.0-upgrade-standalone/) — official sequential-major-upgrade prerequisite and FCV procedure (verified against raw HTML)
- [setFeatureCompatibilityVersion (database command)](https://www.mongodb.com/docs/manual/reference/command/setfeaturecompatibilityversion/) — official one-major-version FCV compatibility table (verified against raw HTML)
- [MongoDB upgrade blocks startup unless featureCompatibilityVersion is migrated from 7.0 to 8.0 · danny-avila/LibreChat · Issue #10304](https://github.com/danny-avila/LibreChat/issues/10304) — community-reported real-world case of a startup failure tied to FCV mismatch (UNVERIFIED — issue's own error log was not included in the fetched content)
- [HashiCorp — Immutable Infrastructure: Benefits, Comparisons & More](https://www.hashicorp.com/en/resources/what-is-mutable-vs-immutable-infrastructure) — HashiCorp's own position on databases staying mutable
- [What Is Immutable Infrastructure? (DigitalOcean)](https://www.digitalocean.com/community/tutorials/what-is-immutable-infrastructure) — community/vendor consensus that stateful services need external data handling
- [Immutable Infrastructure: Why You Should Replace, Not Patch (Lukas Niessen)](https://www.lukasniessen.com/blog/129-immutable-infrastructure/) — hybrid position: infrastructure around a database can be immutable even though the database itself stays mutable
- [Deploy a MongoDB Replica Set in a DevOps fashion style (Medium, Cristian Ramirez)](https://medium.com/@cramirez92/deploy-a-mongodb-replica-set-in-a-devops-fashion-style-infrastructre-as-code-f631d7a0ad80) — a practitioner counter-example that does replace MongoDB replica-set nodes via versioned Packer images
- [Renovate Docs — FAQ](https://docs.renovatebot.com/faq/) — default grouping behavior (major separated; minor+patch combined)
- [Renovate Docs — Default Presets](https://docs.renovatebot.com/presets-default/) — `:separateMajorReleases`, `:separateMultipleMajorReleases`, `:combinePatchMinorReleases` preset descriptions
- [Renovate Docs — Upgrade Best Practices](https://docs.renovatebot.com/upgrade-best-practices/) — guidance to take majors in sequence via `:separateMultipleMajorReleases`
- [Renovate Docs — Configuration Options § dependencyDashboardApproval](https://docs.renovatebot.com/configuration-options/#dependencydashboardapproval) — gate definition and default value
- [Renovate Docs — Configuration Options § allowedVersions / matchCurrentVersion](https://docs.renovatebot.com/configuration-options/#allowedversions) — pinning a dependency to a major/minor line
- [Renovate Docs — Presets § config:recommended](https://docs.renovatebot.com/presets-config/#configrecommended) — confirms the recommended default preset does not gate majors differently from minor/patch in terms of PR creation

## Findings

### Question 1 — MongoDB release cadence: Major vs Rapid/Minor, support lifetime, EOL calendar

#### Finding 1.1: Major Releases — cadence, lifecycle, and platform support

**Evidence:** Raw HTML of the MongoDB Versioning page (verified via direct fetch), inside the section anchored `id="major-releases"` (with a secondary anchor `id="lts-releases"` on the same heading):

> "Major Releases are made available every two years and have a five-year lifecycle. Major Releases introduce new features and improvements and are supported for MongoDB Atlas and on-premises deployments."

Example versions listed on the page: `7.0`, `8.0`.

**Source:** https://www.mongodb.com/docs/manual/reference/versioning/ (verified against raw fetched HTML, substring located inside `<p class="leafygreen-ui-1kp3ins">Major<!-- --> Releases are made available every two years and have a five-year\nlifecycle...`)

**Significance:** This is MongoDB's own definition of a Major Release: supported for both Atlas and on-premises/self-managed deployments, nominal five-year lifecycle. The "every two years" cadence claim is the literal text on the page, but it does not match the observed release-date pattern in the official Lifecycle Schedules table (7.0 released August 2023, 8.0 released October 2024 — about 14 months apart, not 24). This tension is not resolved by any source found and is flagged under "What remains uncertain" below.

**Verification block:**
- URL fetched: https://www.mongodb.com/docs/manual/reference/versioning/ — yes (WebFetch + raw `curl` cross-check)
- Verbatim quote checked: yes, against raw HTML saved locally
- Quote substring confirmed at: embedded JSON/HTML inside the page's `major-releases` section, immediately following the section heading `<div id="lts-releases">`

---

#### Finding 1.2: The section anchor for Major Releases is literally named "lts-releases"

**Evidence:** In the raw HTML of the same Versioning page, the Major Releases heading carries two anchor IDs on adjacent elements: `std-label-major-releases` and `lts-releases`. No visible prose on the page uses the term "LTS" or "Long-Term Support" to describe Major Releases — the term appears only in the internal (non-visible) anchor slug.

**Source:** https://www.mongodb.com/docs/manual/reference/versioning/ (raw HTML anchor IDs, confirmed via direct fetch and `grep`)

**Significance:** MongoDB's own documentation internally treats "Major Release" and "LTS" as synonymous (the anchor slug), but does not use "LTS" as a customer-facing term anywhere in the visible prose of this page. Separately, a MongoDB product-update page (Finding 1.4) does use the phrase "long-term supported release" in prose, applied specifically to 8.0. There is no formal, defined "LTS" designation as a first-class MongoDB support-policy term distinct from "Major Release."

**Verification block:**
- URL fetched: https://www.mongodb.com/docs/manual/reference/versioning/ — yes
- Verbatim quote checked: yes, anchor IDs `std-label-major-releases` and `lts-releases` confirmed present and adjacent in raw HTML
- Quote substring confirmed at: `<div id="lts-releases" class="css-zena35 e1kswsxc0"></div></a></h2><p...>Major<!-- --> Releases are made available every two years...`

---

#### Finding 1.3: Rapid Releases were renamed "Minor Releases" starting with 8.2, and remain Atlas-first

**Evidence:** From the raw HTML of the same page, the Minor Releases section (anchors `std-label-rapid-releases`, `std-label-minor-releases`, `minor-releases` all present on the same heading):

> "Minor releases introduce incremental improvements and new features within a major version release cycle. They are as stable as major releases and suitable for production workloads."
>
> "Starting with MongoDB 8.2, minor releases are also available for on-premises deployments (Community and EA) for specific use cases, such as Search, Vector Search, and enhanced Queryable Encryption capabilities."
>
> "Minor releases may not support some features, including Atlas Live Migration or `mongosync`. If you require these features, use a Major release instead."

Separately, from the MongoDB Blog's Rapid Release explainer:

> "Rapid Releases are only supported for MongoDB Atlas. For on-premises environments, they should be used only for development builds and testing and not for production environments."

And from the "MongoDB 8.1 Server Now Generally Available" product-update page:

> "MongoDB 8.1 is a rapid server release following the major launch of MongoDB 8.0... MongoDB 8.1 is available exclusively for MongoDB Atlas users. Customers running on-premises deployments should continue using MongoDB 8.0, the latest long-term supported release for self-managed environments."

**Source:** https://www.mongodb.com/docs/manual/reference/versioning/ ; https://www.mongodb.com/company/blog/product-release-announcements/understanding-mongodb-stable-api-rapid-release-cadence ; https://www.mongodb.com/products/updates/mongodb-8-1-server-now-generally-available/

**Significance:** The presence of both `rapid-releases` and `minor-releases` anchor IDs on the current page confirms the terminology changed over time (old "Rapid Release" → current "Minor Release"), with the underlying concept unchanged. Critically: **8.1 is explicitly Atlas-only** and on-premises users are directed to stay on 8.0. Starting with **8.2**, minor releases became available on-premises too, but only for specific feature areas (Search, Vector Search, Queryable Encryption) and with the caveat that some features (Atlas Live Migration, `mongosync`) require a Major release instead. Nothing in these sources states that adopting a Minor/Rapid release "forfeits patch support" — the constraint documented is platform availability (Atlas-only for 8.1) and feature scope (8.2+ on-premises is scoped to specific capabilities), not a support-tier penalty per se.

**Verification block:**
- URL fetched: all three — yes
- Verbatim quote checked: yes for all three (versioning page verified against raw HTML; the blog and product-update pages verified via WebFetch tool extraction, not raw-HTML cross-checked)
- Quote substring confirmed at: versioning page — `<div id="minor-releases"...>Minor releases introduce incremental improvements...`; blog page — Rapid Release Atlas-only sentence as returned by WebFetch; product-update page — "long-term supported release" sentence as returned by WebFetch

---

#### Finding 1.4: Published EOL calendar and 8.0's specific EOL date

**Evidence:** From the MongoDB Software Lifecycle Schedules page, the Enterprise Advanced MongoDB Server table (as returned by WebFetch tool extraction):

| Release | Release Date | End of Life Date |
|---|---|---|
| MongoDB 8.3 | May 2026 | October 31, 2029 |
| MongoDB 8.2 | September 2025 | July 31, 2026 |
| MongoDB 8.0 | October 2024 | October 31, 2029 |
| MongoDB 7.0 | August 2023 | August 31, 2027 |
| MongoDB 6.0 | July 2022 | July 31, 2025 |
| MongoDB 5.0 | July 2021 | October 31, 2024 |

From the MongoDB Software Support Policy page (verbatim, WebFetch-extracted):

> "Support for each Major Release of the MongoDB Server will end 5 years after the Release Date, on the date specified at https://www.mongodb.com/legal/support-policy/lifecycles#enterprise-advanced."

**Source:** https://www.mongodb.com/legal/support-policy/lifecycles ; https://www.mongodb.com/legal/support-policy/software

**Significance:** MongoDB **does** publish a formal EOL calendar. **8.0's documented EOL date is October 31, 2029.** The table also shows the anomaly noted in Finding 1.1: 8.0 and 8.3 share the same EOL date (October 31, 2029) despite different release dates, consistent with 8.3 being a Minor release within the 8.x major line rather than an independently-lifecycled release. This is consistent with the "supported in the same timeframe as the leading Major or Minor Release" pattern for patch releases (see Finding 1.5), though 8.3 here is itself a minor, not a patch — this specific alignment (minor sharing the major's EOL date) was not separately confirmed against an explicit prose statement.

**Verification block:**
- URL fetched: both — yes
- Verbatim quote checked: table data as returned by WebFetch tool (not independently cross-checked against raw HTML — flagged as WebFetch-tool-extracted rather than raw-HTML-verified); the Support Policy sentence quoted above is WebFetch-tool-extracted
- Quote substring confirmed at: lifecycles page, Enterprise Advanced table; software support-policy page, Section 2.1 per the tool's extraction

---

#### Finding 1.5: The 8.0 lifecycle was extended after initial release

**Evidence:** From the MongoDB "New in MongoDB" updates feed (WebFetch-extracted, then independently re-confirmed):

> "The end of life dates for MongoDB 7.0 and 8.0 have been extended from 3 years to 4 years for 7.0 and 5 years for 8.0 and future major versions."

Dated September 16, 2025.

**Source:** https://www.mongodb.com/products/updates/longer-lifecycles-for-mongodb-7-0-and-8-0/

**Significance:** 8.0's currently-published 5-year lifecycle (EOL October 31, 2029) is not the original commitment — it was extended from an original 3-year window in September 2025, roughly 11 months after 8.0's October 2024 release. This means engineers planning around "N years of support" for a MongoDB major release should treat the published EOL date as MongoDB's current commitment, not necessarily a static promise made at release time — it has changed once already for the two most recent majors.

**Verification block:**
- URL fetched: https://www.mongodb.com/products/updates/longer-lifecycles-for-mongodb-7-0-and-8-0/ — yes
- Verbatim quote checked: yes
- Quote substring confirmed at: "New in MongoDB" feed entry dated September 16, 2025, "Longer Lifecycles for MongoDB 7.0 and 8.0"

---

### Question 2 — Patch auto-update guidance and apt pinning behavior

#### Finding 2.1: `mongodb-org` apt packages are NOT pinned by default; pinning is opt-in and explicitly labeled "Optional"

**Evidence:** Raw HTML of the MongoDB 8.0 Ubuntu install docs, confirmed via direct fetch:

> "Optional. Although you can specify any available version of MongoDB, apt-get will upgrade the packages when a newer version becomes available. To prevent unintended upgrades, you can pin the package at the currently installed version:"

The documented pinning commands use `dpkg --set-selections`, e.g. `echo "mongodb-org hold" | sudo dpkg --set-selections` (repeated per sub-package: `mongodb-org-database`, `mongodb-org-server`, `mongodb-mongosh`, `mongodb-org-mongos`, `mongodb-org-cryptd`, `mongodb-org-tools`, `mongodb-org-database-tools-extra`).

**Source:** https://www.mongodb.com/docs/v8.0/tutorial/install-mongodb-on-ubuntu/ (verified against raw fetched HTML)

**Significance:** By default, a bare `apt-get install mongodb-org` (or a subsequent unrelated `apt-get upgrade`) will pull in newer `mongodb-org` versions automatically — including patch releases — unless the engineer explicitly runs the hold commands. MongoDB frames this hold step as "Optional," not a default or a strong recommendation; the doc does not state a position on whether to hold in production versus not. It only documents the mechanism and names the risk it addresses ("unintended upgrades").

**Verification block:**
- URL fetched: https://www.mongodb.com/docs/v8.0/tutorial/install-mongodb-on-ubuntu/ — yes (WebFetch + raw `curl` cross-check)
- Verbatim quote checked: yes, against raw HTML saved locally
- Quote substring confirmed at: `...regardless of what version you specified.Optional. Although you can specify any available version of MongoDB,\napt-get will upgrade the packages when a newer version becomes\navailable. To prevent unintended upgrades, you can pin the package\nat the currently installed version:...`

---

#### Finding 2.2: The community has separately flagged that common automation tooling does not implement this hold by default

**Evidence:** GitHub issue title and content summary (WebFetch-extracted):

> "apt-get will upgrade the packages when a newer version becomes available. To prevent unintended upgrades, you can pin the package."

The issue requests that the `community.mongodb` Ansible collection add hold/pin support to its `mongodb_install` component, noting it currently lacks this capability.

**Source:** https://github.com/ansible-collections/community.mongodb/issues/364

**Significance:** This is evidence that at least one widely-used community automation tool for installing MongoDB via Ansible does not, out of the box, protect against the unpinned-apt-upgrade behavior documented in Finding 2.1 — the engineer using it must add the hold step themselves. This is a GitHub issue (a feature request), not confirmation that the feature was ever implemented; the fetched content did not include a resolution status.

**Verification block:**
- URL fetched: https://github.com/ansible-collections/community.mongodb/issues/364 — yes
- Verbatim quote checked: yes (quote matches the MongoDB doc's own wording, cited by the issue author)
- Quote substring confirmed at: issue body, as returned by WebFetch tool extraction

---

#### Finding 2.3: No MongoDB-specific documented incident of `unattended-upgrades` restarting all replica-set members at once was found; cross-database evidence exists for the general risk class

**Evidence:** A real-world incident description for PostgreSQL (WebFetch-extracted):

> Author describes discovering that `unattended-upgrades` "will ignore PGDG packages" by default, yet it still upgraded an installed PGDG PostgreSQL 10 package to the Ubuntu-supplied equivalent version, and "the PostgreSQL 10 database had been restarted (not ideal in production)."

A separate real-world incident for Percona Server for MySQL (WebFetch-extracted):

> "I got a bunch of mysql service that got restarted by unattended-upgrades this morning." Root cause traced to a systemd `TimeoutStartSec` value reset during the Percona Server postinstall script.

**Source:** https://seiler.us/2020-11-18-unattended-upgrades/ ; https://forums.percona.com/t/percona-server-server-get-restarted-by-debian-unattended-upgrades/29804

**Significance:** These are real, documented cases of `unattended-upgrades` restarting a production database service unexpectedly — but both are for PostgreSQL and MySQL/Percona, not MongoDB. Targeted search (multiple query variations) did not surface a MongoDB-specific, community-documented case of `unattended-upgrades` restarting `mongod` on some or all replica-set members simultaneously. This specific sub-question — "is that a known risk the community warns about, for MongoDB specifically" — is **not found** for MongoDB; the closest evidence is the cross-database pattern above plus the MongoDB Community Hub thread in Finding 2.4, which addresses OS maintenance generally (implying awareness of the multi-member-restart risk) without directly discussing `unattended-upgrades` as the trigger mechanism.

**Verification block:**
- URL fetched: both — yes
- Verbatim quote checked: yes for both
- Quote substring confirmed at: seiler.us blog post body, "What Went Wrong" section per the tool's extraction; Percona forum thread, original post per the tool's extraction

---

#### Finding 2.4: MongoDB's own community forum recommends rolling, one-member-at-a-time OS updates on replica-set hosts

**Evidence:** From a MongoDB Community Hub thread (WebFetch-extracted):

> Question: "I'm trying to determine the best way to perform maintenance on the underlying system that my replica set members are running on... I am doing things this way in order to keep the number of voting nodes to an odd number during any time that a server will be offline."
>
> Answer: "Your coworker's procedure is the recommended approach. Reconfiguring for maintenance is unnecessary as long as you ensure you always have a majority of voting members available." The described procedure: shut down one secondary at a time, apply updates, restart it, repeat for the remaining secondaries, then do the primary last. The answer references MongoDB's own blog post "Your Ultimate Guide to Rolling Upgrades."

**Source:** https://www.mongodb.com/community/forums/t/best-way-to-perform-system-updates-on-replica-set-hosts/191752

**Significance:** This is direct MongoDB-community confirmation that OS-level maintenance (which would include applying any patch, automated or manual) on a replica set should be done one member at a time — the same rolling pattern documented for MongoDB binary version upgrades (see Question 3). It does not discuss `unattended-upgrades` specifically, but the guidance implies that any tooling touching multiple members without this discipline (which is exactly what an unpinned, unattended, multi-host apt upgrade could do) runs against MongoDB's own recommended maintenance pattern.

**Verification block:**
- URL fetched: https://www.mongodb.com/community/forums/t/best-way-to-perform-system-updates-on-replica-set-hosts/191752 — yes
- Verbatim quote checked: yes
- Quote substring confirmed at: thread body (question and accepted-style answer) per the tool's extraction

---

### Question 3 — Community/official upgrade procedure for a self-managed replica set

#### Finding 3.1: The official procedure is a rolling, in-place binary upgrade — secondaries first, primary last via `stepDown`

**Evidence:** From "Upgrade to the Latest Self-Managed Patch Release of MongoDB" (WebFetch-extracted):

> "To upgrade a 8.0 replica set, upgrade each member individually, starting with the secondaries and finishing with the primary. Plan the upgrade during a predefined maintenance window."
>
> Secondaries: "Upgrade the secondary's `mongod` binary... After upgrading a secondary, wait for the secondary to recover to the `SECONDARY` state before upgrading the next instance. To check the member's state, issue `rs.status()`... The secondary may briefly go into `STARTUP2` or `RECOVERING`. This is normal."
>
> Primary: "Step down the primary to initiate the normal failover procedure" using `rs.stepDown()` or the `replSetStepDown` command. "During failover, the set cannot accept writes. Typically this takes 10-20 seconds." Then: "Once the primary has stepped down, call the `rs.status()` method... until you see that another member has assumed the `PRIMARY` state," then "Shut down the original primary and upgrade its instance."
>
> Note: "Stepping down the primary is preferable to directly shutting down the primary. Stepping down expedites the failover procedure."

**Source:** https://www.mongodb.com/docs/manual/tutorial/upgrade-revision/

**Significance:** This is MongoDB's official, current-manual procedure for a patch-release upgrade (e.g. 8.0.16 → 8.0.17): one member at a time, secondaries first, primary last with an explicit `stepDown`, each binary replaced in place and the process restarted. This is a **rolling in-place binary upgrade**, not a node-replacement pattern.

**Verification block:**
- URL fetched: https://www.mongodb.com/docs/manual/tutorial/upgrade-revision/ — yes
- Verbatim quote checked: yes, as returned by WebFetch tool
- Quote substring confirmed at: page sections "Upgrade Secondaries" and "Upgrade the Primary" per the tool's extraction

---

#### Finding 3.2: The general OS-maintenance procedure follows the same secondaries-first, primary-last pattern, with an explicit warning about the standalone-restart window

**Evidence:** From "Perform Maintenance on Self-Managed Replica Set Members" (WebFetch-extracted):

> "Perform maintenance on secondaries first, then the primary last. This allows the MongoDB deployment to remain available during the majority of the maintenance window."
>
> Per-member procedure: "Restart the `mongod` instance as a standalone" → "Perform the maintenance task on the standalone instance" → "Restart the `mongod` instance as a member of the replica set."
>
> Primary: `rs.stepDown(300)` — "This steps down the primary and allows a secondary to be elected as the new primary. The 300-second parameter prevents the member from being elected primary again for five minutes."
>
> Warning: "While the member is a standalone, no writes are replicated to this member nor are writes on this member replicated to the other members of the replica set. Ensure that any writes on this standalone do not conflict with oplog writes that will be applied to the member when it rejoins the replica set."

**Source:** https://www.mongodb.com/docs/manual/tutorial/perform-maintence-on-replica-set-members/

**Significance:** This is a distinct, more general procedure (for OS-level maintenance, not necessarily a MongoDB version upgrade) that reinforces the same rolling, secondaries-then-primary discipline, and documents a specific data-consistency hazard (writes on the isolated standalone instance) that would apply to any manual intervention performed this way.

**Verification block:**
- URL fetched: https://www.mongodb.com/docs/manual/tutorial/perform-maintence-on-replica-set-members/ — yes
- Verbatim quote checked: yes, as returned by WebFetch tool
- Quote substring confirmed at: "Recommended Order," "Specific Steps," and "Critical Warning" sections per the tool's extraction

---

#### Finding 3.3: The officially-named "Replace a Self-Managed Replica Set Member" procedure is scoped to hostname changes, not general node replacement for upgrade purposes

**Evidence:** WebFetch-extracted summary of the page:

> "If you need to change the hostname of a replica set member without changing the configuration of that member or the set, you can use this tutorial pattern. For example if you must re-provision systems or rename hosts, you can use this pattern to minimize the scope of that change." The procedure modifies `members[n].host` via `rs.reconfig()`.
>
> "Any replica set configuration change can trigger the current primary to step down, which forces an election."

**Source:** https://www.mongodb.com/docs/manual/tutorial/replace-replica-set-member/

**Significance:** MongoDB does have an officially-named "replace member" tutorial, but its documented scope is narrower than "replace the whole node with a new image as an upgrade strategy" — it is presented as a hostname/`rs.reconfig()` mechanism for when systems are re-provisioned or renamed, not as an alternative upgrade path to the in-place rolling procedure in Findings 3.1–3.2. No official MongoDB document was found in this research that frames node-replacement (new instance, `rs.add`, initial sync, `rs.remove`) as an alternative to the in-place rolling procedure specifically for version upgrades — the in-place rolling procedure is the only one MongoDB documents under "Upgrade."

**Verification block:**
- URL fetched: https://www.mongodb.com/docs/manual/tutorial/replace-replica-set-member/ — yes
- Verbatim quote checked: yes, as returned by WebFetch tool (via WebSearch result summary, not independently re-fetched — flagged accordingly)
- Quote substring confirmed at: page introduction and configuration-change warning, per the tool's extraction

---

#### Finding 3.4: MongoDB documents a hard constraint against rotating more than one member at a time

**Evidence:** WebSearch-surfaced, MongoDB-sourced guidance (paraphrase attributed to official docs by the search tool, not independently re-fetched as a standalone quote):

> "To prevent changing the write quorum, never rotate more than one replica set member at a time."

**Source:** Surfaced via WebSearch aggregation of MongoDB documentation content; not independently re-fetched as a verbatim page quote in this research session.

**Significance:** This constraint is consistent with, and explains the rationale behind, the one-member-at-a-time procedures documented in Findings 3.1 and 3.2 (write-quorum/majority safety). Because this specific sentence was not independently re-fetched and verified against a specific URL's raw content in this session, it is tagged **UNVERIFIED** per the citation discipline and should not be treated as a directly-sourced quote — it is presented as a signal consistent with the verified findings above, not as an independent citation.

**Verification block:**
- URL fetched: not independently re-fetched — UNVERIFIED
- Verbatim quote checked: no
- Quote substring confirmed at: N/A — sourced from WebSearch tool aggregation only

---

### Question 4 — Sequential major-version constraint and FCV

#### Finding 4.1: Major upgrades must be sequential; skipping is not supported

**Evidence:** Raw HTML of "Upgrade a Standalone to 8.0," confirmed via direct fetch:

> "To upgrade an existing MongoDB deployment to 8.0, you must be running a 7.0-series release."

> "To upgrade from a version earlier than the 7.0-series, you must successively upgrade major releases until you have upgraded to 7.0-series. For example, if you are running a 6.0-series, you must upgrade first to 7.0 before you can upgrade to 8.0."

**Source:** https://www.mongodb.com/docs/manual/release-notes/8.0-upgrade-standalone/ (verified against raw fetched HTML)

**Significance:** This is a direct, official, verbatim confirmation that MongoDB major-version upgrades cannot skip a series — a deployment on 6.0 must pass through 7.0 before reaching 8.0. There is no documented "skip a major" path.

**Verification block:**
- URL fetched: https://www.mongodb.com/docs/manual/release-notes/8.0-upgrade-standalone/ — yes (WebFetch + raw `curl` cross-check)
- Verbatim quote checked: yes, against raw HTML saved locally
- Quote substring confirmed at: `...To upgrade an existing MongoDB deployment to <!-- -->8.0<!-- -->, you must be\nrunning a <!-- -->7.0-series<!-- --> release.</p><p...>To upgrade from a version earlier than the <!-- -->7.0-series<!-- -->, you must\nsuccessively upgrade major releases until you have upgraded to\n<!-- -->7.0-series<!-- -->. For example, if you are running a <!-- -->6.0-series<!-- -->, you must\n<a...>upgrade first to 7.0</a> before you can upgrade to <!-- -->8.0<!-- -->...`

---

#### Finding 4.2: FCV must be set to the source major before the binary upgrade begins, and to the target major only after all members are upgraded

**Evidence:** WebFetch-extracted from the same upgrade-standalone page:

> "The 7.0 instance must have `featureCompatibilityVersion` set to `"7.0"`." (a documented prerequisite, checked via `db.adminCommand( { getParameter: 1, featureCompatibilityVersion: 1 } )`)
>
> After the binary is upgraded: "At this point, you can run the 8.0 binaries without the 8.0 features that are incompatible with 7.0. To enable these 8.0 features, set the feature compatibility version (FCV) to 8.0," via `db.adminCommand( { setFeatureCompatibilityVersion: "8.0", confirm: true } )`.

**Source:** https://www.mongodb.com/docs/manual/release-notes/8.0-upgrade-standalone/

**Significance:** `setFeatureCompatibilityVersion` gates whether backwards-incompatible on-disk data format changes are enabled. The documented sequence is: (1) confirm FCV is at the current major before touching binaries, (2) upgrade the binary, (3) the binary can run against the *old* FCV without the new major's backwards-incompatible features, and (4) only once all members are upgraded does the operator explicitly bump FCV to the new major to enable those features. This two-step separation (binary upgrade, then FCV bump) is the mechanism that keeps a downgrade possible during a burn-in window.

**Verification block:**
- URL fetched: https://www.mongodb.com/docs/manual/release-notes/8.0-upgrade-standalone/ — yes
- Verbatim quote checked: yes, as returned by WebFetch tool
- Quote substring confirmed at: "Feature Compatibility Version" and "Upgrade Procedure" (Step 3) sections per the tool's extraction

---

#### Finding 4.3: The documented FCV/binary compatibility tolerance is exactly one major version behind

**Evidence:** Raw HTML of the `setFeatureCompatibilityVersion` command reference page, confirmed via direct fetch:

> `"7.0" featureCompatibilityVersion is supported on MongoDB 7.0 and MongoDB 8.0 deployments.`

> `"6.0" featureCompatibilityVersion is supported on MongoDB 6.0 and MongoDB 7.0 deployments only.`

**Source:** https://www.mongodb.com/docs/manual/reference/command/setfeaturecompatibilityversion/ (verified against raw fetched HTML)

**Significance:** This is the official, verbatim confirmation of the exact tolerance requested: an FCV value of `X.0` is supported on binaries of major version `X.0` and `(X+1).0` only — i.e., a binary can run against an FCV that is at most **one major version behind** its own series. By implication (not separately verified as an explicit "refuses to start" sentence in official docs in this session), a binary would not be a supported configuration against an FCV two or more majors behind, which is consistent with the sequential-upgrade requirement in Finding 4.1 — you cannot reach 8.0 binaries with a 6.0 FCV still on disk because you are required to pass through the 7.0 stage first.

**Verification block:**
- URL fetched: https://www.mongodb.com/docs/manual/reference/command/setfeaturecompatibilityversion/ — yes (WebFetch + raw `curl` cross-check, following a redirect from the mixed-case URL)
- Verbatim quote checked: yes, against raw HTML saved locally
- Quote substring confirmed at: two list items in the "Supported Versions" section, exact text `&quot;7.0&quot; featureCompatibilityVersion is supported on MongoDB\n7.0 and MongoDB 8.0 deployments.` and `&quot;6.0&quot; featureCompatibilityVersion is supported on MongoDB\n6.0 and MongoDB 7.0 deployments only.`

---

#### Finding 4.4: A community-reported case describes a binary refusing to start on a stale FCV (UNVERIFIED against official docs for the exact error text)

**Evidence:** WebFetch-extracted summary of a GitHub issue:

> "MongoDB 8.x requires persistent data to have featureCompatibilityVersion set to 8.0. If the FCV is still 7.0 after upgrading the Docker image to 8.x, MongoDB refuses to start, producing a fatal error and entering a restart loop."

**Source:** https://github.com/danny-avila/LibreChat/issues/10304

**Significance:** This community report appears to describe a stricter startup requirement than what the official prerequisite text in Finding 4.2 states (which says an 8.0 binary CAN run against a 7.0 FCV, just without the new features enabled). The discrepancy was not resolved in this session — the issue's own fatal-error log text was not present in the fetched content, so the exact trigger condition in that specific report (whether it involved an FCV more than one major behind, a different failure mode such as a downgrade-incompatible feature already persisted, or a misconfiguration) is **not found**. This finding is tagged UNVERIFIED for the specific "refuses to start" claim and should not be treated as confirming or contradicting the official FCV compatibility table in Finding 4.3 — only as a real, independently-filed community report that a similar-sounding failure mode exists in practice.

**Verification block:**
- URL fetched: https://github.com/danny-avila/LibreChat/issues/10304 — yes, but the specific error log text referenced in the issue was not present in the fetched content — UNVERIFIED for the exact error condition
- Verbatim quote checked: partial — the summary sentence was returned by the WebFetch tool, but the underlying raw error log was not confirmed
- Quote substring confirmed at: issue body summary, per the tool's extraction; exact log text NOT confirmed

---

### Question 5 — Immutable infrastructure vs in-place patching for stateful services

#### Finding 5.1: HashiCorp's own guidance favors a mutable, in-place approach specifically for databases

**Evidence:** WebFetch-extracted from HashiCorp's own comparison resource:

> "In general, database-like systems tend to be updated much less often than things like our applications, so we might say, 'You know what, we're gonna use a mutable approach to managing databases because it's so infrequent and we don't have to bother with data migration.'"

**Source:** https://www.hashicorp.com/en/resources/what-is-mutable-vs-immutable-infrastructure

**Significance:** HashiCorp — the vendor whose own tooling (Packer) is the standard for building golden images and is used in 4Shark's `mongodb` repo — states its own position that databases are a case where the mutable/in-place pattern is preferred, reasoning from update frequency and avoidance of data-migration complexity, not from an inability to use Packer/immutable patterns at all.

**Verification block:**
- URL fetched: https://www.hashicorp.com/en/resources/what-is-mutable-vs-immutable-infrastructure — yes
- Verbatim quote checked: yes, as returned by WebFetch tool
- Quote substring confirmed at: transcript/body text under the databases discussion, per the tool's extraction

---

#### Finding 5.2: General vendor/community consensus treats stateful services as a poor fit for the pure "replace, don't patch" model

**Evidence:** WebFetch-extracted from DigitalOcean's immutable-infrastructure tutorial:

> "A persistent data layer that includes... External data stores for databases and any other stateful or ephemeral data"

The tutorial frames this as guidance to externalize state (e.g., managed database services, network-attached storage) rather than directly discussing in-place-patch vs replace trade-offs for the database engine itself.

**Source:** https://www.digitalocean.com/community/tutorials/what-is-immutable-infrastructure

**Significance:** This corroborates a broader community pattern (also seen in the general WebSearch results on this topic): the recommended way to reconcile immutable infrastructure with stateful services is to separate compute (which can be replaced) from persistent data (which is externalized or attached), rather than applying the "kill and replace" pattern directly to the database engine's own node. This tutorial does not directly weigh in on whether a MongoDB-style node (compute + local data directory, not a managed/externalized data store) should be patched in place or replaced.

**Verification block:**
- URL fetched: https://www.digitalocean.com/community/tutorials/what-is-immutable-infrastructure — yes
- Verbatim quote checked: yes, as returned by WebFetch tool
- Quote substring confirmed at: persistent-data-layer bullet list, per the tool's extraction

---

#### Finding 5.3: A hybrid position exists — treat the infrastructure around the database as immutable, while the database's own state stays mutable

**Evidence:** WebFetch-extracted:

> "Databases remain mutable because of their state, but you can still bring immutable practices to how you manage the infrastructure around them."

**Source:** https://www.lukasniessen.com/blog/129-immutable-infrastructure/

**Significance:** This source explicitly frames the trade-off as non-binary: the data itself is mutable by necessity, but practices such as versioned base images, schema-migration version control, and managed services can still apply around the data layer. This source does not quantify the initial-sync cost vs image-reproducibility trade-off directly — it names the workarounds (rebuild the server, keep data on persistent storage) without comparing their operational cost against in-place patching.

**Verification block:**
- URL fetched: https://www.lukasniessen.com/blog/129-immutable-infrastructure/ — yes
- Verbatim quote checked: yes, as returned by WebFetch tool
- Quote substring confirmed at: article body, per the tool's extraction

---

#### Finding 5.4: At least one practitioner explicitly applies node-replacement (not in-place patching) to MongoDB replica-set members using versioned Packer images

**Evidence:** WebFetch-extracted from a Medium article specifically about deploying a MongoDB replica set:

> "Once the server exists, we never try to upgrade it to V2. What we will do is to create our server with Packer, call it version 1... then we boot our servers with this version... if we detect some issues or failures on our version 1, what we are going to do is to create brand new servers with version 2 image"

**Source:** https://medium.com/@cramirez92/deploy-a-mongodb-replica-set-in-a-devops-fashion-style-infrastructre-as-code-f631d7a0ad80

**Significance:** This is a concrete, MongoDB-specific counter-example to the "databases stay mutable" consensus in Findings 5.1–5.3 — a practitioner explicitly choosing to replace, not patch, replica-set member nodes via versioned images. The article frames this choice around risk reduction (avoiding undefined intermediate states) and does not discuss or quantify the initial-sync cost that node replacement would impose on a MongoDB replica set, nor does it address arbiter-vs-data-bearing-member differences. This is a single practitioner's blog post, not a MongoDB-official or widely-corroborated position — it demonstrates the pattern is used in the wild, not that it is a community consensus recommendation.

**Verification block:**
- URL fetched: https://medium.com/@cramirez92/deploy-a-mongodb-replica-set-in-a-devops-fashion-style-infrastructre-as-code-f631d7a0ad80 — yes
- Verbatim quote checked: yes, as returned by WebFetch tool
- Quote substring confirmed at: article body describing the Packer versioning workflow, per the tool's extraction

---

### Question 6 — Renovate behavior for semver-level classification and major gating

#### Finding 6.1: Renovate's default behavior separates majors into their own branch/PR and combines minor+patch into one

**Evidence:** WebFetch-extracted from Renovate's FAQ page:

> "Use separate branches for each major version of each dependency"
>
> "Renovate groups the patch and minor versions into one PR. This means you only get a PR for the minor version, `0.9.0`."

**Source:** https://docs.renovatebot.com/faq/

**Significance:** With no explicit major-gating configuration, Renovate still creates a PR for a major update automatically — it just does so on its own branch, separately from combined minor+patch updates. "Separated from minor/patch" is not the same as "gated/blocked" — nothing in this default behavior prevents the major PR from being opened; it only controls branch/PR grouping.

**Verification block:**
- URL fetched: https://docs.renovatebot.com/faq/ — yes
- Verbatim quote checked: yes, as returned by WebFetch tool
- Quote substring confirmed at: "What is the default behavior?" / default major/minor-release-handling subsection, per the tool's extraction

---

#### Finding 6.2: The `:combinePatchMinorReleases` preset names the minor+patch grouping behavior explicitly

**Evidence:** WebFetch-extracted preset description:

> ":combinePatchMinorReleases" — "Do not separate `patch` and `minor` upgrades into separate PRs for the same dependency."

**Source:** https://docs.renovatebot.com/presets-default/

**Significance:** This preset description confirms Finding 6.1's grouping behavior is a named, documented default-preset concept, not an inferred behavior.

**Verification block:**
- URL fetched: https://docs.renovatebot.com/presets-default/ — yes
- Verbatim quote checked: yes, as returned by WebFetch tool
- Quote substring confirmed at: preset entry for `:combinePatchMinorReleases`, per the tool's extraction

---

#### Finding 6.3: `config:recommended` (the default base preset) does not itself gate major updates differently from minor/patch

**Evidence:** WebFetch-extracted:

> "Recommended configuration for most users. It does not matter what programming language you use."

Per the tool's analysis of the preset's composition: "it does not include any gating mechanisms like `dependencyDashboardApproval` or `matchUpdateTypes` restrictions on major updates... it opens pull requests for major updates with the same treatment as minor and patch updates."

**Source:** https://docs.renovatebot.com/presets-config/#configrecommended

**Significance:** Confirms directly the sub-question "with a default config (no explicit major gate), does Renovate open PRs for minor and patch automatically?" — yes, and it also opens PRs for majors automatically (on their own branch per Finding 6.1); nothing in the recommended default preset withholds a major-version PR pending manual approval.

**Verification block:**
- URL fetched: https://docs.renovatebot.com/presets-config/#configrecommended — yes
- Verbatim quote checked: yes for the description line; the "no gating mechanisms" conclusion is the WebFetch tool's own analysis of the preset composition rather than a directly-quoted sentence from the docs, and is presented here as such (not as a verbatim quote)
- Quote substring confirmed at: `config:recommended` preset description, per the tool's extraction

---

#### Finding 6.4: `dependencyDashboardApproval` is the config option that gates PR/branch creation behind manual approval, and can be scoped to majors specifically

**Evidence:** WebFetch-extracted from the Configuration Options reference:

> Description: "Require approval to create/update the Dependency Dashboard issue." Type: boolean. Default: `false`.

From Renovate's Upgrade Best Practices doc (WebFetch-extracted):

> "If you want to require approval for major updates, set `dependencyDashboardApproval` to `true` within a `major` object" — shown as a nested config block, e.g. `{ "major": { "dependencyDashboardApproval": true } }`.

**Source:** https://docs.renovatebot.com/configuration-options/#dependencydashboardapproval ; https://docs.renovatebot.com/upgrade-best-practices/

**Significance:** This directly answers the sub-question about which config option gates majors specifically: `dependencyDashboardApproval`, defaulting to `false` globally, can be nested inside a `major` object (or equivalently a `packageRules` entry matching `matchUpdateTypes: ["major"]`) so that only major-version updates require manual Dependency Dashboard approval before a branch/PR is created, leaving minor/patch on the default automatic-PR behavior.

**Verification block:**
- URL fetched: both — yes
- Verbatim quote checked: yes for both
- Quote substring confirmed at: configuration-options page, `dependencyDashboardApproval` entry; upgrade-best-practices page, major-update handling section, per the tool's extraction

---

#### Finding 6.5: `matchUpdateTypes` is the general filter used to build custom rules per semver level (e.g., automerge non-majors)

**Evidence:** WebFetch-extracted:

> `matchUpdateTypes` is documented as a `packageRules` matching option; the docs example shown was `"matchUpdateTypes": ["minor", "patch", "pin", "digest"]` "to automerge everything except major versions."

**Source:** https://docs.renovatebot.com/configuration-options/ (section on `matchUpdateTypes`)

**Significance:** `matchUpdateTypes` is the mechanism for writing any semver-level-specific `packageRules` entry — not limited to `dependencyDashboardApproval`; it is the same mechanism that would be used to, for example, automerge patch-only updates or apply a different `minimumReleaseAge` per level. Combined with `dependencyDashboardApproval` (Finding 6.4), it is the pairing that gates majors specifically while leaving minor/patch on the default flow.

**Verification block:**
- URL fetched: https://docs.renovatebot.com/configuration-options/ — yes
- Verbatim quote checked: yes, as returned by WebFetch tool
- Quote substring confirmed at: `matchUpdateTypes` entry description and example, per the tool's extraction

---

#### Finding 6.6: `allowedVersions` and `matchCurrentVersion` are the options for pinning Renovate to a specific major line

**Evidence:** WebFetch-extracted example configuration shown in the docs summary:

```json
{
  "packageRules": [
    {
      "matchCurrentVersion": "^1.2",
      "allowedVersions": "<2"
    }
  ]
}
```

Description: `matchCurrentVersion` "Filters package rules based on the current version of a dependency already in use." `allowedVersions` supports "regular expressions" and "negated regex syntax" to restrict which versions are considered acceptable for updates.

**Source:** https://docs.renovatebot.com/configuration-options/ (sections on `allowedVersions` and `matchCurrentVersion`)

**Significance:** This directly answers the "how does one pin Renovate to a specific major line" sub-question: `matchCurrentVersion` selects the `packageRules` entry to apply based on the version currently pinned in the manifest/lockfile, and `allowedVersions` (a range/regex constraint) restricts candidate updates to stay within that major line (e.g., `<2` prevents a jump to `2.x`). This example was returned by the tool as an illustrative pattern; it was not located as a literal worked example with these exact values on the fetched page, so the specific numeric example (`^1.2` / `<2`) should be treated as the tool's own illustration of the documented mechanism rather than a verbatim quoted example — the mechanism description itself (what each option does) is the verified claim.

**Verification block:**
- URL fetched: https://docs.renovatebot.com/configuration-options/ — yes
- Verbatim quote checked: partial — the option descriptions are quoted; the JSON example's exact values were not independently re-confirmed as literal page content
- Quote substring confirmed at: `allowedVersions` and `matchCurrentVersion` entries, per the tool's extraction; JSON example is illustrative, not confirmed verbatim

---

## Trade-offs surfaced

| Approach | Pros (per sources) | Cons (per sources) | Source |
|---|---|---|---|
| In-place rolling binary upgrade (secondaries first, primary last, `stepDown`) | This is the only procedure MongoDB documents under "Upgrade a Replica Set" / "Upgrade to the Latest Self-Managed Patch Release"; no data resync needed; matches MongoDB's own community-forum guidance for OS maintenance too | Requires careful, ordered, manual (or automated) execution per member; a badly-timed automatic restart of multiple members at once breaks write quorum (documented tolerance: never rotate more than one member at a time — Finding 3.4, UNVERIFIED as a direct quote but consistent with verified Findings 3.1–3.2) | Findings 3.1, 3.2, 2.4 |
| Node replacement (new instance from new golden image, add + initial sync + remove) | Practiced by at least one MongoDB-specific practitioner (Finding 5.4) using Packer-versioned images; general immutable-infrastructure literature frames replace-not-patch as reducing configuration drift and undefined intermediate states | Not the procedure MongoDB documents for version upgrades (the only officially-named "Replace a Member" tutorial is scoped to hostname changes — Finding 3.3); general vendor guidance (HashiCorp, Finding 5.1) favors mutable/in-place specifically for databases, citing infrequent updates and avoiding data migration; initial-sync cost and reproducibility trade-off is acknowledged as real by general sources but not quantified by any source found in this research | Findings 3.3, 5.1, 5.3, 5.4 |
| Automatic (unattended) patch-version apt upgrades | None found endorsing this specifically for `mongodb-org` in production | MongoDB's own install docs frame pinning as the way to prevent "unintended upgrades," implying an unpinned default is a risk vector to guard against (Finding 2.1); real, documented incidents exist of `unattended-upgrades` restarting a production database unexpectedly, but for PostgreSQL and MySQL/Percona, not MongoDB specifically (Finding 2.3); MongoDB's own community forum recommends manual, ordered, one-member-at-a-time maintenance instead (Finding 2.4) | Findings 2.1, 2.3, 2.4 |
| Renovate default (no major gate) | Every update type, including majors, surfaces as a PR automatically — nothing is silently missed; majors are separated onto their own branch from minor/patch by default (Finding 6.1) | A major-version PR can be opened without any additional review gate unless `dependencyDashboardApproval` (or an equivalent `matchUpdateTypes`-scoped rule) is explicitly configured (Finding 6.3, 6.4) | Findings 6.1, 6.3, 6.4 |
| Renovate with `dependencyDashboardApproval` scoped to majors | Minor/patch continue flowing automatically (subject to the existing 7-day `minimumReleaseAge`); majors require an explicit manual approval via the Dependency Dashboard before a branch/PR is even created (Finding 6.4) | Requires explicit config — not the tool's default; someone has to periodically check and approve the Dashboard for major updates to ever surface | Finding 6.4 |

## What remains uncertain

- **The "every two years" Major Release cadence claim (Finding 1.1) does not match the observed release-date pattern** in MongoDB's own Lifecycle Schedules table (7.0 → 8.0 was about 14 months, not 24). This is the literal text on MongoDB's current Versioning page, verified against raw HTML, but no source explains or resolves the discrepancy.
- **No MongoDB-specific documented case of `unattended-upgrades` restarting multiple/all replica-set members simultaneously was found** (Finding 2.3). The risk class is real and documented for PostgreSQL and MySQL/Percona, and MongoDB's own community guidance implies awareness of the underlying quorum risk (Finding 2.4), but a direct, MongoDB-specific "this happened and here's why it's dangerous" account was not located despite multiple targeted searches.
- **Whether an 8.0 binary actually refuses to start against an FCV that is exactly one major behind (7.0) was not found stated as an explicit "refuses to start" sentence in MongoDB's official docs** — the official docs (Finding 4.2) state the binary CAN run against a one-major-behind FCV without new features enabled. The community-reported case in Finding 4.4 describes a refusal-to-start scenario, but its exact trigger condition (which FCV distance, or a different root cause) was not confirmed against the primary source's own error log.
- **No official MongoDB document was found that frames node-replacement as a documented alternative upgrade path** to the in-place rolling procedure — only a narrower "change hostname" tutorial (Finding 3.3) and one practitioner's own choice to do so for reasons of drift-avoidance (Finding 5.4). Whether the MongoDB engineering organization has any internal or semi-official position on node-replacement as an upgrade strategy (versus purely a re-provisioning/renaming tool) is unknown from the sources gathered.
- **The initial-sync cost vs image-reproducibility trade-off for node replacement was not quantified by any source found** — every source that discusses the trade-off (HashiCorp, DigitalOcean, Lukas Niessen) describes it qualitatively, without benchmarks, time estimates, or a worked cost comparison specific to MongoDB or to a PSA topology with a non-data-bearing arbiter.
- **Whether 4Shark's PSA topology (2 data-bearing members + 1 arbiter) changes any of the write-quorum or rolling-maintenance guidance found** was not separately researched — all sourced procedures describe the general N-member replica-set case, not a PSA-specific variant.

## Suggested options for main and the engineer

- Option A: keep the current 7-day `minimumReleaseAge` Renovate gate as the only automation control, relying on it plus the documented one-member-at-a-time rolling upgrade procedure (Finding 3.1) for patch releases, with no additional major-specific gate.
- Option B: add a `packageRules` entry scoped by `matchUpdateTypes: ["major"]` with `dependencyDashboardApproval: true` (Finding 6.4) so major-version bumps require explicit Dependency Dashboard approval before a PR/branch is even opened, while minor/patch continue flowing under the existing 7-day gate.
- Option C: pin `mongodb-org` packages via `dpkg --set-selections`/`apt-mark hold` at the OS level (Finding 2.1) in the Packer/Ansible build, independent of whatever Renovate does at the repository level, as a second control against any unpinned apt-level upgrade path outside of Renovate's visibility entirely.
- Option D: continue with the in-place rolling binary upgrade procedure MongoDB documents (Findings 3.1–3.2) rather than adopting a node-replacement pattern, consistent with HashiCorp's own stated preference for mutable databases (Finding 5.1) and the absence of an official MongoDB-documented replacement-based upgrade path (Finding 3.3).
- Option E: adopt a node-replacement pattern for future golden-AMI rotations (new instance, initial sync, remove old), following the practitioner pattern in Finding 5.4, accepting the unquantified initial-sync cost as a trade-off for image reproducibility and reduced configuration drift.

(No recommendation — these are the surfaced options; main and the engineer choose.)

---

## Round 2 — patch notification and Ubuntu 26.04 support

Continues the investigation with four additional, narrower questions. Context supplied by the engineer (not re-derived): 4Shark runs 4 self-managed MongoDB 8.0.26 PSA replica sets on EC2 Ubuntu 20.04 (focal), built from a Packer golden AMI + an Ansible role; the team is 3 engineers with no capacity to manually watch for MongoDB releases; automatic apt upgrades are ruled out; today is 2026-07-14.

### Investigation questions (round 2)

1. How does one learn a MongoDB security patch exists — what official notification channels does MongoDB provide?
2. What third-party/automated mechanisms exist to be notified of a new MongoDB patch or CVE, and do they apply to a version string pinned in an Ansible role / Packer variable (not a package manifest)?
3. What is the community's actual patch cadence for self-managed MongoDB — a recommended interval, or purely CVE-driven?
4. Does MongoDB 8.0 officially support Ubuntu 26.04 LTS, and is Ubuntu 26.04 LTS itself released as of July 2026?

This round returns findings only — no recommendation is made. Main and the engineer decide.

### Sources consulted (round 2)

- [MongoDB Alerts](https://www.mongodb.com/resources/products/alerts) — the official alerts/advisories page, RSS feed link, and CVE listing (verified against raw HTML and raw curl headers)
- [MongoDB Alerts RSS feed](https://www.mongodb.com/resources/products/alerts/rss) — verified as a valid RSS 2.0 feed via raw XML fetch
- `https://www.mongodb.com/resources/products/mongodb-security-bulletins` — verified via `curl -sIL` to be an HTTP 302 redirect to the Alerts page, not a distinct page
- [MongoDB Vulnerability Disclosure Policy](https://www.mongodb.com/company/contact/mongodb-vulnerability-disclosure-policy) — reporting channel (HackerOne, security bug form) and its own pointer back to the Alerts page for public disclosure
- [MongoDB 8.0 Release Notes](https://www.mongodb.com/docs/manual/release-notes/8.0/) — per-patch-version changelog listing CVEs fixed per release (verified against raw HTML)
- [MongoDB Versioning — Database Manual](https://www.mongodb.com/docs/manual/reference/versioning/) — "Patch Releases are made available as needed" and "Always upgrade to the latest stable patch release" (verified against raw HTML; reused from Round 1 for a new quote)
- [Important MongoDB patch available — MongoDB Community Hub](https://www.mongodb.com/community/forums/t/important-mongodb-patch-available/332977) — community announcement of a specific security patch, urgency language
- [GitHub Docs — Dependabot supported ecosystems and repositories](https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories) — full ecosystem list (verified against raw HTML: no "ansible" or "packer" substring present)
- [Renovate Docs — Custom Manager Support using Regex](https://docs.renovatebot.com/modules/manager/regex/) — the `customManagers` regex mechanism and its `renovate:` comment worked example (verified against raw HTML)
- [Renovate Docs — Endoflife Date Datasource](https://docs.renovatebot.com/modules/datasource/endoflife-date/) — built-in datasource based on endoflife.date, with a Terraform `.tfvars` regex-manager worked example (verified against raw HTML)
- [endoflife.date — MongoDB](https://endoflife.date/mongodb) — EOL tracking page for MongoDB with RSS/iCal/API feeds (RSS link `mongodb.atom` verified against raw HTML)
- [NVD — Developers, Vulnerabilities (CVE API 2.0)](https://nvd.nist.gov/developers/vulnerabilities) — `cpeName` / `virtualMatchString` query parameters for vendor/product-scoped CVE queries (WebFetch-tool-extracted; page is a JavaScript SPA shell and raw `curl` could not retrieve the rendered content — flagged accordingly, not raw-HTML-verified)
- [Ubuntu Security Notices — USN-5101-1](https://ubuntu.com/security/notices/USN-5101-1) — confirms the affected package names are `mongodb`, `mongodb-clients`, `mongodb-server`, `mongodb-server-core` (verified against raw HTML), not `mongodb-org`
- `https://repology.org/project/mongodb/versions` — attempted; direct `curl` returned HTTP 403 (blocked); the WebFetch tool's own extraction stated it could not confirm whether the tracked "mongodb" project includes MongoDB Inc.'s official `mongodb-org` packages — tagged UNVERIFIED for that specific claim
- [Oracle Database Patch Maintenance Guidelines](https://docs.oracle.com/en/database/oracle/oracle-database/19/dbptc/index.html) — Oracle's own documented quarterly Critical Patch Update / Release Update cadence, presented as a cross-database comparison point, NOT MongoDB or community-wide consensus (verified against raw HTML)
- [Percona — MongoDB 6.0: Should You Upgrade Now?](https://www.percona.com/blog/mongodb-6-0-should-you-upgrade-now/) — Percona's own cautious-adoption timeline for a major version; no patch-cadence guidance found
- [MongoDB Manual — Production Notes for Self-Managed Deployments](https://www.mongodb.com/docs/manual/administration/production-notes/) — Supported Platforms table (verified against raw HTML: only Ubuntu 20.04/22.04/24.04 present, no 26.04)
- [Install MongoDB Community Edition on Ubuntu — Database Manual v8.0](https://www.mongodb.com/docs/v8.0/tutorial/install-mongodb-on-ubuntu/) — apt repository lines for focal/jammy/noble only (verified against raw HTML)
- `https://s3.amazonaws.com/repo.mongodb.org?list-type=2&prefix=apt/ubuntu/dists/&delimiter=/` — the S3 bucket backing `repo.mongodb.org`'s apt repository, listed directly via `curl` (raw XML, primary-source evidence)
- `https://repo.mongodb.org/apt/ubuntu/dists/resolute/mongodb-org/8.0/Release` and the `noble` equivalent — direct HTTP status checks via `curl -s -o /dev/null -w "%{http_code}"`
- [Ubuntu 26.04 LTS release notes](https://documentation.ubuntu.com/release-notes/26.04/) — official codename and release date (verified against raw HTML)
- [Ubuntu release cycle](https://ubuntu.com/about/release-cycle) — 26.04 row in the official release-cycle table (WebFetch-tool-extracted)
- [Ubuntu 26.04 and MongoDB 8.2+ – Tim's LTS](https://blog.nevyn.co.za/ubuntu-26-04-and-mongodb-8-2/) — a practitioner's own account of installing MongoDB on Ubuntu 26.04 via the archived 24.04 `.deb`, corroborating (not the primary evidence) the S3/HTTP findings

### Findings (round 2)

#### Question 1 — Official MongoDB security-patch notification channels

##### Finding Q1.1: The MongoDB Alerts page is the single official page for security advisories/CVEs, and it exposes an RSS feed

**Evidence:** Raw HTML of the Alerts page, confirmed via direct fetch:

> "This page lists critical alerts and advisories for MongoDB. See the [MongoDB JIRA](https://jira.mongodb.org/secure/BrowseProjects.jspa) for a comprehensive list of bugs and feature requests."

The page is organized into four categories, one of which is named (per WebFetch tool extraction of the page structure) "Security Related: Common Vulnerabilities and Exposures (CVEs)". The raw HTML contains the RSS link target `alerts/rss` (matched five times in the fetched markup, consistent with a repeated RSS icon/link across the page's sections).

**Source:** https://www.mongodb.com/resources/products/alerts (raw HTML fetched via `curl`, saved locally, `grep`-confirmed)

**Significance:** This is MongoDB's documented, single, official page for security advisories and CVE announcements. It is not exclusively a security page (it also lists data-integrity and operations alerts), but the CVE section is explicitly named on the page and is the channel that would carry a MongoDB Server Community Edition CVE announcement.

**Verification block:**
- URL fetched: https://www.mongodb.com/resources/products/alerts — yes (WebFetch + raw `curl` cross-check)
- Verbatim quote checked: yes, against raw HTML saved locally
- Quote substring confirmed at: `This page lists critical alerts and advisories for MongoDB.` (grep-matched three times in the saved HTML, once as plain text and twice inside embedded JSON/markdown blobs)

---

##### Finding Q1.2: The exact RSS feed URL is `https://www.mongodb.com/resources/products/alerts/rss`, and it is a valid RSS 2.0 feed carrying real CVE entries including recent 2026 CVEs

**Evidence:** Raw XML of the feed, fetched directly via `curl`:

```
<?xml version="1.0" encoding="UTF-8" ?>
      <rss version="2.0" xmlns:atom="http://www.w3.org/2005/Atom">
      <channel>
      <title>MongoDB | Product Alerts</title>
      <description>MongoDB news and information.</description>
      <link>https://www.mongodb.com/resources/products/alerts</link>
```

A `grep` for `CVE-2026-` against the same saved file returned ten distinct matches, including `CVE-2026-11933`, `CVE-2026-1847`, `CVE-2026-1848`, `CVE-2026-1849`, `CVE-2026-1850`, `CVE-2026-2302`, `CVE-2026-2303`, `CVE-2026-25609`, `CVE-2026-25610`, `CVE-2026-25612`.

**Source:** https://www.mongodb.com/resources/products/alerts/rss (raw XML fetched via `curl`, saved locally, `grep`-confirmed)

**Significance:** This is a real, currently-active RSS feed (not a dead/placeholder link) that a feed reader, cron job, or Slack/email RSS-to-notification bridge could poll for new entries — including CVE-only entries, since each `<item>` title/description carries the CVE identifier when applicable. `CVE-2026-11933` in this feed matches the CVE fixed in MongoDB 8.0.26 per Finding Q1.3 below, confirming the feed is kept current with the patch-release cadence, not just major security events.

**Verification block:**
- URL fetched: https://www.mongodb.com/resources/products/alerts/rss — yes (raw `curl`, not just the WebFetch tool)
- Verbatim quote checked: yes, against the raw XML file saved locally
- Quote substring confirmed at: channel `<title>` element, first ~60 lines of the raw feed; `CVE-2026-` matches via `grep -o` against the same file

---

##### Finding Q1.3: `mongodb-security-bulletins` is not a distinct page — it is an HTTP 302 redirect to the same Alerts page

**Evidence:** Raw HTTP response headers from `curl -sIL`:

```
HTTP/2 302
content-type: text/plain; charset=utf-8
content-length: 71
location: https://www.mongodb.com/resources/products/alerts
```

followed immediately by a second response:

```
HTTP/2 200
content-type: text/html; charset=utf-8
```

for the target URL.

**Source:** `https://www.mongodb.com/resources/products/mongodb-security-bulletins` (raw `curl -sIL` header dump)

**Significance:** A search for "MongoDB Security Bulletins" surfaces `mongodb.com/resources/products/mongodb-security-bulletins` as a search-engine-indexed title, but the URL itself redirects (HTTP 302) to `mongodb.com/resources/products/alerts` — the same page as Finding Q1.1. There is only one official MongoDB page for this purpose, under two different marketing labels/URLs; there is no second, separately-maintained "bulletins" page with different content.

**Verification block:**
- URL fetched: https://www.mongodb.com/resources/products/mongodb-security-bulletins — yes (raw `curl -sIL`)
- Verbatim quote checked: yes, HTTP response headers reproduced verbatim above
- Quote substring confirmed at: `location:` response header of the first (302) response in the `curl -sIL` output

---

##### Finding Q1.4: Patch release notes name the exact CVE(s) fixed per patch version, functioning as a de facto per-release security changelog — but with no RSS/feed of its own

**Evidence:** Raw HTML of the MongoDB 8.0 Release Notes page, confirmed via direct fetch and `grep`:

> "8.0.26 - June 11, 2026" ... "8.0.26 contains a fix for" ... `CVE-2026-11933`

Per WebFetch tool extraction of the surrounding page (not independently re-verified line-by-line beyond the grep above), earlier patch entries carry the same pattern, e.g. 8.0.5 (Feb 20, 2025) naming CVE-2025-6709 and CVE-2025-6710.

**Source:** https://www.mongodb.com/docs/manual/release-notes/8.0/ (raw HTML fetched via `curl`, saved locally, `grep`-confirmed for the 8.0.26 entry and its CVE)

**Significance:** The 8.0 release-notes page is a changelog an engineer can watch: each patch entry states the date and, when applicable, the CVE(s) it fixes. This means 4Shark's current version (8.0.26) already has a documented fix for CVE-2026-11933 baked in as of June 11, 2026 (context, not independently pursued further in this round — the engineer's stated current version is 8.0.26). However, no RSS/Atom feed was found for this specific page (the WebFetch tool's own extraction stated "No information provided" / "No... visible in the provided content" regarding a feed) — the changelog exists but is not natively pollable the way the Alerts RSS feed (Finding Q1.2) is.

**Verification block:**
- URL fetched: https://www.mongodb.com/docs/manual/release-notes/8.0/ — yes (WebFetch + raw `curl` cross-check for the specific 8.0.26/CVE-2026-11933 substrings)
- Verbatim quote checked: yes for "8.0.26 - June 11, 2026", "8.0.26 contains a fix for", and "CVE-2026-11933" against the raw HTML file; the 8.0.5 entry detail is WebFetch-tool-extracted only, not independently raw-HTML-grepped in this session
- Quote substring confirmed at: `grep -o "8\.0\.26[^<]*"` and `grep -o "CVE-2026-11933[^<]*"` against the saved HTML file, both non-empty

---

##### Finding Q1.5: No official MongoDB mailing list for security announcements was found; the RSS feed is the only push-style subscription mechanism located

**Evidence:** The WebFetch tool's own extraction of the Alerts page stated:

> "The page does **not appear to offer a mailing list subscription mechanism**. The only subscription option presented is the RSS feed."

**Source:** https://www.mongodb.com/resources/products/alerts (WebFetch tool extraction; the underlying page itself was separately raw-HTML-verified for the RSS link in Finding Q1.1, but the absence of a mailing list is reported here as the tool's negative-finding statement, not an independently re-grepped absence)

**Significance:** Not found: an official MongoDB mailing list for security advisories. The MongoDB Vulnerability Disclosure Policy page (fetched separately) also did not surface a mailing list — its only outbound pointer for disclosure information was back to the Alerts page (`"[Security Bulletin / CVEs](https://www.mongodb.com/resources/products/alerts)"`, per WebFetch tool extraction of that page). Absent a mailing list, the RSS feed (Finding Q1.2) is the only official, automatable, push-style channel found in this research.

**Verification block:**
- URL fetched: https://www.mongodb.com/resources/products/alerts — yes; https://www.mongodb.com/company/contact/mongodb-vulnerability-disclosure-policy — yes
- Verbatim quote checked: yes for the "does not appear to offer" sentence, as returned by the WebFetch tool (a negative-finding statement, not a page-native quote — flagged accordingly per citation discipline); the disclosure-policy page's "[Security Bulletin / CVEs]" link text is also WebFetch-tool-extracted, not raw-HTML-verified in this session
- Quote substring confirmed at: WebFetch tool's synthesis of the Alerts page content; not independently re-grepped against raw HTML for the specific absence claim

---

#### Question 2 — Third-party/automated notification mechanisms and their applicability to a pinned Ansible/Packer version string

##### Finding Q2.1: GitHub Dependabot's supported ecosystems do not include Ansible or Packer — it is manifest/lockfile-based, not applicable to a version string pinned in a role variable

**Evidence:** Raw HTML of the Dependabot supported-ecosystems page, `grep`-checked for "ansible" and "packer" (case-insensitive): zero matches for both terms in the entire page. Per WebFetch tool extraction, the documented ecosystems are: "Bazel, Bun, Bundler, Cargo, Composer, Conda, Deno, Dev containers, Docker, Docker Compose, .NET SDK, Helm Charts, Hex (mix), Julia, elm-package, git submodule, GitHub Actions, Go modules, Gradle, Maven, Nix, npm, NuGet, OpenTofu, pip, pipenv, pip-compile, pnpm, poetry, pre-commit, and pub" for version updates.

**Source:** https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories (raw HTML fetched via `curl`, saved locally, `grep -oi "ansible\|packer"` returned no output)

**Significance:** Dependabot works by parsing a known dependency manifest or lockfile format (`Gemfile`, `package.json`, a Dockerfile `FROM` line, etc.). A MongoDB version pinned as an Ansible role variable (e.g. `mongodb_version: "8.0.26"` in a `defaults/main.yml`) or a Packer `.pkr.hcl` variable is not any of the listed manifest formats, so Dependabot has no mechanism to detect or open a PR against it. This directly answers "does Dependabot cover a version string in a repo?" for this specific shape: **no** — not for a non-manifest, free-form variable pin.

**Verification block:**
- URL fetched: https://docs.github.com/en/code-security/reference/supply-chain-security/supported-ecosystems-and-repositories — yes (WebFetch + raw `curl` cross-check)
- Verbatim quote checked: yes — the "no ansible/packer" claim is a confirmed absence (`grep` returned zero matches against the full raw HTML), not a positive quote
- Quote substring confirmed at: raw HTML file, `grep -oi "ansible\|packer"` produced no output (negative-result verification)

---

##### Finding Q2.2: Renovate's `customManagers` regex mechanism is explicitly designed to track a version pinned in an arbitrary non-manifest file via an inline comment

**Evidence:** Raw HTML of the Renovate regex custom-manager doc, confirmed via direct fetch:

> "With `customManagers` using `regex` you can configure Renovate so it finds dependencies that are not detected by its other built-in package managers."

A worked example present on the same page (raw HTML, `grep`-confirmed):

```
renovate: datasource=github-tags depName=node packageName=nodejs/node versioning=node
```

and

```
renovate: datasource=github-releases depName=composer packageName=composer/composer
```

**Source:** https://docs.renovatebot.com/modules/manager/regex/ (raw HTML fetched via `curl`, saved locally, `grep`-confirmed for the `renovate: datasource=` comment pattern)

**Significance:** This directly answers "can Renovate open a PR when a new patch of mongodb appears" for a version pinned in an Ansible role or Packer variable file, and "from which datasource": Renovate's `customManagers` regex mechanism is purpose-built for exactly this shape (a version pinned in a file Renovate does not natively parse, tagged with an inline `# renovate: datasource=... depName=...` comment). This is a general-purpose mechanism, not one specific to MongoDB — the applicable datasource (which one to use for `mongodb-org`'s own release cadence) is addressed in Finding Q2.3.

**Verification block:**
- URL fetched: https://docs.renovatebot.com/modules/manager/regex/ — yes (WebFetch + raw `curl` cross-check)
- Verbatim quote checked: yes, against raw HTML saved locally
- Quote substring confirmed at: `grep -o "renovate: datasource[^<]*"` against the saved HTML file, five matches including the two quoted above

---

##### Finding Q2.3: Renovate ships a built-in `endoflife-date` datasource, sourced from the same endoflife.date API that tracks MongoDB, and it is documented with a worked example combining it with the regex custom manager on a non-standard file

**Evidence:** Raw HTML of the Renovate `endoflife-date` datasource doc, confirmed via direct fetch:

> "endoflife.date provides version and end-of-life information for different packages."

Per WebFetch tool extraction of the same page, the documented worked example combines this datasource with a `customManagers` regex rule against a Terraform `.tfvars` file (not Ansible specifically, but the same non-manifest-file mechanism as Finding Q2.2) to track `amazon-eks` versions.

**Source:** https://docs.renovatebot.com/modules/datasource/endoflife-date/ (raw HTML fetched via `curl`, saved locally, `grep`-confirmed for the introductory sentence)

**Significance:** Combined with Finding Q2.4 (endoflife.date tracks MongoDB) and Finding Q2.2 (the regex custom-manager mechanism), this is a concrete, fully-Renovate-native path capable of opening a PR when endoflife.date's own MongoDB data changes — applied to a version pinned in an Ansible role or Packer variable, using the same `renovate:` comment pattern demonstrated for Terraform `.tfvars` in the docs' own example. Whether `endoflife-date`'s MongoDB entries update fast enough or granularly enough to catch every individual patch release (as opposed to only major/minor lines) was not established in this research — endoflife.date's own product page (Finding Q2.4) was not checked for patch-level granularity.

**Verification block:**
- URL fetched: https://docs.renovatebot.com/modules/datasource/endoflife-date/ — yes (WebFetch + raw `curl` cross-check)
- Verbatim quote checked: yes for the introductory sentence, against raw HTML saved locally; the Terraform `.tfvars` worked-example description is WebFetch-tool-extracted, not independently re-grepped line-by-line in this session
- Quote substring confirmed at: `grep -o "provides version[^<]\{0,150\}"` against the saved HTML file, one match: "provides version and end-of-life information for different packages."

---

##### Finding Q2.4: endoflife.date tracks MongoDB and offers RSS, iCalendar, and JSON API feeds

**Evidence:** Raw HTML of the endoflife.date MongoDB page, `grep`-confirmed for the RSS feed link target:

```
mongodb.atom
```

Per WebFetch tool extraction of the same page, the offered feeds are: an RSS/Atom feed at `/mongodb.atom`, an iCalendar feed at `/calendar/mongodb.ics`, and a JSON API at `/api/v1/products/mongodb/`.

**Source:** https://endoflife.date/mongodb (raw HTML fetched via `curl`, saved locally, `grep -o "mongodb.atom[^\"]*"` confirmed three matches)

**Significance:** endoflife.date is a community-maintained (not MongoDB-official) tracker that specifically covers MongoDB, and it exposes three distinct automatable feed formats. This is the datasource Renovate's built-in `endoflife-date` module (Finding Q2.3) is built on top of. Whether endoflife.date's MongoDB entries are patch-level granular (i.e., would a new 8.0.27 register as a distinct trackable event) versus only minor/major-level was not separately confirmed in this session — the page's version table structure was not examined for this granularity question.

**Verification block:**
- URL fetched: https://endoflife.date/mongodb — yes (WebFetch + raw `curl` cross-check)
- Verbatim quote checked: yes, the `mongodb.atom` feed-link substring, against raw HTML saved locally
- Quote substring confirmed at: `grep -o "mongodb.atom[^\"]*"` against the saved HTML file, three matches (one in a link element, one with a decorative emoji suffix per the WebFetch tool's earlier extraction)

---

##### Finding Q2.5: NVD's CVE API 2.0 supports querying by CPE name (vendor/product), but it is a pull API, not a push notification — it would need an external poller to function as an alert

**Evidence:** Per WebFetch tool extraction of the NVD Developers Vulnerabilities page (raw `curl` could not retrieve rendered content — the page is a JavaScript single-page-application shell, confirmed by the saved file being only 89 lines with no `cpeName` substring present):

> "The CVE API is used to easily retrieve information on a single CVE or a collection of CVE from the NVD."

> "This parameter returns all CVE associated with a specific CPE. The exact value provided with `cpeName` is compared against the CPE Match Criteria within a CVE applicability statement."

Example query shown: `https://services.nvd.nist.gov/rest/json/cves/2.0?cpeName=cpe:2.3:o:microsoft:windows_10:1607:*:*:*:*:*:*:*`

**Source:** https://nvd.nist.gov/developers/vulnerabilities — **UNVERIFIED against raw HTML** (the page is client-rendered; `curl` returned an 89-line JS-app shell with no matching content, so the quotes above are WebFetch-tool-extracted only, not independently confirmed against the page's raw source in this session)

**Significance:** NVD's CVE API 2.0 can be queried filtered by a CPE name matching MongoDB Server, which would let a script or cron job check for new CVEs periodically. This is a pull mechanism (something must call it on a schedule), not a push/subscription mechanism like the RSS feeds in Findings Q1.2 and Q2.4 — it answers "could 4Shark build a poller against NVD" but does not by itself constitute a notification channel without additional tooling (a script + a schedule + somewhere to post the result). Because the source page could not be raw-HTML-verified, this finding is presented with reduced confidence per the citation discipline's UNVERIFIED tag, though the WebFetch tool's extraction is internally consistent with NVD's known public API 2.0 design.

**Verification block:**
- URL fetched: https://nvd.nist.gov/developers/vulnerabilities — yes via WebFetch tool; raw `curl` fetch attempted but returned an unrendered JS shell (no matching content) — UNVERIFIED against raw HTML
- Verbatim quote checked: no independent raw-HTML confirmation; WebFetch tool extraction only
- Quote substring confirmed at: not confirmed in raw source; tool-extraction only

---

##### Finding Q2.6: Ubuntu Security Notices (USN) track the Ubuntu-archive `mongodb` package family, not MongoDB Inc.'s own `mongodb-org` packages that 4Shark actually runs

**Evidence:** Raw HTML of USN-5101-1, `grep`-confirmed package names:

```
mongodb
mongodb-clients
mongodb-server
mongodb-server-core
```

Per WebFetch tool extraction of the same notice, these packages are sourced "from the Ubuntu archive (distributed by Canonical)... available through Launchpad's Ubuntu source repository at `launchpad.net/ubuntu/+source/mongodb`," with the fixed version shown as `1:3.6.9+really3.6.8+90~g8e540c0b6d-0ubuntu5.3` for Ubuntu 20.04 LTS.

**Source:** https://ubuntu.com/security/notices/USN-5101-1 (raw HTML fetched via `curl`, saved locally, `grep -o "mongodb[a-z-]*"` confirmed the four package names, no `mongodb-org` match)

**Significance:** This is a direct, verified confirmation that Ubuntu's own USN tracker does not cover the `mongodb-org` package family MongoDB Inc. publishes via `repo.mongodb.org` and that 4Shark installs. The USN-tracked `mongodb` package on Ubuntu 20.04 is stuck at a legacy `3.6.x`-derived version — a completely different package and version lineage from `mongodb-org` 8.0.26. **USN does not apply to 4Shark's MongoDB installation.**

**Verification block:**
- URL fetched: https://ubuntu.com/security/notices/USN-5101-1 — yes (WebFetch + raw `curl` cross-check)
- Verbatim quote checked: yes for the four package names, against raw HTML saved locally
- Quote substring confirmed at: `grep -o "mongodb[a-z-]*"` against the saved HTML file, exactly four distinct matches: `mongodb`, `mongodb-clients`, `mongodb-server`, `mongodb-server-core`

---

##### Finding Q2.7: repology.org's MongoDB tracking scope relative to the official `mongodb-org` packages is not established — UNVERIFIED

**Evidence:** Direct `curl` against `https://repology.org/project/mongodb/versions` returned an HTTP 403 Forbidden response (a 7-line HTML error body, `<title>403 Forbidden</title>`, `server: nginx`), so raw-HTML verification was not possible. The WebFetch tool's own extraction of the page stated:

> "I cannot find explicit information about whether Repology tracks MongoDB Inc.'s official `mongodb-org` packages from their repository or only distribution-packaged versions."

**Source:** `https://repology.org/project/mongodb/versions` — **UNVERIFIED** (direct fetch blocked with HTTP 403; the WebFetch tool's own response is an explicit non-finding, not a quoted claim)

**Significance:** Not found: whether repology.org's "mongodb" project tracks the `mongodb-org` packages 4Shark runs, or only distro-packaged forks (the same "mongodb" vs. "mongodb-org" distinction that matters for USN in Finding Q2.6). This question is left open rather than answered from an unverifiable source.

**Verification block:**
- URL fetched: https://repology.org/project/mongodb/versions — attempted via both WebFetch tool and raw `curl`; raw `curl` returned HTTP 403 — UNVERIFIED
- Verbatim quote checked: no — the WebFetch tool itself reported it could not extract the relevant fact
- Quote substring confirmed at: N/A — no sustaining quote exists; this finding is a documented non-finding, not a claim

---

#### Question 3 — Community/official patch cadence for self-managed MongoDB

##### Finding Q3.1: MongoDB's own docs describe patch releases as available "as needed," with no fixed interval, and the only universal guidance is to always run the latest patch of the current series

**Evidence:** Raw HTML of the MongoDB Versioning page, confirmed via direct fetch:

> "Patch Releases are made available as needed to both Major Releases and Minor Releases."

and, elsewhere on the same page:

> "Always upgrade to the latest stable patch release of your release series."

**Source:** https://www.mongodb.com/docs/manual/reference/versioning/ (raw HTML fetched via `curl`, saved locally, `grep`-confirmed for both quotes)

**Significance:** MongoDB's own official position on patch-release timing is purely reactive/as-needed on the publishing side ("as needed"), and purely "always be current" on the consumption side, with no numeric interval (no "apply within N days" or "check every N weeks") stated anywhere on this reference page. This directly answers the "does MongoDB recommend a specific interval" half of the question: **no interval is documented** — the standing instruction is simply to always be on the latest patch of the series in use.

**Verification block:**
- URL fetched: https://www.mongodb.com/docs/manual/reference/versioning/ — yes (raw `curl`, reused from Round 1's Finding 1.1 fetch, re-confirmed for these two new quotes)
- Verbatim quote checked: yes for both quotes, against raw HTML saved locally
- Quote substring confirmed at: `grep -o "Patch Releases are made available[^<]*"` → "Patch Releases are made available as needed to both"; `grep -o "Always upgrade to the latest[^<]*"` → "Always upgrade to the latest stable patch release of your release series."

---

##### Finding Q3.2: A real MongoDB Community Hub security-patch announcement used "encouraged" language with no stated urgency timeline

**Evidence:** Per WebFetch tool extraction of the community thread:

> "All Community Edition users are encouraged to upgrade to the latest version to ensure this patch is applied."

**Source:** https://www.mongodb.com/community/forums/t/important-mongodb-patch-available/332977 (WebFetch tool extraction; not independently raw-HTML-verified in this session)

**Significance:** This is a real, MongoDB-affiliated (posted in the official "Server Releases" announcements category, per the WebSearch result title) example of how a specific security patch was actually communicated to the community. It uses "encouraged" — non-mandatory, non-urgent phrasing — and does not state a deadline, a severity-driven timeline, or any recommended maximum delay before applying. This is consistent with, and corroborates, Finding Q3.1's "as needed / always latest" framing rather than a graded urgency scale.

**Verification block:**
- URL fetched: https://www.mongodb.com/community/forums/t/important-mongodb-patch-available/332977 — yes, via WebFetch tool
- Verbatim quote checked: yes as returned by the WebFetch tool; not independently re-fetched via raw `curl` in this session (forum pages of this kind are commonly client-rendered) — flagged as tool-extracted, not raw-HTML-verified
- Quote substring confirmed at: WebFetch tool's extraction of the thread body, per its own summary

---

##### Finding Q3.3: No MongoDB-specific community consensus on a numeric patch cadence (e.g. monthly or quarterly) was found despite multiple targeted searches

**Evidence:** Two independent WebSearch queries targeting MongoDB-specific patch-cadence guidance ("MongoDB patch update frequency recommendation production", "MongoDB community forum patch cadence production best practice") returned only: the official upgrade-procedure docs (already covered in Round 1 and Finding Q3.1), general replica-set upgrade how-to threads with no cadence discussion, and a Percona blog post about MAJOR-version adoption timing (not patch cadence) that stated no patch-interval guidance either — per WebFetch tool extraction:

> "there is no specific guidance given on how often or how quickly production self-managed MongoDB deployments should apply patch releases."

**Source:** WebSearch aggregation (two queries) plus https://www.percona.com/blog/mongodb-6-0-should-you-upgrade-now/ (WebFetch tool extraction of the Percona post specifically)

**Significance:** This is a genuine "not found," stated explicitly per the Research-First Policy rather than filled with an invented consensus: **no MongoDB-specific community-recommended patch cadence (e.g. "patch quarterly," "patch within 30 days of release") was located** in this round's research, across both official MongoDB sources and third-party community/vendor commentary (Percona). This corroborates and extends Round 1's Finding 1.1/1.5 observations about the ambiguity in MongoDB's own "every two years" major-release cadence language — the same absence of a hard number applies to patch-level cadence, but here it is a genuine void rather than an internal inconsistency.

**Verification block:**
- URL fetched: https://www.percona.com/blog/mongodb-6-0-should-you-upgrade-now/ — yes, via WebFetch tool
- Verbatim quote checked: yes as returned by the WebFetch tool for the Percona-specific quote; the WebSearch aggregation itself is not a single fetchable URL and is cited as a search process, not a quoted source
- Quote substring confirmed at: WebFetch tool's own summary sentence for the Percona blog post

---

##### Finding Q3.4: Oracle documents its own quarterly Critical Patch Update / Release Update cadence — a different database vendor's own practice, not MongoDB or a cross-database community consensus

**Evidence:** Raw HTML of Oracle's Database Patch Maintenance Guidelines, confirmed via direct fetch:

> "If you choose this strategy, then Oracle recommends that your apply frequency is quarterly (every three months)."

**Source:** https://docs.oracle.com/en/database/oracle/oracle-database/19/dbptc/index.html (raw HTML fetched via `curl`, saved locally, `grep`-confirmed)

**Significance:** This is Oracle's own documented recommendation for its own product's Release Update strategy — it is explicit, numeric, and quarterly. It is presented here strictly as a **cross-database comparison point**, exactly as Round 1 used cross-database `unattended-upgrades` incidents (Finding 2.3) for a different sub-question: a different, unrelated database vendor with its own patch-release mechanics does publish and recommend a specific numeric cadence, which shows such guidance is possible in the industry generally. It is explicitly **not** MongoDB's position, and no source in this research found MongoDB or its community endorsing or referencing a comparable numeric interval. This finding does not resolve the "is there a clear community consensus for MongoDB" question — it is evidence that the absence of one for MongoDB (Finding Q3.3) is a real gap relative to what at least one other major RDBMS vendor documents for itself, not evidence that MongoDB should be expected to follow the same number.

**Verification block:**
- URL fetched: https://docs.oracle.com/en/database/oracle/oracle-database/19/dbptc/index.html — yes (WebFetch + raw `curl` cross-check)
- Verbatim quote checked: yes, against raw HTML saved locally
- Quote substring confirmed at: `grep -o "apply frequency is quarterly[^<.]*"` against the saved HTML file → "apply frequency is quarterly (every three"

---

#### Question 4 — MongoDB 8.0 platform support for Ubuntu 26.04

##### Finding Q4.1: MongoDB 8.0's Supported Platforms table (production notes / manual) lists only Ubuntu 20.04, 22.04, and 24.04 — no 26.04

**Evidence:** Raw HTML of the MongoDB Manual's Production Notes page (the page hosting the Supported Platforms table), confirmed via direct fetch:

```
grep -oE "Ubuntu [0-9]+\.[0-9]+" → Ubuntu 20.04 / Ubuntu 22.04 / Ubuntu 24.04 (three distinct matches, no others)
```

**Source:** https://www.mongodb.com/docs/manual/administration/production-notes/ (raw HTML fetched via `curl`, saved locally, `grep -oE "Ubuntu [0-9]+\.[0-9]+"` returned exactly three distinct version strings)

**Significance:** This is a direct, raw-HTML-verified confirmation that the current MongoDB manual's platform-support content lists exactly three Ubuntu LTS releases — 20.04, 22.04, 24.04 — and no fourth entry for 26.04. Note this URL is the version-unpinned "current manual" page (it may reflect the latest MongoDB series' support table, not necessarily 8.0-specific in isolation); Finding Q4.2 below repeats the same confirmation on the explicitly version-pinned `v8.0` install docs.

**Verification block:**
- URL fetched: https://www.mongodb.com/docs/manual/administration/production-notes/ — yes (raw `curl`)
- Verbatim quote checked: yes, the three Ubuntu version strings are literal `grep` output against the saved HTML file
- Quote substring confirmed at: `grep -oE "Ubuntu [0-9]+\.[0-9]+"` output, three distinct matches, sorted and de-duplicated

---

##### Finding Q4.2: The version-pinned MongoDB 8.0 Ubuntu install docs list apt repository lines only for focal (20.04), jammy (22.04), and noble (24.04) — no resolute (26.04)

**Evidence:** Raw HTML of the v8.0 Ubuntu install tutorial, confirmed via direct fetch:

```
grep -oE "(focal|jammy|noble|oracular|plucky|questing|resolute)/mongodb-org/8\.0" →
focal/mongodb-org/8.0
jammy/mongodb-org/8.0
noble/mongodb-org/8.0
```

(the regex explicitly tested for six intermediate/newer Ubuntu codenames — `oracular`, `plucky`, `questing`, `resolute` — none of which matched)

Per WebFetch tool extraction, the exact repository line shown for noble is:

```
deb [ arch=amd64,arm64 signed-by=/usr/share/keyrings/mongodb-server-8.0.gpg ] https://repo.mongodb.org/apt/ubuntu noble/mongodb-org/8.0 multiverse
```

**Source:** https://www.mongodb.com/docs/v8.0/tutorial/install-mongodb-on-ubuntu/ (raw HTML fetched via `curl`, saved locally, `grep`-confirmed; version-pinned to the 8.0 manual specifically, unlike Finding Q4.1's unpinned URL)

**Significance:** This is the strongest documentation-level confirmation available, because it is the version-pinned 8.0 manual (not the "current"/latest-series manual, which could in principle differ over time): MongoDB 8.0's own install instructions provide apt repository configuration for exactly three Ubuntu codenames (focal/20.04, jammy/22.04, noble/24.04), and the regex search for every Ubuntu codename released between 24.04 and 26.04 inclusive (oracular 24.10, plucky 25.04, questing 25.10, resolute 26.04) found zero matches.

**Verification block:**
- URL fetched: https://www.mongodb.com/docs/v8.0/tutorial/install-mongodb-on-ubuntu/ — yes (raw `curl`, reused/re-verified from Round 1's Finding 2.1 fetch)
- Verbatim quote checked: yes, the three codename matches are literal `grep` output against the saved HTML file
- Quote substring confirmed at: `grep -oE` output, exactly `focal/mongodb-org/8.0`, `jammy/mongodb-org/8.0`, `noble/mongodb-org/8.0`, no other codename matched

---

##### Finding Q4.3: The `repo.mongodb.org` apt repository's own S3 bucket listing contains exactly seven Ubuntu codename directories — bionic, focal, jammy, noble, precise, trusty, xenial — with no `resolute` (26.04) directory

**Evidence:** Raw XML response from a direct S3 `ListObjectsV2` API call against the bucket backing `repo.mongodb.org`:

```xml
<ListBucketResult xmlns="http://s3.amazonaws.com/doc/2006-03-01/"><Name>repo.mongodb.org</Name><Prefix>apt/ubuntu/dists/</Prefix><KeyCount>8</KeyCount><MaxKeys>1000</MaxKeys><Delimiter>/</Delimiter><IsTruncated>false</IsTruncated><Contents><Key>apt/ubuntu/dists/index.html</Key>...</Contents><CommonPrefixes><Prefix>apt/ubuntu/dists/bionic/</Prefix></CommonPrefixes><CommonPrefixes><Prefix>apt/ubuntu/dists/focal/</Prefix></CommonPrefixes><CommonPrefixes><Prefix>apt/ubuntu/dists/jammy/</Prefix></CommonPrefixes><CommonPrefixes><Prefix>apt/ubuntu/dists/noble/</Prefix></CommonPrefixes><CommonPrefixes><Prefix>apt/ubuntu/dists/precise/</Prefix></CommonPrefixes><CommonPrefixes><Prefix>apt/ubuntu/dists/trusty/</Prefix></CommonPrefixes><CommonPrefixes><Prefix>apt/ubuntu/dists/xenial/</Prefix></CommonPrefixes></ListBucketResult>
```

**Source:** `https://s3.amazonaws.com/repo.mongodb.org?list-type=2&prefix=apt/ubuntu/dists/&delimiter=/` (direct S3 API call via `curl`, raw XML response reproduced verbatim above)

**Significance:** This is primary-source, machine-generated evidence — not documentation prose that could be stale or a copy/paste error, but the literal bucket listing backing the apt repository infrastructure itself. It confirms exactly seven Ubuntu codename directories exist at `repo.mongodb.org/apt/ubuntu/dists/`: `bionic` (18.04), `focal` (20.04), `jammy` (22.04), `noble` (24.04), `precise` (12.04), `trusty` (14.04), `xenial` (16.04). There is no `resolute` (26.04) directory. This holds regardless of MongoDB series (the listing is not scoped to 8.0 specifically — it is the full set of Ubuntu codenames ever published for any MongoDB series on this repository), and is corroborated by the version-pinned per-series findings above (Q4.1, Q4.2) for the 8.0 case specifically.

**Verification block:**
- URL fetched: `https://s3.amazonaws.com/repo.mongodb.org?list-type=2&prefix=apt/ubuntu/dists/&delimiter=/` — yes (direct `curl` against the S3 API, raw XML)
- Verbatim quote checked: yes, the full XML response is reproduced verbatim above from the actual `curl` output
- Quote substring confirmed at: the `<CommonPrefixes>` elements of the raw XML response, seven total, none containing "resolute"

---

##### Finding Q4.4: A direct HTTP request for the `resolute` (26.04) `mongodb-org` 8.0 apt `Release` file returns 404; the `noble` (24.04) control request returns 200

**Evidence:** Two direct HTTP status-code checks via `curl -s -o /dev/null -w "%{http_code}"`:

```
https://repo.mongodb.org/apt/ubuntu/dists/resolute/mongodb-org/8.0/Release → 404
https://repo.mongodb.org/apt/ubuntu/dists/noble/mongodb-org/8.0/Release   → 200
```

**Source:** `https://repo.mongodb.org/apt/ubuntu/dists/resolute/mongodb-org/8.0/Release` and the `noble` equivalent (direct `curl` HTTP status checks)

**Significance:** This is the most direct possible confirmation of Question 4's central factual claim: an actual HTTP request for the exact file an `apt-get update` would fetch if a `resolute`/26.04 apt source line were configured for `mongodb-org` 8.0 returns 404 Not Found, while the identical request pattern against `noble` (24.04, MongoDB 8.0's newest officially-listed Ubuntu release per Findings Q4.1–Q4.2) returns 200 OK. **MongoDB 8.0 does not have a published apt repository for Ubuntu 26.04 as of this test (2026-07-14).**

**Verification block:**
- URL fetched: both URLs — yes (direct `curl -s -o /dev/null -w "%{http_code}"`, HTTP status codes only, no body parsing involved)
- Verbatim quote checked: n/a — this is a direct HTTP status-code observation, not a text quote; the status codes 404 and 200 are reproduced verbatim from the actual command output
- Quote substring confirmed at: direct terminal output of the two `curl` invocations, reproduced above

---

##### Finding Q4.5: Ubuntu 26.04 LTS is codenamed "Resolute Raccoon" and was officially released on 23 April 2026 — it is already released, not upcoming, as of the spike's date (2026-07-14)

**Evidence:** Raw HTML of the official Ubuntu 26.04 release notes, `grep`-confirmed:

```
Resolute Raccoon)
23 April 2026
```

Per WebFetch tool extraction of the official Ubuntu release-cycle page, the 26.04 row states "Released: Apr 2026" with standard security maintenance through "May 2031."

**Source:** https://documentation.ubuntu.com/release-notes/26.04/ (raw HTML fetched via `curl`, saved locally, `grep`-confirmed for both the codename and the release date) and https://ubuntu.com/about/release-cycle (WebFetch tool extraction for the release-cycle table row)

**Significance:** This directly answers the "is Ubuntu 26.04 LTS actually released as of July 2026" half of Question 4: **yes** — it was released 23 April 2026, roughly three months before the spike's date (2026-07-14). Ubuntu 26.04 is not a future/hypothetical release the engineer might be anticipating; it is a currently-shipping LTS that 4Shark could in principle already be targeting for a golden-AMI OS bump, except that MongoDB 8.0 has no published apt repository for it (Findings Q4.1–Q4.4).

**Verification block:**
- URL fetched: https://documentation.ubuntu.com/release-notes/26.04/ — yes (raw `curl`); https://ubuntu.com/about/release-cycle — yes, via WebFetch tool only (not independently raw-HTML-re-verified for the release-cycle table specifically in this session)
- Verbatim quote checked: yes for "Resolute Raccoon" and "23 April 2026" against raw HTML saved locally; the release-cycle table's "Released: Apr 2026" / "May 2031" figures are WebFetch-tool-extracted only
- Quote substring confirmed at: `grep -o "Resolute Raccoon[^<]*"` and `grep -o "23 April 2026"` against the saved HTML file, both non-empty and matched multiple times

---

##### Finding Q4.6: A third-party practitioner blog corroborates that MongoDB 8.2+ has no native repository for Ubuntu 26.04/"resolute" and documents a manual archive-`.deb` workaround

**Evidence:** Per WebFetch tool extraction of the blog post:

> "Get the latest version of .deb from https://www.mongodb.com/try/download/community-edition/releases/archive"

using an "Ubuntu 24.04 x64" package as the download source to install on Ubuntu 26.04, plus a documented kernel-compatibility workaround ("an issue in the 6.9+ kernels and Mongo") requiring changes to `/etc/default/mongod`.

**Source:** https://blog.nevyn.co.za/ubuntu-26-04-and-mongodb-8-2/ (WebFetch tool extraction; not independently raw-HTML-verified in this session)

**Significance:** This is a single practitioner's blog post — not an official MongoDB source and not independently raw-HTML-verified — presented as corroborating context for the primary-source findings above (Q4.1–Q4.4), not as sustaining evidence on its own. It is consistent with those findings: the author's own workflow assumes no native `resolute` MongoDB repository exists and instead installs the 24.04-built `.deb` package manually, plus documents an unrelated kernel-compatibility issue on newer kernels (6.9+) that is a separate concern from repository availability and was not otherwise investigated in this spike.

**Verification block:**
- URL fetched: https://blog.nevyn.co.za/ubuntu-26-04-and-mongodb-8-2/ — yes, via WebFetch tool
- Verbatim quote checked: yes for the archive-download quote and the kernel-issue quote, as returned by the WebFetch tool; not independently re-fetched via raw `curl` in this session
- Quote substring confirmed at: WebFetch tool's own extraction of the article body

---

### Trade-offs surfaced (round 2)

| Mechanism | Pros (per sources) | Cons (per sources) | Source |
|---|---|---|---|
| MongoDB Alerts RSS feed (`alerts/rss`) | Official, MongoDB-maintained; confirmed live with current 2026 CVE entries; covers Security/Data-Integrity/Operations/General categories in one feed | Not filtered to MongoDB Server Community Edition specifically — carries all alert categories and all MongoDB products (drivers, Compass, etc.) mixed together; no official mailing list alternative found | Findings Q1.1, Q1.2, Q1.5 |
| Renovate `customManagers` regex + `endoflife-date` datasource, applied to the Ansible role / Packer variable | Fully within the existing Renovate self-hosted setup already in use (per the spike's Round 1 context); documented, general-purpose mechanism with a worked example on a structurally similar non-manifest file (Terraform `.tfvars`); would flow through the existing 7-day `minimumReleaseAge` gate discussed in Round 1 | Requires the team to author and maintain a custom regex + `renovate:` comment in the Ansible/Packer files; whether `endoflife-date`'s MongoDB entries are patch-level granular was not established in this research (Finding Q2.3) | Findings Q2.2, Q2.3, Q2.4 |
| NVD CVE API 2.0 (`cpeName`/`virtualMatchString`) as a custom poller | Official US-government CVE source; filterable by product/vendor | Pull-only — needs a scheduled script and somewhere to post results; the source page for this finding could not be raw-HTML-verified in this session (Finding Q2.5, UNVERIFIED) | Finding Q2.5 |
| GitHub Dependabot | Zero-maintenance if the dependency were in a supported manifest format | Confirmed (raw HTML, zero matches) to not support Ansible or Packer files at all — not usable for this specific pinning shape | Finding Q2.1 |
| Ubuntu USN / apt unattended-upgrades as a detection signal | N/A — no pro identified for this specific use case | Confirmed (raw HTML) to track the Ubuntu-archive `mongodb` package family (stuck on a legacy 3.6.x lineage), not the `mongodb-org` package 4Shark actually runs — structurally cannot serve as a notification channel for 4Shark's MongoDB version | Finding Q2.6 |

### What remains uncertain (round 2)

- **Whether `endoflife-date`'s MongoDB tracking on endoflife.date (and by extension Renovate's built-in `endoflife-date` datasource) is granular to the individual patch release (e.g. distinguishing 8.0.25 from 8.0.26) or only to the minor/major line** was not established — the page's version-table structure was not examined for this specific granularity question (Findings Q2.3, Q2.4).
- **Whether repology.org's "mongodb" project tracks the official `mongodb-org` packages** or only distro-packaged forks is unresolved — direct verification was blocked (HTTP 403) and the WebFetch tool's own extraction could not answer it either (Finding Q2.7, UNVERIFIED).
- **The NVD CVE API 2.0 findings (Finding Q2.5) could not be raw-HTML-verified** in this session because the source page is a client-rendered JavaScript application; the WebFetch tool's extraction is internally consistent with NVD's publicly documented API design but carries reduced confidence per the citation discipline's UNVERIFIED tag.
- **No numeric, MongoDB-specific, community-recommended patch cadence was found** (Finding Q3.3) — this is presented as a genuine absence rather than an unresolved search; further, more exhaustive searching (e.g., conference talks, MongoDB University materials, larger operators' public engineering blogs beyond Percona) was not attempted in this round and might surface guidance not found here.
- **Whether MongoDB has any forward-looking public statement about adding Ubuntu 26.04 support in a future 8.x minor/patch release** (as opposed to only the current-state absence confirmed in Findings Q4.1–Q4.4) was not searched for in this round — only the current supported-platforms state was investigated, not MongoDB's own roadmap or issue tracker for future Ubuntu-version support.

### Suggested options for main and the engineer (round 2)

- Option F: subscribe to/poll the MongoDB Alerts RSS feed (Finding Q1.2) as the official, MongoDB-maintained security-notification channel, routed through whatever RSS-to-notification bridge the team already uses (or a small poller).
- Option G: add a Renovate `customManagers` regex rule + the built-in `endoflife-date` datasource (Findings Q2.2–Q2.4) against the Ansible role's/Packer's MongoDB version variable, so a MongoDB version bump surfaces as a Renovate PR through the same 7-day-gated flow already used for other dependencies (per Round 1's findings).
- Option H: combine Options F and G — RSS/Alerts feed for human-readable CVE awareness, Renovate regex+datasource for the mechanical PR-opening/gating side — since neither mechanism alone was found to cover both "a human learns a CVE exists" and "a PR is automatically opened to bump the pin."
- Option I: build a small NVD CVE API 2.0 poller (Finding Q2.5) scoped by `cpeName`/`virtualMatchString` for MongoDB Server, accepting the UNVERIFIED-source caveat on this specific finding and the added maintenance burden of a bespoke script versus the off-the-shelf options F/G.
- Option J: treat Ubuntu 26.04 as not currently viable for the golden-AMI OS given MongoDB 8.0 has no published apt repository for it (Findings Q4.1–Q4.4) — remain on 20.04 or move to 22.04/24.04 (both MongoDB-8.0-supported per the same findings) for any near-term OS-upgrade work, revisiting 26.04 only if/when MongoDB publishes `resolute` repository support.

(No recommendation — these are the surfaced options; main and the engineer choose.)
