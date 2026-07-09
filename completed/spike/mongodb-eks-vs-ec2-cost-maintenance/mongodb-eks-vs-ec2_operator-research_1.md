<!-- Auxiliary file for SPIKE.md — MongoDB Kubernetes Operator maintenance-surface research, gathered 2026-07-08 -->

# MongoDB Kubernetes Operator — upgrade automation and lifecycle research

## The "MongoDB Community Kubernetes Operator" named in the task brief is deprecated

Source: https://github.com/mongodb/mongodb-kubernetes-operator

> "DEPRECATED: This repository is deprecated but we will continue a best-effort support until November 2025."

> Replacement: "there will be no functional changes in the new repository - only a better and unified experience" — pointing to `mongodb/mongodb-kubernetes`.

Source: https://github.com/mongodb/mongodb-kubernetes

> "MCK unifies and replaces two previous operators: the MongoDB Enterprise Kubernetes Operator and the \"MongoDB Community Operator\" (the mongodb-kubernetes-operator). The Community Operator has an End-of-Life date of November 2025, with migration guides provided for seamless transitions to MCK."

> License: "licensed under the Apache 2.0"; "Customers with prior Enterprise Operator contracts can adopt MCK without contract changes."

> Community Edition support: "MCK supports self-managed MongoDB Community Edition... enables users to manage MongoDB Community Server replica sets... including user creation, SCRAM authentication, and custom role management—all without requiring Ops Manager integration."

**Significance**: Best-effort support for the literal "MongoDB Community Kubernetes Operator" ended November 2025 — already in the past relative to this spike's date (2026-07-08). Any EKS adoption today would target the successor `mongodb/mongodb-kubernetes` (MCK), not the deprecated repo. MCK remains Apache 2.0 / free and still supports self-managed Community Edition (the hard constraint — DocumentDB/Atlas ruled out — still holds), but this is itself a first, concrete instance of "the operator is a new component with its own upgrade/migration surface" (§ Maintenance axis in SPIKE.md) — the operator 4Shark would deploy has already gone through one forced migration before 4Shark would even start.

## Version-upgrade mechanics (fetched from the current/successor docs)

Source: https://www.mongodb.com/docs/kubernetes/current/tutorial/upgrade-mdb-version/

Upgrade is declarative — set `spec.version` to the target version and re-apply:

```yaml
apiVersion: mongodb.com/v1
kind: MongoDB
metadata:
  name: my-standalone-downgrade
spec:
  version: "8.0.1"
  type: Standalone
  project: my-project
  credentials: my-credentials
  persistent: false
```

> "Kubernetes automatically reconfigures your deployment with the new specifications."

On `featureCompatibilityVersion` (FCV) — **NOT automatic**:

> "If you update this value to a later version of MongoDB for your database resources, the feature compatibility version remains at the MongoDB version you're upgrading from to give you the option to downgrade if necessary."

The docs state the FCV must be set manually afterward: `spec.featureCompatibilityVersion` must be explicitly bumped to the new version (or to `AlwaysMatchVersion`) for it to change — mirroring the manual `db.adminCommand({ setFeatureCompatibilityVersion: ... })` step in 4Shark's own OS-upgrade `PLAN.md` (Steps 1/3/4/5), which is unchanged by platform.

**Not found**: an explicit, sourced statement of how long a rolling engine-version upgrade takes end-to-end via the operator (no published benchmark located). The architecture fact this spike relies on for automation of the *mechanical* rolling-restart sequencing comes from the prior `mongodb-on-ecs` spike's Finding 9, which quoted the (now-deprecated but structurally unchanged in MCK) operator architecture docs: MongoDB is deployed as a StatefulSet, pods get stable identities, and the operator "deliberately block[s] Kubernetes' native rolling-upgrade mechanism because unordered restarts 'can trigger multiple re-elections.'" This is a structural inference (the operator owns and sequences the one-at-a-time pod replacement automatically once `spec.version` changes) rather than a measured time figure — flagged as such in SPIKE.md.

## Kubernetes version skew and node-vs-control-plane update independence

Source: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html

> "Are Amazon EKS managed node groups automatically updated along with the cluster control plane version? No. A managed node group creates Amazon EC2 instances in your account. These instances aren't automatically upgraded when you or Amazon EKS update your control plane."

> "The Kubernetes project tests compatibility between the control plane and nodes for up to three minor versions... running a cluster with nodes that are persistently three minor versions behind the control plane isn't recommended."

**Significance**: control-plane upgrade and worker-node upgrade are two independent maintenance actions on EKS — both must be tracked and both carry their own effort, they do not collapse into a single operation.

## What remains uncertain (operator-specific)

- Not found: the MongoDB Community Kubernetes Operator's (or MCK's) own deployment HA model (single-replica Deployment vs multiple replicas) and its own resource footprint — not directly investigated in this spike beyond confirming it runs inside the cluster's existing worker-node capacity (no separately billed control-plane-side component per the EKS pricing page's billable-components list).
- Not found: a MongoDB-published or community-published number for "hours saved per major-version upgrade cycle by using the operator vs manual EC2 rolling upgrade" — the SPIKE's maintenance-hours comparison is a reasoned inference from the automation mechanism (declarative `spec.version` + operator-owned ordered StatefulSet rollout replacing manual per-node SSH + `systemctl` + `rs.status()` polling), not a cited empirical benchmark.

**Verification block**: URL fetched (github.com/mongodb/mongodb-kubernetes-operator, github.com/mongodb/mongodb-kubernetes, www.mongodb.com/docs/kubernetes/current/tutorial/upgrade-mdb-version/, docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html) / Verbatim quotes checked / Quote substrings confirmed present in the WebFetch/WebSearch tool output at time of fetch (2026-07-08). Single-fetch per source, consistent with this session's Methodology Note (see SPIKE.md).
