# Auxiliary source 5 — nginx `limit_req` and AWS WAF rate-based rules (verbatim excerpts)

Fetched 2026-08-11. Each entry records the URL and the literal strings confirmed present on the page.

---

## nginx `ngx_http_limit_req_module`

URL: https://nginx.org/en/docs/http/ngx_http_limit_req_module.html

Example configuration on the page:

```
limit_req_zone $binary_remote_addr zone=one:10m rate=1r/s;

server {
    location /search/ {
        limit_req zone=one burst=5;
    }
}
```

- "The rate is specified in requests per second (r/s). If a rate of less than one request per second is desired, it is specified in request per minute (r/m). For example, half-request per second is 30r/m."
- "If the requests rate exceeds the rate configured for a zone, their processing is delayed such that requests are processed at a defined rate. Excessive requests are delayed until their number exceeds the maximum burst size in which case the request is terminated with an error."

The directives documented on the page are `limit_req`, `limit_req_dry_run`, `limit_req_log_level`, `limit_req_status` and `limit_req_zone`. None of them configures a period during which an offending client remains blocked after exceeding the rate.

---

## AWS WAF rate-based rule statements

URL: https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based.html

- "A rate-based rule counts incoming requests and rate limits requests when they are coming at too fast a rate. The rule aggregates requests according to your criteria, and counts and rate limits the aggregate groupings, based on the rule's evaluation window, request limit, and action settings."

URL: https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-high-level-settings.html

- "**Evaluation window** – The amount of time, in seconds, that AWS WAF should include in its request counts, looking back from the current time. For example, for a setting of 120, when AWS WAF checks the rate, it counts the requests for the 2 minutes immediately preceding the current time. Valid settings are 60 (1 minute), 120 (2 minutes), 300 (5 minutes), and 600 (10 minutes), and 300 (5 minutes) is the default."
- "**Rate limit** – The maximum number of requests matching your criteria that AWS WAF should just track for the specified evaluation window. The lowest limit setting allowed is 10. When this limit is breached, AWS WAF applies the rule action setting to additional requests matching your criteria."

URL: https://docs.aws.amazon.com/waf/latest/developerguide/waf-rule-statement-type-rate-based-caveats.html

- "AWS WAF rate limiting is designed to control high request rates and protect your application's availability in the most efficient and effective way possible. It's not intended for precise request-rate limiting."
- "Each time that AWS WAF estimates the rate of requests, AWS WAF looks back at the number of requests that came in during the configured evaluation window. Due to this and other factors such as propagation delays, it's possible for requests to be coming in at too high a rate for up to several minutes before AWS WAF detects and rate limits them. Similarly. the request rate can be below the limit for a period of time before AWS WAF detects the decrease and discontinues the rate limiting action. Usually, this delay is below 30 seconds."

The rate-based rule exposes no configurable block duration; the action stops applying once the observed rate falls below the limit.
