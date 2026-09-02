# Auxiliary — Cost and pricing raw data (Hermes Agent spike)

Raw figures and the arithmetic behind the cost section of `SPIKE.md`. Every number below is either a direct verbatim quote from a fetched source, or the author's own arithmetic built on top of a quoted rate (marked "own calculation").

## 1. Hermes Agent infrastructure requirements (cloud-API mode, no local model)

Source: WebSearch aggregation of Hermes Docker/system-requirements guidance (`shop.zimaspace.com`, `heroxhost.com`, `openclawlaunch.com` — third-party hosting/VPS advisory sites, not Nous Research's own docs; treat as directional, not authoritative):

> "Official Hermes Docker guidance lists 1 GB RAM minimum and 2–4 GB recommended" / "1 CPU core as the minimum and 2 cores as recommended" / "a server with around 2 CPU cores, 2–4 GB RAM, 20–30 GB SSD storage"

Local-model mode (running an open-weight model on the box instead of a cloud API) needs far more — "8 GB RAM for smaller 3B models... 32 GB or more for larger 27B+ models" — not the relevant mode for this comparison, since the engineer already has Claude API/subscription access and would run cloud-API mode.

## 2. AWS EC2 translation (own calculation)

Source: [instances.vantage.sh/aws/ec2/t3.medium](https://instances.vantage.sh/aws/ec2/t3.medium) — fetched directly.

> "$0.0416 per hour" (t3.medium, 2 vCPU, 4 GiB RAM — matches the "2 CPU / 2-4GB RAM recommended" spec above)

Own calculation: $0.0416/hr × 730 hr/month ≈ **$30.37/month** for compute alone. Add ~20-30GB gp3 EBS storage (~$0.08/GB-month per AWS's published gp3 rate) ≈ $2-2.50/month. **Total: roughly $32-33/month** for a right-sized always-on EC2 instance running Hermes in cloud-API mode. This is a small, capped, predictable cost — it is NOT the variable that drives the total bill up; the inference cost is.

## 3. Anthropic / OpenRouter metered API pricing

Source: [openrouter.ai/anthropic/claude-sonnet-4.5](https://openrouter.ai/anthropic/claude-sonnet-4.5) — fetched directly.

> "$3 / $15 per 1M" — confirmed again in the FAQ section: "$3.00/M input tokens and $15.00/M output tokens"

OpenRouter passes through provider rates and separately charges "a 5.5% fee when you purchase credits" (per WebSearch aggregation of OpenRouter's own pricing docs — not independently re-fetched, treat as UNVERIFIED at the exact percentage, though directionally consistent with OpenRouter's publicly known fee model).

## 4. Real-world reported cost of heavy / multi-agent metered usage

Source: WebSearch aggregation citing CloudZero's Claude Code pricing analysis and Anthropic's own published usage figures (`cloudzero.com/blog/claude-code-pricing`, `cloudzero.com/blog/claude-code-agents`) — NOT independently re-fetched by direct WebFetch in this spike; treat the specific dollar figures as UNVERIFIED-but-plausible secondary-source data, not as independently confirmed primary-source quotes.

- "Anthropic's published figures put Claude Code at about $13 per developer per active day and $150 to $250 per developer per month, with 90% of users under $30 on any active day." (typical single-agent, subscription-covered usage — cited as an Anthropic-published figure by the secondary source, not fetched from Anthropic directly)
- "3 parallel agents at $30-40 per day and 5-10 agents at $50-130 per day" (CloudZero's own third-party estimate, per the aggregator)
- "Power users on heavy automation reach $500 to $2,000 per month"
- "Microsoft's Experiences + Devices division reportedly experienced token billing that hit ~$2,000 per engineer per month with heavy agent usage" — this is a reported figure from a secondary source, not independently verified against a primary Microsoft or Anthropic statement in this spike.

**What this data is good for**: an order-of-magnitude anchor for "what does metered, always-on, multi-agent usage cost per engineer" — roughly $150-250/month at light-normal usage, $400-2,000+/month at heavy/parallel usage, per person, uncapped. **What it is NOT good for**: a precise prediction for this specific 3-engineer team's workload, which depends on how much of their work actually shifts onto metered inference and how aggressively they run parallel/always-on agents.

## 5. The engineer's "tens of thousands per month" fear — not independently confirmed

No source found in this research states a "tens of thousands per month" figure for a small team. The documented ceiling found (Microsoft's reported ~$2,000/engineer/month for heavy agentic use) would put a 3-engineer team at roughly $6,000/month if every engineer ran at that same heavy-use ceiling, on metered billing, with no subscription offset. Reaching "tens of thousands" would require usage well beyond what's documented here (e.g., many always-on parallel workflow agents running continuously, not just heavy interactive use) — plausible in principle because metered API billing is structurally uncapped, but not a scenario this spike found a documented real-world example of. Treat the engineer's number as a directionally-correct worst-case intuition (uncapped billing CAN run arbitrarily high) rather than a confirmed data point.
