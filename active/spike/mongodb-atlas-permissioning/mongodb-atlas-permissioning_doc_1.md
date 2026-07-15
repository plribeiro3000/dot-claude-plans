# Auxiliary source — Atlas org/project roles (fixed predefined set)

Preserved fetched content supporting SPIKE.md Findings 1 and 3.

## Source: https://www.mongodb.com/docs/atlas/reference/user-roles/

Fetched twice this session (organization/project role enumeration; then again for
custom-role scope and Network Access Manager exact privileges; then again for the
exact descriptions of GROUP_DATA_ACCESS_READ_WRITE / GROUP_READ_ONLY / GROUP_CLUSTER_MANAGER).

### Organization Roles (complete list as returned by the page)

1. `Organization Owner` (`ORG_OWNER`)
2. `Organization Project Creator` (`ORG_GROUP_CREATOR`)
3. `Organization Billing Admin` (`ORG_BILLING_ADMIN`)
4. `Organization Stream Processing Admin` (`ORG_STREAM_PROCESSING_ADMIN`)
5. `Organization Billing Viewer` (`ORG_BILLING_READ_ONLY`)
6. `Organization Read Only` (`ORG_READ_ONLY`)
7. `Organization Member` (`ORG_MEMBER`)

### Project Roles (complete list as returned by the page)

1. `Project Owner` (`GROUP_OWNER`)
2. `Project Replica Set Manager` (`GROUP_REPLICA_SET_MANAGER`)
3. `Project Cluster Manager` (`GROUP_CLUSTER_MANAGER`)
4. `Project Cluster Creator` (`GROUP_CLUSTER_CREATOR`)
5. `Project Cluster Log Viewer` (`GROUP_CLUSTER_LOG_VIEWER`)
6. `Project Cluster Resilience Tester` (`GROUP_CLUSTER_RESILIENCE_TESTER`)
7. `Project Stream Processing Owner` (`GROUP_STREAM_PROCESSING_OWNER`)
8. `Project Access Manager` (`GROUP_ACCESS_MANAGER`)
9. `Project Data Access Admin` (`GROUP_DATA_ACCESS_ADMIN`)
10. `Project Data Access Read/Write` (`GROUP_DATA_ACCESS_READ_WRITE`)
11. `Project Data Access Read Only` (`GROUP_DATA_ACCESS_READ_ONLY`)
12. `Project Database Access Admin` (`GROUP_DATABASE_ACCESS_ADMIN`)
13. `Project Backup Manager` (`GROUP_BACKUP_MANAGER`)
14. `Project Backup Creator` (`GROUP_BACKUP_CREATOR`)
15. `Project Backup Recovery Operator` (`GROUP_BACKUP_RECOVERY_OPERATOR`)
16. `Project Backup Export Operator` (`GROUP_BACKUP_EXPORT_OPERATOR`)
17. `Project Network Access Manager` (`GROUP_NETWORK_ACCESS_MANAGER`)
18. `Project Observability Viewer` (`GROUP_OBSERVABILITY_VIEWER`)
19. `Project Trigger Manager` (`GROUP_TRIGGER_MANAGER`)
20. `Project Read Only` (`GROUP_READ_ONLY`)
21. `Project Index Manager` (`GROUP_INDEX_MANAGER`)
22. `Project Search Index Editor` (`GROUP_SEARCH_INDEX_EDITOR`)
23. `Project Real Time Performance Operator` (`GROUP_REAL_TIME_PERFORMANCE_OPERATOR`)
24. `Project Support Access Manager` (`GROUP_SUPPORT_ACCESS_MANAGER`)
25. `Project Alerts Manager` (`GROUP_ALERTS_MANAGER`)
26. `Project Model Owner` (`GROUP_MODEL_OWNER`)

There is no "custom control-plane role" concept anywhere on this page — every entry above is
a fixed, named, built-in role. Confirmed by direct re-query: *"there is no mention of custom
roles anywhere in the content ... The page only discusses pre-defined Atlas user roles at the
organization and project levels."*

### Project Network Access Manager — exact privilege scope

> "`Project Network Access Manager`
> `GROUP_NETWORK_ACCESS_MANAGER`
> Grants privileges to update project network settings for the following:
> - Access lists
> - VPC peering
> - Private Link"

### Exact descriptions of the three roles 4Shark currently assigns

**`GROUP_DATA_ACCESS_READ_WRITE`** ("Project Data Access Read/Write"):

> "Grants access to the Data Explorer, with the privileges to perform the following actions
> through the Atlas UI:
> - View and create databases and collections.
> - UI only: View, modify, and delete documents. You can't read or write data using the Atlas
>   Administration API.
> - View indexes.
> - Retrieve process and audit logs for all clusters in the project.
> - View the sample query field values in the Performance Advisor.
> - View collection-level query latency with Namespace Insights.
> - View collection-level query shape performance with Query Shape Insights.
> - View query performance, including raw queries, in the Query Profiler.
> - View real-time performance in the Real-Time Performance Panel.
> - View documents using the Search Tester.
> - Launch MongoDB Charts.
> - Download stream processing workspace audit logs.
> - View stream processing workspaces.
> - View connections in the connection registry."

**`GROUP_READ_ONLY`** ("Project Read Only"):

> "Grants view-only access to the project control plane metadata. The user can view all
> activity, operational data, users, and user roles.
> The user, however, cannot access the Data Explorer or retrieve process and audit logs. The
> user can view cluster metric charts.
> Grants access to view connection details for Stream Processing Workspaces.
> Grants access to MongoDB Charts only if invited to the project by a Project Owner. The user,
> however, cannot access data from Charts, unless the Project Owner also grants them data
> source access."

**`GROUP_CLUSTER_MANAGER`** ("Project Cluster Manager"):

> "Grants the privileges to perform the following actions:
> - Grants access to edit, pause, and resume Atlas clusters.
> - Test failover.
> The Project Cluster Manager role doesn't allow users to:
> - Create and terminate Atlas clusters.
> - Access the Data Explorer.
> - Retrieve process and audit logs."

**Significance for the current-state read**: `GROUP_DATA_ACCESS_READ_WRITE` grants
Atlas-UI Data Explorer read-write only — it is not a database credential and does not
grant driver/`mongosh` access. It is a distinct control-plane grant from the
`mongodbatlas_database_user` shared credential documented in
`app-beta-001/mongodb.tf:60-84`. Both paths reach the data plane, through different
doors, and both currently bypass any elevation step for the baseline team on the
productive projects.
