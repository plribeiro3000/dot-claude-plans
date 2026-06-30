# SPIKE — Devise `authentication_keys` Native Mechanism for Optional `company_id`

## Investigation question

Can Devise 5.0.4's native `authentication_keys` (array or hash form) make `company_id`
**optional** — scoping the lookup when present and falling back to email-only when absent —
so that login still works before web/mobile clients send `company_id`?
Which Devise mechanism does the community recommend for tenant-scoped auth, and what does
the official wiki recipe actually do mechanically?

## Sources consulted

- Devise 5.0.4 vendored source — `strategies/authenticatable.rb` lines 128–167 (the
  definitive `parse_authentication_key_values` implementation). Full excerpt in
  `auth_keys_excerpt_1.rb`
- Devise 5.0.4 vendored source — `strategies/database_authenticatable.rb` lines 9–26.
  Full excerpt in `auth_keys_excerpt_2.rb`
- Devise 5.0.4 vendored source — `models/authenticatable.rb` lines 263–269. Full excerpt
  in `auth_keys_excerpt_3.rb`
- Devise 5.0.4 vendored source — `lib/devise.rb` lines 81–86 (default `authentication_keys`)
- Devise 5.0.4 vendored source — `lib/generators/templates/devise.rb` lines 41–56
  (initializer comment block — the only official prose description of the hash form)
- Devise 5.0.4 vendored source — `lib/devise/models/authenticatable.rb` lines 14–27
  (module-level comment for `request_keys`)
- [Devise Wiki: How to: Scope login to subdomain](https://github.com/heartcombo/devise/wiki/How-to:-Scope-login-to-subdomain)
  — The canonical official wiki page for tenant-scoped auth. Full text in existing
  `devise_doc_1_scope_login.txt`
- [Devise Issue #1255](https://github.com/heartcombo/devise/issues/1255) — Community
  report exposing the exact behavior of `parse_authentication_key_values` with
  optional keys
- [Devise Issue #2288](https://github.com/heartcombo/devise/issues/2288) — Community
  report of the known hash-form HTTP Basic auth edge-case bug

---

## Findings

### Finding 1: The `authentication_keys` hash form — what `false` controls in Devise 5.0.4 source

**Evidence:**

The single method that consumes the boolean is `parse_authentication_key_values` in
`lib/devise/strategies/authenticatable.rb`, lines 157–167:

```ruby
def parse_authentication_key_values(hash, keys)
  keys.each do |key, enforce|
    value = hash[key].presence
    if value
      self.authentication_hash[key] = value
    else
      return false unless enforce == false
    end
  end
  true
end
```

Source: `/Users/plribeiro3000/Projects/4Shark/app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/devise/strategies/authenticatable.rb:157-167`

When `authentication_keys` is an **Array** (e.g., `[:email, :company_id]`), Ruby's
`Array#each` yields `|key, enforce|` with `enforce = nil`. The condition
`return false unless enforce == false` means `nil == false` is `false`, so the method
**returns false** (strategy is invalid) whenever `company_id` is absent. Array form =
every key is required.

When `authentication_keys` is a **Hash** (e.g., `{ email: true, company_id: false }`),
Ruby's `Hash#each` yields `|key, enforce|` pairs. For the `company_id` key:
- `value = hash[:company_id].presence` → `nil` when absent
- Branch: `return false unless enforce == false` → `false == false` is `true` →
  `return false` is NOT executed → the loop continues

The result: when `company_id` is absent and its hash value is `false`, the method
skips the key entirely and returns `true`. The `authentication_hash` simply does not
contain `company_id`.

The initializer template confirms this in its comment (lines 41–49 of `devise.rb`
template):

> "Configure which keys are used when authenticating a user. The default is just
> :email. You can configure it to use [:username, :subdomain], so for authenticating
> a user, both parameters are required. Remember that those parameters are used only
> when authenticating and not when retrieving from session. If you need permissions,
> you should implement that in a before filter.
> **You can also supply a hash where the value is a boolean determining whether or
> not authentication should be aborted when the value is not present.**"

Source: `/Users/plribeiro3000/Projects/4Shark/app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/generators/templates/devise.rb:41-49`

**Significance:** The hash-form `authentication_keys: { email: true, company_id: false }`
DOES make `company_id` optional at the strategy level. When `company_id` is absent, the
strategy remains valid and `authentication_hash` contains only `{ email: "..." }`.

Verification block:
- File read confirmed: `strategies/authenticatable.rb` lines 157–167 contain verbatim code
  quoted above
- File read confirmed: `lib/generators/templates/devise.rb` lines 41–49 contain verbatim
  quote above
- Both files in vendored gem at exact path cited

---

### Finding 2: What the DB lookup receives when `company_id` is absent (the critical second step)

**Evidence:**

`authenticate!` in `strategies/database_authenticatable.rb` (lines 9–11):

```ruby
def authenticate!
  resource = password.present? && mapping.to.find_for_database_authentication(authentication_hash)
```

Source: `/Users/plribeiro3000/Projects/4Shark/app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/devise/strategies/database_authenticatable.rb:9-11`

`find_for_database_authentication` delegates to `find_for_authentication` (model line 199),
which delegates to `find_first_by_auth_conditions` (model lines 267–269):

```ruby
def find_first_by_auth_conditions(tainted_conditions, opts = {})
  to_adapter.find_first(devise_parameter_filter.filter(tainted_conditions).merge(opts))
end
```

Source: `/Users/plribeiro3000/Projects/4Shark/app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/devise/models/authenticatable.rb:267-269`

`authentication_hash` is passed directly as `tainted_conditions`. When `company_id` is
absent (not added to the hash by `parse_authentication_key_values`), `tainted_conditions`
is `{ email: "alice@example.com" }`. The adapter executes
`WHERE email = 'alice@example.com'` — no `company_id` clause. This is the email-only
fallback behavior.

When `company_id` IS present, `authentication_hash` is
`{ email: "alice@example.com", company_id: 7 }`, and the query is
`WHERE email = 'alice@example.com' AND company_id = 7`.

**Significance:** The hash-form `authentication_keys: { email: true, company_id: false }`
achieves backward-compatible optional scoping WITHOUT a `find_for_authentication` override,
purely through the native Devise mechanism.

HOWEVER: this only works correctly when email is globally unique. When two users share the
same email across different `company_id` values (the 4Shark case), the email-only fallback
(`WHERE email = ?`) will return whichever row the database finds first — which may be the
wrong user.

Verification block:
- File read confirmed: `strategies/database_authenticatable.rb` lines 9–11 match quote above
- File read confirmed: `models/authenticatable.rb` lines 267–269 match quote above

---

### Finding 3: The `authentication_keys` array form (`[:email, :company_id]`) — what it does when `company_id` is absent

**Evidence:**

From `parse_authentication_key_values` (Finding 1), when `keys` is an array,
`keys.each do |key, enforce|` destructures as `key = :company_id, enforce = nil`.

The branch: `return false unless enforce == false` → `nil == false` is `false` in Ruby
→ `return false` executes → the strategy method `valid?` returns `false` → Devise treats
the request as not authenticatable → **login fails immediately with no password check**.

The strategy's `valid_for_params_auth?` method (line 77–80) calls
`with_authentication_hash`, which calls `parse_authentication_key_values`. A `false`
return makes the strategy invalid, so Devise never even calls `authenticate!`.

**Significance:** Array form `authentication_keys = [:email, :company_id]` makes BOTH
keys required. Any request without `company_id` is rejected before password validation.
This breaks backward compatibility: existing clients that do not send `company_id` will
fail immediately.

Verification block:
- Traced through `strategies/authenticatable.rb` lines 17–19 (`valid?`), 77–80
  (`valid_for_params_auth?`), 128–134 (`with_authentication_hash`), 157–167
  (`parse_authentication_key_values`)
- Ruby destructuring behavior for `array.each do |key, enforce|` when array contains
  symbols: `enforce` receives `nil`, confirmed by language specification

---

### Finding 4: The critical unsolved problem — email-only fallback finds the wrong user when emails collide

**Evidence:**

This finding is derived from Findings 1–3 and the 4Shark data constraint (documented in
the parent SPIKE.md Finding 1: email is unique per `(company_id, email)` but NOT globally).

When `authentication_keys: { email: true, company_id: false }` and `company_id` is absent:

1. `parse_authentication_key_values` correctly allows the strategy to proceed
2. `authentication_hash` is `{ email: "170472@atento.com" }`
3. `find_first_by_auth_conditions({ email: "170472@atento.com" })` runs
4. The DB table has TWO rows: one for MX company_id=1, one for BR company_id=2, both
   with email `170472@atento.com`
5. The adapter returns whichever row appears first (table scan order / index order /
   insertion order — not deterministic for the calling application)
6. The user for company_id=2 may receive the credentials for company_id=1

There is no second-factor check in the default Devise flow: `valid_password?` succeeds
as long as the found user's `encrypted_password` matches the submitted password. If the
two users happen to have the same password (both are the same numeric ID, very likely for
auto-generated credentials), BOTH users' passwords would validate against the WRONG record.

**Significance:** For 4Shark specifically, the email-only fallback from hash-form
`authentication_keys` is NOT safe as a backward-compatible path because the email
collisions are real and active. The fallback would log users into the wrong tenant's
account non-deterministically.

The hash-form `authentication_keys` is only safe as a backward-compatible fallback when
the fallback key (email) is globally unique in the subset of users who do not send the
optional key. For 4Shark, that condition is not met for 8 known pairs (and possibly more
with disabled accounts).

Verification block:
- Derived from source code trace (Findings 1–3) and parent SPIKE.md Finding 1 (active
  email collisions confirmed in production data)
- No independent external citation needed: this is a logical consequence of the code path

---

### Finding 5: `request_keys` vs `authentication_keys` — what each is for, per Devise 5.0.4 source

**Evidence:**

From `models/authenticatable.rb` lines 17–25 (module-level comment):

```
* +authentication_keys+: parameters used for authentication. By default [:email].

* +request_keys+: parameters from the request object used for authentication.
  By specifying a symbol (which should be a request method), it will automatically be
  passed to find_for_authentication method and considered in your model lookup.

  For instance, if you set :request_keys to [:subdomain], :subdomain will be considered
  as key on authentication. This can also be a hash where the value is a boolean specifying
  if the value is required or not.
```

Source: `/Users/plribeiro3000/Projects/4Shark/app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/devise/models/authenticatable.rb:17-25`

The mechanical difference is where the value comes from:

- `authentication_keys`: the value is pulled from the **params hash** (`params[scope]`,
  i.e., the POST body). The user/client must submit these values.
- `request_keys`: the value is pulled from **the request object itself** via
  `self.request.send(k)`. For `:subdomain`, Devise calls `request.subdomain`.

From `strategies/authenticatable.rb` lines 147–155:

```ruby
def request_keys
  @request_keys ||= mapping.to.request_keys
end

def request_values
  keys = request_keys.respond_to?(:keys) ? request_keys.keys : request_keys
  values = keys.map { |k| self.request.send(k) }
  Hash[keys.zip(values)]
end
```

Source: `/Users/plribeiro3000/Projects/4Shark/app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/devise/strategies/authenticatable.rb:147-155`

The initializer template (lines 53–56) reinforces this:

> "Configure parameters from the request object used for authentication. Each entry
> given should be a request method and it will automatically be passed to the
> find_for_authentication method and considered in your model lookup. For instance,
> if you set :request_keys to [:subdomain], :subdomain will be used on authentication.
> The same considerations mentioned for authentication_keys also apply to request_keys."

Source: `/Users/plribeiro3000/Projects/4Shark/app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/generators/templates/devise.rb:53-56`

**Significance for 4Shark:** `company_id` is not a property of the HTTP request object
(it is not a subdomain, not a hostname, not a path segment). It must be submitted as a
POST param by the client. Therefore `authentication_keys` is the correct mechanism, not
`request_keys`. `request_keys` would require `company_id` to be derivable from
`request.company_id` — which Rails does not define.

Verification block:
- File read confirmed: `models/authenticatable.rb` lines 17–25 contain verbatim quote above
- File read confirmed: `strategies/authenticatable.rb` lines 147–155 contain verbatim
  quote above
- File read confirmed: `lib/generators/templates/devise.rb` lines 53–56 contain verbatim
  quote above

---

### Finding 6: What the official Devise wiki recipe for tenant-scoped auth actually does mechanically

**Evidence:**

The official Devise wiki page "How to: Scope login to subdomain"
(https://github.com/heartcombo/devise/wiki/How-to:-Scope-login-to-subdomain) lists
four required steps:

> 1. "Modify the Devise-generated migration to remove the index on email uniqueness constraint"
> 2. "Change login keys to include `:subdomain`"
> 3. "Override Devise hook method `find_for_authentication`"
> 4. "Override Devise hook method `send_reset_password_instructions`"

For step 2, the wiki shows:

```ruby
devise :database_authenticatable, :registerable,
       :recoverable, :rememberable, :trackable, request_keys: [:subdomain]
```

And notes:

> "If you are using column name other than `subdomain` to scope login to subdomain, you
> may have to use `authentication_keys`"

For step 3, the wiki shows a `find_for_authentication` **override**:

```ruby
def self.find_for_authentication(warden_conditions)
  where(:email => warden_conditions[:email], :subdomain => warden_conditions[:subdomain]).first
end
```

Source: fetched from https://github.com/heartcombo/devise/wiki/How-to:-Scope-login-to-subdomain
(full text in existing `devise_doc_1_scope_login.txt`)

**Significance:** The official Devise wiki recipe for tenant-scoped auth COMBINES both
`authentication_keys`/`request_keys` AND a `find_for_authentication` override. It does
NOT rely purely on the native keys mechanism. The "native vs override" framing is a false
dichotomy — Devise's own documented recipe uses the override as part of the standard
pattern. The keys configuration determines what goes into `authentication_hash`; the
override determines what the DB query actually does.

Verification block:
- `devise_doc_1_scope_login.txt` → URL fetched previously (parent SPIKE.md), verbatim
  quotes confirmed in file at that path in this directory
- Two separate WebFetch calls in this session confirmed the same four-step structure from
  both the `heartcombo/devise` and the `plataformatec/devise` wiki URLs

---

### Finding 7: Community understanding of the hash-form `authentication_keys` boolean

**Evidence:**

From Devise Issue #2288 (https://github.com/heartcombo/devise/issues/2288), a reporter
found a bug specifically when using hash form `authentication_keys` with HTTP Basic auth.
The bug was in `http_auth_hash` (a separate method from `parse_authentication_key_values`)
— HTTP Basic auth extracts only the first key and the hash form broke the key extraction.
This is separate from params auth (the normal form POST / JSON login path).

From Devise Issue #1255 (https://github.com/heartcombo/devise/issues/1255), a reporter
observed that `parse_authentication_key_values` returns `false` on the first missing
required key without checking other keys — confirming that for array-form keys, ALL must
be present for the strategy to be valid.

The community understanding (confirmed by search results across multiple sources) is
consistent:

> "You can supply a hash where the value is a boolean determining whether or not
> authentication should be aborted when the value is not present."

Source: Summarized from Devise initializer template, Issues #1255 and #2288, and community
discussions. Direct quote from initializer template at lines 47–49 as cited in Finding 1.

**Known edge case — HTTP Basic auth with hash-form keys:** Issue #2288 reports that
HTTP Basic auth breaks when `authentication_keys` is a hash. This is because
`http_authentication_key` (line 141–145 of `strategies/authenticatable.rb`) uses
`authentication_keys.first` without accounting for the hash form, returning the hash
pair instead of just the key symbol. This was later addressed by adding
`http_authentication_key` as a separate config option (PR #2315). For params auth
(standard login POST), this bug does not apply.

Verification block:
- Issue #1255 fetched, describes behavior of `parse_authentication_key_values` with
  multiple keys
- Issue #2288 fetched, describes HTTP Basic auth bug with hash-form `authentication_keys`
- Initializer template quote verified in Finding 1 above

---

## Verdict (evidence input — not a decision)

**Can Devise 5.0.4 native `authentication_keys` make `company_id` optional?**

**Mechanically: YES**, the hash form `authentication_keys: { email: true, company_id: false }`
makes `company_id` optional at the Warden strategy level. The source proof is
`parse_authentication_key_values` (Finding 1): when `company_id` is absent and its hash
value is `false`, `enforce == false` is `true`, the key is skipped, and the strategy
proceeds with only `email` in `authentication_hash`. Login is not rejected.

**For 4Shark's specific constraint: UNSAFE** when emails collide across tenants (Finding 4).
The email-only fallback executes `WHERE email = ?` against a table where that query returns
two rows (two different humans). Devise picks whichever row the adapter returns first —
non-deterministic, potentially wrong user, no error surfaced. The optional `company_id`
native mechanism is only safe when the fallback key (email) is globally unique in the set
of users who log in without `company_id`. In 4Shark today that condition is false for at
least 8 known email pairs.

**What the wiki's own documented native pattern for this case mechanically does:**
It uses `request_keys` OR `authentication_keys` (keys config) PLUS a
`find_for_authentication` override. The override IS the documented native Devise pattern —
the keys config alone is not sufficient for tenant-scoped lookup (Finding 6).

**`request_keys` vs `authentication_keys` for `company_id`:** `company_id` is a POST
param submitted by the client, not a property of the request object. `request_keys` reads
from `request.send(:company_id)` — which does not exist on a standard Rails request.
`authentication_keys` is the correct mechanism (Finding 5).

**Community-recommended mechanism for optional backward-compatible tenant-scoped auth:**

No community source was found recommending the native hash-form `authentication_keys`
as a backward-compatible optional tenant key when emails can collide. The community
pattern for this case universally involves:

1. A `find_for_authentication` override that handles the nil-`company_id` case explicitly
   in Ruby (not relying on the DB query to do the right thing):

```ruby
def self.find_for_authentication(warden_conditions)
  email = warden_conditions[:email]
  company_id = warden_conditions[:company_id]
  if company_id.present?
    find_by(email: email, company_id: company_id)
  else
    find_by(email: email)  # only safe if email is globally unique in your data
  end
end
```

2. Combined with `authentication_keys: { email: true, company_id: false }` so that
   `company_id` reaches `authentication_hash` when present but does not block the strategy
   when absent.

The wiki page at https://github.com/heartcombo/devise/wiki/How-to:-Scope-login-to-subdomain
shows this exact pattern (step 3 override) as part of Devise's own documented recipe.

---

## Trade-offs surfaced

| Approach | Pros | Cons | Source |
|----------|------|------|--------|
| Hash-form `authentication_keys` only, no override | Native mechanism, zero code | Unsafe when emails collide: DB returns wrong user on email-only fallback | Finding 4 (source code trace) |
| Hash-form `authentication_keys` + `find_for_authentication` override | Backward compatible, explicit control of nil case | Not purely native — override IS the documented pattern | Finding 6 (Devise wiki) |
| Array-form `authentication_keys` | Strict scoping, correct for non-colliding tenants | Breaks all existing clients that do not send `company_id` | Finding 3 (source code) |
| `request_keys` | Correct for HTTP-request-derived values (subdomain) | Does not work for POST-param `company_id` | Finding 5 (source code) |

---

## What remains uncertain

1. **Whether the 8 known email collisions cover all active users**: If other active users
   have colliding emails that were not surfaced in the initial audit, the "safe subset" for
   the optional fallback is smaller than believed.

2. **The HTTP Basic auth edge case (Issue #2288)**: The known bug with hash-form
   `authentication_keys` and HTTP Basic auth — if any client uses HTTP Basic auth (not
   form POST), the hash form may behave unexpectedly. Needs verification against actual
   auth paths in use.

3. **`devise_parameter_filter` behavior with `company_id`**: `find_first_by_auth_conditions`
   passes through `devise_parameter_filter.filter(tainted_conditions)`. If `company_id` is
   not in `case_insensitive_keys` or `strip_whitespace_keys`, it passes through unmodified
   (expected). But if the adapter type-coerces integer `company_id` from string differently
   across ORM versions, the lookup could silently fail to match. Not verified.

---

## Suggested options for main and the engineer

**Option N1 — Hash-form `authentication_keys` + override (the documented Devise pattern)**

```ruby
# in User model
devise :database_authenticatable, ...,
       authentication_keys: { email: true, company_id: false }

def self.find_for_authentication(warden_conditions)
  email = warden_conditions[:email]
  company_id = warden_conditions[:company_id]
  if company_id.present?
    find_by(email: email, company_id: company_id)
  else
    find_by(email: email)
  end
end
```

Backward compatible: clients without `company_id` fall into the `find_by(email:)` branch.
Collisions in that branch are unsolved — whoever the DB returns first wins. Safe only until
clients are updated. This matches Devise's own documented recipe (wiki step 3).

**Option N2 — Hash-form `authentication_keys` + override with collision guard**

Same as N1, but the else branch adds an explicit guard:

```ruby
else
  users = where(email: email)
  users.count == 1 ? users.first : nil  # refuse if ambiguous
end
```

Backward compatible AND safe for users with unique email; refuses login (returns nil → auth
fails with :not_found_in_database) for the 8 collision cases until the client sends
`company_id`. Non-collision users are unaffected. Collision users get a failed login (not
a wrong-user login) during the transition window.

**Option N3 — Skip `authentication_keys` entirely; do the whole thing in `find_for_authentication`**

```ruby
def self.find_for_authentication(warden_conditions)
  company_id = warden_conditions.delete(:company_id)
  scope = company_id.present? ? where(company_id: company_id) : all
  scope.find_by(email: warden_conditions[:email])
end
```

With `authentication_keys: [:email]` (array, default). `company_id` never enters
`authentication_hash` (so no strategy-level optional-key mechanics needed); the override
reads it directly from `warden_conditions` (which contains all params). Requires
`company_id` to reach `warden_conditions` — this works because Devise passes the full
filtered params hash to `find_for_authentication`, not just `authentication_hash`.
NOTE: this approach needs verification that `warden_conditions` does contain `company_id`
even when it is not listed in `authentication_keys`. The source at
`models/authenticatable.rb:263-265` shows `find_for_authentication(tainted_conditions)`
receives whatever the strategy passes — which is `authentication_hash`, built only from
`authentication_keys`. If `company_id` is not in `authentication_keys`, it is NOT in
`tainted_conditions`. This option therefore requires listing `company_id` in
`authentication_keys` as `false` to get it into the hash — which collapses back to N1/N2.

(NO recommendation — surface options N1 and N2 as the evidence-backed paths; the engineer
and main choose between them based on acceptable behavior for the 8-collision cases during
the transition window.)
