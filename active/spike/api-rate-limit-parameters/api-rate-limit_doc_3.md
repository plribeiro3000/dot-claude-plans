# Auxiliary source 3 — Cloudflare rate limiting: allowed durations and published examples

Fetched 2026-08-11. Each entry records the URL and the literal strings confirmed present on the page.

---

## Cloudflare rate limiting rules — parameters

URL: https://developers.cloudflare.com/waf/rate-limiting-rules/parameters/

Duration (mitigation timeout):

- "Once the rate is reached, the rate limiting rule applies the rule action to further requests for the period of time defined in this field (in seconds)."
- "The available API values are: `0`, `10`, `60` (one minute), `120` (two minutes), `300` (five minutes), `600` (10 minutes), `3600` (one hour), or `86400` (one day)."
- Setting `mitigation_timeout` to `0` applies the action only to requests exceeding the configured limit (request throttling) rather than to all requests for a fixed duration.

Period (counting window):

- "The available API values are: `10`, `60` (one minute), `120` (two minutes), `300` (five minutes), `600` (10 minutes), or `3600` (one hour)."

---

## Cloudflare rate limiting rules — best practices

URL: https://developers.cloudflare.com/waf/rate-limiting-rules/best-practices/

Counting periods appearing in the page's example configurations: "10 seconds", "1 minute", "2 minutes", "3 minutes", "5 minute", "10 minutes", "1 hour".

Actions and durations appearing verbatim:

- "Rate (Requests / Period) | 50 requests / 10 seconds"
- "Action | Block for 1 day" (credential stuffing example)
- "Action | Block for 10 minutes" (OTP endpoint protection example)

Several examples use "Managed Challenge" or a plain "Block" with no explicit duration stated.

---

## Cloudflare rate limiting rules — use cases

URL: https://developers.cloudflare.com/waf/rate-limiting-rules/use-cases/

Complexity-based rate limiting example:

- Threshold: "Score per period: `400`"
- Period: "`1 minute`"
- Action: Block
- Duration: "`10 minutes`"
