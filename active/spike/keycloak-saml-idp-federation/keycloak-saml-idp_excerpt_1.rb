# SOURCE: /Users/plribeiro3000/Projects/4Shark/app/app/controllers/authentication/sessions_controller.rb
# Lines 1-55

# frozen_string_literal: true

module Authentication
  class SessionsController < ApplicationController
    skip_before_action :verify_authenticity_token

    def show
      if authenticator_configuration.nil?
        redirect_to 'https://vendedor.app4shark.com/session/create?error=companyNotFound', allow_other_host: true, status: :found
      elsif current_company.enabled? && current_user.present?
        token = JsonWebToken.encode(user_id: current_user.id)

        if authenticator_configuration.web?
          redirect_to authenticator_configuration.redirect_url(token: token), allow_other_host: true, status: :found
        else
          I18n.locale = current_company.locale
          @redirect_url = authenticator_configuration.redirect_url(token: token)
          render :show
        end
      else
        redirect_to authenticator_configuration.redirect_url(error: 'unauthorized'), allow_other_host: true, status: :found
      end
    end

    private

    def authenticator_configuration
      if instance_variable_defined?(:@authenticator_configuration)
        @authenticator_configuration
      else
        @authenticator_configuration = AuthenticatorConfiguration.find_by(uuid: params[:id])
      end
    end

    def current_company
      @current_company ||= authenticator_configuration.company
    end

    def current_user
      return @current_user if defined?(@current_user)

      if authenticator_configuration.identity_provider_user_uuid.present?
        user_identifier = authenticator_configuration.find_user_identifier_by(code: params[:code], base_url: request.base_url)

        return unless user_identifier

        @current_user = current_company.users.enabled.joins(:identifiers).find_by('user_identifiers.value': user_identifier)
      else
        email = authenticator_configuration.find_user_email_by(code: params[:code], base_url: request.base_url)

        @current_user = current_company.users.enabled.find_by(email: email)
      end
    end
  end
end

# ---

# SOURCE: /Users/plribeiro3000/Projects/4Shark/app/app/models/authenticator.rb
# Lines 1-32

# frozen_string_literal: true

class Authenticator
  attr_reader :authenticator_configuration

  def initialize(authenticator_configuration)
    @authenticator_configuration = authenticator_configuration
  end

  def find_email_by(code:, base_url:)
    redirect_uri = "#{base_url}/authentication/sessions/#{authenticator_configuration.uuid}"

    body = {
      grant_type: 'authorization_code',
      client_id: authenticator_configuration.client_id,
      client_secret: authenticator_configuration.client_secret,
      code: code,
      redirect_uri: redirect_uri
    }

    token_url = "#{authenticator_configuration.url}/realms/#{authenticator_configuration.realm}/protocol/openid-connect/token"
    uri = URI.parse(token_url)
    response = Net::HTTP.post_form(uri, body)
    parsed_response = JSON.parse(response.body)
    token = parsed_response['access_token']

    return unless token

    decoded_token_body, _token_encryption = JWT.decode(token, nil, false, { algorithm: 'RS256' })
    decoded_token_body['email']
  end
end

# ---

# SOURCE: /Users/plribeiro3000/Projects/4Shark/app/app/models/authenticator_configuration.rb
# Lines 1-61

# frozen_string_literal: true

class AuthenticatorConfiguration < ApplicationRecord
  PROVIDERS = %w[microsoft google].freeze
  TYPES = %w[WebAuthenticatorConfiguration MobileAuthenticatorConfiguration].freeze

  belongs_to :company, optional: true, inverse_of: :authenticators

  validates :client_id, presence: true
  validates :client_secret, presence: true
  validates :identity_provider_client_id, presence: true
  validates :identity_provider_client_secret, presence: true
  validates :identity_provider_tenant_id, presence: true, if: :microsoft?
  validates :provider, presence: true, inclusion: { in: PROVIDERS }
  validates :realm, presence: true
  validates :type, inclusion: { in: TYPES }
  validates :url, presence: true
  validates :uuid, presence: true

  encrypts :client_secret, :identity_provider_client_id, :identity_provider_client_secret, :identity_provider_tenant_id

  before_create :generate_uuid

  def authenticator
    @authenticator || Authenticator.new(self)
  end

  def identity_provider
    @identity_provider ||= AzureIdentityProvider.new(self)
  end

  def microsoft?
    provider == 'microsoft'
  end

  def web?
    type == 'WebAuthenticatorConfiguration'
  end

  def mobile?
    type == 'MobileAuthenticatorConfiguration'
  end

  def find_user_email_by(code:, base_url:)
    authenticator.find_email_by(code: code, base_url: base_url)
  end

  def find_user_identifier_by(code:, base_url:)
    email = authenticator.find_email_by(code: code, base_url: base_url)

    return unless email

    identity_provider.find_user_identifier_by(email: email)
  end

  private

  def generate_uuid
    self.uuid ||= SecureRandom.uuid
  end
end

# ---

# SOURCE: /Users/plribeiro3000/Projects/4Shark/app/app/models/authenticator_configuration/azure_identity_provider.rb
# Lines 1-43

# frozen_string_literal: true

class AuthenticatorConfiguration < ApplicationRecord
  class AzureIdentityProvider
    attr_reader :configuration

    def initialize(configuration)
      @configuration = configuration
    end

    def find_user_identifier_by(email:)
      authentication_response =
        Faraday.post("https://login.microsoftonline.com/#{configuration.identity_provider_tenant_id}/oauth2/v2.0/token") do |req|
          req.headers['Content-Type'] = 'application/x-www-form-urlencoded'
          req.body = authentication_body
        end

      parsed_response = JSON.parse(authentication_response.body)
      token = parsed_response['access_token']

      response =
        Faraday.get('https://graph.microsoft.com/v1.0/users') do |req|
          req.headers['Authorization'] = "Bearer #{token}"
          req.headers['Content-Type'] = 'application/json'
          req.params['$filter'] = "Mail eq '#{email}'"
          req.params['$select'] = configuration.identity_provider_user_uuid
        end

      parsed_response = JSON.parse(response.body)

      return if parsed_response.nil? || parsed_response['value'].blank?

      parsed_response['value'].first[configuration.identity_provider_user_uuid]
    end

    private

    def authentication_body
      "client_id=#{configuration.identity_provider_client_id}&scope=https%3A%2F%2Fgraph.microsoft.com%2F.default" \
        "&client_secret=#{configuration.identity_provider_client_secret}&grant_type=client_credentials"
    end
  end
end
