<!-- Provided by the coordinating (main) session, sourced from AWS Cost Explorer
     (UnblendedCost + UsageQuantity, monthly granularity), queried 2026-07-28.
     Preserved verbatim here as the auxiliary backing the cost Finding in SPIKE.md. -->

# ECR storage cost — Cost Explorer, Jan-Jul 2026

Usage types: `TimedStorage-ByteHrs` = us-east-1, `SAE1-TimedStorage-ByteHrs` = sa-east-1.
`UsageQuantity` is already expressed in GB-month by Cost Explorer for this usage type.

| Month | us-east-1 (GB-mo / USD) | sa-east-1 (GB-mo / USD) | Storage total (GB-mo) | Total ECR USD (incl. DataTransfer) |
|---|---|---|---|---|
| 2026-01 | 53.44 / 5.34 | 4.06 / 0.41 | 57.50 | 5.75 |
| 2026-02 | 52.25 / 5.23 | 3.78 / 0.38 | 56.03 | 9.98 |
| 2026-03 | 45.37 / 4.54 | 0.67 / 0.07 | 46.04 | 6.94 |
| 2026-04 | 54.68 / 5.47 | 5.69 / 0.57 | 60.37 | 9.95 |
| 2026-05 | 64.08 / 6.41 | 12.51 / 1.25 | 76.59 | 11.67 |
| 2026-06 | 73.80 / 7.38 | 16.10 / 1.61 | 89.90 | 15.04 |
| 2026-07 | 71.91 / 7.19 | 18.91 / 1.89 | 90.82 | 12.24 |

Notes carried over from the coordinator's message (used as-is, not re-derived):

- Storage growth Jan->Jul: 57.50 -> 90.82 GB-month, +58%.
- sa-east-1 storage growth Jan->Jul: 4.06 -> 18.91 GB-month, ~4.6x, tracking the pace at which new integrator clients are onboarded.
- `DataTransfer-Out-Bytes` is the largest line item in several months (USD 3-6/month) and is image-pull traffic, NOT storage — a lifecycle policy does not reduce it. It must not be counted as savings from this change.
