# Auxiliary file for SPIKE.md — partial verbatim excerpts for reference.
# Sources (app repo, backend):
#   ~/Projects/4Shark/app/app/models/variable.rb (lines 1-110, frequency enum at 68-79)
#   ~/Projects/4Shark/app/app/models/seat.rb (lines 1-18, TYPES at 7-8)
#   ~/Projects/4Shark/app/db/schema.rb (companies table, boolean columns, lines 506-533)
# Repo commit at capture time: 611d5a5c80d9ecd42df90e325615d178a153a8d4
# Relevant to demand 2 (frequency enum — monthly totalizer) and demand 3/4
# (seat hierarchy, per-company legal-module precedent for a collapse-default flag).

# --- variable.rb:1-110 --------------------------------------------------------
# frozen_string_literal: true

class Variable < ApplicationRecord
  TYPES = %w[DealVariable IndicatorVariable EasyVariable].freeze

  belongs_to :company, optional: true, inverse_of: :variables
  belongs_to :disabler, class_name: 'User', inverse_of: :disabled_variables, optional: true
  belongs_to :document, class_name: 'VariableDocument', inverse_of: :variables, foreign_key: :variable_document_id, optional: true
  belongs_to :owner, class_name: 'User', inverse_of: :owned_variables, optional: true
  has_many :aggregated_indicators, dependent: :destroy, inverse_of: :variable
  has_many :calendar_audit_rows, class_name: 'CalendarAudit::Row', inverse_of: :variable, dependent: :nullify
  has_many :calendar_performance_analyses, dependent: :destroy, inverse_of: :variable
  has_many :deal_fields, dependent: :restrict_with_exception, inverse_of: :variable
  has_many :goals, dependent: :destroy, inverse_of: :variable
  has_many :incentive_variables, dependent: :destroy, inverse_of: :variable
  has_many :indicators, dependent: :destroy, inverse_of: :variable
  has_many :plan_variables, dependent: :destroy, inverse_of: :variable
  has_many :pre_aggregated_indicators, dependent: :destroy, inverse_of: :variable
  has_many :rankifier_variables, dependent: :destroy, inverse_of: :variable
  has_many :requirements, dependent: :destroy, inverse_of: :variable
  has_many :variable_track_collections, dependent: :destroy, inverse_of: :variable
  has_many :variable_tracks, dependent: :destroy, inverse_of: :variable

  has_many :incentives, through: :incentive_variables
  has_many :performance_analyses, through: :calendar_performance_analyses
  has_many :plans, through: :plan_variables
  has_many :rankifiers, through: :rankifier_variables

  has_one :metric, dependent: :destroy, inverse_of: :variable

  validates :calculation, presence: true, if: :indicator?
  validates :company_id, presence: true
  validates :data_type, presence: true
  validates :default, presence: true
  validates :frequency, presence: true, if: :indicator?
  validates :key, presence: true, format: { with: /\A[a-z]+[a-z0-9_]*\z/ }
  validates :name, presence: true
  validates :override_calculation, presence: true, if: :indicator?
  validates :owner_id, presence: true
  validates :type, presence: true, inclusion: { in: TYPES }
  validate :key_value
  validate :string_calculation

  scope :booleans, -> { where(data_type: 'BooleanDataType') }
  scope :dates, -> { where(data_type: 'DateDataType') }
  scope :deals, -> { where(type: 'DealVariable') }
  scope :durations, -> { where(data_type: 'DurationDataType') }
  scope :easy, -> { where(type: 'EasyVariable') }
  scope :for_calculation, ->(calculation) { where(calculation: calculation) if calculation.present? }
  scope :for_company, ->(company_id) { where(company_id: company_id) if company_id.present? }
  scope :for_data_type, ->(data_type) { where(data_type: data_type) if data_type.present? }
  scope :for_frequency, ->(frequency) { where(frequency: frequency) if frequency.present? }
  scope :for_plan, ->(plan_id) { joins(:plans).where('plans.id': plan_id) if plan_id.present? }
  scope :for_type, ->(type) { where(type: type) if type.present? }
  scope :for_variable_document, ->(variable_document_id) { where(variable_document_id: variable_document_id) if variable_document_id.present? }
  scope :ignore, ->(variables) { where.not(id: variables) }
  scope :indicators, -> { where(type: 'IndicatorVariable') }
  scope :numbers, -> { where(data_type: 'NumberDataType') }
  scope :percents, -> { where(data_type: 'PercentDataType') }
  scope :strings, -> { where(data_type: 'StringDataType') }
  scope :timetable, -> { where(data_type: %w[NumberDataType PercentDataType DurationDataType]) }
  scope :with_metrics, -> { joins(:metric) }
  scope :without_metrics, -> { where.missing(:metric) }

  enumerize :calculation, in: { average: 0, sum: 1, last: 2 }, scope: true, skip_validations: ->(variable) { variable.calculation_not_needed? }

  # This is the "monthly" indicator concept demand 2 refers to.
  enumerize :frequency,
            in: {
              daily: 0,
              weekly: 1,
              monthly: 2,
              single: 3
            },
            scope: true,
            skip_validations:
              lambda { |variable|
                variable.frequency_not_needed?
              }

  enumerize :override_calculation,
            in: {
              override_average: 0,
              override_sum: 1
            },
            scope: true,
            skip_validations:
              lambda { |variable|
                variable.override_calculation_not_needed?
              }

  rescue_unique_constraint index: :index_variables_on_company_id_and_key, field: :key
  rescue_unique_constraint index: :index_variables_on_company_id_and_name, field: :name
  pg_search_scope :search_for, against: %i[name key id], using: { tsearch: { prefix: true } }
  pg_search_scope :search_for_name_or_key, against: %i[name key], using: { tsearch: { prefix: true } }
  strip_attributes :name, :key

  delegate :average?, :sum?, :last?, to: :calculation, allow_nil: true
  delegate :boolean?, to: :data_type_object
  delegate :daily?, :weekly?, :monthly?, to: :frequency, allow_nil: true
  delegate :date?, to: :data_type_object
  delegate :duration?, to: :data_type_object
  delegate :format, to: :data_type_object
  delegate :number?, to: :data_type_object
  delegate :output, to: :data_type_object
  delegate :override_average?, :override_sum?, to: :override_calculation, allow_nil: true
  delegate :percent?, to: :data_type_object
  delegate :string?, to: :data_type_object

  after_destroy :delete_datasets
  # (truncated — file continues past line 110)
end

# --- seat.rb:1-18 --------------------------------------------------------------
# frozen_string_literal: true

class Seat < ApplicationRecord
  API_TYPES =
    %w[Admin President VicePresident Director Superintendent GeneralManager Manager Coordinator Supervisor SalesRepresentative].freeze

  # The full seat-type hierarchy, most to least senior. The dashboard template
  # (roadmap-barigui_excerpt_2.html) currently only distinguishes
  # SalesRepresentative from every other type — a binary split, not the full
  # 10-level hierarchy named here.
  TYPES =
    %w[SuperAdmin Admin President VicePresident Director Superintendent GeneralManager Manager Coordinator Supervisor SalesRepresentative].freeze

  belongs_to :parent, polymorphic: true, optional: true
  belongs_to :role, optional: true, inverse_of: :seats
  belongs_to :user, optional: true, inverse_of: :seat
  has_many :histories, class_name: 'SeatHistory', inverse_of: :seat, dependent: :destroy
  has_many :subordinates, class_name: 'Seat', inverse_of: :parent, as: :parent, dependent: :nullify

  validates :role_id, presence: true
  validates :type, inclusion: { in: TYPES }
  validate :circular_dependency
  # (truncated — file continues)
end

# --- db/schema.rb companies table — boolean columns (lines 506-533) -----------
# Cited as PRECEDENT: a per-company boolean toggle for role-dependent behavior
# already exists in this schema (manager_legal_module / operator_legal_module),
# though it governs LEGAL ACCEPTANCE REQUIREMENTS by role, not UI panel
# collapse-by-default state. It establishes the pattern shape (a company-level
# boolean read in Ruby via `company.manager_legal_module?`), not the specific
# behavior demand 4 needs.
#
#   t.boolean "anonymized", default: false, null: false
#   t.boolean "auto_data_processing", default: false, null: false
#   t.boolean "basic_authentication", default: true, null: false
#   t.boolean "client", default: true
#   t.string "commission_queue_suffix"
#   t.boolean "deal_eligibility_module", default: false, null: false
#   t.boolean "goal_calculation_module", default: true, null: false
#   t.boolean "manager_legal_module", default: true, null: false
#   t.boolean "money_sanitization", default: true, null: false
#   t.boolean "operator_legal_module", default: true, null: false
#   t.boolean "payment_api_exportation_module", default: false, null: false
#   t.boolean "payment_floating_point", default: false, null: false
#   t.string "payroll_queue_suffix"
#   t.string "primary_webclient_host", default: "", null: false
#   t.boolean "subsidiaries_module", default: false, null: false
#   t.string "type", limit: 8000
#   t.boolean "verified_emails", default: false, null: false
#   t.string "webclient_hosts", default: [], array: true
