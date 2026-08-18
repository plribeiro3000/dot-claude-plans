# PLAN — Separate password reset from user update

**Project**: `app` (backend) + `app-webclient` (frontend) · **Owner**: Paulo Ribeiro

## Problem

Changing another user's password is a field on the general user-update mutation, so it inherits none of the controls the platform already has for a password reset. `UpdateUserGraphqlMutation` accepts `password` and `password_confirmation` and calls `user.update` directly (`app/graphql_mutations/update_user_graphql_mutation.rb:19-24`):

```ruby
def execute
  user = User.find(id)
  authorize(user, :update?)
  user.update(user_params)
  respond_with(user)
end
```

Three things that should happen on a password reset do not happen on this path:

The **`registration_password` flag stays as it is**, so the user is never forced to choose their own password on the next login. The flag exists and defaults to `true`; the controlled reset sets it (`app/models/user.rb:314-318`), and a user changing their own password clears it (`app/models/user.rb:330-334`). It also governs whether the complexity rules apply (`app/models/user.rb:304`) — a temporary password is exempt precisely because it is meant to be replaced.

**No `password_reset` record is created**, so the reset leaves no trace in the user's own history.

**No `SecurityEvent` is emitted**, so nothing records that the reset happened or who performed it. This is the sharp one: the whole reason account management counts as administrative access is that whoever sets a user's password can authenticate as that user. Without an event, that step is invisible.

The controlled path exists but is reachable only through the batch flow. `User#reset_password` requires a `document:` argument, and its only caller is `PasswordDocument::Processor`, which does emit the event with both parties recorded — subject in `user_id`, actor in `metadata[:owner_id]` (`app/workers/password_document/processor.rb:27-37`).

## Target shape

Password change stops being a field on user update and becomes its own operation, mirroring what the platform already does for a user changing their own password.

`ChangePasswordGraphqlMutation` is the sibling to follow (`app/graphql_mutations/change_password_graphql_mutation.rb`): it acts through a model method, derives the event type from the outcome, creates the `SecurityEvent` inline with request context (`channel`, `remote_ip`, `user_agent`), and returns through `respond_with`. The new mutation is that shape with two differences — it acts on another user rather than `current_user`, so it carries a `policy` declaration and an `authorize` call, and it records the actor in `metadata` the way the batch worker does.

On the model side, the documentless reset is a sibling of `reset_password` rather than a new optional argument on it. The batch path works and is exercised in production; widening its signature to serve a second caller couples two flows that have no reason to move together.

The `authentication.password_reset` event type already exists in the catalog with its severity mapped, and `metadata[:owner_id]` already distinguishes actor from subject, so no change to `SecurityEvent` is needed.

## Execution

**Backend, one change.** Add the dedicated mutation and its model method; remove `password` and `password_confirmation` from `UpdateUserGraphqlMutation` (arguments and permitted params).

**Frontend, one change.** Move the password field out of the user-update screen into a call to the new mutation.

## Deploy

Two deploys, backend first, frontend immediately after, with the frontend build ready before the backend ships.

The frontend sends the password through `updateUser` today (`app-webclient/src/app/user/update/user-update.component.ts:110-115`, and the mutation document declares `$password` and `$passwordConfirmation` at lines 140-154), so removing the arguments is a breaking contract change between the two services.

**The window breaks the whole user-update screen, not only the password field.** A GraphQL document that declares a variable and passes it to an argument the schema no longer defines fails validation as a whole — the server rejects the operation before executing any of it. So during the window, editing a user's name, e-mail or department fails as well, not just changing a password.

That cost is accepted: the window lasts as long as the frontend deploy, password reset remains available through the batch upload flow, and a blocked user can open a ticket. An expand/contract sequence — ship the new mutation first, migrate the frontend, remove the old arguments in a third deploy — would avoid the window entirely at the cost of a third deploy and a period where both paths accept passwords. It is not the chosen path.

## Decisions taken

**The system generates the password; the operator never chooses it.** An operator-typed password leaves the operator able to authenticate as that user afterwards — the event would record that they could, not that they did not. A generated secret the operator never holds closes the escalation path instead of only making it visible, which is the reason this change exists. The generated value is delivered to the user through the existing channel for a credential, never returned in the mutation response.

**The operation gets its own permission key.** Reusing `user_update` would mean every profile able to edit a user can also reset passwords, which reproduces at the permission layer the same conflation this change removes at the mutation layer. The new key is added to `Company::SuperAdmin::Processor::MODULE_KEYS` and provisioned across existing companies — the worker is already idempotent (`find_or_create_by` per action), so provisioning is a re-run over the company set rather than a bespoke migration.

## Open decisions

**Whether the batch path is left alone.** It already behaves correctly. Bringing it under the same model method is optional and can happen later without affecting this change.

## Starting the implementation

This plan is the input to a fresh session, which loads `coding-policies` and `ruby-coding-policies` before writing anything (§ Policy Priming). Both decisions above are settled — the implementing session does not reopen them.

Read before writing: `app/graphql_mutations/change_password_graphql_mutation.rb` (the sibling shape), `app/graphql_mutations/update_user_graphql_mutation.rb` (the file being changed), `app/models/user.rb:314-322` (`reset_password`), `app/workers/password_document/processor.rb:27-37` (the event with the actor in `metadata`), and `app/policies/user_policy.rb`.
