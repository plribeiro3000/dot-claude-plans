# SPIKE — DR Restore-Test Fidelity (BCP/DRP item P7)

## Investigation question

4Shark has provisioned cross-region DR backups (AWS Backup, daily backup +
copy to us-west-2, 7d local + 7d DR retention) for its 7 application
databases. The BCP/DRP document being written for vendor-security
assessments (Positivo, Grupo Barigui) must state an RTO/RPO and claim the DR
is "tested annually, RTO achieved" (item P7). The current planning docs say
only "do one restore test from the DR vault" without specifying its
fidelity.

Questions to answer with cited sources, not opinion:

1. What makes a restore test "valid" evidence for a BCP/DRP — is a
   restore-to-a-laptop ever accepted, or must it be the real managed
   platform (RDS/Aurora)?
2. What is the industry taxonomy of DR test depth, and which tier does a
   "tested annually, RTO achieved" claim actually require?
3. Does AWS Backup's native Restore Testing feature satisfy this
   requirement, and how does it work?
4. Does restoring an AWS Backup recovery point for RDS/Aurora create a new
   instance/cluster or restore in place — and what does that imply for the
   real "prod corrupted" recovery path and RTO measurement?
5. Does a valid test need to match production's infrastructure
   (instance class, Multi-AZ, sizing), or is a smaller non-prod target
   enough?
6. How should 4Shark state and test RPO honestly, given daily backup +
   cross-region copy?

## Sources consulted

- [AWS Well-Architected Framework — Reliability Pillar, REL13-BP02](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/rel_planning_for_recovery_disaster_recovery.html) — the four DR strategies, their RTO/RPO bands, and what "restore" mechanically does in a real disaster. See auxiliary `dr-restore-test-fidelity_doc_1.txt`.
- [AWS Well-Architected Framework — Reliability Pillar, REL13-BP03](https://docs.aws.amazon.com/wellarchitected/latest/reliability-pillar/rel_planning_for_recovery_dr_tested.html) — the dedicated "test DR implementation" best practice. Same auxiliary file.
- [AWS Backup — Restore testing](https://docs.aws.amazon.com/aws-backup/latest/devguide/restore-testing.html) — the native `RestoreTestingPlan`/`RestoreTestingSelection` mechanism. See `dr-restore-test-fidelity_doc_2.txt`.
- [AWS Backup — Restore testing validation](https://docs.aws.amazon.com/aws-backup/latest/devguide/restore-testing-validation.html) — event-driven validation hooks. Same auxiliary file.
- [AWS Storage Blog — Implementing restore testing for recovery validation using AWS Backup](https://aws.amazon.com/blogs/storage/implementing-restore-testing-for-recovery-validation-using-aws-backup/) — framing of why the feature exists. Same auxiliary file (medium confidence — summarized extraction).
- [AWS Backup Audit Manager — Controls and remediation](https://docs.aws.amazon.com/aws-backup/latest/devguide/controls-and-remediation.html) — the "Restore time for resources meet target" control that turns a restore test into dated compliance evidence. See `dr-restore-test-fidelity_doc_3.txt`.
- [Amazon RDS User Guide — Restoring to a DB instance](https://docs.aws.amazon.com/AmazonRDS/latest/UserGuide/USER_RestoreFromSnapshot.html) — confirms restore-from-snapshot always creates a new instance. See `dr-restore-test-fidelity_doc_4.txt`.
- [NIST SP 800-34 Rev. 1 — Contingency Planning Guide for Federal Information Systems](https://nvlpubs.nist.gov/nistpubs/legacy/sp/nistspecialpublication800-34r1.pdf) — the impact-graded TT&E (Testing, Training, Exercises) taxonomy, read directly from the PDF (pages 27, 29-30). See `dr-restore-test-fidelity_doc_5.txt`.
- [ISO 22301:2019 Clause 8.5 exercise program — third-party summary (iso-docs.com)](https://iso-docs.com/blogs/iso-22301-standard/iso-22301-clause-8-5-exercise-program) — general exercise/testing program shape. NOT the official ISO text (paywalled). See `dr-restore-test-fidelity_doc_6.txt`.
- [Google SRE Book — Data Integrity: What You Read Is What You Wrote](https://sre.google/sre-book/data-integrity/) — the "backups vs proven restores" distinction and "full end-to-end test" framing. See `dr-restore-test-fidelity_doc_7.txt`.
- [Acsense — Disaster Recovery Testing: A Comprehensive Guide](https://acsense.com/blog/disaster-recovery-testing-a-comprehensive-guide/) — the checklist/tabletop/walkthrough/simulation/parallel/full-interruption taxonomy. See `dr-restore-test-fidelity_doc_8.txt`.
- `https://www.oreilly.com/library/view/chaos-engineering/9781492043850/ch05.html` (Google DiRT primary chapter) — **UNVERIFIED**: fetch returned HTTP 403 Forbidden (paywalled). No claim in this SPIKE is sustained by this source; DiRT is mentioned only via the search-result summary as background context, not as a cited Finding.

## Findings

### Finding 1: None of the authoritative testing frameworks accept a laptop/local-DB restore as valid evidence — all define fidelity around "the operational environment" or "an actual test of the components... used to conduct daily operations"

**Evidence:**

NIST SP 800-34 Rev. 1's own definition box for "Testing":

> "A test is conducted in as close to an operational environment as
> possible; if feasible, an actual test of the components or systems used
> to conduct daily operations for the organization should be used."

And the general guidance in §3.5.1:

> "Testing can take on several forms and accomplish several objectives but
> should be conducted in as close to an operating environment as
> possible."

Google's SRE book states the same idea from an engineering-practice angle:

> "The only test that should let you sleep at night is a full end-to-end
> test."

**Source:** NIST SP 800-34 Rev. 1, p. 27 (`dr-restore-test-fidelity_doc_5.txt`); Google SRE Book, Data Integrity chapter (`dr-restore-test-fidelity_doc_7.txt`).

**Significance:** "Components... used to conduct daily operations" for
4Shark's app databases are RDS/Aurora, not a local Postgres process. None of
the fetched sources contain an explicit sentence naming "a laptop" as
acceptable or unacceptable — that specific artifact is not addressed by any
authority found — but every authority frames validity around proximity to
the real operational platform, which a local Postgres restore structurally
is not (different engine build, no AWS Backup `StartRestoreJob` mechanics
exercised, no IAM/VPC/security-group path exercised, no lazy-loading
behavior exercised). A laptop restore proves the backup file is
structurally importable; it does not exercise the recovery mechanism 4Shark
would actually invoke in a disaster (AWS Backup → RDS/Aurora).

### Finding 2: NIST SP 800-34 grades required test depth by system impact level — and 4Shark's client-PII databases point toward the "functional exercise... recovery from backup media" tier at minimum

**Evidence:**

> "For low-impact systems, a tabletop exercise at an organization-defined
> frequency is sufficient... For moderate-impact systems, a functional
> exercise at an organization-defined frequency should be conducted... 
> Exercise procedures should be developed to include an element of system
> recovery from backup media... For high-impact systems, a full-scale
> functional exercise at an organization-defined frequency should be
> conducted. The full-scale functional exercise should include a system
> failover to the alternate location. This could include additional
> activities such as full notification and response of key personnel to
> the recovery location, recovery of a server or database from backup
> media or setup, and processing from a server at an alternate location.
> The test should also include a full recovery and reconstitution of the
> information system to a known state."

**Source:** NIST SP 800-34 Rev. 1, p. 29-30 (`dr-restore-test-fidelity_doc_5.txt`).

**Significance:** This is a graded, cited taxonomy tying the *required*
test depth to the *impact* of the system, not to organizational
preference. NIST does not classify 4Shark's specific systems — that
classification (low/moderate/high, under the FIPS 199 model NIST assumes)
is an internal judgment call the engineer/team would make, informed by the
fact that these databases hold client PII under LGPD, feed vendor-security
assessments explicitly demanding "RTO achieved," and serve productive
paying clients. The "moderate" tier's requirement — "an element of system
recovery from backup media" — is the floor a "tested annually, RTO
achieved" claim would need to satisfy under this framework; the "high"
tier additionally requires the full failover + reconstitution-to-known-
state step (i.e., the application cutover, not just the DB restore).

### Finding 3: The DR-test-type industry taxonomy has six named tiers; "parallel testing" (restore to a non-prod duplicate) and "full-interruption testing" (drill on live production) are the two highest-fidelity tiers, and only the latter touches production

**Evidence:**

> "Parallel testing is a comprehensive testing approach. It involves
> creating a duplicate recovery system to use when running DRP tests."
>
> "Full-interruption testing is similar to parallel testing. However, in
> this scenario, the tests are conducted on the live production system
> rather than a duplicate recovery system. This testing method is by far
> the most realistic..."

**Source:** Acsense, "Disaster Recovery Testing: A Comprehensive Guide" (`dr-restore-test-fidelity_doc_8.txt`).

**Significance:** This taxonomy independently corroborates the engineer's
framing that production restore-testing is a distinct (and separately
risky) tier from non-prod restore-testing — "parallel testing" against a
non-prod duplicate is a recognized, named tier in its own right, not a
watered-down compromise. It sits below "full-interruption" (which the
engineer has already ruled out for production, for a data-loss reason this
taxonomy does not itself address — see Finding 6) and above
tabletop/walkthrough/simulation.

### Finding 4: AWS's own Well-Architected guidance treats "never exercise failovers in production" as an anti-pattern, and frames DR testing as needing to happen "in production" for complex/critical paths — a data point in tension with the engineer's "production is out" premise, which the engineer resolves separately via the data-loss argument

**Evidence:**

> "Common anti-patterns: Never exercise failovers in production."
>
> "If you have a complex or critical recovery path, you still need to
> regularly exercise that failure in production to convince yourself that
> the recovery path works... you should fail over to the standby
> regularly, regardless of need."
>
> "Our experience has shown that the only error recovery that works is the
> path you test frequently."

**Source:** AWS Well-Architected Framework, REL13-BP03 (`dr-restore-test-fidelity_doc_1.txt`).

**Significance:** This guidance is written for standby/failover
architectures (pilot light, warm standby, multi-site active-active) where
"failing over" means routing live traffic to an already-live, already
-replicated standby with near-zero RPO — not for a "Backup and restore"
strategy where "restore" means reconstructing a database from a
point-in-time snapshot. For 4Shark's actual DR strategy (Backup and
restore, per Finding 5), restoring the production database's own recovery
point onto production infrastructure is not "failing over to a warm
standby" — it is overwriting/duplicating over the only copy of live data,
which is where the engineer's data-loss argument applies (see Finding 6).
AWS's anti-pattern is real and cited, but it presumes a DR strategy tier
4Shark has not adopted; it does not directly contradict the engineer's
"production is out for restore testing" conclusion under the Backup-and-
restore strategy specifically.

### Finding 5: 4Shark's cross-region AWS Backup setup is the "Backup and restore" DR strategy tier — AWS's own framework states this restore path always deploys new resources, not in-place recovery, and defines RTO to include infrastructure/app steps beyond the raw restore

**Evidence:**

> "Backup and restore (RPO in hours, RTO in 24 hours or less): Back up your
> data and applications into the recovery Region... In the event of a
> disaster, you will deploy your infrastructure (using infrastructure as
> code to reduce RTO), deploy your code, and restore the backed-up data to
> recover from a disaster in the recovery Region."
>
> "For backup and restore, restoring data from backup creates resources for
> that data such as EBS volumes, RDS DB instances, and DynamoDB tables. You
> also need to restore the infrastructure and deploy code."

And, confirmed independently at the RDS API level:

> "You can't restore from a DB snapshot to an existing DB instance; you
> create a new DB instance when you restore the snapshot."
>
> "When you restore a DB instance, the default virtual private cloud (VPC),
> DB subnet group, and VPC security group are associated with the restored
> instance, unless you choose different ones. As soon as the restore is
> complete and your new DB instance is available, you can also change the
> VPC settings by modifying the DB instance."

**Source:** AWS Well-Architected Framework, REL13-BP02 (`dr-restore-test-fidelity_doc_1.txt`); Amazon RDS User Guide, "Restoring to a DB instance" (`dr-restore-test-fidelity_doc_4.txt`).

**Significance:** Two mechanical facts follow directly from these sources,
answering research question 4:

1. **A real "prod corrupted" recovery is never "restore over the existing
   cluster."** It is always: restore recovery point → brand-new RDS/Aurora
   instance with a new endpoint → repoint the application's connection
   string/DNS/secret to the new endpoint → validate. AWS's own RTO
   definition ("the maximum acceptable delay between the interruption of
   service and restoration of service" — REL13-BP02 context, corroborated
   generally across the fetched WAF pages) spans that whole path, not just
   the database-restore duration.
2. A restore-testing setup that only measures "how long did
   `StartRestoreJob` take" (which is what AWS Backup's native Restore
   Testing feature measures — see Finding 7) is measuring a real but
   partial component of RTO. It does not, by itself, drill or time the
   application-cutover step.

### Finding 6: 4Shark's cross-region backup RPO is "hours," not near-zero — and this is expected and documented behavior for the Backup-and-restore DR strategy tier, distinct from RDS/Aurora's own native point-in-time recovery (PITR)

**Evidence:**

> "Backup and restore (RPO in hours, RTO in 24 hours or less): Back up your
> data and applications into the recovery Region. Using automated or
> continuous backups will permit point in time recovery (PITR), which can
> lower RPO to as low as 5 minutes in some cases."

**Source:** AWS Well-Architected Framework, REL13-BP02 (`dr-restore-test-fidelity_doc_1.txt`).

**Significance:** AWS's own framework distinguishes the "Backup and
restore" strategy's baseline RPO (hours, i.e., bound by backup cadence) from
what "automated or continuous backups" with "point in time recovery (PITR)"
can achieve (as low as 5 minutes). This is presented as an optional
enhancement to the Backup-and-restore strategy, not something it has by
default. 4Shark's context statement that native RDS PITR is "independent
and separate" from the cross-region AWS Backup copies is consistent with
this source: PITR (via transaction logs, minute-level granularity) is a
same-region continuous-recovery mechanism; it does not, on its own, replicate
data cross-region — the cross-region DR posture 4Shark has today rests on
the daily AWS Backup copy job, whose cadence is what actually bounds the
DR-region RPO, independent of whatever local PITR window exists.
No fetched source in this spike specifically addresses "how to phrase RPO
honestly in a BCP" beyond the general framing that RPO is a stated business
risk-tolerance decision (from the general web-search summary on RPO —
this general claim did not resolve to a single quotable authoritative
source and is therefore not elevated to a cited Finding; flagged here as
context only, not as a citation-backed claim).

### Finding 7: AWS Backup's native "Restore testing" feature automates exactly the mechanism these frameworks call for — real, scheduled, RDS/Aurora-capable restores, with optional automated validation and deletion — and produces dated compliance evidence, but it measures only the restore job itself, not application cutover, and carries no AWS-provided RTO guarantee

**Evidence:**

> "Restore testing, a feature offered by AWS Backup, provides automated and
> periodic evaluation of restore viability, as well as the ability to
> monitor restore job duration times."
>
> "The resource types you can assign to your testing plan include: Aurora,
> ... Amazon RDS..."
>
> "Restore testing runs restore jobs in the same way as on-demand restores
> and uses the same recovery points (backups) as an on-demand restore."
>
> "After the restore test plan completes its run, you can use the results
> to show compliance for organizational or governance requirements such as
> the successful completion of restore test scenarios or the restore job
> completion time."
>
> "Once the optional validation completes or the validation window closes,
> AWS Backup deletes the resources involved with the restore test."

And on the RTO-evidence side, AWS Backup Audit Manager's dedicated control:

> "Evaluates if restoring protected resources completed within the target
> restore time. This control checks if the restore time of a particular
> resource meets the target duration. The rule is NON_COMPLIANT if
> LatestRestoreExecutionTimeMinutes of a resource type is greater than
> maxRestoreTime in minutes."
>
> "Note: AWS Backup does not provide any service-level agreements (SLAs)
> for a restore time. Restore times can vary based upon system load and
> capacity, even for restores containing the same resources."

On instance-class/sizing fidelity, the feature treats it as an overridable
parameter, not a fixed requirement:

> "It is recommended in most cases to maintain these parameters; however,
> you can change the values... parameters such as availability zone,
> database name, database instance class, and VPC security group will
> appear with inferred values you can change if applicable."

**Source:** AWS Backup, "Restore testing" and "Restore testing validation" (`dr-restore-test-fidelity_doc_2.txt`); AWS Backup Audit Manager, "controls-and-remediation.html" (`dr-restore-test-fidelity_doc_3.txt`).

**Significance:** This is the AWS-native mechanism whose real, RDS/Aurora-
targeted restore mechanics directly match what NIST SP 800-34's "moderate"
tier calls for ("an element of system recovery from backup media") and
what Finding 1's "as close to an operational environment as possible" bar
calls for — it runs the actual `StartRestoreJob` path against the actual
managed database engine, not a local substitute. It also directly produces
the auditable, dated evidence a "tested annually, RTO achieved" BCP clause
needs (via restore-testing job history + the "Restore time meets target"
Audit Manager control). Two gaps remain, both cited above: (a) it measures
restore-job duration only, not the application-cutover step that a true
end-to-end RTO includes (Finding 5); (b) AWS explicitly disclaims any SLA
on restore time, so the RTO number is 4Shark's own measured claim, not an
AWS guarantee.

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|---|---|---|---|
| Restore to local/laptop Postgres | Fastest, free, no AWS resources created | Does not exercise AWS Backup's `StartRestoreJob` mechanism, IAM/VPC path, or the actual RDS/Aurora engine; no source found treats this as meeting "as close to an operational environment as possible" or "components... used to conduct daily operations" | NIST SP 800-34 p.27 (`doc_5`); Google SRE (`doc_7`) |
| Restore to real RDS/Aurora, but smaller/cheaper instance class than production | Exercises the real managed platform and the real restore mechanism; proves recoverability; cheaper than like-for-like | Restore duration (and therefore measured RTO) may not represent production's true restore time — larger production data volumes and instance classes materially affect duration, especially with RDS/Aurora's lazy-loading behavior | AWS Backup restore-testing "Restore parameters" section (`doc_2`); RDS "lazy loading" note (`doc_4`) |
| Restore to like-for-like production-sized RDS/Aurora | Measures a true, representative RTO | Higher cost per test; more infra to tear down afterward | AWS Backup cost-control guidance (`doc_2`) |
| AWS Backup native Restore Testing (automated, scheduled) | Matches NIST's "as close to operational environment as possible" bar; produces dated, auditable evidence automatically (Audit Manager control); auto-cleans-up; supports RDS/Aurora natively | Measures restore-job duration only — does not drill or time application cutover/repoint; no AWS SLA on restore time, so the RTO claim is still 4Shark's own measurement | `doc_2`, `doc_3` |
| Manual periodic restore drill to a throwaway RDS/Aurora in the DR region, with documented steps and timing (including a manual cutover step) | Captures the full path including cutover; fully under 4Shark's control; can be run against a chosen non-prod stack | Manual effort each time; risk of "drudgery... not performed... deeply or frequently enough" per Google SRE's critique of manual recovery tests | Google SRE (`doc_7`) |
| Full game-day: restore + actual application cutover on a non-prod stack (beta/demo), including pointing the app's DB connection at the recovered instance | Highest fidelity short of touching production; matches NIST's "high-impact" tier ("full recovery and reconstitution... to a known state") and the "parallel testing" tier in the DR taxonomy; produces the most convincing "RTO achieved" evidence | Most operationally involved; requires coordinating a real cutover on a live (if non-prod) stack | NIST SP 800-34 p.29-30 (`doc_5`); Acsense taxonomy (`doc_8`) |
| Full-interruption test on production itself | "By far the most realistic" per the DR-test taxonomy; matches AWS's "regularly... in production" anti-pattern guidance for critical paths | For 4Shark's Backup-and-restore DR strategy specifically, restoring a recovery point does not "fail over to a live standby" — it reconstructs from a point-in-time snapshot, so testing it on production means accepting data loss back to the recovery-point instant, which the engineer's framing already rules out for productive client data | Acsense taxonomy (`doc_8`); AWS WAF REL13-BP03 anti-pattern (`doc_1`) — noted as applying to standby/failover strategies, not directly to Backup-and-restore |

## What remains uncertain

- No fetched source states a rule like "an auditor will reject a laptop
  restore" in those words — the "as close to operational environment as
  possible" framing is the closest sourced proxy, and it is a strong one,
  but it is inference from framework language, not a direct prohibition
  found in any text.
- No fetched source gives a single authoritative sentence on "how to
  phrase RPO honesty in a BCP document" — the general web-search summary on
  RPO communication did not resolve to one quotable, citable primary source
  and was therefore excluded as a Finding rather than force-fit into one.
- FIPS 199 impact classification (low/moderate/high) is a NIST US-federal
  concept; NIST itself does not classify 4Shark's specific systems, and no
  source found maps FIPS 199 tiers onto LGPD-context private-sector vendor-
  security assessments (Positivo, Grupo Barigui) directly — the mapping
  from "this is client PII feeding a vendor-security assessment" to "this
  is at least moderate-impact" in this SPIKE is the engineer/team's own
  judgment call, informed by but not dictated by NIST SP 800-34.
- The Google DiRT primary chapter (O'Reilly) could not be fetched (403);
  its only appearance in this SPIKE is as background context from a search
  snippet, explicitly marked UNVERIFIED, and no claim rests on it.
- Whether 4Shark's actual application architecture (connection string,
  secrets, DNS) makes the "repoint to new RDS/Aurora endpoint" cutover step
  fast (seconds, via a parameterized secret) or slow (manual, multi-step)
  was not investigated in this spike — it is a 4Shark-codebase question,
  not an external-research question, and would need to be answered before
  picking between Option B and Option C below (see Suggested options).

## Suggested options for main and the engineer

- **Option A — AWS Backup native Restore Testing, automated, on a
  designated non-prod target (beta/demo).** Configure a `RestoreTestingPlan`
  scoped to the 7 protected resources (or a representative subset),
  targeting RDS/Aurora resources with restore parameters pointed at the
  beta/demo account or a dedicated non-prod restore-test scope, on an
  annual (or more frequent) schedule, with `RestoreTestingValidation` via
  Lambda/EventBridge, and the Audit Manager "Restore time for resources meet
  target" control turned on to produce dated compliance evidence
  automatically. Matches NIST's "moderate-impact" tier and Finding 1's
  environment-fidelity bar. Does not by itself drill or measure the
  application-cutover step (Finding 5), so the RTO figure it produces is a
  restore-duration figure, not a full incident-response RTO, unless
  complemented by Option C periodically.

- **Option B — Manual periodic restore drill to a throwaway RDS/Aurora in
  the DR region (us-west-2), with documented steps and timing, including a
  manual cutover step to a scratch application instance or a read-only
  smoke test against the restored database.** Fully under 4Shark's control,
  can include the cutover step end-to-end, but is manual — carries the risk
  Google SRE's "drudgery... not performed... deeply or frequently enough"
  critique names for infrequent manual recovery tests (Finding 1/7). Maps
  to the "parallel testing" tier in the DR taxonomy (Finding 3).

- **Option C — Full game-day: restore onto beta/demo's actual RDS/Aurora
  infrastructure, then actually repoint the beta/demo application's
  connection to the recovered instance (real cutover), measure end-to-end
  time from "declare disaster" to "application serving from recovered
  data."** Matches NIST's "high-impact" tier ("full recovery and
  reconstitution... to a known state") and the "parallel testing" tier
  exercised to its fullest — this is the option that produces an "RTO
  achieved" number that includes the cutover step Finding 5 shows the raw
  restore duration omits. Most operationally involved of the three; would
  need a decision on cadence (e.g., annual, matching the BCP's "tested
  annually" language) versus AWS Backup Restore Testing running more
  frequently as a lighter-weight complement.

- **Not mutually exclusive**: Option A (automated, frequent, dated evidence
  for the recurring compliance record) can run alongside a periodic Option
  B or C (an annual, higher-fidelity drill that closes the "does the
  measured RTO actually include cutover" gap Finding 5 and Finding 7
  surface). Which combination — and which non-prod stack, cadence, and
  scope of the 7 databases — is the engineer's decision; this SPIKE
  surfaces the evidence and the trade-offs, not the choice.
