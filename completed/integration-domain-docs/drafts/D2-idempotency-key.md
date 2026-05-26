# Idempotency key

Network failures happen during integration. A client sends a request, the server processes it, but the response is dropped before reaching the client. The client doesn't know whether to retry. Without protection, retries duplicate the operation: two Deals created instead of one, two Identifiers, two Goals.

The platform protects against this with the `X-Idempotency-Key` header — a [Stripe-inspired pattern](https://stripe.com/docs/api/idempotent_requests) where the client supplies a unique value per logical operation, and the server short-circuits retries to the cached response of the original call.

```
POST /api/v3/users/123/promotions
X-Idempotency-Key: job-100-user-123-promotion
```

## How it behaves

- **First call with a given key**: the server processes normally and caches the result
- **Retry within 1 hour with the same key**: the server returns the cached response without re-processing
- **Successful responses (2xx)**: cached, with different shapes per operation type:
  - For CREATE operations (POST returning 201): the server caches the created resource's internal ID. On retry, it fetches the resource from the database and returns the full response body with 201 status. This guarantees the client gets the same response as the original request
  - For UPDATE/DELETE/state-change operations (returning 204): the server caches a boolean flag. On retry, it returns 204 No Content immediately without re-processing
- **Error responses (4xx, 5xx)**: NOT cached. A retry after an error re-runs the operation; the client can fix the input and try again with the same key
- **Per-company scope**: the cache is scoped per company. Two different companies sending the same idempotency key are independent

## Why 1-hour TTL

One hour is enough time for retries during network instability while keeping memory usage low. After that, the key expires and can be reused.

## Why errors aren't cached

If the server returned an error, the client should be able to fix the issue and retry with the same key. Caching the error would force the client to invent a new key just to get past a fixable problem.

## Why this matters for the integrator

A retry without an idempotency key risks duplicating the operation if the original call succeeded but the response was lost in transit. With an idempotency key, the retry is safe: either the original call succeeded (and the retry sees the cached success) or the original call did not commit (and the retry will execute fresh).

The integrator's recommended practice:

- Generate a deterministic key per logical operation. A common pattern: `"<resource>-<external-id>-<operation>-<source-revision>"` or `"<job-id>-<user-id>-<action>"`. The deterministic shape ensures the same operation always uses the same key, even if the integrator process restarts
- Send the key on every state-changing call
- On retry of a failed call, REUSE the same key — the platform's "errors don't cache" rule means the retry is allowed to re-execute, which is what the integrator wants

## Common pitfalls

- **Reusing keys across different operations** — the cache lookup is by key alone, regardless of what the request body says. A second call with a different body but the same key will get the cached response of the first call. The integrator must guarantee key uniqueness per operation
- **Reusing keys after the cache expires** — the cache is 1 hour; after that, the key is "fresh" and a call with that key will execute. This is the intended behavior but can surprise an integrator that retries 24 hours after the original failure
- **Reusing keys after delete-and-recreate within the cache window** — if you create a resource, delete it, and want to recreate it within the 1-hour cache window, you must use a NEW idempotency key. The original key still returns the cached "created" response from the first creation, even though the resource has since been deleted. This follows the same pattern used by Stripe and other major API providers
- **Not sending a key at all** — the endpoint still works without the header, but retries are at the integrator's risk

## Implementation

The cache interface is provided by methods in `ApiController`:

- `cache_key` — generates the cache key from the header value (includes company_id, controller, action so the same header value across endpoints stays distinct)
- `cached_resource_id` — returns the cached resource ID if it exists (for CREATE operations)
- `cached?` — checks whether the request has already been processed
- `cache(resource)` — saves the resource ID to the cache (for CREATE operations)
- `cache_request` — saves a boolean flag to the cache (for UPDATE/DELETE operations)

Usage in a CREATE controller:

```ruby
def create
  if cached?
    return render json: User.find(cached_resource_id), status: :created
  end

  # ... process ...

  if success
    render json: user, status: :created
    cache(user)
  end
end
```

Usage in an UPDATE/DELETE controller:

```ruby
def destroy
  if cached?
    head :no_content
    return
  end

  # ... process ...

  if success
    head :no_content
    cache_request
  end
end
```

## Reference

The implementation choices (cache backend, key namespace, response serialization) and trade-offs are specified in the spike at `~/.claude/plans/active/idempotency-key/`.
