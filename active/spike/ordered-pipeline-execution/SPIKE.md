# SPIKE — Ordered pipeline execution with optional steps

**Conducted by:** Engineering team
**Date:** 2026-03-31
**Status:** Research complete — pending decisions

---

## Goal

Answer the following questions before redesigning the integrator's extraction pipeline:

1. How do tools like Fivetran, Hevo, Airbyte, and Singer/Meltano handle execution ordering of multiple data streams/syncs?
2. How does the Sidekiq community handle ordered job execution, job pipelines, and DAGs?
3. What patterns exist in Ruby/Rails for defining a fixed execution order where steps are optional?
4. Which approach best fits our specific case: a fixed, ordered pipeline where each step is a stream that may or may not exist for a given client?

**Context:** The integrator currently processes data in a fixed order (subsidiaries → groups → hierarchies → users by role → products → deals → etc.). Each step corresponds to a `Stream` that a client may or may not have configured. Order is hardcoded via worker chaining: each worker calls `NextWorker.perform_async(job_id)` at the end, regardless of whether the current step did any real work. This couples every worker to its successor, making the order invisible, hard to change, and impossible to reconfigure without touching source code.

---

## Method

- Static analysis of the integrator codebase to map the current chaining structure
- Research into how industry ETL/ELT tools handle stream ordering
- Research into Sidekiq-specific patterns for ordered job execution
- Research into Ruby/Rails library patterns for ordered step execution with optional skipping

---

## Evidence

### Current State: Worker Chaining in the Integrator

The integrator has two independent execution chains — one for API sources and one for database sources. Each is a linear chain of workers where every worker hard-codes the name of its successor.

**API chain** (started by `HealthCheck::Processor` → `ConnectionCheck::Processor`):

```
Subsidiary::ApiExtractor
  → Hierarchy::ApiExtractor
    → User::Admin::ApiExtractor
      → User::President::ApiExtractor
        → User::VicePresident::ApiExtractor
          → User::Director::ApiExtractor
            → User::Superintendent::ApiExtractor
              → User::GeneralManager::ApiExtractor
                → User::Manager::ApiExtractor
                  → User::Coordinator::ApiExtractor
                    → User::Supervisor::ApiExtractor
                      → User::SalesRepresentative::ApiExtractor
                        → ParentUpdate::ApiExtractor
                          → UserIdentifier::ApiExtractor
                            → Client::ApiExtractor
                              → Product::ApiExtractor
                                → Group::ApiExtractor
                                  → Groupification::ApiExtractor
                                    → UserField::ApiExtractor
                                      → UserActivity::ApiExtractor
                                        → Deal::ApiExtractor
                                          → DealExtraField::ApiExtractor
                                            → Modifier::ApiExtractor
                                              → Goal::ApiExtractor
                                                → [job.finish_extraction → Subsidiary::ApiTransformer]
```

**Database chain** (started by `DatabaseIntegrator`):

```
Subsidiary::DatabaseExtractor (paginated, self-calls until exhausted)
  → Hierarchy::DatabaseExtractor
    → User::DatabaseExtractor
      → UserIdentifier::DatabaseExtractor
        → Client::DatabaseExtractor
          → Product::DatabaseExtractor
            → Group::DatabaseExtractor
              → Groupification::DatabaseExtractor
                → UserField::DatabaseExtractor
                  → UserActivity::DatabaseExtractor
                    → Deal::DatabaseExtractor
                      → DealExtraField::DatabaseExtractor
                        → Modifier::DatabaseExtractor
                          → Goal::DatabaseExtractor
                            → [job.finish_extraction → Subsidiary::DatabaseTransformerProducer]
```

**Key observations:**

- Every worker knows the name of its successor. The order is distributed across ~24 files.
- Skipping a step means calling the next worker anyway (the stream check is internal to each worker, but `perform_async` to the successor always runs).
- Adding a new step requires modifying the predecessor's source file.
- Reordering steps requires modifying multiple files.
- The `Stream` model already has a `position` field (`field :position, type: Integer`), but it is not used for orchestration — the order is in the code, not the data.
- The `Stream` model already has an `enabled` scope and `disabled` flag — the opt-in/opt-out mechanism already exists at the data level.

### Finding 1: ETL/ELT Tools — External Orchestration is the Industry Standard

**Airbyte** treats each connection as an independent sync unit. It has no native mechanism for ordering dependencies between connections. The recommended approach is to delegate orchestration to an external tool — the Airbyte team explicitly recommends **Dagster** (and also supports Airflow). Each connection is triggered by the orchestrator via API, and the DAG structure lives in the orchestrator, not in Airbyte.

**Fivetran** follows the same model. Each connector syncs independently on its own schedule. Sequential dependencies must be managed externally (Airflow, Dagster, Prefect, etc.).

**Singer (open source)** processes streams sequentially within a single tap run. A tap outputs `SCHEMA`, `RECORD`, and `STATE` messages for all its streams interleaved on stdout, piped to a target. There is no dependency-ordering between streams — it is a flat, sequential message stream. Cross-tap ordering is not handled by Singer itself; Meltano uses Airflow for this.

**Meltano** generates Airflow DAGs automatically from `meltano job` definitions. A job is an ordered sequence of tasks (tap → target → transform). Cross-job dependencies are expressed as Airflow DAG relationships. The ordering is defined once in configuration and executed by the orchestrator.

**Key takeaway:** These tools offload ordering concerns to a DAG orchestrator. Their internal stream handling is sequential within a unit of work, but ordering between units is always external. This is viable when each unit is a long-running, largely independent sync. It does not map well to the integrator's model, where the entire pipeline is a single `Job` with shared state and strict ordering constraints.

### Finding 2: Dagster's Software-Defined Assets Model

Dagster's model is the most instructive from an architecture standpoint. Assets declare their upstream dependencies, and Dagster automatically derives the execution order. There is no explicit "run A before B" instruction — you declare "B depends on A", and Dagster handles the rest.

This declarative, dependency-driven model is exactly what the integrator is missing. Currently, the ordering is implicit (hardcoded in worker bodies). Making it explicit and data-driven is the core design change available.

### Finding 3: Sidekiq Batches (Pro)

Sidekiq Pro Batches allow grouping jobs and running callbacks when the group completes. The documented pattern for sequential multi-stage workflows is:

1. Create a parent batch for the overall workflow.
2. Create a child batch for each stage, containing the jobs for that stage.
3. In the child batch's `on(:success)` callback, reopen the parent batch and add the next child batch.

This produces a sequential chain: Stage A (parallel jobs) → callback → Stage B (parallel jobs) → callback → etc.

**Constraints:**
- Requires Sidekiq Pro (paid).
- Adds complexity: three new concepts (Batch, parent/child relationships, callbacks) on top of the existing worker model.
- The integrator's extraction steps are not parallelizable within a stage — each step is a single sequential operation (often paginated). Batches are designed for parallel fans.
- Overhead is justified when stages have multiple parallel jobs. For single-job stages, a batch is just a callback wrapper with extra setup.

**Verdict:** Sidekiq Batches can enforce ordering, but the Pro requirement and the added complexity make this a poor fit for a pipeline where every stage is a single sequential job.

### Finding 4: Faktory Enterprise Batches

Faktory Enterprise has a batch mechanism similar to Sidekiq Pro. Jobs within a batch are concurrent; ordering between stages is achieved via callbacks that create the next batch. Same pattern, same constraints. Faktory is not used in this codebase and would require migrating the entire job infrastructure.

### Finding 5: Plain Ordered List (Array-Based Pipeline)

The simplest Ruby pattern for this problem: define the pipeline as an ordered array of step descriptors, then execute them in sequence in a single coordinator.

```ruby
PIPELINE = [
  SubsidiaryStep,
  HierarchyStep,
  UsersStep,
  ProductStep,
  GroupStep,
  DealStep,
  # ...
]

PIPELINE.each do |step|
  step.run(job) if step.enabled_for?(job)
end
```

This pattern is:
- Order is visible and centralized in one place.
- Adding/reordering steps changes one file, not the step itself.
- Optional steps are handled by a guard — the step is in the list but no-ops if not configured.
- No new dependencies required.
- Works with any job backend (Sidekiq, inline execution, etc.).

The challenge: this collapses async execution into synchronous execution unless each step enqueues a job and the coordinator waits for completion.

### Finding 6: Plain Ordered List with Sidekiq — the "Pipeline Runner" Pattern

The ordered list can drive async execution through a pipeline runner worker that knows its position in the list:

```ruby
STEPS = [:subsidiary, :hierarchy, :users, :products, :groups, :deals, ...]

class PipelineRunner
  include Sidekiq::Worker

  def perform(job_id, step_index = 0)
    return if step_index >= STEPS.length

    step_name = STEPS[step_index]
    step = resolve_step(step_name, job_id)

    if step.applicable?
      step.run
      # Step calls PipelineRunner.perform_async(job_id, step_index + 1) when done
    else
      PipelineRunner.perform_async(job_id, step_index + 1) # skip and advance
    end
  end
end
```

The coordinator passes a cursor (step index) forward. Each step still executes asynchronously but calls back to the coordinator rather than to the next step directly. The pipeline definition lives in one place.

This is the pattern that most naturally fits the current codebase structure while eliminating the coupling.

### Finding 7: dry-transaction (Railway-Oriented Programming)

`dry-transaction` implements the Railway Oriented Programming pattern: each step returns `Success` or `Failure`, and the chain halts on failure. Steps are defined declaratively in a class:

```ruby
class MyPipeline
  include Dry::Transaction

  step :subsidiaries
  step :hierarchies
  step :users
  step :products
end
```

**Assessment for this use case:**
- Designed for synchronous, in-process operations.
- Not designed for async/queued execution.
- Skipping a step requires the step to return `Success` with the same input (pass-through), not true skipping.
- The "halt on failure" semantic is inverted from what we need — we want to continue past unavailable steps, not halt.
- Not a fit.

### Finding 8: Waterfall Gem

`waterfall` implements a flow-control pattern for service objects. Chains steps, dams on failure, supports conditionals. Similar to dry-transaction, it is synchronous and in-process. Not applicable to async queued execution.

### Finding 9: state_machines (already in the Gemfile)

The codebase already uses `state_machines` and `state_machines-mongoid`. State machines can model a pipeline as a progression through states:

```
initial → subsidiary_done → hierarchy_done → users_done → ... → complete
```

Each state transition represents a completed step. Events trigger transitions. Guards can skip steps. The state is persisted in the `Job` document.

**Assessment:**
- Well-suited to tracking *where in the pipeline the job currently is*.
- The state machine models the execution state, not the execution logic.
- Can be combined with the Pipeline Runner pattern: the state machine tracks position, the runner resolves the next step from the current state.
- Already a dependency — no new gems required.
- Provides built-in state persistence and transition history.
- The graphviz integration (already in the Gemfile for development) can generate a visual pipeline diagram automatically.

### Finding 10: Stream.position Field (Unused)

The `Stream` model already has a `position` field. It is not currently used for orchestration. If the pipeline order were derived from `Stream#position` values rather than hardcoded in workers, it would be possible to reconfigure the pipeline order via data (admin UI) without code changes. This is a stronger version of the ordered array pattern — the order lives in the database, not in code.

---

## Conclusions

### On ETL/ELT Tools

Airbyte, Fivetran, Singer, and Meltano all delegate ordering between pipeline units to external DAG orchestrators (Airflow, Dagster). Their internal model treats each connection/tap as independent. This approach does not transfer to the integrator's model, where the entire pipeline is a single job with shared state and the ordering constraint comes from business rules (users must exist before deals), not scheduling convenience.

### On Sidekiq Patterns

Sidekiq Pro Batches and Faktory Enterprise Batches implement ordered stages through callback-driven batch chaining. This pattern works but introduces Pro licensing, significant complexity, and is optimized for parallel-fan stages rather than single sequential steps. It solves a harder problem than what we have.

### On Ruby Patterns

The simplest viable patterns for a fixed-order optional-step pipeline in Ruby are:

1. **Ordered array + pipeline runner worker**: Pipeline definition is centralized, each step executes asynchronously, the runner advances the cursor. Steps do not know their successors. The order is visible in one place.

2. **State machine as position tracker**: Use the existing `state_machines` dependency to track pipeline position as job state. Combine with the runner pattern: state transition = step completion, next state = next step.

3. **Stream.position as order source**: If the order were read from `Stream#position` at runtime, the pipeline could be reconfigured without code changes. This is the most data-driven approach and aligns with the fact that the `position` field already exists but is unused.

### On the Current Design's Core Problem

The root problem is not that workers chain to each other — it is that the *pipeline definition* (what step comes after what) is distributed across 24+ files instead of living in one place. Any redesign should consolidate the ordering into a single authoritative location, whether that is:

- A constant array in a pipeline coordinator class
- The `Stream#position` field in the database
- A state machine definition in the `Job` model

The worker chaining pattern (each step dispatching its successor) is a valid async execution mechanism. The problem is coupling: every step knows its successor. The fix is inversion — steps report completion to a coordinator, and the coordinator decides what runs next.

### Recommended Direction

The pattern that best fits the current codebase:

**A pipeline coordinator that reads an ordered list and dispatches steps by cursor, with steps reporting completion back to the coordinator.**

- Coordinator worker holds or reads the ordered step list.
- Each step calls `PipelineCoordinator.perform_async(job_id, next_index)` on completion instead of calling the next step directly.
- If a step has no active stream, the coordinator skips it immediately.
- The `Stream#position` field can serve as the source of order at runtime.
- The existing `state_machines` can optionally track pipeline position for observability.
- No new gems required.
- No Sidekiq Pro required.
- Order is visible in one place.
- Adding, removing, or reordering steps touches one definition, not the individual workers.

---

## Next Steps

- **Decision needed**: The findings present a clear direction (pipeline coordinator + cursor), but the engineer must decide:
  1. Whether the order should live in code (constant array) or in data (`Stream#position`).
  2. Whether `state_machines` should be used to track pipeline position, or whether the cursor index alone is sufficient.
  3. Whether the API and database chains should share a single pipeline definition or remain separate.

- If the direction is approved, use `@agent-planner` to create a PLAN.md for the refactoring.

---

> **What is a Spike?** A time-boxed research task aimed at reducing uncertainty. The goal is fact-finding, not decision-making. A spike may lead to a PLAN.md (implementation), an ADR (architecture decision), or simply documented knowledge for future reference.
>
> **Further reading:**
> - [Spikes - Scaled Agile Framework](https://framework.scaledagile.com/spikes)
> - [Technical Spike - Microsoft Engineering Fundamentals Playbook](https://microsoft.github.io/code-with-engineering-playbook/design/design-reviews/recipes/technical-spike/)
