# RUNBOOK — Commcenter integrator wipe (Bucket B, MANUAL, one target at a time)

`bin/ecs run commcenter` (ephemeral Fargate task — no service needs to be up; it cleans
itself on disconnect). Single-customer MongoDB, isolated — no multi-tenant blast radius.

You drive each target: confirm count → `delete_all` → re-check. **Scoped by `_type`** so
the kept org-structure resources are never touched.

## Scope (aligned with the app wipe)

- **DELETE** resource types: `Deal` (5037), `Client` (3694), `Modifier` (410),
  `Product` (369), `Goal` (78). `DealExtraField` = 0.
- **KEEP** resource types: `User`, `Subsidiary`, `Hierarchy`, `Group`, `Groupification`.
- **DELETE** collections: `ClientCollection`, `DealCollection`, `GoalCollection`,
  `ModifierCollection`, `ProductCollection`.
- **KEEP** collections: `GroupCollection`, `GroupificationCollection`,
  `HierarchyCollection`, `SubsidiaryCollection`, `UserCollection` (+ the empty User* ones).
- **DELETE** run history: `Job` (520) + `JobMetric` (per original instruction; not org structure).
- **KEEP config** (never in scope): `Source`, `Stream`, `AttributeMapping`,
  `Authentication` — needed to re-integrate at go-live.

> `Resource` is STI — all types live in the `resources` collection. **Never**
> `Resource.delete_all` (it would wipe User/Hierarchy/Group/Groupification too). Always
> scope by subclass / `_type`.

---

## 1) Resources — delete by type (one at a time)

```ruby
Deal.count;     Deal.delete_all;     Deal.count       # 5037 → 0  (embedded imports/requests go with them)
```
```ruby
Client.count;   Client.delete_all;   Client.count     # 3694 → 0
```
```ruby
Modifier.count; Modifier.delete_all; Modifier.count   # 410 → 0
```
```ruby
Product.count;  Product.delete_all;  Product.count    # 369 → 0
```
```ruby
Goal.count;     Goal.delete_all;     Goal.count       # 78 → 0
```

Checkpoint — kept types must be UNCHANGED:
```ruby
[User.count, Hierarchy.count, Groupification.count, Group.count]   # expect [1460, 444, 351, 39]
```

## 2) Collections — delete the deleted-types' staging

```ruby
ClientCollection.count;   ClientCollection.delete_all;   ClientCollection.count    # 27 → 0
DealCollection.count;     DealCollection.delete_all;     DealCollection.count      # 91 → 0
GoalCollection.count;     GoalCollection.delete_all;     GoalCollection.count      # 3 → 0
ModifierCollection.count; ModifierCollection.delete_all; ModifierCollection.count  # 4 → 0
ProductCollection.count;  ProductCollection.delete_all;  ProductCollection.count   # 4 → 0
```

Kept collections must be UNCHANGED:
```ruby
[GroupCollection.count, GroupificationCollection.count, HierarchyCollection.count, SubsidiaryCollection.count, UserCollection.count]
# expect [3, 4, 10, 1, 17]
```

## 3) Jobs + JobMetric (run history)

```ruby
JobMetric.count; JobMetric.delete_all; JobMetric.count   # job stats (has_one per job)
Job.count;       Job.delete_all;       Job.count         # 520 → 0
```

---

## Verification (Phase 3)

Re-run the per-type aggregate — only the KEEP types remain:
```ruby
Resource.collection.aggregate([{ "$group" => { "_id" => "$_type", "count" => { "$sum" => 1 } } }]).sort_by { |r| -r["count"] }.each { |r| puts r["_id"].to_s + "@" + r["count"].to_s }
# expect ONLY: User@1460, Hierarchy@444, Groupification@351, Group@39
```
Then re-run `discovery-integrator.rb`: `resources_total@2294`, `jobs@0`, deleted
collections `@0`, kept collections unchanged.

## Teardown

`bin/ecs run` cleans its own ephemeral task on disconnect — nothing to scale down
(the runner service is already at 0). Just exit the console.
