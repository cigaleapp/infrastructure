# Shared infrastructure used by every deployment in this module.
#
# File layout: this module is shared by all deployments on the platform, so
# each deployment's resources live in <deployment>.tf, with its variables in
# <deployment>_variables.tf and outputs in <deployment>_outputs.tf.
# Shared (cross-deployment) variables live in variables.tf.

data "hyperfluid_env" "this" {
  name = var.env_name
}

locals {
  env = data.hyperfluid_env.this.id
}
