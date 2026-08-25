# Phase 0 — DESCOBERTA (READ-ONLY). Which plans cover the competence, and who they pay.
# Target: app-shared-001. Paste into: bin/ecs run <stack>
# READ-ONLY. Nothing is mutated.
#
# Start here for a cargo whose plan is not known. Every plan of the company covering the period is
# listed with its group, override flag, metric-backed variables and commission state; the plan that
# pays a cargo is read off that list instead of guessed from its name.
#
# People are located by name fragment because a client's list gives nothing else, but a name is
# never the resolution — identifiers are printed so the match is confirmed before anything depends
# on it. A coordinator written down as "ID 1918117" had User id 1119697, and that is the confusion
# this avoids.
#
# mirrors_already_below is the number that decides whether the external: true filter is doing work
# for this cargo: it is the revenue a previous cargo already mirrored inside this person's subtree,
# and mirroring it again pays it twice.

company_id = 2077
competence_period_id = 528210
name_fragments = ['Joel Geraldo', 'Joao Luis', 'Carnelos']

puts '=== SECTION 1 — plans covering the competence'

Plan.for_company(company_id).find_each do |plan|
  period = plan.periods.find_by(id: competence_period_id)

  next if period.nil?

  commission = Commission.for_company(company_id).for_plan(plan.id).for_period(competence_period_id).first

  if commission.nil?
    commission_state = 'NOT_CUT'
  else
    commission_state = "#{commission.id}@#{commission.status}@participants@#{commission.user_commissions.count}"
  end

  puts "plan@#{plan.id}@#{plan.name}@type@#{plan.type}@status@#{plan.status}@group@#{plan.group_id}" \
       "@override@#{plan.override?}@commission@#{commission_state}"
  puts "  variables_with_metrics@#{plan.variables.with_metrics.pluck(:id, :key).inspect}"
rescue StandardError => error
  puts "plan@#{plan.id}@ERROR: #{error.message}"
end

puts '=== SECTION 2 — locating people by name, identifiers printed for confirmation'

name_fragments.each do |name_fragment|
  matches = User.for_company(company_id).where('users.name ILIKE ?', "%#{name_fragment}%")

  puts "fragment@#{name_fragment}@matches@#{matches.count}"

  matches.order(:id).find_each do |candidate|
    identifier_values = UserIdentifier.where(company_id: company_id, user_id: candidate.id).pluck(:value)
    group_ids = Groupification.where(user_id: candidate.id).pluck(:group_id).compact.uniq
    statement_plan_ids = PlanStatement.where(user_id: candidate.id).pluck(:plan_id).compact.uniq
    subtree_user_ids = UserScope.new(candidate, User).resolve.pluck(:id) - [candidate.id]

    mirrors_below =
      Deal
      .for_company(company_id)
      .where(user_id: subtree_user_ids)
      .where(external: false)
      .enabled

    puts "  user@#{candidate.id}@#{candidate.name}@identifiers@#{identifier_values.inspect}" \
         "@disabled_at@#{candidate.disabled_at}@seat@#{candidate.seat.id}@subtree@#{subtree_user_ids.size}"
    puts "    groups@#{group_ids.inspect}@statement_plans@#{statement_plan_ids.inspect}"
    puts "    mirrors_already_below@#{mirrors_below.count}@total@#{mirrors_below.sum('sold_price * quantity')}"
  rescue StandardError => error
    puts "  user@#{candidate.id}@ERROR: #{error.message}"
  end
end

puts 'DESCOBERTA_DONE'
