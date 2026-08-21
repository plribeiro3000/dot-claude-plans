# Atento TPRM — Controls the Filed Answers Rest On

Every answer in `PLAN.md` describes the target state, and the questionnaire is filed. This file is
the list of controls those answers assert, grouped by who has to be involved — so each claim the
client now holds can be traced to the action that makes it true.

All 119 items are reviewed and their approved answers are recorded in `PLAN.md` — 90 `SÍ`, 18 `NO`,
11 `N/A`.

An item's **Blocks** line names the questionnaire items whose answer is not true without it. An item
with no **Blocks** line costs nothing in the questionnaire and is listed because the review surfaced
it. An entry still to be applied is picked up as its own piece of work with its own planning; this
file is the record of what each answer depends on, not a tracker of that work.

## Documents the review produced

Four changes to the `compliance` repository came out of the review, and they are the reason five
items carry a different verdict than the vendor template did. In every case the control already
operated and what was missing was the artifact — which is the diagnosis worth carrying into the
partner conversation, because it says the gap was registration rather than capability.

| PR | Document | Items it moved |
|---|---|---|
| #11 | `records/registro-de-operacoes-de-tratamento-ropa.md` corrected — Cloudflare and Redis Cloud added as suboperators | 13.1, 19.1, 20.2 rest on it |
| #12 | `internal/metodologia-de-classificacao-de-risco-de-tratamento.md` — ANPD Resolução CD/ANPD nº 2/2022 criteria, applied to all nine treatment activities | 18.4, 18.5 → `SÍ` |
| #13 | `internal/politica-de-gestao-de-fornecedores-e-suboperadores.md` + `records/inventario-de-fornecedores.md` — thirteen providers with function, personal-data flag, criticality and designated contact | 13.1, 20.1 → `SÍ` |
| #14 | `internal/procedimento-de-atendimento-a-solicitacoes-de-titulares.md` — LGPD arts. 18 and 19, built from the internal erasure runbook | 22.1 → `SÍ` |

The set in `compliance/internal/` now holds nineteen documents. Three of them were written during
this review and none of the nineteen carries an issue date — which is what makes "date and sign the
policy set" below the single most-depended-on task in this file.

## Needs a partner conversation first

These touch other people's machines or change a company-level document. None of them is the
engineer's to execute alone.

### Remove local install privilege from every employee workstation

Employee accounts run without administrative privilege; installation happens only through the
administrator account held by the Dirección Técnica. This is what makes the answers to 2.1 and 2.3
true, and it is the one action that reaches machines belonging to people who report to a partner —
so the partner agrees before anything is touched, and tells their team what changes and when.

Two consequences worth naming in that conversation, because they are what the affected person
feels: an application that installs per-user into the profile folder needs no elevation today and
will start needing a request, and any driver or system-level tool becomes an administrator task.
Neither is a side effect — both are the control the questionnaire is asking about.

**Blocks:** 2.3
**Done when:** no employee account can install software, and the administrator credential is held
by the Dirección Técnica only.

### Enforce automatic session lock on every employee workstation

The same visit sets the inactivity lock. Windows exposes it as the machine policy *Interactive
logon: Machine inactivity limit*, which writes `InactivityTimeoutSecs` under
`HKEY_LOCAL_MACHINE\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System`. Because the value
lives in `HKLM` rather than `HKCU`, a standard account cannot write to it — the setting survives the
user, which is the property the control needs. The questionnaire's threshold is 15 minutes, so the
value is `900`.

Two operational limits shape how this gets applied. The `Local Security Policy` / `gpedit.msc`
interface ships with Pro and Enterprise but not with Home, where the registry value still applies
and is the only path. And without domain or Entra join there is no remote push, so each machine is
configured by hand — which is why this pairs with the install-privilege change rather than standing
alone.

**Blocks:** 4.3
**Done when:** every employee workstation locks after 15 minutes of inactivity and the standard
account cannot alter or disable it.

### Enforce the host firewall on every employee workstation

Windows blocks inbound connections by default, so what is missing is 4Shark imposing it rather than
relying on the default staying untouched. The machine policy *Windows Defender Firewall: Protect all
network connections* greys out the user's own control, and without administrative privilege the
setting cannot be reverted. It is one more checkbox in the same configuration session as the two
items above.

What the answer commits to beyond the setting itself is the ongoing part: that a new machine, a
reinstall, or a new hire arrives with the firewall enforced.

**Blocks:** 4.5
**Done when:** the firewall is enforced by policy on every workstation and the standard account
cannot disable it.

### Apply the equivalent settings on the macOS and Linux machines

The fleet is not uniform: the operations team, which is the part that reaches real client data,
works on Windows, and the Windows recipe above covers those machines. The remaining machines —
engineering and the partners — run macOS and Ubuntu, and none of the Windows policies exist there.

Those machines are still corporate assets, and the answers to 2.3, 4.1, 4.3, 4.5 and 5.5 say "the
workstations" without qualifying by operating system. Leaving them out would make each of those five
answers partly false.

The equivalents, so the visit is not blocked by looking them up on the spot. On macOS: a
configuration profile setting the screen-lock delay, the application firewall enabled, and the daily
account separated from an administrator account. On Ubuntu: the desktop's automatic screen lock,
`ufw` enabled, and the daily user outside the `sudo` group with a separate administrative account.

One judgement belongs to the engineer rather than to this list: on the machines belonging to the
Dirección Técnica and the partners, running day-to-day without administrative privilege is a real
change to how they work. The control asks for exactly that — general-purpose activity from a
non-privileged account — but whether to apply it to themselves is their call, and answering
otherwise would narrow what the five answers claim.

**Blocks:** 2.3, 4.1, 4.3, 4.5, 5.5 — on the non-Windows portion of the fleet
**Done when:** every corporate machine, regardless of operating system, carries the four settings.

### Write the workstation baseline on one page

The three settings above are the baseline; what the questionnaire asks beyond applying them is that
the baseline exist as a document. One page naming each setting and its value is the whole
deliverable — no separate work, just writing down what the visit does.

It carries no recurring commitment: the question accepts review "annually **or** on significant
change", so the page is updated when the configuration changes rather than on a calendar.

**Blocks:** 4.1
**Done when:** a page states the standard workstation configuration — no administrative privilege,
15-minute inactivity lock, host firewall enforced — and matches what the machines actually have.

### Date and sign the policy set

**This is the most-depended-on task in the file: four answers cannot be written without it and three
more are weaker until it happens.** The nineteen documents in `compliance/internal/` are stored as
templates with unfilled placeholders — `**Data de emissão:** [DD/MM/AAAA]` and `**Aprovação:** [Nome
do Responsável Técnico]` are literal in the files, by design, since the repository holds the source
and the filled copy is rendered for signature. An assessor reads an undated, unapproved policy as a
draft, which is the same as not having one.

The date this produces is what fills the `[FECHA]` marker in four cells. It is **not** the DocuSign
date already on record: that round signed an earlier hand-made set the engineer reports carries copy
and wording errors, so citing it would attach the current text to an approval of different content.
The date to use is the one publishing the corrected set generates.

**Blocks:** 19.4, 20.1, 21.6, 22.1 — each carries `[FECHA]` and cannot be written without it.
**Also unblocks:** the formal-approval claim in 14.3, 15.1, 16.1, 21.6, 23.1 and 26.1. Those answers
stand today in a weakened form, with `formalmente aprobado por la dirección` removed six times over
because the claim does not hold until the round runs.
**Done when:** each document carries a real issue date and a named approver, and the publication date
is recorded here.

### Register the training sessions

The last sessions ran from 06/10/2025 to 10/10/2025, and that is the date the section-23 answers
carry. The `Registro de Treinamentos` in the engineer's Drive does not record them — it starts at
the June 2026 sessions — so the register the answers point at has to be built backwards from the
calendar and the mail record of that week.

Item 12.1 is what makes this more than bookkeeping: it claims annual recurrence and names the
register as its evidence, so the document that proves the control is also what can disprove the
claim. If the interval between two sessions turns out longer than a year, the cadence wording moves
in 12.1, 23.2, 23.3 and 23.4 together rather than one at a time.

The client-facing version carries no participant names. The answer claims a control, and a roster
would disclose team size — which no answer in this questionnaire does, by the engineer's standing
constraint.

**Blocks:** 12.1 — the register it cites is the one document an answer names that did not go in the
pack.
**Done when:** the register covers the October 2025 sessions and reaches the client.

### Reconcile the information-security policy with what 4Shark actually operates

The Segurança da Informação policy commits 4Shark to controls that do not exist — ISO 27001
adoption, data-loss prevention, and a media inventory among them. A published policy promising a
control 4Shark does not run is worse than a narrower policy, because the assessor can compare the
two and the gap is then documented by 4Shark itself.

The decision is which way to close the gap per promise: implement the control, or amend the policy
to describe what is really done. That is a partner call, not an engineering one.

**Done when:** every commitment in the policy is either operating or removed from the text.

## Engineering — the development team

### Move the Devise pepper out of source

The pepper is committed in plaintext at `app/config/initializers/devise.rb:120`. It is the secret
that, together with bcrypt, protects stored passwords: an attacker holding a database dump *and*
the pepper attacks the hashes offline far more comfortably than with the dump alone. Anyone with
read access to the repository holds it.

The cheap path changes nothing operationally: move the **same value** into the parameter store and
read it from an environment variable. No password is invalidated, because the value is unchanged.

One limit to state plainly rather than discover later: the value stays recoverable from git
history, so "never in source" becomes true going forward and not retroactively.

**Blocks:** 3.5 (the `nunca en código fuente` line)
**Done when:** the initializer reads the pepper from the environment and the repository working
tree carries no pepper value.

### Extend automated restore testing to every database and environment

Item 11.1 answers that the monthly restore test covers all databases. It currently runs against one
representative productive database, chosen because the infrastructure is identical everywhere, so
proving the mechanism on the largest one proves the mechanism — but not that every database has been
exercised, which is what an assessor reads into "all".

The work is small by design: the restore testing plan takes the databases as a list, so each
addition is one entry in `protected_resource_arns`, wired per stack in that stack's
`restore_testing.tf` alongside `modules/restore_testing_plan`.

Two things worth deciding while doing it. Non-productive environments cost the same to include and
make the claim unqualified, which is the point of the change. And the measured restore time scales
with database size, so each newly covered database produces its own number rather than inheriting
the representative one — which matters if the numbers are ever shown.

**Blocks:** 11.1
**Done when:** the monthly automated restore test covers every database in every environment.

### Activate automated analysis over the audit logs

Item 8.1 answers `SÍ` on the basis that the audit records are not only collected and retained but
also reviewed. Collection and retention are already strong — account actions are kept indefinitely
in an object-locked bucket — and what is missing is the review, which is one of the three minimums
the question names.

The same gap was raised in the Positivo vendor assessment and the mitigation is already chosen:
activate GuardDuty over CloudTrail, VPC Flow Logs and DNS, plus Security Hub against the CIS AWS
Foundations Benchmark, with SOC procedures formalized around the alerts. That work carries its own
90-day commitment there, which may be the tighter clock.

One lesson from that assessment applies directly: its reviewer rejected the wording that SIEM
adoption "was under evaluation" and demanded fact rather than intent, forcing a downgrade. The `SÍ`
here therefore requires the activation to have happened, not to be planned.

**Blocks:** 8.1
**Done when:** automated analysis runs continuously over the audit logs and its findings reach
someone.

### Ship the second factor for the application's support profile

Item 6.5 answers `SÍ` on the basis that every administrative access requires a second factor,
including the application's support profile, which authenticates with a password alone until this
lands. A pull request for it is open, and it ships alongside the workstation changes — so both have
to be done before the questionnaire is sent, not one or the other.

**Blocks:** 6.5
**Done when:** the support profile requires a second factor to authenticate.

### Confirm — or configure — that the VPN authenticates against the corporate identity provider

Item 6.4 answers `SÍ` on the basis that establishing the VPN connection carries the identity
provider's mandatory MFA. That holds only if the VPN delegates authentication to that provider; with
its own local users, no second factor applies at connection time and the answer is false.

The VPN module declares no authentication settings (`terraform/modules/vpn/`), which decides
nothing either way — that configuration lives in the VPN product's own admin interface rather than
in code.

**Blocks:** 6.4
**Done when:** the VPN's authentication is confirmed to run through the corporate identity provider,
either because it already does or because it was changed to.

### Decide whether to rotate the pepper value

Rotating it invalidates every stored password hash — a password reset for the entire user base.
That is not a reason to refuse; it is the reason it is a separate decision with its own plan, and
it must not ride along with the move above.

**Done when:** the decision is taken and recorded, either way.

### Correct the KMS transition comment in terraform

`modules/app/kms.tf` describes the two-keys-per-stack arrangement as transitional and prescribes
deleting `aws_kms_key.this` once it holds no readable data. The migration onto dedicated keys is
complete in the sense that consumers were repointed; whether the old key is free of readable data
is a different milestone, and the comment itself names the distinction.

Running as a spawned session; the deliverable is one PR against `develop`, with no apply.

**Done when:** the comment matches the real position, or the resources match the comment.

### Complete the service-provider inventory

The RoPA already carries a suboperator list — AWS, Google Workspace, 1Password, Zendesk — and the DPA
carries the suboperator-authorization clause. What 13.1 asks for beyond that is a criticality
classification and a designated corporate contact per provider, and neither field exists anywhere
today. The supplier-management policy that would hold them is registered as absent in the LGPD gap
analysis, so the inventory and that policy close in one effort.

The RoPA's own suboperator section is broader than the four-name summary above suggests — it already
carries Google Analytics and the observability trio New Relic, Datadog and Rollbar. Read the record at
`compliance/records/registro-de-operacoes-de-tratamento-ropa.md` rather than a summary of it.

Measured against what the Terraform provider declarations show as provisioned, two suboperators were
missing from that record and are added by compliance PR #11: Cloudflare, which resolves names and
terminates TLS for traffic bound to the platform, and Redis Cloud, which holds the background queue.
Three others were assessed and deliberately excluded — Netlify serves the web interfaces without
storing subject data, GitHub receives no subject data, and MongoDB Atlas has an infrastructure module
written but no environment instantiating it, so nothing sits under it today. That last one becomes a
suboperator the moment a first environment uses it.

Datadog needed no LGPD decision once the code was read: it receives counters whose tags are action,
API version, company identifier, controller and environment (`app/app/workers/api_metric_incrementor.rb:23-30`),
none of which identifies a natural person. Rollbar is the opposite and is correctly listed — person
tracking is left at the gem default, which calls `current_user`, and the request parameters reaching it
are filtered only by the list in `app/config/initializers/filter_parameter_logging.rb:8`, which covers
neither name nor document number.

The questionnaire text and the RoPA still contradict each other: the text lists GitHub and omits
Zendesk and the observability providers. An assessor receiving both documents sees two different
inventories of the same company, which costs more than the inventory earns.

The reconciliation table with the per-provider evidence is at
`/tmp/vendor_inventory_reconciliation_20260819.html`.

**Done.** The RoPA was corrected by compliance PR #11, and PR #13 added the supplier management policy
with the inventory it requires — thirteen providers, each with function, whether it processes personal
data, criticality and designated contact, plus the annual review. Items 13.1 and 20.1 both answer `SÍ`
on that basis.

Two residues stay with the engineer rather than in this file: confirming the criticality proposed per
provider, and deciding whether Émerson Oliveira holds any provider as designated contact instead of
the DPO. Slack and Monday were left out of the inventory because no source in code declares them; they
enter once confirmed.

### Add the 24-hour breach notification commitment to Atento's data processing agreement

Item 21.2 answers `SÍ` to notifying within 24 hours of becoming aware of an incident affecting personal
data processed for the client. That is a contractual obligation rather than a technical capability, so
until the clause exists the answer describes a practice; with it, the answer describes an obligation —
and only the second sustains a `SÍ` in a filed questionnaire.

The answer deliberately does not mention the general 72-hour term offered to other clients. Naming it
would frame the 24 hours as a commercial exception, which invites the question of how a non-standard
process is guaranteed, and it discloses terms of other contracts that nobody asked about.

**Blocks:** 21.2
**Done when:** the agreement with Atento carries the 24-hour notification term.

## Facts to confirm — no work, just an answer

Each of these is asserted by an answer already written. Confirming costs a sentence; being wrong
costs the credibility of the whole questionnaire.

**Does homologação ever receive a copy of production data, or is it synthetic only?** Two answers now
rest on it — 3.2 states it directly, and 12.5 uses it as the control against publishing data to an
unintended audience. One confirmation settles both; being wrong costs both.

**Does a presentable architecture data-flow diagram exist?** 19.1 names it as one of the three
instruments covering the data lifecycle. `app/docs/architecture/` holds technical markdown, which is
not the same as a diagram an assessor can be shown. If none exists the mention is dropped and the two
remaining instruments still sustain the `SÍ`.

**Was the infrastructure provider's data processing addendum formally accepted?** This is the item
with the sharpest consequence on the list. The standard contractual clauses that 16.4 names as the
international-transfer safeguard reach 4Shark through that addendum, so if the acceptance never
happened, the safeguard declared in the answer's own column does not exist — and that column is the
one an assessor reads first on this question.

**Do any of the other group entities have access to client data?** `legal-compliance-documents/PLAN.md:173`
records four CNPJs with the operation fragmented across them. The answer to 16.4 states no other group
company accesses data processed for the client; the documented fragmentation reads as fiscal and
contractual rather than data-access, but that reading is not a confirmation.

**Is 3680 days the legally correct retention for Mexico and Colombia?** The database holds that
figure for both, set by its own migration, as `countries.anonymizing_window_days`. Only Brazil
(1855 days) is cited in the answer, so an unconfirmed figure is not published — but if 3680 is
right, naming all three is stronger than naming one, and a client operating in four countries is
exactly who notices the difference. Affects 3.3.

**Does the cookie consent banner persist a queryable record on the 4Shark side?** 19.6 answers a
three-part question — when consent was obtained, from whom, and its content — and describes a record
holding the timestamp, the pseudonymous browser identifier and the accepted categories. If the banner
only writes the preference into the visitor's own browser, the ability to *demonstrate* lives on the
data subject's device and nowhere else. The `SÍ` survives either way; what changes is whether the
final clause about the record stays.

**Do the penetration test report and the client assessments carry dates?** 24.1 asks for them and the
answer carries none. Nothing breaks without them — but `la totalidad de los hallazgos remediados y
validados en retest` is the most concrete claim in that whole section, and a date is what shows the
scrutiny is recent rather than historical. Optional, and the engineer's call.

## Sweep every answer for single-jurisdiction legal anchoring

The questionnaire is answered in Spanish for a group operating across Latin America, so an answer
that grounds itself in one country's statute reads as an answer written for one country. Naming the
data categories carries the same information and holds in every jurisdiction; naming a single law
does not, and invites the assessor to ask which of their countries the rest of the answers were
written for.

The vendor-template text this review replaces cites Brazilian law by name, so any answer carrying
that anchor inherited it rather than chose it. A retention figure that genuinely differs per country
is the one legitimate case for naming a country — there the number belongs to that jurisdiction and
the answer says so.

**Done when:** every answer either names no statute, or names one because the fact itself is
specific to that jurisdiction.

## Resolve the classification conflict between items 3.1 and 19.1

Item 3.1 asserts that data is classified into six types — personal, sensitive personal, access
credentials, source code, internal operational documents, public documents — each with its own
handling, access, storage, retention and disposal rules, formalised in two named policies. Item 19.1
removed that same claim after finding no document defines those types or rules: `SPIKE.md:60` marks
the Política de Classificação da Informação as absent, and `legal-compliance-documents/PLAN.md:162`
records it as deferred until the team grows or ISO 27001 is pursued.

Two cells of the same questionnaire cannot claim a classification scheme and say it does not exist.
An assessor reading in sequence sees the contradiction, and it is the kind that costs credibility
across every other answer.

The cheap resolution is dropping the paragraph from 3.1 — its `SÍ` rests on schema-as-code being the
inventory, which the first paragraph carries alone. The other resolution is writing the
classification policy, which is the same move behind every document listed in "Documents the review
produced": the practice arguably exists, since the six types are how the team actually treats data,
and what is missing is the artifact. That is a larger piece of work than those four were, and it is
the reason dropping the paragraph is the recommended path.

**Blocks:** the final workbook write
**Done when:** either 3.1 no longer claims the scheme, or the policy exists and 19.1 claims it too.

## The delivery

The questionnaire was filed with Atento on 20/08/2026, in the mail thread the client opened
("Formulario de Seguridad"), addressed to the requester with the 4Shark and Atento participants in
copy. Two attachments went with it: the answered workbook
`~/Downloads/4Shark_Atento_TPRM_Questionnaire.xlsx`, written from `PLAN.md` with the yellow working
highlight dropped, and `anexos.zip`, carrying the supporting documentation in two folders —
`originales` (the Portuguese set as issued, plus the pentest report and the infrastructure
provider's data processing addendum) and `traducidos` (a literal Spanish rendering of the 4Shark
documents).

The Spanish rendering is a translation of the text and not a jurisdiction version: the policies are
issued under Brazilian law, the legal references stay Brazilian, and the covering message says so —
the original is the valid document and the translation exists so the client's security team can read
it. The two third-party documents are not translated, being their authors'.

Four questions decided the answers' final wording and each is settled in the filed text: the policy
publication date is 05/07/2023 (19.4, 20.1, 21.6, 22.1); the last training sessions ran 06/10/2025
to 10/10/2025 (23.2, 23.3, 23.4); the infrastructure provider's addendum is the international-transfer
safeguard and is attached (16.4, 20.2, 20.3); and item 3.1 no longer claims a data-classification
scheme, so it no longer contradicts 19.1.

**One document an answer cites is not in the pack.** Item 12.1 names a training register alongside
the awareness programme, and that register is still to be assembled from the calendar and mail
record of the October 2025 sessions. The client-facing version omits participant names — the answer
claims a control, not a roster, and naming people would disclose team size, which no answer in this
questionnaire does.

## Sending it again

Should the pack ever be reissued, the workbook and the zip are rebuilt rather than reused: the
Spanish documents are rendered from the compliance repository, which is the source of truth, and a
zip made by the macOS Finder carries `__MACOSX` and `.DS_Store` entries that a `zip -r -X` over the
folder does not.
