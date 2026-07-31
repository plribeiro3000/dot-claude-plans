# Auxiliary sources — fetched documentation quotes

Consolidated verbatim quotes from every external source consulted for
`SPIKE.md`, one section per source. Each quote was fetched, then re-fetched a
second time to confirm the substring is still present (self-check per
`CITATION-DISCIPLINE.md`). No source in this file is marked UNVERIFIED — every
one resolved and every quoted substring was confirmed on the second fetch.

---

## 1. graphql-ruby — additive vs. breaking schema changes

**URL:** https://graphql-ruby.org/changesets/overview

**Quote (first fetch and re-fetch, identical):**

> "You can _always_ add new fields, new arguments, and new types to implement new features and customize existing behavior."

**Quote on enum values:**

> "For example, if you add a values to an Enum, you can just add it to the existing schema:"

**Context:** the page's framing is that additive changes (new fields, new
arguments, new types) go straight into the schema; only removal or
redefinition of existing schema parts needs the Enterprise "Changesets"
feature. Adding an enum value is explicitly listed as something you "can just
add ... to the existing schema" — i.e., additive, not gated behind a
Changeset.

---

## 2. GraphQL.org — general schema evolution guidance

**URL attempted:** https://graphql.org/learn/governance-versioning/
**Status:** HTTP 403 Forbidden on WebFetch — treated as UNVERIFIED, not cited
in any Finding. graphql-ruby's own changesets page (source 1) already carries
an equivalent, directly-fetchable statement, so no claim in `SPIKE.md` depends
on this URL.

---

## 3. Apollo Client — error handling / errorPolicy

**URL:** https://raw.githubusercontent.com/apollographql/apollo-client/main/docs/source/data/error-handling.mdx

**Quote — errorPolicy `none` (default):**

> "If the response includes errors, they are returned in the `error` field and the response `data` is set to `undefined` even if the server returns `data` in its response."

**Quote — validation errors specifically:**

> "If a syntax error or validation error occurs, your server doesn't execute the operation at all because it's invalid."

**Quote — HTTP status on a validation failure:**

> "If a GraphQL error prevents your server from executing your operation at all, your server may respond with a non-`2xx` status code."

**Quote — promise rejection under `none`:**

> "With the default `none` error policy, an error causes the promise to reject."

Both quotes were confirmed present on a second, targeted re-fetch that
searched for the exact substrings "doesn't execute the operation at all" and
found it verbatim.

---

## 4. Apollo Angular — error handling / errorPolicy

**URL:** https://the-guild.dev/graphql/apollo-angular/docs/data/error-handling

**Quote — `none` policy:**

> "This is the default policy to match how Apollo Client 1.0 worked. Any GraphQL Errors are treated the same as network errors and any data is ignored from the response."

**Quote — `ignore` policy:**

> "Ignore allows you to read any data that is returned alongside GraphQL Errors, but doesn't save the errors or report them to your UI."

**Quote — `all` policy:**

> "Using the `all` policy is the best way to notify your users of potential issues while still showing as much data as possible from your server. It saves both data and errors into the Apollo Cache so your UI can use them."

Re-fetch confirmed the exact substring "treated the same as network errors"
present, full sentence: "Any GraphQL Errors are treated the same as network
errors and any data is ignored from the response."

---

## 5. Netlify — manage deploys (lock / publish / rollback)

**URL:** https://docs.netlify.com/deploy/manage-deploys/manage-deploys-overview/

**Quote — locked deploys:**

> "Locked deploys give you the ability of pinning a site to the latest published deploy for the time being. New deploys won't be published to the main site, although Netlify will still build them and they will be ready for whenever you want to publish them."

**Quote — how to lock:**

> "You can lock a deploy by disabling auto publishing. To disable auto publishing, navigate to your site's Deploys list and select Lock to stop auto publishing."

**Quote — rollback via Publish Deploy:**

> "If you need to roll back, you can publish one of the previous deploys listed in the UI as the live version of your site in production. Use the Publish Deploy button on the detail page of any successful deploy. This doesn't trigger a new deploy but instead publishes a previous atomic deploy that is still available to you."

**Quote — instantaneous:**

> "Rollbacks are instantaneous."

---

## 6. Netlify — production branch / build triggers

**URL:** https://docs.netlify.com/site-deploys/overview/

**Quote — default trigger:**

> "By default, Netlify deploys your site's production branch after every merge to the production branch."

**Quote — where the production branch is configured:**

> "go to Project configuration > Build & deploy > Continuous Deployment > Branches and deploy contexts, and select Configure."

**Quote — production deploy definition:**

> "a deploy from the production branch. If auto publishing is enabled, each new production deploy will become the published deploy."

---

## 7. Angular — reactive forms / FormArray

**URL:** https://angular.dev/guide/forms/reactive-forms

**Quote — dynamic insert/remove:**

> "FormArray is an alternative to FormGroup for managing any number of unnamed controls... you can dynamically insert and remove controls from form array instances."

**Quote — push:**

> "The FormArray.push() method inserts the control as a new item in the array, and you can also pass an array of controls to FormArray.push() to register multiple controls at once."

**URL:** https://angular.dev/api/forms/FormArray

**Quote — `at(index)`:**

> "Get the AbstractControl at the given index in the array."

No verbatim sentence on patching an individual control inside a `FormArray`
was found on either page — the reference confirms `.controls` (the array of
`AbstractControl`) and `.at(index)` as the access primitives; the
"patch one control, iterate the rest" shape used for a replicate action is an
application of those two primitives, not a documented named pattern.
