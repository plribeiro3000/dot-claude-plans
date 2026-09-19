# Ready-to-apply activation file for Monday's follow-up PR.
# Copy into terraform/shared-resources/cost_allocation_tags.tf on a new branch,
# then plan + apply that stack. It was removed from PR #1175 before merge (an
# aws_ce_cost_allocation_tag cannot apply until the key has appeared on a billed
# resource, ~24h after the first tagged stack was live), so it is not on develop.
#
# Activates the Entity/Project/Client cost allocation tags for Cost Explorer.
resource "aws_ce_cost_allocation_tag" "entity" {
  tag_key = "Entity"
  status  = "Active"
}

resource "aws_ce_cost_allocation_tag" "project" {
  tag_key = "Project"
  status  = "Active"
}

resource "aws_ce_cost_allocation_tag" "client" {
  tag_key = "Client"
  status  = "Active"
}
