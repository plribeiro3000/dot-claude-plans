# AUXILIARY FILE: xlsx_zip_pattern_excerpts_aux_2.rb
# Verbatim excerpts for XLSX generation (caxlsx) and S3 upload (CarrierWave + fog-aws).
# Referenced from PLAN-SPIKE.md § Pattern C and § Pattern D.

# ─────────────────────────────────────────────────────────────────────────────
# 1. XLSX generation pattern — CommissionWorkBook
#    Source: app/app/work_books/commission_work_book.rb:1-69
#    THE canonical XLSX generation pattern in this codebase.
# ─────────────────────────────────────────────────────────────────────────────
# class CommissionWorkBook
#   def generate
#     @package = Axlsx::Package.new
#     @workbook = @package.workbook
#     style.add
#     summary_work_sheet.add
#     ...
#     @package.serialize(file_path)   # writes to tmp/
#     File.new(file_path)             # returns a File object for CarrierWave
#   end
#
#   private
#
#   def file_name
#     commission = I18n.with_locale(company.locale) { I18n.transliterate(Commission.model_name.human.parameterize) }
#     plan_name = I18n.transliterate(@plan.name.downcase.tr(' /', '-'))
#     commission_date = @commission.updated_at.strftime('%d%m%Y')
#     "#{commission}-#{plan_name}-#{commission_date}.xlsx"
#   end
#
#   def file_path
#     @file_path ||= Rails.root.join('tmp', file_name)
#   end
# end

# ─────────────────────────────────────────────────────────────────────────────
# 2. CarrierWave + fog-aws configuration
#    Source: app/config/initializers/carrierwave.rb:1-12
#    Source: app/app/uploaders/application_uploader.rb:1-9
# ─────────────────────────────────────────────────────────────────────────────
# CarrierWave.configure do |config|
#   config.fog_credentials = {
#     provider: 'AWS',
#     aws_access_key_id: ApplicationConfiguration.aws_access_key,
#     aws_secret_access_key: ApplicationConfiguration.aws_secret_access_key
#   }
#   config.fog_directory = ApplicationConfiguration.aws_bucket   # ENV['AWS_BUCKET']
#   config.fog_public = false
# end
#
# class ApplicationUploader < CarrierWave::Uploader::Base
#   include CarrierWave::MiniMagick
#   storage :fog unless Rails.env.test?
# end

# ─────────────────────────────────────────────────────────────────────────────
# 3. PlanStatementPortableAttachment + PlanStatementPortableUploader
#    Source: app/app/models/plan_statement_portable_attachment.rb:1-7
#    Source: app/app/uploaders/plan_statement_portable_uploader.rb:1-7
#    These are the EXISTING upload infrastructure for this domain.
# ─────────────────────────────────────────────────────────────────────────────
# class PlanStatementPortableAttachment < Attachment
#   mount_uploader :file, PlanStatementPortableUploader
#   alias file_name file_identifier
# end
#
# class PlanStatementPortableUploader < ApplicationUploader
#   def store_dir
#     "uploads/plan_statement_portables/#{model.attachable_id}"
#     # e.g. uploads/plan_statement_portables/42  (the PlanStatementPortable id)
#   end
# end
#
# class PlanStatementPortableBatchUploader < ApplicationUploader
#   def store_dir
#     "uploads/plan_statement_portable_batches/#{model.attachable_id}"
#     # e.g. uploads/plan_statement_portable_batches/7  (the PlanStatementPortableBatch id)
#   end
# end

# ─────────────────────────────────────────────────────────────────────────────
# 4. Attachment upload pattern (used by report generator workers)
#    Source: app/app/workers/commission/report_generator.rb:10-11
#    CarrierWave assignment: report.file = File.object  → fog uploads on save
# ─────────────────────────────────────────────────────────────────────────────
# report.file = CommissionWorkBook.new(commission).generate
# Attachment.with_uncached_connection { report.finish! }

# ─────────────────────────────────────────────────────────────────────────────
# 5. rubyzip — present in Gemfile (line 70) but NO production usage found.
#    grep -rn "Zip::" app/app/ returns zero results outside log files.
#    Gem line:  gem 'rubyzip'  (Gemfile:70)
#    This means ZIP creation will be new code with no existing project pattern.
# ─────────────────────────────────────────────────────────────────────────────

# ─────────────────────────────────────────────────────────────────────────────
# 6. PlanStatementPortableBatch model state machine
#    Source: app/app/models/plan_statement_portable_batch.rb:34-43
# ─────────────────────────────────────────────────────────────────────────────
# state_machine :status, initial: :initial do
#   event :process do
#     transition initial: :processing
#     transition processing: :processing
#   end
#   event :finish do
#     transition processing: :final
#   end
# end
#
# PlanStatementPortable model (per-declaration record):
# state_machine :status, initial: :processing do
#   event :finish do
#     transition processing: :final
#   end
# end
