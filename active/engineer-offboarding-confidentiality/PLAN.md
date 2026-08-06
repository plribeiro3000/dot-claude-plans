# Post-Employment Confidentiality Instrument — Departing Senior Engineer

Record of the work done to build a defensible post-employment protection package for a departing
key engineer, the conceptual framework it produced, and the state everything was left in when the
company chose a different path.

**Status**: parked. The confidentiality-instrument track described here was **not** adopted. The
decision was taken to send the non-compete instrument instead. Everything below is complete enough
to be resumed without redoing the research.

**Language note**: this is an internal engineering planning document, so the prose is English per
`LANGUAGE-POLICY.md`. Legal citations, clause text, entity names and quoted material are preserved
literally in Portuguese as Category 4 embedded content.

---

## 1. Context

A senior engineer was terminated for cost reasons. He was the company's first employee, stayed
close to eight years, acted as the technical backup to leadership, and held broad access to code,
infrastructure, production data and business information.

The company cannot fund a paid post-employment restraint, so a compensated non-compete was ruled
out at the start of this work. The stated goal was to protect the specific, non-public, economically
valuable elements of the product without restricting the engineer's freedom to work — including at
a competitor — and without producing an instrument vulnerable to invalidation as a disguised
non-compete.

## 2. What was investigated

**Codebase.** All 23 repositories in the `4shark` GitHub organisation. The `app` repository was
swept exhaustively for business invariants after the engineer corrected the framing (see §3).

**Legal sources.** LPI art. 195 XI, Lei do Software art. 4º, Código Civil arts. 412/413/416, STJ
REsp 2.047.758/SP (Informativo 849), STJ REsp 1.498.829/SP, INPI software-registration guidance,
WIPO Guide to Trade Secrets, TST case law on post-contractual non-compete validity.

**Existing documents.** The two templates supplied by the accountant, the v2 confidentiality
instrument generated earlier in the session, and the market-practice research report.

## 3. The conceptual framework — the most reusable output

This is the part worth keeping regardless of which instrument is eventually used. It went through
two corrections, both driven by the engineer, and the final form is the one to start from.

### 3.1 Three levels

- **Level 1 — the idea.** "A variable-compensation system." "A goal dashboard." Protectable by no
  one, ever. INPI is explicit that conceptual software is not protectable.
- **Level 2 — the general technique.** Cache with fallback, blue/green deployment, producer/consumer,
  soft delete with audit columns. Public, in textbooks and vendor documentation. Claiming it weakens
  the whole instrument.
- **Level 3 — the concrete choice.** Not "use a cache" but *which TTL for which resource*. Not "have
  rules" but *the exact list of variable names each rule type accepts*. This is where the asset is.

### 3.2 The four tests

An item qualifies only if it passes all four: it is **specific** (a file, a list, a number can be
pointed at); it is **not public**; it is **not obvious** to a competent senior engineer facing the
same problem; and it is **valuable because it is hidden**.

### 3.3 The fourth test that was initially missed

**What a client can see by using the product is not a secret.** The immutability rule for
incentives is visible in the UI — the edit button is disabled and the clone button is not — so a
user learns it in seconds. Applying this filter eliminated most of the concept list drafted in §4.

The same filter reclassifies the rule-type variable vocabulary. It is tempting to read that list as
the crown jewel — it is specific, arbitrary in the technical sense, and would be damning if it
appeared in a competitor's product. But clients who configure rules know it, because it is the
language they write formulas in. That makes it confidential-contractual, held legitimately by N
third parties under NDA, rather than a trade secret in the strict sense. The proof burden is
correspondingly heavier.

### 3.4 The decisive distinction — information, not method

The contract protects **information that is recorded** (code, schemas, data, documentation,
decisions), never **method the engineer knows how to apply**. A clause list describing solution
patterns contradicts the instrument's own general-skill exclusion and hands the other side an
argument that the whole document overreaches.

Verified against WIPO: *"employees may use, in their post-employment activities, general knowledge,
skills and experience that they acquired from the normal course of work with the (former) employer."*

The combination doctrine survives this: *"a secret may also be made up of a combination of elements,
each of which by itself is publicly known, but where the combination, which is kept secret, provides
a competitive advantage."* It protects the company's specific combination — it does not stop the
engineer from applying the underlying pattern elsewhere.

### 3.5 Identification is a litigation burden, not a drafting burden

The contract defines the class; the internal inventory identifies the item if a dispute arises.
Enumerating secrets in a signed contract destroys the secret the contract exists to protect. STJ
REsp 1.498.829/SP imposed the particularity requirement on the *lawsuit*, not on the agreement.

## 4. The business-rule inventory of `app`

Twelve families, 47 rules, all read directly from code with file and line. Full detail in
`artefatos/regras_negocio_app_20260805.html`.

The central finding is that the reuse-then-freeze principle the engineer described for incentives is
**not an isolated rule — it is applied consistently to six configuration entities**, and reappears
in three more places:

| Entity | Freezes when | Evidence |
|---|---|---|
| Incentive | a plan uses it | `incentive_policy.rb:15` |
| Rankifier | an incentive uses it | `rankifier_policy.rb:22` |
| Calendar | a plan or performance analysis uses it | `calendar_policy.rb:15-16` |
| Role | a person occupies it | `role_policy.rb:22` |
| Acceptment reason | an acceptment uses it | `acceptment_reason_policy.rb:15` |
| Performance analysis | a calendar uses it | `performance_analysis_policy.rb:22` |

The escape hatch is the clone, and the rule lives as an **asymmetry between two neighbouring
methods**: `update?` carries the `record.plans.any?` guard, `clone?` deliberately does not
(`incentive_policy.rb:12-34`). Clone also has its own permission, separate from create and update.

The principle reappears in: commission with a generated report cannot be reprocessed
(`commission_policy.rb:82`); an anonymised user can be neither edited nor re-enabled
(`user_policy.rb:14,23`); a cancelled plan has no outbound state transition
(`plan.rb:117-144`).

Three rules found that the engineer had not named and that survive the client-visibility filter:

- **Participation is computed from history, not present state.** Who enters a commission is whoever
  had a group membership overlapping the calendar window, via `GroupificationHistory`
  (`plan.rb:173-190`). Someone who joined or left mid-period is included, to be pro-rated. The client
  sees the result, never the criterion — so this is not observable from the product.
- **Two responsibles minimum, and a sales rep can never be one.** `RESPONSIBLE_TYPES` holds 9 of the
  11 seat levels; `SuperAdmin` and `SalesRepresentative` are excluded (`plan.rb:4,403-417`). This is
  segregation of duties and conflict-of-interest control embedded in the product.
- **The test suite is an asset and is usually forgotten in inventories.** Every exception test exists
  because something broke in production; the suite is negative knowledge in executable form.

Open items where business context was needed and never obtained: why the minimum is **three** active
statuses (`status_policy.rb:31`), and how much of the 36 state machines is market convention versus
4Shark's own design.

## 5. Findings that are independent of which instrument is used

### 5.1 The contracting entity is not the obvious one

All three source documents carry `[RAZÃO SOCIAL DA EMPRESA]`. The authoritative record is
`compliance/records/entidades-do-grupo.md`, which lists four group entities and maps the NDA to the
**employer**: *"Confidentiality agreement (NDA) | Internal (per relationship) | the contracting
entity (current staff: 4Shark Soluções Financeiras Ltda)"* — CNPJ 49.673.485/0001-73. Not
4SHARK TECNOLOGIA LTDA, which *"holds no client contracts today."*

The same record warns: *"The authoritative source for the CNPJs and the client distribution is
accounting (Sérgio). Confirm before each generation."*

### 5.2 A prior NDA conflicts with any longer term

The company's standard template (`compliance/internal/contrato-de-confidencialidade.md`, v1.0) is
**project-scoped** and sets post-project confidentiality at *"[12 meses ou outro prazo]"*, with
foro elected in São Paulo/SP. Any new instrument setting five years collides with it, and a generic
"most specific provision prevails" clause does not resolve the collision — twelve months is more
specific than five years. This needs express novation naming the prior instrument and its date.

### 5.3 The reasonable-protection-measures evidence is not yet provable

The 13 internal policies in `compliance/internal/` carry `**Data de emissão:** [DD/MM/AAAA]` and
blank signature fields. The repository was created 2026-06-24, about a month before the departure.
Without dated, approved, signed policies, the third statutory requirement of art. 195 XI — that the
information was subject to reasonable protection measures — is materially harder to prove.

### 5.4 Access is documented and objectively determinable

`terraform/identity/github.tf:37-68` maps teams to repositories, and commit `aecf872` (2026-08-04,
on `develop`) removes the engineer. He was `maintainer` on five teams with `admin` on their
repositories: **20 repositories**. The two he never had were `compliance` and `data-privacy`.

He also held AWS console plus programmatic access with `ecs:ExecuteCommand` on `task/*` and
`cluster/*` **with no MFA condition** (`identity/policies_baseline.tf:96-142`) — a Rails console on
any production task, meaning read, write and delete across all customer data.

Note for reuse: `rubocop-fourshark` is in that list and is a **public** repository. Any annex must
exclude it explicitly, or the instrument claims as confidential something the company published.

### 5.5 Technical exposure that no contract addresses

These are the only items in this whole effort that **prevent** rather than punish, and they are not
parked — see §8.

The `app` repository versions `config/credentials.yml.enc`. Its decryption key, `config/master.key`,
is git-ignored but present on the disk of anyone who cloned and configured the project. Until the
signing key is rotated, whoever holds that copy can decrypt the versioned credentials across the
entire history, including the `secret_key_base` that signs sessions and JWTs.

`engineer-offboarding-access-reduction/TASKS.md` still lists as pending: the IAM access key was not
deleted, the orphaned virtual MFA device was not removed, and VPN (Pritunl) revocation is a separate
step outside the identity stack.

There is also no record of which queries the engineer ran in production, so extraction can be
neither asserted nor ruled out.

## 6. The decision

The accountant's own guidance had been against a non-compete: *"por mais que pagamos toda a rescisao
e multa inclusive do 40% do FGTS nao seria aconselhavel colocar non-compete mas pelo menos termos de
confidencialidade ... pelo menos foi essa a diretivas que recebi para ter validade juridica"*
(Slack, 2026-08-04).

On 2026-08-05 that was overridden: *"estou aqui com o danilo e solicitou para mandarmos esse non
compete mesmo / com todas as clausulas / de nao competicao"*. The response was to proceed and record
where the risk sits: *"se o danilo quer ir no outro entao fica no risco de decisao dele"*.

**Consequence for this plan**: the confidentiality-instrument track is parked. The non-compete
document was hardened instead (see §7). The known risk is that a post-employment non-compete without
adequate financial consideration is at high risk of invalidation — TST case law requires a reasonable
term, preserved professional freedom, and financial compensation. In the precedent located, the
validated clause ran one year against *"previsão de pagamento de seis salários em caso de dispensa
imotivada"*.

## 7. What was delivered, and where it is

All artifacts are copied into `artefatos/` so they survive `/tmp` being cleared.

| Artifact | What it is |
|---|---|
| `regras_negocio_app_20260805.html` | 12 families, 47 business rules of `app`, each with code and line |
| `checklist_ativos_4shark_20260805.html` | The conceptual framework and 25 candidate assets, in plain language |
| `inventario_segredos_offboarding_20260805.html` | Legal inventory, 16 gaps, matrix against the three documents, 13 prioritised changes |
| `nao_compete_clausulas_adicionais_20260805.txt` | The added clauses in clean text, plus the 11 blanks with the criterion for each |
| `Instrumento de Não Concorrência e Confidencialidade - v2.docx` | The hardened non-compete, ready except for the blanks |
| `Instrumento de Não Concorrência e Confidencialidade.docx` | The original, untouched |
| `Termo Pós-Contratual de Confidencialidade e Proteção de Informações.docx` | The lighter alternative that was not chosen |

### 7.1 What was changed in the non-compete

Nine edits, all applied and verified against the rendered document. The one that matters most is
**Cláusula 14-A**, which anchors confidentiality, non-use and IP in their own legal basis so they
survive if the non-compete clause falls — without it, striking Cláusula 2 for want of consideration
puts the whole instrument's cause in play.

The others: non-use made explicit (6.4); lawful-disclosure carve-out (6.5); IP ownership stated
under Lei 9.609 art. 4º instead of the circular original (7.1 rewritten); incident notification and
cooperation (8-A); consideration given indemnificatory nature, payment date, and a non-payment
consequence that releases only the non-compete (9.2 rewritten, 9.3, 9.4); penalty capped at the total
consideration (10.4); conservative reduction instead of outright invalidity (14.3); novation of the
prior instrument (16.2); labour-court competence reserved (17.2).

### 7.2 What is still blank

Eleven placeholders, four of which decide validity: term (2.1), protected competing activity (2.2 —
must be narrow, "soluções de remuneração variável", never "tecnologia"), territory (2.4), and the
consideration (9.1). Full list with criteria in the `.txt` artifact, Part 1.

## 8. Not parked — the technical items

These stand regardless of the contractual decision and are the only measures that reduce actual
capability:

1. Rotate `secret_key_base` and recycle `credentials.yml.enc` in `app`.
2. Delete the IAM access key and the orphaned virtual MFA device.
3. Revoke VPN (Pritunl) access.
4. Date, approve and collect signatures on the 13 internal policies in `compliance/internal/`.

## 9. If this is resumed

Start from §3 — the framework is the durable output and does not need redoing. Then:

Confirm with accounting which group entity signs, and locate the confidentiality agreement the
engineer actually signed on hiring, with its date and its filled term.

Draft the annex as **nine categories of artifact and data** — source code and derived artifacts;
data models and schemas; per-client configuration and parameters; rules, formulas and calculation
criteria *as recorded*; internal technical documentation including discarded alternatives; security
controls, vulnerabilities and credentials; personal and client operational data; commercial
information; undisclosed roadmap. Never as methods or concepts, for the reason in §3.4.

Attach the systems annex built in §5.4 from the terraform data, with `rubocop-fourshark` excluded,
and the signed return-and-deletion declaration — which is the piece with the highest practical
return, because it converts a hard claim (trade-secret misappropriation) into an easy one (false
statement in a signed instrument).

Keep the 47 business rules in the internal inventory only. They are the map of where value sits and
the roadmap for an expert examination; they are not contract text.

## 10. Open questions

Which group entity is on the employment contract. Which confidentiality agreement the engineer
signed and with what term. Whether he signed acknowledgement of the internal policies. Whether he
had access to commercial information — no evidence of it was found in any repository. What he
legitimately extracted during employment, which nothing records. His compensation, needed to
calibrate the penalty under CC art. 412. And the literal text of LPI art. 195 XI, which could not be
retrieved from an official source — Planalto refused every connection attempt and the MDIC page
truncates before the article, so it is confirmed only indirectly through the STJ decision applying
it.
