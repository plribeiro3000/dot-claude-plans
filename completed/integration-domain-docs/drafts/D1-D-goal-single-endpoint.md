# Goal — single endpoint, two STI types

`POST /api/v3/goals` and `PATCH /api/v3/goals` create and update both UserGoal and GroupGoal. The discriminator is the `type` field in the payload (`"UserGoal"` or `"GroupGoal"`). There are no separate endpoints per goal type.

## The two types

A Goal is the target value a Variable must reach over a period, attached to a subject:

- **UserGoal** — subject is a single User (one row per user)
- **GroupGoal** — subject is a Group (one row per group, applied to all users in the group)

The discriminator drives the validation: a UserGoal requires `user_id` and forbids `group_id`; a GroupGoal requires `group_id` and forbids `user_id`. The model normalizes this on save — if the type says `GroupGoal`, the `user_id` field is nulled before insert.

The two share everything else: the same endpoint, the same payload shape, the same period semantics (`starts_at` / `ends_at`), the same direction semantics (`ascending` / `descending`), the same baseline-vs-target rules.

## Why one endpoint and not two

A goal is a goal regardless of subject. The decision to attach it to a user or a group is a parameter of the request, not a different kind of resource. Splitting the endpoint into `/api/v3/user_goals` and `/api/v3/group_goals` would suggest the resources are different — and downstream the client would build separate code paths for each, even though the platform treats them identically once the goal is created.

The single-endpoint design also matches how the integration team thinks: "create a sales target for this group" or "create a sales target for this user" are the same action mechanically. The platform reflects that.

## Constraints worth knowing

The platform enforces mutual exclusion at the database level: for a given Variable, you cannot have both a UserGoal targeting that Variable for a given user AND a GroupGoal targeting the same Variable for the user's group at the same time. Whichever was created first wins; the second creation rejects with a uniqueness error.

This constraint exists because mixed goal types would make commission calculation ambiguous — when computing a user's progress against a sales target, the platform must know whether to look up a per-user goal or to derive from the group's goal. Allowing both would mean every calculation has to choose which to honor, and the choice would not be expressible cleanly to the client.

## Implication for the integrator

When mapping the client's compensation rules to goals, the integration team must decide per Variable whether goals are individual or collective. The platform will not accept "this Variable has user goals for some people and group goals as fallback for the rest". A rule that needs that flexibility must be expressed differently — typically by splitting the rule into two Variables, one for each goal mode.

Drift in this dimension typically appears as a UserGoal creation rejecting because a GroupGoal already exists for the same Variable, or vice versa. The error message points at the unique index, not at the conceptual mismatch — the integrator team has to translate the index name into "you have conflicting goal types for the same variable".
