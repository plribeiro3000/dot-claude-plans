# SOURCE: /Users/plribeiro3000/Projects/4Shark/app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/devise/models/authenticatable.rb
# Lines 263–269 — find_for_authentication and find_first_by_auth_conditions
# Shows that authentication_hash is passed as tainted_conditions directly to the DB adapter.
# When company_id is absent (false in hash-form auth_keys), it is simply NOT in authentication_hash,
# so the DB query runs: WHERE email = ? (no company_id clause) — email-only fallback.

def find_for_authentication(tainted_conditions)
  find_first_by_auth_conditions(tainted_conditions)
end

def find_first_by_auth_conditions(tainted_conditions, opts = {})
  to_adapter.find_first(devise_parameter_filter.filter(tainted_conditions).merge(opts))
end
