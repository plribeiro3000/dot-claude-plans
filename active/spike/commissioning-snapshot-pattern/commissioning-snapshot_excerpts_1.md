# Raw fetched excerpts — commissioning snapshot pattern spike

Auxiliary file for `SPIKE.md`. Each block is a verbatim excerpt pulled from the cited URL during research, kept here so the engineer can revise the spike's conclusions without re-fetching every source. Fetched 2026-09-04.

---

## Martin Fowler — Snapshot (Analysis Patterns / EAA Dev)

URL: https://martinfowler.com/eaaDev/Snapshot.html

> "A Snapshot is simply a view of an object with all the temporal aspects removed."

> "Temporality adds a good bit of complexity to a design and there are times you don't want to take that into account...you want to do work with respect to a particular timepoint...Or maybe you are linking to a system that doesn't understand temporality."

> "Snapshots are a view to help accessing, so in most cases they should be immutable. An exception to this is where you might update a snapshot and then apply it back to the real object as at some date. This is not something that I'd do very often, and usually only when working with an external system that isn't aware of temporality."

---

## Martin Fowler — Event Sourcing (EAA Dev)

URL: https://martinfowler.com/eaaDev/EventSourcing.html

> "Capture all changes to an application state as a sequence of events."

> "Event Sourcing ensures that all changes to application state are stored as a sequence of events. Not just can we query these events, we can also use the event log to reconstruct past states, and as a foundation to automatically adjust the state to cope with retroactive changes."

> "The key to Event Sourcing is that we guarantee that all changes to the domain objects are initiated by the event objects."

---

## Martin Fowler — Class Table Inheritance (EAA Catalog)

URL: https://martinfowler.com/eaaCatalog/classTableInheritance.html

> "Represents an inheritance hierarchy of classes with one table for each class."

(Page gives only the one-line pattern definition; the sparse-column comparison with Single Table Inheritance is in the book chapter, not on the web page.)

---

## Stripe — Ledger: Stripe's system for tracking and validating money movement

URL (redirects to): https://stripe.dev/blog/ledger-stripe-system-for-tracking-and-validating-money-movement

> "Ledger, an immutable and auditable log, as a trustworthy system of record for all of our financial data."

> "Transactions previously published into Ledger cannot be deleted or modified, and we can always reconstruct past state by processing all events up to that point."

> "Ledger's immutability ensures we can audit and reproduce any data point at any time."

---

## bluepes.com — Product bundle pricing for marketplaces: the architecture

URL: https://bluepes.com/blog/product-bundle-pricing-marketplace

> "If the order holds a live reference, changing the package's price or swapping a component silently rewrites what every past order appears to contain, and last quarter's numbers stop matching what customers paid."

> "A snapshot makes the order a record of what happened, which is the same principle behind event sourcing: history is an append-only set of facts, not a live projection that mutates when the present changes."

> the snapshot must include "the bundle's component list as it was at the time of purchase, the quantity of each component, the price charged for the bundle, any per-component price allocation needed for tax, refunds, or accounting."

> "Skipping this is a quiet failure mode. Everything works in the demo, and the problem only surfaces months later, when someone edits a popular package and finance asks why historical revenue shifted."

---

## Kimball Group — Slowly Changing Dimensions, Part 2

URL: https://www.kimballgroup.com/2008/09/slowly-changing-dimensions-part-2/

> "The Type 2 SCD requires that we issue a new employee record for Ralph Kimball effective July 18, 2008."

> "great care must be taken to use the correct contemporary surrogate keys from this dimension in every affected fact table. This assures that the correct dimension profiles are associated with fact table activity."

(Type 2 SCD keeps the dimension as its OWN row, versioned, and the fact table stores a foreign key to whichever dimension row was current at the time — it does not embed the attribute values directly in the fact row. This differs structurally from the order/bundle snapshot approach above, which copies the values straight into the transactional row.)

---

## collectiveidea/audited (GitHub README)

URL: https://github.com/collectiveidea/audited

> "Audited (previously acts_as_audited) is an ORM extension that logs all changes to your models."

> "Audits contain information regarding what action was taken on the model and what changes were made."

(Describes a change-log/diff-history tool — records what changed between states over time. Does not describe a mechanism for freezing the inputs a calculation read at the moment it ran.)

---

## nathanmlong.com — Better Single Table Inheritance

URL: https://nathanmlong.com/2013/05/better-single-table-inheritance/

> "This is bad OO. It's also bad database normalization: lots of NULLs in the table. That, in turn, means you can't set non-shared columns to NOT NULL as a last-resort guard against bad data."

> "You won't validate the presence of a `site_address` for a `WrestlingContract`, but it will still have the methods `site_address` and `site_address=`."

> approach: store "common attributes in a single table, non-shared attributes in separate tables with foreign key references, and use object delegation so that each model transparently pulls what it needs from both."

> `has_one :details, class_name: 'WrestlingContractDetails'` (verified verbatim in the "Do it With Delegation" section)

---

## dev.37signals.com — The Rails Delegated Type Pattern

URL: https://dev.37signals.com/the-rails-delegated-type-pattern/

> "the table keeps getting bigger widthwise. It has to have all the different kinds of columns that you might have for any type"

> "The bigger the table is, the harder and slower it is to migrate."

> "your recordings table basically never changes. You just add new types, which are their own fresh tables"

> "there's no penalty to adding a new type" (paraphrase in the fetch tool's summary of the surrounding point; treat as observation, not verbatim, unless re-confirmed)

---

## api.rubyonrails.org — ActiveRecord::DelegatedType

URL: https://api.rubyonrails.org/classes/ActiveRecord/DelegatedType.html

> "the 'superclass' is a concrete class that is represented by its own table, where all the superclass attributes that are shared amongst all the 'subclasses' are stored"

> "You can get around the pagination problem by using single-table inheritance, but now you're forced into a single mega table with all the attributes from all subclasses."

---

## PostgreSQL docs — ALTER TABLE (Notes section)

URL: https://www.postgresql.org/docs/current/sql-altertable.html

> "When a column is added with ADD COLUMN and a non-volatile DEFAULT is specified, the default value is evaluated at the time of the statement and the result stored in the table's metadata, where it will be returned when any existing rows are accessed. The value will be only applied when the table is rewritten, making the ALTER TABLE very fast even on large tables. If no column constraints are specified, NULL is used as the DEFAULT. In neither case is a rewrite of the table required."

> "Adding a column with a volatile DEFAULT (e.g., clock_timestamp()), a stored generated column, an identity column, or a column with a domain data type that has constraints will cause the entire table and its indexes to be rewritten."

---

## Heap.io — When To Avoid JSONB In A PostgreSQL Schema

URL: https://www.heap.io/blog/when-to-avoid-jsonb-in-a-postgresql-schema

> "This probably won't bite you in a key-value / document-store workload, but it's easy to run into this if you're using JSONB along with analytical queries." (re: lack of column statistics causing bad query plans; the fetch tool's summary reported a demonstrated case running "2,000x slower with JSONB versus traditional columns" — treat that multiplier as the tool's paraphrase pending re-confirmation, the statistics-and-join-plan claim itself is directly supported)

> "For values that occur in most of your rows, it's still a good idea to keep them separate."

> "We found a disk space savings of about 30% by pulling 45 commonly used fields out of JSONB and into first-class columns." (verified verbatim)

> "For datasets with many optional values, it is often impractical or impossible to include each one as a table column. In cases like these, JSONB can be a great fit."

---

## writesoftwarewell.com — Readonly Attributes in Rails

URL: https://writesoftwarewell.com/readonly-attributes-in-rails

> `attr_readonly` marks "some attributes on your Active Record models as readonly, to prevent them from further modification."

> Rails 7.1+: attempting to modify a readonly attribute on an already-saved record raises `ActiveRecord::ReadonlyAttributeError`. Rails ≤7.0: the update is silently ignored (in-memory change, not persisted).

> Restriction: "You can only set the value of a readonly attribute when the object isn't saved in the database."

## mohnishjadwani.com — attr_readonly

URL: https://www.mohnishjadwani.com/posts/attr_readonly/

> "Attributes listed as readonly will be used to create a new record but update operations will ignore these fields."

(Both sources describe `attr_readonly` as an ActiveRecord-layer guard, not a database-level constraint — it does not stop `update_all`, `update_column`, or a raw SQL `UPDATE` from changing the value.)
