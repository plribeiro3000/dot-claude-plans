# Phase 11 — COUNTS. Recompute lojas_atingimento, atingimento_lideres and hc against the base as it
# stands now, print each beside the Indicator stored on the Executivo, correct the divergent ones.
# Target: app-shared-001. Paste into: bin/ecs run <stack>
# dry_run = true reports and writes NOTHING. dry_run = false UPDATES INDICATORS IN PRODUCTION.
#
# These three variables carry no metric, so no mirror reaches them: their value enters as an EXTERNAL
# Indicator, one per Executivo. That makes them the one part of the delivery that a deal-level
# reconciliation cannot touch, and the reason they need their own pass.
#
# ALL THREE ARE FUNCTIONS OF THE SUBTREE, so any hierarchy move invalidates them silently — the
# stored Indicator keeps the count taken against the tree of the day it was written.
#
# THE ATTRIBUTION INCLUDES THE EXECUTIVO. Several stores hang their goal on the Executivo instead of
# a dedicated leader, so a subtree that excludes its own root loses those outright.
#
# EVERY GOAL EXISTS TWICE and only one of the two is real: the one bound to the plan that measures it
# (Goal has_many :plans, through: :goal_plans -- goal.rb:15,21). The other ends on the 30th and has
# no plan. Counting without that filter doubles every store and every leader while looking correct.
#
# goals.value and modifiers.value are STRINGS. The conversion is variable.data_type.format(value),
# the same call Indicator#format makes (indicator.rb:85-87); comparing or summing the raw column is
# a string operation and gives a wrong answer without raising.
#
# The store variables are read from the plan that apures them rather than from a list, so a store
# added or retired is picked up on its own. The hc_ variables are matched by key prefix and printed
# in full, because nothing else groups them.

require 'csv'

dry_run = true

company_id = 2077

executivos_plan_id = 78939
lojas_plan_id = 78944
lideres_plan_id = 78938
competence_period_id = 528210

lojas_atingimento_variable_id = 36927
atingimento_lideres_variable_id = 36928
headcount_variable_id = 36480
vendas_instaladas_variable_id = 36311

expected_bucket = '4shark-shared-001'

puts "bucket@#{ApplicationConfiguration.aws_bucket}@expected@#{expected_bucket}"

if ApplicationConfiguration.aws_bucket != expected_bucket
  puts '[counts] wrong stack -- nothing was read'
else
  executivos_plan = Plan.find(executivos_plan_id)
  period = executivos_plan.periods.find(competence_period_id)
  executivos_commission = Commission.for_company(company_id).for_plan(executivos_plan_id).for_period(competence_period_id).first

  lojas_plan = Plan.find(lojas_plan_id)
  lojas_commission = Commission.for_company(company_id).for_plan(lojas_plan_id).for_period(competence_period_id).first
  loja_variable_ids = lojas_plan.variables.pluck(:id)

  lideres_plan = Plan.find(lideres_plan_id)
  lideres_commission = Commission.for_company(company_id).for_plan(lideres_plan_id).for_period(competence_period_id).first

  headcount_variable_ids =
    IndicatorVariable
    .where(company_id: company_id)
    .where("key LIKE 'hc\\_%'")
    .pluck(:id, :key)

  puts "period@#{period.id}@#{period.starts_at}@#{period.ends_at}"
  puts "lojas@plan@#{lojas_plan.id}@commission@#{lojas_commission.id}@variables@#{loja_variable_ids.size}"
  puts "lideres@plan@#{lideres_plan.id}@commission@#{lideres_commission.id}@participants@#{lideres_commission.user_commissions.count}"
  puts "headcount_variables@#{headcount_variable_ids.inspect}"

  rows = []
  matching_count = 0
  diverging_count = 0
  absent_count = 0
  applied_count = 0
  failed_count = 0

  UserCommission.where(commission_id: executivos_commission.id).order(:user_id).find_each do |executivo_commission|
    executivo = User.find(executivo_commission.user_id)
    # The root is kept: a store whose goal hangs on the Executivo has no other holder in the subtree.
    subtree_user_ids = UserScope.new(executivo, User).resolve.pluck(:id)

    reached_loja_keys = []
    missed_loja_keys = []

    Goal
      .where(company_id: company_id, type: 'UserGoal', group_id: nil)
      .where(variable_id: loja_variable_ids)
      .where(user_id: subtree_user_ids)
      .where(starts_at: period.starts_at, ends_at: period.ends_at)
      .order(:id)
      .pluck(:id)
      .each do |goal_id|
        goal = Goal.find(goal_id)

        if goal.plans.empty?
          next
        end

        variable = goal.variable
        goal_value = variable.data_type.format(goal.value)

        holder_commission = UserCommission.find_by(commission_id: lojas_commission.id, user_id: goal.user_id)

        reached_value =
          if holder_commission.nil?
            0
          else
            aggregated = holder_commission.aggregated_indicators.find_by(variable_id: variable.id)

            if aggregated.nil?
              0
            else
              aggregated.format
            end
          end

        if reached_value >= goal_value
          reached_loja_keys << "#{variable.key}:#{reached_value}/#{goal_value}"
        else
          missed_loja_keys << "#{variable.key}:#{reached_value}/#{goal_value}"
        end
      end

    reached_lider_ids = []
    missed_lider_ids = []
    lider_without_goal_ids = []

    UserCommission
      .where(commission_id: lideres_commission.id, user_id: subtree_user_ids)
      .order(:user_id)
      .pluck(:id)
      .each do |lider_commission_id|
        lider_commission = UserCommission.find(lider_commission_id)

        lider_goal =
          Goal
          .where(company_id: company_id, type: 'UserGoal', group_id: nil)
          .where(variable_id: vendas_instaladas_variable_id)
          .where(user_id: lider_commission.user_id)
          .where(starts_at: period.starts_at, ends_at: period.ends_at)
          .find { |candidate_goal| candidate_goal.plans.any? }

        if lider_goal.nil?
          lider_without_goal_ids << lider_commission.user_id
          next
        end

        goal_value = lider_goal.variable.data_type.format(lider_goal.value)
        aggregated = lider_commission.aggregated_indicators.find_by(variable_id: vendas_instaladas_variable_id)

        reached_value =
          if aggregated.nil?
            0
          else
            aggregated.format
          end

        if reached_value >= goal_value
          reached_lider_ids << "#{lider_commission.user_id}:#{reached_value}/#{goal_value}"
        else
          missed_lider_ids << "#{lider_commission.user_id}:#{reached_value}/#{goal_value}"
        end
      end

    headcount_total = 0
    headcount_detail = []

    headcount_variable_ids.each do |headcount_variable_id, headcount_variable_key|
      Indicator
        .for_company(company_id)
        .for_variable(headcount_variable_id)
        .where(user_id: subtree_user_ids)
        .where(compiled_at: period.starts_at..period.ends_at)
        .order(:id)
        .pluck(:id)
        .each do |headcount_indicator_id|
          headcount_indicator = Indicator.find(headcount_indicator_id)
          headcount_total += headcount_indicator.format
          headcount_detail << "#{headcount_variable_key}:#{headcount_indicator.format}"
        end
    end

    computed_by_variable_id = {
      lojas_atingimento_variable_id => reached_loja_keys.size,
      atingimento_lideres_variable_id => reached_lider_ids.size,
      headcount_variable_id => headcount_total
    }

    puts "executivo@#{executivo.id}@#{executivo.name}@subtree@#{subtree_user_ids.size}"
    puts "  lojas@reached@#{reached_loja_keys.inspect}"
    puts "  lojas@missed@#{missed_loja_keys.inspect}"
    puts "  lideres@reached@#{reached_lider_ids.inspect}"
    puts "  lideres@missed@#{missed_lider_ids.inspect}"
    puts "  lideres@without_goal@#{lider_without_goal_ids.inspect}"
    puts "  hc@detail@#{headcount_detail.inspect}"

    computed_by_variable_id.each do |variable_id, computed_value|
      variable = IndicatorVariable.find(variable_id)

      stored_indicator =
        Indicator
        .for_company(company_id)
        .for_variable(variable_id)
        .where(user_id: executivo.id)
        .where(compiled_at: period.starts_at..period.ends_at)
        .first

      written_value =
        if computed_value == computed_value.to_i
          computed_value.to_i.to_s
        else
          computed_value.to_s
        end

      if stored_indicator.nil?
        absent_count += 1
        rows << [executivo.id, executivo.name, variable.key, nil, nil, computed_value, written_value, 'ABSENT', nil]
        puts "    #{variable.key}@computed@#{computed_value}@stored@ABSENT"
        next
      end

      stored_value = stored_indicator.format
      # Read before the update: this column is what a reversal reads back.
      previous_raw_value = stored_indicator.value

      puts "    #{variable.key}@computed@#{computed_value}@stored@#{stored_value}" \
           "@raw@#{previous_raw_value.inspect}@destroyable@#{stored_indicator.destroyable?}"

      if stored_value == computed_value
        matching_count += 1
        next
      end

      diverging_count += 1

      if dry_run
        rows << [executivo.id, executivo.name, variable.key, stored_indicator.id, previous_raw_value,
                 computed_value, written_value, 'PLANNED', nil]
      # An indicator stops being destroyable once the competence is processed, so the correction is
      # an update of the value -- destroy would be refused (indicator.rb:97-105).
      elsif stored_indicator.update(value: written_value)
        applied_count += 1
        rows << [executivo.id, executivo.name, variable.key, stored_indicator.id, previous_raw_value,
                 computed_value, written_value, 'UPDATED', nil]
      else
        failed_count += 1
        rows << [executivo.id, executivo.name, variable.key, stored_indicator.id, previous_raw_value,
                 computed_value, written_value, 'FAILED', stored_indicator.errors.full_messages.join(' / ')]
      end
    end
  rescue StandardError => error
    puts "executivo@#{executivo_commission.user_id}@ERROR: #{error.message}"
  end

  puts "MATCHING@#{matching_count}@DIVERGING@#{diverging_count}@ABSENT@#{absent_count}" \
       "@APPLIED@#{applied_count}@FAILED@#{failed_count}"

  aws_bucket = ApplicationConfiguration.aws_bucket
  timestamp = Time.now.utc.strftime('%Y%m%d-%H%M%S')
  file_path = "integration-debug/audits/#{company_id}/premiacao-contagens/#{timestamp}.csv"

  csv_string =
    CSV.generate do |csv|
      csv << %w[executivo_id executivo_name variable_key indicator_id stored_value computed_value
                written_value outcome detail]
      rows.each { |row| csv << row }
    end

  Aws.with_connection { |connection| connection.put_object(aws_bucket, file_path, csv_string) }

  puts "s3://#{aws_bucket}/#{file_path}"

  if dry_run
    puts 'COUNTS_REPORTED'
  else
    puts 'COUNTS_DONE'
  end
end
