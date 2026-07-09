<!-- Auxiliary file for SPIKE.md — raw pricing citations, sa-east-1, gathered 2026-07-08 -->

# Raw pricing data — sa-east-1 (São Paulo)

All prices below were retrieved via `WebFetch` against third-party AWS-pricing aggregator pages (`aws-pricing.com`, a static-rendered pricing mirror) because `aws.amazon.com/ec2/pricing/on-demand/` and `instances.vantage.sh` render their pricing tables via JavaScript and returned no usable regional figures to `WebFetch` (confirmed empirically in this session — see Methodology Note in SPIKE.md). Per Citation Discipline, each figure below carries the exact `WebFetch`-returned quote and the source URL. These were single-fetch (not independently re-fetched a second time in this session), so confidence is "search/fetch-tool-mediated," consistent with the prior `mongodb-on-ecs` spike's Methodology Note.

## EC2 On-Demand — sa-east-1

| Instance | vCPU | Memory | Price/hr | Source |
|---|---|---|---|---|
| t3.micro | 2 | 1.0 GiB | $0.0168 | https://aws-pricing.com/t3.micro.html — "the on-demand hourly rate for the t3.micro instance type in the South America (São Paulo) region (sa-east-1) is **$0.0168 per hour**" |
| t3.small | 2 | 2.0 GiB | $0.0336 | https://aws-pricing.com/t3.small.html — "The on-demand hourly price for t3.small in the **sa-east-1** (South America - São Paulo) region is **$0.0336 per hour**, or **$24.53 per month**" |
| t3.medium | 2 | 4.0 GiB | $0.0672 | https://aws-pricing.com/t3.medium.html — "the on-demand hourly rate for t3.medium is **$0.0672 per hour**, which translates to approximately $49.06 monthly" |
| t3.large | 2 | 8.0 GiB | $0.1344 | https://aws-pricing.com/t3.large.html — "The t3.large instance costs \"$0.1344\" per hour in the sa-east-1 region... \"2 vCPUs and 8 GiB memory\"" |
| t3.xlarge | 4 | 16.0 GiB | $0.2688 | https://aws-pricing.com/t3.xlarge.html — "the on-demand hourly rate for t3.xlarge is **$0.2688 per hour** (approximately $196.22 monthly)" |
| m5.xlarge | 4 | 16.0 GiB | $0.306 | https://aws-pricing.com/m5.xlarge.html — "this instance type costs **$0.306 per hour** on-demand pricing" |
| c5.xlarge | 4 | 8.0 GiB | $0.262 | https://aws-pricing.com/c5.xlarge.html — "the on-demand hourly rate is **$0.262 per hour**, which translates to approximately $191.26 monthly" |

Canonical vCPU/memory specs cross-checked against AWS's own product page:
https://aws.amazon.com/ec2/instance-types/t3/ — "t3.micro: vCPUs: 2, Memory: 1.0 GiB"; "t3.small: vCPUs: 2, Memory: 2.0 GiB"; "t3.xlarge: vCPUs: 4, Memory: 16.0 GiB"

### Derived $/vCPU-hour (T3 family, within the burstable general-purpose line)

| Instance | $/hr | vCPU | $/vCPU-hr |
|---|---|---|---|
| t3.micro | 0.0168 | 2 | 0.0084 |
| t3.small | 0.0336 | 2 | 0.0168 |
| t3.medium | 0.0672 | 2 | 0.0336 |
| t3.large | 0.1344 | 2 | 0.0672 |
| t3.xlarge | 0.2688 | 4 | 0.0672 |
| c5.xlarge | 0.262 | 4 | 0.0655 |
| m5.xlarge | 0.306 | 4 | 0.0765 |

Note: within the T3 family, price roughly doubles at each size step (micro→small→medium→large) while vCPU count stays flat at 2 and only memory doubles — so $/vCPU-hr increases the larger the instance, because the extra spend buys memory, not more CPU. t3.xlarge is the first step where vCPU also doubles (2→4), landing $/vCPU-hr back at the same level as t3.large. c5.xlarge (compute-optimized, no burst credits) and m5.xlarge (general-purpose, fixed performance) both carry a HIGHER $/vCPU-hr than t3.small, because they trade the T3 family's baseline-performance/burst-credit discount for fixed, non-burstable performance.

## EBS — sa-east-1

Source: https://aws-pricing.com/sa-east-1.html

> "gp2 (General Purpose SSD): \"$0.19\" per GB/month"
> "gp3 (General Purpose SSD): \"$0.152\" per GB/month for storage, plus \"$0.0095\" per provisioned IOPS and \"$77.824\" for throughput provisioning"

The gp3 IOPS/throughput add-on figures returned by the fetch look like a scraping/formatting artifact (a flat "$77.824" for "throughput provisioning" does not match AWS's documented gp3 pricing shape, which charges per-GB-month for throughput above the free 125 MiB/s baseline, not a flat fee) — flagged as low-confidence and NOT used in this spike's cost math. Only the base per-GB-month storage rates (gp2 $0.19, gp3 $0.152) are used, since 4Shark's current MongoDB EBS volumes carry no provisioned IOPS/throughput beyond gp2/gp3 defaults (confirmed absent from `mongodb.tf` — see SPIKE.md Finding 1).

**Terraform ground truth**: `~/Projects/4Shark/terraform/integrator-atento/mongodb.tf:38,83,128` (and identical in almaviva/commcenter/maqnelson/redebrasil) shows `volume_type = "gp2"` on all three members, NOT gp3. This corrects the task brief's assumption of gp3.

## EKS control plane — pricing and version lifecycle

Source: https://aws.amazon.com/eks/pricing/

> "The standard EKS cluster pricing is **$0.10 per cluster per hour** for Kubernetes versions under standard support, and **$0.60 per cluster per hour** for extended support versions."

> Billable components list (re-fetched for confirmation): "EKS Cluster Fee... Compute Resources... Storage... Data Transfer: cross AZ traffic from nodes to the Kubernetes control plane... Public IPv4 Addresses... Optional Add-ons: Provisioned Control Plane, EKS Auto Mode, EKS Capabilities (Argo CD, ACK, KRO), and Hybrid Nodes each have their own separate hourly fees" — no separate line item for AWS-maintained add-ons like the EBS CSI driver; only the underlying EC2/EBS resources they consume are billed.

Source: https://docs.aws.amazon.com/eks/latest/userguide/kubernetes-versions.html

> "The community releases new Kubernetes minor versions (such as `1.36`) on average once every four months."

> "A minor version is under standard support in Amazon EKS for the first 14 months after it's released. Once a version is past the end of standard support date, it enters extended support for the next 12 months."

> "Standard support for a Kubernetes version in Amazon EKS begins when a Kubernetes version is released on Amazon EKS, and will end 14 months after the release date. Extended support for a Kubernetes version will begin immediately after the end of standard support, and will end after the next 12 months."

> "You can run clusters on any version for up to 12 months after the end of standard support for that version. This means that each version will be supported for 26 months in Amazon EKS (14 months of standard support plus 12 months of extended support)."

> "Clusters running on a Kubernetes version that has completed its 26-month lifecycle... will be auto-upgraded to the next version."

Release calendar table (verbatim from the same page):

| Kubernetes version | Upstream release | Amazon EKS release | End of standard support | End of extended support |
|---|---|---|---|---|
| 1.36 | April 22, 2026 | June 2, 2026 | August 2, 2027 | August 2, 2028 |
| 1.35 | December 17, 2025 | January 27, 2026 | March 27, 2027 | March 27, 2028 |
| 1.34 | August 27, 2025 | October 2, 2025 | December 2, 2026 | December 2, 2027 |
| 1.33 | April 23, 2025 | May 29, 2025 | July 29, 2026 | July 29, 2027 |
| 1.32 | December 11, 2024 | January 23, 2025 | March 23, 2026 | March 23, 2027 |
| 1.31 | August 13, 2024 | September 26, 2024 | November 26, 2025 | November 26, 2026 |
| 1.30 | April 17, 2024 | May 23, 2024 | July 23, 2025 | July 23, 2026 |

## EKS managed node group — OS lifecycle automation

Source: https://docs.aws.amazon.com/eks/latest/userguide/update-managed-node-group.html

> "When you initiate a managed node group update, Amazon EKS automatically updates your nodes for you... If you're using an Amazon EKS optimized AMI, Amazon EKS automatically applies the latest security patches and operating system updates to your nodes as part of the latest AMI release version."

> "When a node in a managed node group is terminated due to a scaling operation or update, the Pods in that node are drained first."

> eksctl one-line command: `eksctl upgrade nodegroup --name=node-group-name --cluster=my-cluster --region=region-code`

> "For Update strategy, select one of the following options: Rolling update – This option respects the Pod disruption budgets for your cluster... Force update – This option doesn't respect Pod disruption budgets."

**Verification block**: URL fetched (both docs.aws.amazon.com pages + aws.amazon.com/eks/pricing/ + the 7 aws-pricing.com instance pages + aws.amazon.com/ec2/instance-types/t3/) / Verbatim quotes checked / Quote substrings confirmed present in the WebFetch tool output at time of fetch (2026-07-08). Not independently re-fetched a second time (single-fetch, per the Methodology Note in SPIKE.md).
