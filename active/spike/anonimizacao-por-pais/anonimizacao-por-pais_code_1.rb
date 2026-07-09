# Auxiliary file — anonimizacao-por-pais spike
# Consolidated reference bundle: the CURRENT (as of 2026-07-08) anonymization pipeline code
# in the `app` repository (~/Projects/4Shark/app). Copied verbatim for line-by-line reference
# during the spike. Each block is labeled with its source file:line range.
#
# This is NOT production code to be run — it is a reading aid so the engineer can review the
# whole pipeline in one place without re-opening eight files.

# =============================================================================
# lib/application_configuration.rb:439-442
# The single, global retention window. Everything else in this file derives its cutoff from
# this one method.
# =============================================================================

# Default window of ~5.5 years for anonymization after company or user disablement
def user_anonymizing_window
  Integer(ENV.fetch('USER_ANONYMIZING_WINDOW', 2008)).days.ago
end

# =============================================================================
# app/workers/company/anonymizer.rb:1-13
# Cron entry point (via lib/tasks/cron.rake `anonymization:company`). Fans out to three
# independent, parallel pipelines. No arguments — no scoping by company or country.
# =============================================================================

# frozen_string_literal: true

class Company < ApplicationRecord
  class Anonymizer < ApplicationWorker
    sidekiq_options queue: :anonymizing

    def perform
      Company::UserAnonymizer.perform_async
      Company::DocumentRedactor::Producer.perform_async
      Company::ActionAnonymizer::Producer.perform_async
    end
  end
end

# =============================================================================
# app/workers/company/user_anonymizer.rb:1-23
# Pipeline 1 of 3: users. NOT company-scoped (see LGPD-DATA-ERASURE.md pitfall R2) — it always
# processes every disabled company past the window at once. This is the query shape that a
# per-country window would need to change: today ONE flat cutoff, ONE query.
# =============================================================================

# frozen_string_literal: true

require 'csv'

class Company < ApplicationRecord
  class UserAnonymizer < ApplicationWorker
    sidekiq_options queue: :anonymizing

    def perform
      company_ids =
        Company.with_uncached_connection { Company.where(disabled_at: ...ApplicationConfiguration.user_anonymizing_window).pluck(:id) }

      company_ids.each do |company_id|
        user_ids = User.with_uncached_connection { User.where(company_id: company_id, anonymized: false).pluck(:id) }

        user_ids.each do |user_id|
          User::Anonymizer::Consumer.perform_async(user_id)
        end
      end
    end
  end
end

# =============================================================================
# app/workers/user/anonymizer/producer.rb:1-33
# A SEPARATE, second pipeline: users individually disabled INSIDE an active (enabled) company.
# Same global window, applied directly on `disabled_at` at the User level (no Company cutoff
# step first, because the company itself is still enabled). Triggered by a DIFFERENT cron task
# (`anonymization:user`, see cron.rake below).
# =============================================================================

# frozen_string_literal: true

require 'csv'

class User < ApplicationRecord
  module Anonymizer
    class Producer < ApplicationWorker
      sidekiq_options queue: :anonymizing

      def perform
        company_ids =
          Company.with_uncached_connection { Company.enabled.pluck(:id) }

        company_ids.each do |company_id|
          user_ids =
            User.with_uncached_connection do
              User
                .where(
                  company_id: company_id,
                  anonymized: false,
                  disabled_at: ...ApplicationConfiguration.user_anonymizing_window
                )
                .pluck(:id)
            end

          arguments = user_ids.zip
          Sidekiq::Client.push_bulk('class' => User::Anonymizer::Consumer, 'args' => arguments)
        end
      end
    end
  end
end

# =============================================================================
# app/workers/user/anonymizer/consumer.rb:1-31
# Per-user anonymization (shared by BOTH pipelines above — Company::UserAnonymizer calls this
# directly; User::Anonymizer::Producer calls it via push_bulk). Redacts PII, destroys
# identifiers, cascades to UserIdentifierAction anonymization.
# =============================================================================

# frozen_string_literal: true

require 'csv'

class User < ApplicationRecord
  module Anonymizer
    class Consumer < ApplicationWorker
      sidekiq_options queue: :anonymizing

      def perform(user_id)
        user = User.find(user_id)
        user.anonymized = true
        user.email = "#{User::ANONYMIZED_VALUE}@#{User::ANONYMIZED_VALUE}.com"
        user.unique_register_id = User::ANONYMIZED_VALUE
        user.first_name = User::ANONYMIZED_VALUE
        user.last_name = User::ANONYMIZED_VALUE
        user.save!

        identifier_values = user.identifiers.pluck(:value)
        actions_by_identifier_value = UserIdentifierAction.where(company_id: user.company_id, user_identifier_value: identifier_values)
        actions_by_new_identifier_value = UserIdentifierAction.where(company_id: user.company_id, new_user_identifier_value: identifier_values)
        action_ids = actions_by_identifier_value.or(actions_by_new_identifier_value).pluck(:id)
        Sidekiq::Client.push_bulk('class' => Company::ActionAnonymizer::Consumer, 'args' => action_ids.zip)

        user.identifiers.update_all(primary: false)
        user.identifiers.destroy_all
      end
    end
  end
end

# =============================================================================
# app/workers/company/action_anonymizer/producer.rb:1-24
# Pipeline 2 of 3: UserIdentifierAction rows. Same global-window cutoff shape as
# Company::UserAnonymizer.
# =============================================================================

# frozen_string_literal: true

class Company < ApplicationRecord
  module ActionAnonymizer
    class Producer < ApplicationWorker
      sidekiq_options queue: :anonymizing

      def perform
        company_ids =
          Company.with_uncached_connection { Company.where(disabled_at: ...ApplicationConfiguration.user_anonymizing_window).pluck(:id) }

        company_ids.each do |company_id|
          action_ids =
            UserIdentifierAction.with_uncached_connection do
              UserIdentifierAction.where(company_id: company_id, anonymized: false).pluck(:id)
            end

          Sidekiq::Client.push_bulk('class' => Company::ActionAnonymizer::Consumer, 'args' => action_ids.zip)
        end
      end
    end
  end
end

# =============================================================================
# app/workers/company/document_redactor/producer.rb:1-17
# Pipeline 3 of 3: Document (UserDocument / UserIdentifierActionDocument) S3 attachment
# redaction. Same global-window cutoff shape again.
# =============================================================================

# frozen_string_literal: true

class Company < ApplicationRecord
  module DocumentRedactor
    class Producer < ApplicationWorker
      sidekiq_options queue: :anonymizing

      def perform
        company_ids =
          Company.with_uncached_connection { Company.where(disabled_at: ...ApplicationConfiguration.user_anonymizing_window).pluck(:id) }

        Sidekiq::Client.push_bulk('class' => Company::DocumentRedactor::Consumer, 'args' => company_ids.zip)
      end
    end
  end
end

# =============================================================================
# lib/tasks/cron.rake:114-150
# Both cron tasks (company-level and individual-user-level), with the pipeline comments
# already in the file.
# =============================================================================

# namespace :anonymization do
#   desc 'Anonymize users, documents and identifier actions from disabled companies'
#   # Schedule: daily at 05:00 UTC (cron(0 5 * * ? *))
#   # Environments: shared, beta, demo, atento
#   #
#   # Orchestrates the anonymization of companies disabled longer than the configured
#   # window (ApplicationConfiguration.user_anonymizing_window, ~5.5 years): user
#   # anonymization, document redaction and action anonymization run in parallel.
#   #
#   # Queue: anonymizing
#   # Pipeline: Company::Anonymizer -> Company::UserAnonymizer -> User::Anonymizer::Consumer (per user)
#   #                               -> Company::DocumentRedactor::Producer -> Consumer (per company)
#   #                               -> Company::ActionAnonymizer::Producer -> Consumer (per action)
#
#   task company: :environment do
#     puts '[cron:anonymization:company] Enqueuing Company::Anonymizer'
#     jid = Company::Anonymizer.perform_async
#     puts "[cron:anonymization:company] Enqueued successfully (JID: #{jid})"
#   end
#
#   desc 'Anonymize individually disabled users'
#   # Schedule: daily at 05:00 UTC (cron(0 5 * * ? *))
#   # Environments: shared, beta, demo, atento
#   #
#   # Finds users in enabled companies who have been individually disabled
#   # longer than the configured window (ApplicationConfiguration.user_anonymizing_window).
#   # Redacts PII (email, name, unique_register_id) and removes identifiers.
#   #
#   # Queue: anonymizing
#   # Pipeline: User::Anonymizer::Producer -> Consumer (per user)
#
#   task user: :environment do
#     puts '[cron:anonymization:user] Enqueuing User::Anonymizer::Producer'
#     jid = User::Anonymizer::Producer.perform_async
#     puts "[cron:anonymization:user] Enqueued successfully (JID: #{jid})"
#   end
# end
