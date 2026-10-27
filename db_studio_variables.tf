# Variables for the db-studio deployment (see db_studio.tf).
#
# Defaults mirror the app as it runs in the "default" environment. Override
# in terraform.tfvars (or the environment) to change the image, sizing or
# replica count.

# ---- db-studio --------------------------------------------------------------

variable "db_studio_image_repository" {
  type    = string
  default = "ghcr.io/drizzle-team/gateway"
}

variable "db_studio_image_tag" {
  type    = string
  default = "latest"
}

variable "db_studio_tier" {
  type    = string
  default = "nano"
}

variable "db_studio_replicas" {
  type    = number
  default = 1
}
