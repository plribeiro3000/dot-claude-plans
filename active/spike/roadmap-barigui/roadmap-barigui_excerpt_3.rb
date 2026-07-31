# Auxiliary file for SPIKE.md — full verbatim copy for reference.
# Sources (app repo, backend):
#   ~/Projects/4Shark/app/app/graphql_resolvers/user_aggregated_user_commission_dataset_graphql_resolver.rb
#   ~/Projects/4Shark/app/app/models/user_commission_dataset/user_aggregator.rb
#   ~/Projects/4Shark/app/app/graphql_types/query_type.rb:247 (field declaration only)
# Repo commit at capture time: 611d5a5c80d9ecd42df90e325615d178a153a8d4
# Relevant to demand 1 (ranking expansion) — this is the entire backend surface
# behind `userAggregatedUserCommissionDatasets`.

# --- query_type.rb:247 -------------------------------------------------------
#   field :user_aggregated_user_commission_datasets, resolver: UserAggregatedUserCommissionDatasetGraphqlResolver
# No `connection: true` is declared explicitly here — it is implied by the
# resolver's own `type ....connection_type` declaration below.

# --- user_aggregated_user_commission_dataset_graphql_resolver.rb -------------
# frozen_string_literal: true

class UserAggregatedUserCommissionDatasetGraphqlResolver < ApplicationGraphqlResolver
  argument :calendar_id, ID, required: false
  argument :sort, String, required: false
  argument :period_id, ID, required: false
  argument :plan_id, ID, required: false
  argument :user_id, ID, required: false

  type UserCommissionDatasetGraphqlType.connection_type, null: false

  def resolve(calendar_id: nil, plan_id: nil, period_id: nil, user_id: nil, sort: nil)
    user_id_collection = user_id.present? ? [user_id.to_i] : user_ids

    if plan_id
      UserCommissionDataset::UserAggregator
        .by_plan(
          plan_id: plan_id,
          user_ids: user_id_collection,
          period_id: period_id,
          sort: sort
        )
    else
      UserCommissionDataset::UserAggregator
        .by_calendar(
          calendar_id: calendar_id,
          user_ids: user_id_collection,
          period_id: period_id,
          sort: sort
        )
    end
  end

  private

  def user_ids
    return if current_company.main? || current_role.unscoped_queries?

    UserScope.new(current_user, User).resolve.pluck(:id)
  end
end

# --- user_commission_dataset/user_aggregator.rb ------------------------------
# frozen_string_literal: true

class UserCommissionDataset
  class UserAggregator
    def self.by_calendar(calendar_id:, user_ids:, period_id: nil, sort: nil)
      calendar = Calendar.find(calendar_id)
      plan_ids = calendar.plans.enabled.denormalized.with_status(:final).pluck(:id)
      user_ids = Array(user_ids).compact
      match = { plan_id: { '$in': plan_ids } }
      match[:user_id] = { '$in': user_ids } if user_ids.any?
      match[:period_id] = period_id.to_i if period_id.present?
      pipeline = shared_pipeline.unshift({ '$match': match })

      order_by =
        case sort
        when 'highest_point'
          { points: -1 }
        when 'lowest_value'
          { money: 1 }
        when 'lowest_point'
          { points: 1 }
        else
          { money: -1 }
        end

      pipeline.push({ '$sort': order_by })
      pipeline.push({ '$limit': 10 })                                # <-- the hardcoded cap
      UserCommissionDataset.collection.aggregate(pipeline).to_a
    end

    def self.by_plan(plan_id:, user_ids:, period_id: nil, sort: nil)
      user_ids = Array(user_ids).compact
      match = { plan_id: plan_id.to_i }
      match[:user_id] = { '$in': user_ids } if user_ids.any?
      match[:period_id] = period_id.to_i if period_id.present?
      pipeline = shared_pipeline.unshift({ '$match': match })

      order_by =
        case sort
        when 'highest_point'
          { points: -1 }
        when 'lowest_value'
          { money: 1 }
        when 'lowest_point'
          { points: 1 }
        else
          { money: -1 }
        end

      pipeline.push({ '$sort': order_by })
      pipeline.push({ '$limit': 10 })                                # <-- the hardcoded cap
      UserCommissionDataset.collection.aggregate(pipeline).to_a
    end

    def self.shared_pipeline
      [
        {
          '$project': {
            calendar_id: 1,
            money: 1,
            plan_id: 1,
            points: 1,
            user_id: 1,
            plan_statement_id: 1,
            statement_id: 1
          }
        },
        {
          '$group': {
            _id: { user_id: '$user_id' },
            calendar_id: { '$max': '$calendar_id' },
            money: { '$sum': '$money' },
            plan_id: { '$max': '$plan_id' },
            user_id: { '$max': '$user_id' },
            points: { '$sum': '$points' },
            plan_statement_id: { '$max': '$plan_statement_id' },
            statement_id: { '$max': '$statement_id' }
          }
        }
      ]
    end
  end
end

# --- Supporting scopes referenced in findings --------------------------------
# ~/Projects/4Shark/app/app/scopes/user_scope.rb
#
# class UserScope < ApplicationScope
#   def resolve
#     if company.main?
#       scope
#     elsif role.unscoped_queries?
#       scope
#         .where(company_id: user.company_id)
#     else
#       HierarchyScope.new(user, User).resolve
#     end
#   end
# end
#
# ~/Projects/4Shark/app/app/scopes/hierarchy_scope.rb
#
# class HierarchyScope < ApplicationScope
#   def resolve
#     hierarchy_sql =
#       "(WITH RECURSIVE hierarchy(id) AS (SELECT id FROM seats WHERE id = #{user.seat.id} " \
#       'UNION ALL SELECT seats.id FROM hierarchy JOIN seats ON seats.parent_id = hierarchy.id) SELECT id FROM hierarchy)'
#
#     scope
#       .joins(:seat)
#       .where("seats.id in (#{hierarchy_sql})")
#   end
# end
#
# Note: HierarchyScope resolves the FULL descendant subtree (recursive), not
# direct reports only. A "filter by immediate manager" argument on the ranking
# resolver would need a narrower, non-recursive scope:
#   User.joins(:seat).where(seats: { parent_id: manager.seat.id })
# — no existing scope class implements this narrower query today.
