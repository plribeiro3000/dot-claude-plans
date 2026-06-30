# SOURCE: /Users/plribeiro3000/Projects/4Shark/app/vendor/bundle/ruby/4.0.0/gems/devise-5.0.4/lib/devise/strategies/database_authenticatable.rb
# Lines 9–26 — full DatabaseAuthenticatable#authenticate! showing that find_for_database_authentication
# receives authentication_hash directly, without post-filter for absent optional keys.

def authenticate!
  resource  = password.present? && mapping.to.find_for_database_authentication(authentication_hash)
  hashed = false

  if validate(resource){ hashed = true; resource.valid_password?(password) }
    remember_me(resource)
    resource.after_database_authentication
    success!(resource)
  end

  mapping.to.new.password = password if !hashed && Devise.paranoid
  unless resource
    Devise.paranoid ? fail(:invalid) : fail(:not_found_in_database)
  end
end
