# Access Management Follow-ups

## Context

4Shark grants AWS access through three systems that must agree: Google Workspace decides whether a
person can authenticate, IAM Identity Center decides what they can do, and — for engineers only —
an IAM user carries the credential Terraform and the MFA elevation run on. The operator tier now
reaches AWS through the access portal with no key and no password handed over, the Google
organizational units gate which SAML apps each tier sees, and `ADD-TEAM-MEMBER.md` documents the
granting procedure end to end.

Four things that surfaced while building that have no owner. This plan holds them so they are not
lost, ordered by consequence rather than by effort.

## 1. SAML certificate rotation — has a deadline

The Google IdP certificate shared by all three SAML apps (AWS, Cloudflare, MongoDB Atlas) expires
**20 September 2026**. One certificate serves all three, so its expiry takes down single sign-on for
every one of them at once: nobody reaches the AWS access portal, the Cloudflare dashboard, or Atlas.
AWS documents the rotation as a recurring administrator task — *"you'll occasionally need to replace
older IdP certificates with newer ones... you might need to replace an IdP certificate when the
expiration date on the certificate approaches"* ([Configure SAML and SCIM with Google Workspace and
IAM Identity Center](https://docs.aws.amazon.com/singlesignon/latest/userguide/gs-gwp.html)).

Nothing tracks the date and no runbook covers the procedure. What the work needs: research how
Google Workspace rotates the certificate for a SAML app, what has to be re-uploaded on the Identity
Center side, whether the three apps rotate independently or together, and whether a window of
downtime is unavoidable. The output is a runbook under `engineer-access/` plus a reminder that fires
well before the date.

## 2. The operator toolkit has no source of truth

The toolkit handed to an external operator — the entry `CLAUDE.md`, the rules snippet, the settings
snippet, and copies of the read-only skills — exists as `~/Downloads/integrator-toolkit.zip` on one
machine and in no repository. Two consequences follow. Another engineer cannot send it without
asking for the file, and the embedded skill copies drift from `~/.claude/skills/` as those evolve,
silently, with nothing comparing them.

The decision this needs before any file is written: is the toolkit **generated** from the live
skills by a script, or **maintained by hand** as an independent copy? Generation keeps the copies
honest and costs a build step; a hand-maintained copy is simpler and goes stale. That choice belongs
to the engineer, and it determines where the artifact lives and what reviews it.

## 3. The Google access-control model is documented only where it is used

`ADD-TEAM-MEMBER.md` names which organizational unit each tier lives in, which is what a person
granting access needs. It does not explain how the model works: that a SAML app's visibility is set
per organizational unit, that a child unit inherits its parent's setting until it is given its own,
that an access group always overrides the unit and can only turn a service ON, and that the ordering
matters — the children are switched on before the root is switched off, or everyone loses access
during propagation.

Whoever adds a fourth SAML app, creates a new tier, or debugs "why can this person not see the AWS
button" has to derive all of it again. The gap is a reference document, not a procedure.

## 4. The `leadership` organizational unit's security posture

Two people sit in an organizational unit with no MFA and passwords kept outside a password manager.
That was tolerable while their accounts reached nothing; it stops being tolerable the moment one of
them moves to a tier that reaches AWS, because the Google account becomes the single door to the
infrastructure.

This is a people problem being handled in conversation, not a documentation gap. It is recorded here
only so it is not mistaken for something already solved.

## Order

Item 1 first: it is the only one with a date, and the failure it prevents is a simultaneous
sign-on outage across three services. Item 2 second, because it needs a decision before it needs
work. Items 3 and 4 carry no deadline.
