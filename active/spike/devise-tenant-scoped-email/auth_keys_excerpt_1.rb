# SOURCE: /Users/plribeiro3000/Projects/4Shark/app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/devise/strategies/authenticatable.rb
# Lines 128–167 — the complete with_authentication_hash + parse_authentication_key_values chain

# Sets the authentication hash and the password from params_auth_hash or http_auth_hash.
def with_authentication_hash(auth_type, auth_values)
  self.authentication_hash, self.authentication_type = {}, auth_type
  self.password = auth_values[:password]

  parse_authentication_key_values(auth_values, authentication_keys) &&
  parse_authentication_key_values(request_values, request_keys)
end

def authentication_keys
  @authentication_keys ||= mapping.to.authentication_keys
end

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
