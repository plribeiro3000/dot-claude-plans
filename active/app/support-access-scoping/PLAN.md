# PLAN — Scoping support access to client data

**Project**: `app` · **Driver**: Atento TPRM questionnaire, item 3.2 (access control by need-to-know) · **Owner**: Paulo Ribeiro

## Problem

Support staff reach every client's data at all times. Read-only prevents corruption; it does nothing against disclosure, which is the risk the privacy half of a vendor assessment measures and the risk LGPD art. 6.º III addresses — *"limitação do tratamento ao mínimo necessário para a realização de suas finalidades, com abrangência dos dados pertinentes, proporcionais e não excessivos em relação às finalidades do tratamento"*.

The question the control asks is not whether unrestricted reading is comfortable, but whether it is **necessary**. An analyst handling a ticket for client A does not need client B open on the same screen. Standing access exceeds the stated purpose.

The target: access that is born from a reason, scoped to one client, valid for a window, and recorded.

## How the current bypass works

The bypass is **not** a single function. It is an idiom repeated across the policy layer — `app/policies/security_event_audit_policy.rb:15` is representative:

```ruby
def download?
  return false if company.client? && user.company_id != record.company_id
```

Read it inverted: the cross-company guard applies **only when the acting user's company is a client**. A user whose company is not a client (`Company#main?` is `!client?`, `app/models/company.rb:150-152`) skips the guard entirely, so `record.company_id` is never compared — every client's record is reachable.

**Measured surface: 121 occurrences across 81 policy files.** That single number decides the shape of the work: the condition cannot be amended in place 121 times without an unacceptable risk of missing one, and a missed one is a silent hole.

A second, narrower unscoping vector exists alongside it, in resolvers and a few policies: `current_company.main? || current_role.unscoped_queries?`. `unscoped_queries` is a boolean on `roles` (`db/schema.rb:1938`, default `false`), so it is an explicit per-role opt-out rather than an implicit consequence of company type. It needs the same treatment but is a much smaller set.

## What already exists and is reused

Three pieces are already built, which is what keeps this from being a from-scratch feature.

**Per-user permission grants.** `Permission` grants an action to a role **or** to a user, mutually exclusive by validation (`app/models/permission.rb:3-11`). Individual, non-role-derived grants are already a first-class shape in the model.

**The audit spine.** `SecurityEvent` exists and is in production (`app/models/security_event.rb`, design in `docs/architecture/SECURITY_EVENTS.md`), with a controlled event-type catalog, a frozen `SEVERITY_BY_TYPE` map, and a documented capture pattern. Recording an elevation is adding a type to the catalog and one capture site — not building a log.

**Company typing.** `Company#main?` / `#client?` already distinguish the internal company from client companies, and `SuperAdmin` is an STI subclass of `Seat` (`app/models/super_admin.rb:3`) whose permissions are provisioned per company by `Company::SuperAdmin::Processor`.

## Approach — two phases

The phases exist because of the 121 sites. Collapsing them into one PR mixes a mechanical, fully-verifiable refactor with new behavior, and makes the review unable to distinguish "this changed by accident" from "this changed on purpose".

### Phase 1 — Extract the idiom (behavior-preserving)

`ApplicationPolicy` (`app/policies/application_policy.rb`) already exposes `company`, `user`, `seat`, `role` and `record` to every policy, so a predicate defined there reaches all 81 files with no plumbing.

Replace the 121 repetitions with one call to a predicate on the base class. Behavior must be **identical** after this phase — the predicate's body is the current expression, moved.

The name is settled at implementation time under Pattern Priming against the sibling policies; it should read in the domain space (whether the acting user's access reaches the record's company), not the implementation space.

What makes this phase safe to review: the diff is uniform, the predicate body is the old expression verbatim, and any behavior difference is a bug rather than a design choice. It is also independently valuable — 121 copies of a security-relevant condition is a latent inconsistency regardless of this feature.

The `unscoped_queries` sites are folded into the same phase so both vectors end up behind one predicate.

### Phase 2 — The temporary grant

With one predicate to change, the JIT behavior lands in a single place.

A grant record scoped to one company, owned by a user, carrying a reason and an expiry. The extracted predicate consults it: a `main?`-company user reaches a client company's record only while an active grant covers that company. Absent a grant, a support user reaches nothing — default-deny, which is the platform's existing posture for permissions.

The elevation flow is self-service: the analyst picks the client, states the reason, receives the window. No client action is required, so support autonomy is unchanged — this is the pattern already used one layer down on AWS, where personal accounts are read-only by default and mutation requires MFA elevation bounded to one hour.

Expiry is enforced on read (a grant whose window has passed does not satisfy the predicate) rather than by a sweeper job — a sweeper that fails silently leaves access open, and the read-time check cannot.

The `SecurityEvent` capture goes in with the grant, not after it. Without the record of who elevated, for which client and why, the design answers the questionnaire but not the question that appears during an incident.

## Open decisions

These are the engineer's, and they change scope rather than approach.

**Window length.** The AWS precedent is one hour. A support ticket may outlive that; a longer window weakens the control. Renewal-on-demand versus a longer default is a real trade-off.

**Who may elevate.** Every support user, or a named subset. The grant model does not care; the answer decides whether an approval step exists at all.

**Scope granularity.** One client per grant is the assumption here. Whether an analyst can hold several simultaneously is a product decision.

**Historical access.** Whether existing standing access is revoked at cutover or expires naturally decides whether Phase 2 ships with a migration.

## Risks

**A missed site in Phase 1 is a silent hole.** The mitigation is that the phase is mechanical and the count is known — 121 occurrences, 81 files, verifiable by the same search after the change returning zero.

**The predicate becomes a hot path.** It is consulted on every authorization check. The grant lookup needs an index covering the acting user and the target company, checked against `db/schema.rb` before the query is written.

**Read-only is not the only surface.** This plan scopes what support can read through policies. Any path that reaches client data outside the policy layer is out of scope here and needs its own assessment.

## Relationship to the Atento questionnaire

The questionnaire does not require this to be built before the form is returned. Item 3.2 can be answered honestly describing the current control — individual credential, no write capability, access logged — and stating the per-client granularity as planned work. What cannot be done is answering `SÍ` claiming need-to-know while access is unrestricted.

See `~/Projects/4Shark/dot-claude-plans/active/content/vendor-assessment-atento-tprm/COMPLIANCE.md`.
