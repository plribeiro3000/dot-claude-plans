# Auxiliary file — anonimizacao-por-pais spike
# Consolidated reference bundle: the CURRENT (as of 2026-07-08) per-user jurisdiction
# resolution code already in the `app` repository. This is the existing mechanism used for
# `/legalDocumentAcceptance` — the spike's central finding is that this same mechanism can
# resolve a user's country for the anonymization window, since it already resolves a user's
# country for a different purpose (which legal documents apply to them).

# =============================================================================
# app/models/user.rb:197-201 — state_id presence validation (with an escape hatch)
# =============================================================================

# validates :state_id, presence: true, unless: -> { state_iso3166_present? }
# validates :identifiers, length: { minimum: 1 }, unless: :anonymized?
# validates :unique_register_id, presence: true, identity: { identity_type: :register_type, format: true }, unless: :anonymized?
# validate :anonymization

# =============================================================================
# app/models/user.rb:376-391 — the existing per-user jurisdiction resolution, used today for
# legal document acceptance (`/legalDocumentAcceptance`, the Control B precedent referenced in
# JURISDICTION.md).
# =============================================================================

def legal_documents
  @legal_documents ||= LegalDocument.enabled.for_company(company_id).for_country(state.country_id)
end

def pending_legal_documents
  legal_documents.where(
    'NOT EXISTS (SELECT 1 FROM legal_document_acceptances ' \
    'WHERE legal_document_acceptances.legal_document_id = legal_documents.id ' \
    'AND legal_document_acceptances.user_id = ?)',
    id
  )
end

def pending_legal_documents_acceptance?
  pending_legal_documents.any?
end

# =============================================================================
# app/models/user.rb:484-494 — how state_id gets set from an ISO 3166 code (import/API path)
# =============================================================================

def state_iso3166_present?
  state_iso3166.present?
end

def resolve_state_iso3166
  return if state_iso3166.nil?

  self.state_id = State.find_by!(iso3166: state_iso3166).id
rescue ActiveRecord::RecordNotFound
  errors.add(:state_id, :not_found)
end

# =============================================================================
# app/models/state.rb — full file. The join between a user's individual address (state) and a
# country.
# =============================================================================

# frozen_string_literal: true

class State < ApplicationRecord
  has_many :users, dependent: :nullify, inverse_of: :state
  belongs_to :country, optional: true, inverse_of: :states

  validates :country_id, presence: true
  validates :iso3166, presence: true

  scope :for_country, ->(country) { where(country_id: country) if country.present? }

  pg_search_scope :search_for_name_or_acronym, against: %i[name acronym], using: { tsearch: { prefix: true } }
  rescue_unique_constraint index: :index_states_on_acronym, field: :acronym

  def self.search_by_name_or_acronym(string)
    return search_for_name_or_acronym(string).with_pg_search_rank if string.present?

    where(nil)
  end
end

# =============================================================================
# app/models/country.rb — full file
# =============================================================================

# frozen_string_literal: true

class Country < ApplicationRecord
  has_many :business_territories, class_name: 'CompanyBusinessTerritory', dependent: :destroy, inverse_of: :country
  has_many :company_branches, dependent: :destroy, inverse_of: :country
  has_many :legal_documents, dependent: :destroy, inverse_of: :country
  has_many :register_types, dependent: :destroy, inverse_of: :country
  has_many :states, dependent: :destroy, inverse_of: :country

  # Keep through associations defined after the regular ones
  has_many :companies, through: :business_territories

  validates :flag_url, presence: true

  scope :for_company, ->(company) { joins(:business_territories).where('business_territories.company_id': company) if company.present? }

  pg_search_scope :search_for_name_or_acronym, against: %i[name acronym], using: { tsearch: { prefix: true } }
  rescue_unique_constraint index: :index_countries_on_acronym, field: :acronym

  def self.search_by_name_or_acronym(string)
    return search_for_name_or_acronym(string).with_pg_search_rank if string.present?

    where(nil)
  end
end

# =============================================================================
# app/models/legal_document.rb — full file. Shows the country-scoping pattern already in
# production: `for_country` scope, `country_id` presence-validated.
# =============================================================================

# frozen_string_literal: true

class LegalDocument < ApplicationRecord
  belongs_to :company, optional: true, inverse_of: :legal_documents
  belongs_to :country, optional: true, inverse_of: :legal_documents
  has_many :acceptances, class_name: 'LegalDocumentAcceptance', dependent: :destroy, inverse_of: :legal_document

  validates :country_id, presence: true
  validates :name, presence: true
  validates :path, presence: true

  scope :for_company, ->(company_id) { where(company_id: [company_id, nil]) if company_id.present? }
  scope :for_country, ->(country_id) { where(country_id: country_id) if country_id.present? }
end

# =============================================================================
# app/models/company.rb:12,71,76,78 — a Company can have MULTIPLE countries (business
# territories). This is the second, DIFFERENT source of "country" for a user — the company's
# declared operating countries, as opposed to the user's own state/address. The two can
# disagree; see SPIKE.md "What remains uncertain".
# =============================================================================

# has_many :business_territories, class_name: 'CompanyBusinessTerritory', inverse_of: :company, dependent: :destroy
# ...
# has_many :countries, through: :business_territories
# ...
# accepts_nested_attributes_for :business_territories, allow_destroy: true, reject_if: :all_blank
# validates :business_territories, length: { minimum: 1 }
