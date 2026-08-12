# Auxiliary source 1 — Published per-caller rate limits (verbatim excerpts)

Fetched 2026-08-11. Each entry records the URL and the literal strings confirmed present on the page.

---

## GitHub REST API

URL: https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api

- "All of these requests count towards your personal rate limit of 5,000 requests per hour."
- "The primary rate limit for unauthenticated requests is 60 requests per hour."
- "GitHub Apps authenticating with an installation access token use the installation's minimum rate limit of 5,000 requests per hour."
- "If the installation is on a GitHub Enterprise Cloud organization, the installation has a rate limit of 15,000 requests per hour."
- "No more than 100 concurrent requests are allowed."
- "No more than 900 points per minute are allowed for REST API endpoints."
- "In general, no more than 80 content-generating requests per minute and no more than 500 content-generating requests per hour are allowed."

---

## Stripe API

URL: https://docs.stripe.com/rate-limits (English rendering via `?locale=en-US`)

- "In general, rate limits are measured in API requests per second, per Stripe account. The global rate limit applies to total API usage per account, while some endpoints have additional limits of their own."
- Global API rate limit — Live mode: "100 requests per second"
- Global API rate limit — Sandbox: "25 requests per second"
- "Individual API endpoints (unless otherwise noted) | 25 requests per second"
- Files API: "20 read requests per second", "20 write requests per second"
- Payouts API: "15 [create](...) requests per second", "30 [concurrent requests](...) per business"
- Search API: "20 read requests per second"

---

## Shopify GraphQL Admin API

URL: https://shopify.dev/docs/api/usage/limits

- Standard limit: "100 points/second"
- Advanced Shopify limit: "200 points/second"
- Shopify Plus limit: "1000 points/second"
- Shopify for enterprise (Commerce Components): "2000 points/second"
- "Calls to the GraphQL Admin API are limited based on calculated query costs, which means you should consider the cost of requests over time, rather than the number of requests."

Note: the page expresses the limit in calculated query cost points per second, not requests per second, and carries no REST Admin API requests-per-second figure.

---

## Slack Web API

URL: https://docs.slack.dev/apis/web-api/rate-limits

- "Web API Tier 1 | 1+ per minute | Access tier 1 methods infrequently. A small amount of burst behavior is tolerated."
- "Web API Tier 2 | 20+ per minute | Most methods allow at least 20 requests per minute, while allowing for occasional bursts of more requests."
- "Web API Tier 3 | 50+ per minute | Tier 3 methods allow a larger number of requests and are typically attached to methods with paginating collections of conversations or users."
- "Web API Tier 4 | 100+ per minute | Enjoy a large request quota for Tier 4 methods, including generous burst behavior."

---

## Discord API

URL: https://docs.discord.com/developers/topics/rate-limits

- "All bots can make up to 50 requests per second to our API. If no authorization header is provided, then the limit is applied to the IP address."
- "Currently, this limit is **10,000 per 10 minutes**. An invalid request is one that results in **401**, **403**, or **429** statuses."

---

## Atlassian Jira Cloud REST API

URL: https://developer.atlassian.com/cloud/jira/platform/rate-limiting/

- "The values below show the default steady state requests per second (RPS) limits for the given API based on its HTTP method."
- GET | 100
- POST | 100
- PUT | 50
- DELETE | 50

---

## Cloudflare's own API

URL: https://developers.cloudflare.com/fundamentals/api/reference/limits/

- "The global rate limit for the Cloudflare API is 1,200 requests per five minute period per user, and applies cumulatively regardless of whether the request is made via the dashboard, API key, or API token."
