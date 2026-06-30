# PLAN — Compliance documents (current services, no AI)

> Status: **executed, with open follow-ups**. Session date: 2026-06-25. This file is the durable record of what was done, decided, and left pending in the compliance-document work — the decisions and pending items lived only in the session chat otherwise. Research backing the cookie decisions is in `cookie-consent/SPIKE.md` (same parent dir). The AI-assistant work is a separate topic at `~/.claude/plans/active/spike/4shark-internal-ai-assistant/`.

## Goal

Finalize 4Shark's compliance documents for the **current** services (no AI assistant) — make the RoPA, the DPA, and the public privacy policy accurate and consistent, and republish the corrected public policy.

## What was executed (all merged)

- **`compliance` PR #2** — registered the observability sub-processors (**New Relic, Datadog, Rollbar**) in the RoPA § 3 and the DPA Cláusula Quarta, and added **Zendesk** to the DPA clause (it was in the RoPA but missing from the DPA — pre-existing gap, fixed).
- **`compliance` PR #3** — corrected two false/defensive statements in the public privacy policy cookies section: removed *"não trocamos cookies com … terceiros"* (false) and replaced the *"desativação impede o acesso"* note with an accurate statement that strictly-necessary cookies are exempt from consent under the LGPD.
- **Public policy PDF republished to S3** — rebuilt the corrected policy via `compliance/build/build.sh`, filled the placeholders with the **current entity** (kept as-is, see decision below), and **overwrote `s3://4shark-legal/4shark_politica_de_privacidade_brasil_v2.pdf`** (the version the site serves). Old v2 backed up at `/tmp/politica_s3_v2_20260625.pdf` — **/tmp is volatile (lost on reboot)**; if a durable backup matters, move it.
- **`dot-claude` PR #287** — removed an entity-reconciliation note (legacy entity + external-party reference) from the `GENERATE-COMPLIANCE-DOCUMENTS.md` runbook; the engineer had said that question was to be checked "at the end", not documented in the runbook.

## Decisions taken (2026-06-25)

- **Google Analytics → remove (option C of the cookie research).** GA is NOT declared in the policy, NOT added to the RoPA/DPA. The actual **removal of GA from the front-end was deferred** by the engineer ("voltamos no futuro").
- **Session/auth cookie** — confirmed by research (ANPD cookie guide + ePrivacy Art. 5(3)) to be a strictly-necessary cookie, **exempt from consent**; no opt-out is owed for it. The corrected policy reflects this.
- **Public-policy entity/CNPJ — kept as 4SHARK TECNOLOGIA LTDA (23.839.883/0001-23).** Engineer decided NOT to change it now ("a gente não vai mudar o CNPJ"). The entity-reconciliation question is deferred to "the end", out of current scope.
- **Legal-proof tag — deferred.** Not created (Git Tag & Version Policy requires explicit per-tag authorization).

## Open follow-ups (the debt)

1. **Remove Google Analytics from the front-end** (separate repo). Deferred. While GA still runs, the policy is *neutral/silent* about it — it no longer lies ("no third-party cookies" removed), but it omits an active third party. Closing this fully = delete the GA tag from the front-end, then the policy is plainly truthful.
2. **Legal-proof git tag** in the `compliance` repo for the published policy version — the runbook/README say the proof of "what the document said at time X" is a git tag + deterministic rebuild, not the PDF. Not done; needs the engineer's explicit tag authorization.
3. **Entity structure — RESOLVED (2026-06-26).** Research (`multi-entity-privacy-policy/SPIKE.md`) confirmed LGPD does NOT require a privacy policy per CNPJ; market practice is one group policy; no enforcement precedent for CNPJ identification. Decision: a **three-category entity rule** — public-facing (privacy policy) + RoPA → the **principal entity** (4SHARK TECNOLOGIA LTDA, the group's original entity, which holds the shared infra); internal policies → the **employer** (4Shark Soluções Financeiras Ltda, where all staff are); client-facing (DPA) → the **entity on each client's contract** (one template, filled per client). The runbook's old "3× per operator" rule was wrong and was replaced (dot-claude PR #289, compliance README PR #4). The multi-CNPJ structure is NOT an LGPD problem and requires NO inter-entity binding — the entities stay separate (tax structure); any formalization of the shared-infra relationship is an optional contractual matter for legal, not an LGPD requirement.
   - Minor follow-up (optional, non-blocking): the two data-treatment policies still carry `[ENTIDADE]` placeholders but are now classified internal (employer entity); they could be hardcoded to 4Shark Soluções Financeiras Ltda like the other internal policies, for consistency.
4. **Deepgram DPA** has no confirmed LGPD coverage (from `cookie-consent` research is GA; this one is from the AI ANALYSIS) — only relevant if the AI assistant's voice path advances. Tracked in the AI topic's `ANALYSIS.md`.

## Pointers

- Cookie-consent research + sources: `~/.claude/plans/active/compliance-docs/cookie-consent/SPIKE.md` + `cookie-consent_*.txt`.
- Multi-entity / multi-CNPJ privacy-policy research + sources: `~/.claude/plans/active/compliance-docs/multi-entity-privacy-policy/SPIKE.md` + `privpolicy_*.txt`.
- **Group entities — single source of truth:** `~/Projects/4Shark/compliance/records/entidades-do-grupo.md` (the 4 CNPJs, roles, and the per-document entity rule). The generation runbook reads it. PRs: compliance #5 (record), dot-claude #290 (runbook reference). Document kept with placeholders (not hardcoded), per engineer decision.
- Repo `compliance` (`~/Projects/4Shark/compliance/`): RoPA `records/registro-de-operacoes-de-tratamento-ropa.md`, DPA `internal/acordo-de-processamento-de-dados-pessoais.md`, public policy `public/br/politica-de-privacidade.md`. PRs #2, #3.
- Repo `dot-claude`: runbook `docs/runbooks/compliance/GENERATE-COMPLIANCE-DOCUMENTS.md`. PR #287.
- Generation/publish process: the `GENERATE-COMPLIANCE-DOCUMENTS.md` runbook (fill placeholders in a working copy, `build.sh` → PDF, upload to S3; entity/CNPJ from accounting).
- Ephemeral HTML reports from this session live in `/tmp/spike_4shark_*.html` — regenerable from the SPIKE/PLAN markdown; not the source of truth.
