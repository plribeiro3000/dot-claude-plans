# Phase 1 — Discovery (integrator-commcenter, MongoDB). READ-ONLY.
# Paste into: bin/ecs run integrator-commcenter
# Single-customer stack — the whole DB is commcenter's, no company scoping.
# Output is @-separated for Excel paste. Each count is isolated.

collection_class_names = %w[
  Collection
  ClientCollection
  DealCollection
  DealExtraFieldCollection
  GoalCollection
  GroupCollection
  GroupificationCollection
  HierarchyCollection
  ModifierCollection
  ProductCollection
  SubsidiaryCollection
  UserActivityCollection
  UserCollection
  UserFieldCollection
  UserIdentifierCollection
]

# ---- resources (STI base; imports/requests are embedded, counted with the parent) ----
begin
  puts 'resources_total@' + Resource.count.to_s
  Resource.integration_status.values.each do |status_value|
    puts 'resources_' + status_value.to_s + '@' + Resource.where(integration_status: status_value).count.to_s
  end
rescue StandardError => error
  puts 'resources_total@ERROR: ' + error.message
end

# ---- jobs (cascades *_collections + JobMetric on destroy) ----
begin
  puts 'jobs@' + Job.count.to_s
rescue StandardError => error
  puts 'jobs@ERROR: ' + error.message
end

# ---- collection family (raw extracted staging data per job) ----
collection_class_names.each do |class_name|
  begin
    puts class_name + '@' + class_name.constantize.count.to_s
  rescue StandardError => error
    puts class_name + '@ERROR: ' + error.message
  end
end

puts 'DISCOVERY_DONE@integrator-commcenter'
