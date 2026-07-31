# Full copy of app/models/rule.rb as it exists on develop at the time of this spike
# (2026-07-30, after release 3.60.0 shipped the same day — see app/CHANGELOG.md:31-32).
# Preserved verbatim for line-number reference, because this file has already shifted
# twice during this feature's planning (SPIKE §4.5 -> auxiliary-variables_call-sites_1.md
# -> this state) and BE-4's whole subject is these exact line numbers.
#
# Source: ~/Projects/4Shark/app/app/models/rule.rb (read via the Read tool, verbatim)

# frozen_string_literal: true

class Rule < ApplicationRecord
  # #validate_syntax adds the formula reasons by hand, so no validator carries the option.
  # too_few_operands and too_many_operands are left out on purpose: they report expected and
  # actual, and the column holds one value, so half of the pair would reach the message alone.
  CONSTRAINT_OPTION_BY_ATTRIBUTE_AND_ERROR_KEY = { value: { parse_error: :excerpt, undefined_function: :function } }.freeze

  PARSE_EXCEPTIONS =
    [Dentaku::Error, Dentaku::ZeroDivisionError, Dentaku::ArgumentError, NoMethodError, ArgumentError, NameError].freeze

  TYPES = %w[FormulaRule IndicatorRule LimiterRule RankingRule RedemptionRule].freeze

  belongs_to :incentive, optional: true, inverse_of: :rules
  belongs_to :variable_track, optional: true, inverse_of: :rule
  has_many :commissionings, dependent: :nullify, inverse_of: :rule

  validates :type, presence: true, inclusion: { in: TYPES }
  validates :value, presence: true
  validate :formula_syntax, if: :formula?
  validate :indicator_syntax, if: :indicator?
  validate :ranking_syntax, if: :ranking?
  validate :limiter_syntax, if: :limiter?
  validate :redemption_syntax, if: :redemption?

  scope :formula, -> { where(type: 'FormulaRule') }
  scope :indicator, -> { where(type: 'IndicatorRule') }
  scope :limiter, -> { where(type: 'LimiterRule') }
  scope :ranking, -> { where(type: 'RankingRule') }
  scope :redemption, -> { where(type: 'RedemptionRule') }

  def formula
    return @formula if @formula.present? && @formula.text == value

    @formula = Formula.new(value)
  end

  def formula?
    type == 'FormulaRule'
  end

  def limiter?
    type == 'LimiterRule'
  end

  def indicator?
    type == 'IndicatorRule'
  end

  def ranking?
    type == 'RankingRule'
  end

  def redemption?
    type == 'RedemptionRule'
  end

  def calculate(options = {})
    calculate!(options)
  rescue *PARSE_EXCEPTIONS => _e
    0
  end

  def calculate!(options = {})
    Dentaku!(value, cast_values(options)).to_f
  end

  private

  def cast_values(options)
    options.each_key do |key|
      options[key] = BigDecimal(options[key].to_s) if options[key].instance_of?(Float)
    end
  end

  def formula_syntax
    validate_syntax(
      statuses_options
          .merge(metrics_options)
          .merge(deal_extra_fields_options)
          .merge(
            dias_em_aberto: rand(1..30),
            estado: 'executed',
            horas_trabalhadas: rand(1..10),
            meta: rand(4_000_000_000..5_000_000_000),
            parcela: rand(1..7),
            quantidade: rand(1..65),
            valor: rand(1_000_000_000..1_500_000_000),
            open_days: rand(1..30),
            status: 'executed',
            work_hours: rand(1..10),
            goal: rand(4_000_000_000..5_000_000_000),
            installment: rand(1..7),
            quantity: rand(1..65),
            value: rand(1_000_000_000..1_500_000_000)
          )
    )
  end

  def indicator_syntax
    variable_options = incentive.company.easy? ? easy_variables_options : indicator_variables_options

    validate_syntax(
      statuses_options
        .merge(variable_options)
        .merge(
          meta: rand(4_000_000_000..5_000_000_000),
          orcamento: rand(5_000_000_000..7_500_000_000),
          premio: rand(1_000_000_000..2_000_000_000),
          quantidade_transacoes: rand(1..145),
          goal: rand(4_000_000_000..5_000_000_000),
          budget: rand(5_000_000_000..7_500_000_000),
          premium: rand(1_000_000_000..2_000_000_000),
          deal_quantity: rand(1..145)
        )
    )
  end

  def ranking_syntax
    validate_syntax(
      statuses_options
        .merge(indicator_variables_options)
        .merge(
          alcance: rand(1..112),
          meta: rand(4_000_000_000..5_000_000_000),
          orcamento: rand(5_000_000_000..7_500_000_000),
          premio: rand(1_000_000_000..2_000_000_000),
          quantidade_transacoes: rand(1..145),
          quartil: rand(1..4),
          quintil: rand(1..5),
          ranking: rand(1..25),
          resultado: rand(1..100),
          reach: rand(1..112),
          goal: rand(4_000_000_000..5_000_000_000),
          budget: rand(5_000_000_000..7_500_000_000),
          premium: rand(1_000_000_000..2_000_000_000),
          deal_quantity: rand(1..145),
          quartile: rand(1..4),
          quintile: rand(1..5),
          result: rand(1..100)
        )
    )
  end

  def limiter_syntax
    validate_syntax(
      statuses_options
          .merge(indicator_variables_options)
          .merge(
            alcance_orcamento: rand(1..130),
            meta: rand(4_000_000_000..5_000_000_000),
            orcamento: rand(5_000_000_000..7_500_000_000),
            premio: rand(1_000_000_000..2_000_000_000),
            premio_grupo: rand(2_500_000_000..5_000_000_000),
            quantidade_transacoes: rand(1..145),
            budget_reach: rand(1..130),
            goal: rand(4_000_000_000..5_000_000_000),
            budget: rand(5_000_000_000..7_500_000_000),
            premium: rand(1_000_000_000..2_000_000_000),
            group_premium: rand(2_500_000_000..5_000_000_000),
            deal_quantity: rand(1..145)
          )
    )
  end

  def redemption_syntax
    validate_syntax(
      statuses_options
          .merge(indicator_variables_options)
          .merge(
            pontos: rand(1..150),
            points: rand(1..150)
          )
    )
  end

  def validate_syntax(options = {})
    formula_error = formula.error

    return errors.add(:value, formula_error.reason, **formula_error.details) if formula_error.present?

    calculate!(options)
  rescue *PARSE_EXCEPTIONS => _e
    errors.add(:value, :invalid)
  end

  def metrics_options
    incentive.company.variables.indicators.enabled.joins(:metric).each_with_object({}) do |variable, options|
      options["#{variable.key}_goal"] = rand(1..5_000) # english variable
      options["meta_#{variable.key}"] = rand(1..5_000) # portuguese variable
      options[variable.key] = rand(1..5_000)
    end
  end

  def statuses_options
    incentive.company.statuses.enabled.each_with_object({}) do |status, options|
      options["group_total_quantity_#{status.key}"] = rand(5000..10_000)
      options["quantidade_total_#{status.key}"] = rand(5000..10_000)
      options["quantidade_total_grupo_#{status.key}"] = rand(5000..10_000)
      options["total_#{status.key}"] = rand(5000..10_000)
      options["group_total_#{status.key}"] = rand(5000..10_000)
      options["total_grupo_#{status.key}"] = rand(5000..10_000)
      options["total_quantity_#{status.key}"] = rand(5000..10_000)
    end
  end

  def deal_extra_fields_options
    incentive.company.variables.deals.to_h do |variable|
      [variable.key, rand(1..5_000)]
    end
  end

  def indicator_variables_options
    incentive.company.variables.indicators.enabled.each_with_object({}) do |variable, options|
      options["#{variable.key}_goal"] = rand(5000..10_000) # english variable
      options["meta_#{variable.key}"] = rand(5000..10_000) # portuguese variable
      options[variable.key] = rand(1..5_000)
    end
  end

  def easy_variables_options
    incentive.company.variables.easy.enabled.to_h do |variable|
      [variable.key, rand(1..5_000)]
    end
  end
end
