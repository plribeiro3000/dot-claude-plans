# Research notes — MongoDB on ECS (raw search material)

This file preserves the raw material gathered via the `WebSearch` tool during the spike, organized by topic. It exists so a future revision of `SPIKE.md` can re-weight or drop sources without re-running every search. `WebFetch` was unavailable in the research environment for every external domain tested except `example.com` (confirmed by direct test) — all external evidence below was obtained through `WebSearch`, which fetches pages internally and returns attributed snippets/quotes. No independent re-fetch/re-verification pass was possible. See `SPIKE.md` § Methodology Note for how this constrains the citation rigor.

---

## Topic: MongoDB on ECS — prior art

Query: `MongoDB running on ECS production stateful container AWS`

- AWS Database Blog: "Deploy a containerized application with Amazon ECS and connect to Amazon DocumentDB (with MongoDB compatibility) securely" — https://aws.amazon.com/blogs/database/deploy-a-containerized-application-with-amazon-ecs-and-connect-to-amazon-documentdb-securely/ — AWS's own paired content for "ECS + Mongo-API database" pairs ECS with DocumentDB, not self-managed MongoDB.
- Medium (Jens Båvenmark): "Streamlining MongoDB Deployment on AWS ECS with Terraform" — uses the official MongoDB image + EFS for persistence. https://medium.com/aws-specialists/streamlining-mongodb-deployment-on-aws-ecs-with-terraform-93bcb48da72c
- Medium (Jazz Tong): "MongoDB Replica Set in AWS ECS with Terraform" — notes the official MongoDB image has no built-in auto replica-set configuration, so the Bitnami MongoDB image is used (env-var-driven replica set config). https://medium.com/geekculture/mongodb-replica-set-in-aws-ecs-with-terraform-4621451c6190
- Brett Namba blog: "Running MongoDB in AWS ECS with persistent EFS storage" — https://brettnamba.com/posts/2025/02/running-mongodb-in-aws-ecs-with-persistent-efs-storage/
- GitHub (luiscoco): "AWS-ECS-Setup-and-Run-MongoDB-in-ECS" — walkthrough repo. https://github.com/luiscoco/AWS-ECS-Setup-and-Run-MongoDB-in-ECS
- Terraform Registry module: `everest-engineering/mongodb-ecs/aws` — https://registry.terraform.io/modules/everest-engineering/mongodb-ecs/aws / https://github.com/everest-engineering/terraform-aws-mongodb-ecs
- Community pattern for EC2-launch-type + EBS pre-native-integration: `rexray/ebs` Docker volume plugin used to provision/attach EBS to ECS-on-EC2 tasks before AWS shipped native EBS support.

## Topic: ECS native EBS volume integration

Queries: `AWS ECS attach EBS volume to task documentation`, `AWS ECS EBS volume support launched date`, `"ECS" EBS volume attachment "one Amazon EBS volume" per task availability zone`, `ECS EBS volume terminationPolicy deleteOnTermination`, `repost.aws knowledge-center ecs-task-ebs-volume`, `ECS EBS volume configuration volumeType gp3 iops throughput`, `ECS EC2 launch type bind mount host EBS volume task placement constraint`

- Launch announcement: "Amazon ECS and AWS Fargate now integrate with Amazon EBS" — dated January 2024. https://aws.amazon.com/about-aws/whats-new/2024/01/amazon-ecs-fargate-integrate-ebs/
- AWS News Blog: "Amazon ECS supports a native integration with Amazon EBS volumes for data-intensive workloads" — https://aws.amazon.com/blogs/aws/amazon-ecs-supports-a-native-integration-with-amazon-ebs-volumes-for-data-intensive-workloads/ — "You can provision Amazon EBS storage for your ECS tasks running on AWS Fargate and Amazon Elastic Compute Cloud (Amazon EC2)."
- Primary doc: "Use Amazon EBS volumes with Amazon ECS" — https://docs.aws.amazon.com/AmazonECS/latest/developerguide/ebs-volumes.html
  - "You can attach at most one Amazon EBS volume to each Amazon ECS task, and it must be a new volume. You can't attach an existing Amazon EBS volume to a task."
  - "you can configure a new Amazon EBS volume at deployment using the snapshot of an existing volume"
  - "you must set configuredAtLaunch to true because Amazon EBS volumes can't be configured for attachment in the task definition"
  - IAM: `AmazonECSInfrastructureRolePolicyForVolumes` managed policy required.
- "Specify Amazon EBS volume configuration at Amazon ECS deployment" — https://docs.aws.amazon.com/AmazonECS/latest/developerguide/configure-ebs-volume.html
  - deleteOnTermination default `true`; standalone tasks can override to `false` to preserve; **service-managed tasks cannot** — "Volumes that are attached to tasks that are managed by a service aren't preserved and are always deleted upon task termination."
  - volumeType (gp3 default), iops (gp3/io1/io2, gp3 default 3000), throughput (gp3 only, max 1000 MiB/s), sizeInGiB.
- AZ pinning: "EBS volumes are specific to the Availability Zone that you create them in, and you must ensure that the instance that you want to attach your volume to is in the same Availability Zone." Also: "you can't configure Amazon EBS volumes for attachment to Fargate Amazon ECS tasks in the use1-az3 Availability Zone."
- Bind mounts (EC2 launch type, pre-existing mechanism, not the new EBS feature): "Use bind mounts with Amazon ECS" — https://docs.aws.amazon.com/AmazonECS/latest/developerguide/bind-mounts.html
  - "the host parameter is used to tie the lifecycle of the bind mount to the host Amazon EC2 instance, rather than the task"
  - "If the host parameter contains a sourcePath file location, then the data volume persists at the specified location on the host Amazon EC2 instance until you delete it manually."
  - "Amazon ECS doesn't sync your storage across Amazon EC2 instances... If your tasks require persistent storage after stopping and restarting, always specify the same Amazon EC2 instance at task launch time with the AWS CLI start-task command."
- Fargate ephemeral (non-persistent) task storage: default 20 GiB, configurable up to 200 GiB. "Ephemeral storage is non-persistent storage, which makes it unsuitable for workloads requiring persistent data storage like databases." https://docs.aws.amazon.com/AmazonECS/latest/developerguide/fargate-task-storage.html

## Topic: MongoDB and NFS/EFS

Query: `MongoDB NFS EFS data directory not recommended official documentation`, `"avoid using NFS" MongoDB dbPath`

- MongoDB "Operations Checklist for Self-Managed Deployments" — https://www.mongodb.com/docs/manual/administration/production-checklist-operations/
  - "Avoid using NFS drives for your dbPath. Using NFS drives can result in degraded and unstable performance."
  - Also references a "Remote Filesystems (NFS)" section with fstab options if NFS must be used anyway.
- AWS ECS Workshop (community/AWS-authored workshop site, not core product docs): https://ecsworkshop.com/stateful_workloads/ — demonstrates EFS as the storage provider for a generic "stateful container on ECS Fargate" workshop module, and notes the AZ trade-off: "consuming volumes from an EFS file system allows you to work cross-AZ, while consuming volumes from an EC2 EBS disk ties the container to a specific AZ." This is generic stateful-workload guidance, not MongoDB-specific, and does not reconcile with MongoDB's own NFS warning.

## Topic: AWS DocumentDB compatibility gaps

Queries: `AWS DocumentDB MongoDB compatibility limitations unsupported features`, `DocumentDB functional differences "does not support" transactions aggregation change streams`

- Amazon DocumentDB compatibility page — https://docs.aws.amazon.com/documentdb/latest/developerguide/compatibility.html — DocumentDB implements a subset of the MongoDB API; supports up to certain MongoDB compatibility modes (5.0 / 8.0) but many features remain unavailable.
- Functional differences page — https://docs.aws.amazon.com/documentdb/latest/devguide/functional-differences.html
  - Unsupported/limited: capped collections, map-reduce, GridFS, text indexes, vector search indexes, partial indexes, case-insensitive indexes, time-series collections, on-demand materialized views, client-side field level encryption, queryable encryption.
  - Unsupported commands: `collMod`, `collMod:expireAfterSeconds`, `copydb`, `createView`, `filemd5`, `reIndex`, `connPoolStats`, `dbHash`, `features`, `getLastError`, `getPrevError`, `parallelCollectionScan`, `resetError`, `endSessions`, `killAllSessionsByPattern`, `refreshSessions`, sharding commands (aside from `enableSharding`/`shardCollection`).
  - Unsupported query operators: `$expr`, `$jsonSchema`, `$text`, `$where`, `$meta`, `$box`, `$center`, `$centerSphere`, `$polygon`, `$near`, `$uniqueDocs`.
  - Unsupported aggregation operators (older DocumentDB versions): `$accumulator`, `$count`, `$stdDevPop`, `$stdDevSamp`, `$pow`, `$trunc`, `$round`, `$first`, `$last`, `$switch`, `$binarySize`, `$bsonSize`, various date functions. Some (`$replaceWith`, `$set`, `$unset` in change-stream pipelines) are reportedly supported in newer DocumentDB 8.0 compatibility mode per search synthesis — not independently re-verified.
  - Change streams: no DDL events (drop/rename/dropDatabase); cannot open a change stream against a non-primary node; no `resumeAfter` in some contexts (search-synthesized, not independently re-verified against the primary doc text).
  - Transactions: DocumentDB transactions "can be indeterminate and 'ambiguous'"; scoped to a single primary node; no retryable writes; cannot create new collections inside a transaction, no cursors within a transaction.
- MongoDB's own comparison page (naturally has an incentive to highlight gaps — treat as a corroborating, non-neutral source): https://www.mongodb.com/resources/compare/documentdb-vs-mongodb/compatibility — "the only place to access fully featured MongoDB as a service on AWS is through MongoDB Atlas"; DocumentDB "lacks native integration for time series, search, and analytical use cases."

## Topic: ECS vs Kubernetes StatefulSet / no ECS StatefulSet primitive

Queries: `ECS vs Kubernetes StatefulSet stateful workloads comparison`, `AWS containers roadmap ECS stateful workloads statefulset feature request github issue`, `github.com/aws/containers-roadmap issues 1008/127`

- Kubernetes official docs — https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/ — StatefulSets give "stable, unique network identifiers, stable persistent storage, ordered graceful deployment and scaling, and ordered automated rolling updates."
- **GitHub `aws/containers-roadmap` issue #1008 — "[ECS] Support StatefulSets in ECS"** — https://github.com/aws/containers-roadmap/issues/1008 — opened 2020-08-03, status **open** as of this research, 41 reactions. Requests a StatefulSets equivalent of EKS in the ECS world, where (verbatim) "each has a persistent identifier that it maintains across any rescheduling."
- **GitHub `aws/containers-roadmap` issue #127 — "[ECS]: ECS Stateful Services"** — https://github.com/aws/containers-roadmap/issues/127 — requests a service type where "each Task within a service [can] play a specific role, which is particularly true for some stateful workloads, in which specific Tasks play a special role such as 'primary' or 'leader'," with a stable identifier per task that survives replacement.
- MongoDB Community Kubernetes Operator architecture — https://github.com/mongodb/mongodb-kubernetes-operator/blob/master/docs/architecture.md and https://www.mongodb.com/docs/kubernetes-operator/master/tutorial/mdb-resources-arch/ — "the Kubernetes Operator deploys each resource as a StatefulSet"; "Pods are defined as StatefulSets so they benefit from stable identities"; "the Kubernetes Operator generates a Persistent Volume Claim" per pod; the Operator explicitly blocks Kubernetes' native rolling upgrade because it "can trigger multiple re-elections."
- Kubernetes blog (2017-01-30, Sandeep Dinesh, Google Cloud) — https://kubernetes.io/blog/2017/01/running-mongodb-on-kubernetes-with-statefulsets/ — "Conventional wisdom says you can't run a database in a container... With StatefulSets, these headaches finally go away."

## Topic: Replica set expansion / migration mechanics

Queries: `MongoDB replica set expand add member rs.add() step down primary official docs`, `MongoDB zero downtime migration add replica set member different infrastructure step down primary migrate`

- MongoDB official — "Add Members to a Self-Managed Replica Set" — https://www.mongodb.com/docs/manual/tutorial/expand-replica-set/ — "Use rs.add() to add the new member to the replica set. You can only add members while connected to the primary."
- MongoDB official — "rs.add()" reference — https://www.mongodb.com/docs/manual/reference/method/rs.add/
- MongoDB official — "Force a Self-Managed Replica Set Member to Become Primary" — https://www.mongodb.com/docs/manual/tutorial/force-member-to-be-primary/ — stepping down via `rs.stepDown()`/`replSetStepDown` without `force: true` causes the stepped-down primary to nominate an eligible secondary for immediate election.
- Community guidance on adding a new member with `priority: 0, votes: 0` until synced, to avoid a majority-online-but-no-primary situation on MongoDB < 5.0.
- Community blog walkthroughs of cross-infrastructure zero-downtime migration via add-member → wait-for-SECONDARY → step-down-old-primary: https://mschmitt.org/blog/mongodb-migration-replicaset/ and https://eng.blackbuck.com/mongodb-cluster-migration-with-zero-downtime/
- MongoDB official — replica set geographic/AZ distribution guidance — https://www.mongodb.com/docs/manual/core/replica-set-architecture-geographically-distributed/ — recommends distributing members across ≥3 data centers/AZs so a single-DC/AZ loss still leaves a majority for election.

## Topic: Amazon Linux EOL (minimal "just upgrade the OS" path)

Query: `Amazon Linux 2016 end of life security patching old AMI upgrade EC2 instance`

- endoflife.date/amazon-linux and AWS's own "Update on Amazon Linux AMI end-of-life" blog: Amazon Linux 1 (the original 2016-era AMI line) reached end-of-life 2023-12-31, no further security updates. Amazon Linux 2 (AL2) end-of-life is 2026-06-30. AWS recommends migrating to Amazon Linux 2023 (AL2023), supported until 2029.

## Topic: Cost/option landscape (Atlas, self-managed, DocumentDB) — lower confidence, blog-tier

Query: `MongoDB Atlas AWS managed alternative self-managed comparison feature parity full MongoDB`

- Various SEO/blog aggregator sources (NetApp, Vantage, oneuptime, "The Startup" on Medium) converge on: Atlas = fully-managed, full MongoDB feature set, cross-cloud, premium price; DocumentDB = AWS-native, cheaper than Atlas in some sizes, but is "not fully compatible with MongoDB" and "the only place to access fully featured MongoDB as a service on AWS is through MongoDB Atlas" (this last quote traced to the MongoDB-authored comparison page above, not a neutral source — flagged accordingly in SPIKE.md). Cost figures in these blog posts are illustrative/dated and not treated as verified facts in SPIKE.md — presented only as directional signal.

## Internal sources (4Shark plans repo, not external — no re-fetch caveat applies, these are local files)

- `~/.claude/plans/active/spike/integrator-stateful-services-fargate/SPIKE.md` — prior 4Shark spike (2026-03-19) that evaluated MongoDB on **Fargate + EFS** (ephemeral storage was ruled out immediately since the integrator's MongoDB holds durable cross-run state) and concluded: "MongoDB should remain on EC2 with the stop/start pattern already implemented" — did **not** evaluate the native ECS↔EBS attachment feature (EC2 launch type or Fargate), only EFS.
- `~/.claude/plans/active/spike/mongodb-integrator-daily-shutdown/SPIKE.md` — prior 4Shark spike (2026-03-18) establishing the current baseline: 3-node PSS replica set on EC2, private-IP-stable stop/start, ~12s election time, `MONGO_SERVER_SELECTION_TIMEOUT` raised to 30s to absorb election on driver reconnect.
