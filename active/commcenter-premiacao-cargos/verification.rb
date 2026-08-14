# Phase 3 — VERIFICATION (READ-ONLY). Prove the target carries the subtree's figure.
# Target: app-shared-001, company_id 2077. Paste into: bin/ecs run app-shared-001
# READ-ONLY. Nothing is mutated.
#
# Run AFTER the compensation for the competência has been cut and reprocessed — the mirrored deals
# only reach the aggregated value once the metric recalculates, and the aggregated value lives on a
# UserCommission, which does not exist before the commission is created.
#
# Two independent readings are printed. The first counts the mirrors directly, by the external
# column that marks a record as produced by the platform rather than received from an integration.
# The second reads AggregatedIndicator, which is the number the platform itself computed — that one
# is the answer, the mirror count only explains it.
#
# modifiers.value and aggregated_modifiers.value are varchar (schema.rb:1120, :84): coerce through
# variable.format before comparing, the way AggregatedIndicator#calculate! does. Never SUM() them.

company_id = 2077
target_user_id = 1119697    # Alex Lima Lofeu
target_plan_id = 78941      # Remuneração Variável Coordenador de Call Center Julho 26
target_period_id = 528210   # 2026-07-01..2026-07-31

plan = Plan.find(target_plan_id)
period = plan.periods.find(target_period_id)

mirrored_deals =
  Deal
  .for_company(company_id)
  .where(user_id: target_user_id)
  .where(date: period.starts_at..period.ends_at)
  .where(external: false)

puts "mirrored_deals@#{mirrored_deals.count}@enabled@#{mirrored_deals.enabled.count}"
puts "mirrored_total@#{mirrored_deals.enabled.sum('sold_price * quantity')}"

commission = Commission.for_company(company_id).for_plan(target_plan_id).for_period(target_period_id).first

if commission.nil?
  puts 'commission@NOT_CUT_YET'
else
  target_user_commission = UserCommission.find_by(commission_id: commission.id, user_id: target_user_id)

  if target_user_commission.nil?
    puts "commission@#{commission.id}@status@#{commission.status}@user_commission@NOT_FOUND"
  else
    puts "commission@#{commission.id}@status@#{commission.status}@money@#{target_user_commission.money}"

    plan.variables.with_metrics.each do |variable|
      aggregated_indicator = target_user_commission.aggregated_indicators.find_by(variable_id: variable.id)

      if aggregated_indicator.nil?
        puts "  variable@#{variable.id}@#{variable.key}@AGGREGATED_NOT_FOUND"
        next
      end

      puts "  variable@#{variable.id}@#{variable.key}@aggregated@#{aggregated_indicator.format}"
    end
  end
end

puts 'VERIFICATION_DONE'
