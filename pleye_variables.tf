# Variables for the Pleye deployment (see pleye.tf).
#
# Defaults mirror the app as it runs in the "default" environment. Override
# in terraform.tfvars (or the environment) to change the image, sizing or
# replica count.

# ---- Database ---------------------------------------------------------------

variable "pleye_db_node_tier" {
  description = "Tier for the pleye-db cluster: nano, micro, small, medium, large, xlarge."
  type        = string
  default     = "small"
}

variable "pleye_db_storage_gb" {
  description = "Storage for pleye-db in GB (platform limit 1-30)."
  type        = number
  default     = 10
}

# ---- Secrets (write-only: never stored in Terraform state) ------------------

variable "pleye_master_key" {
  description = "Pleye MASTER_KEY. Leave empty to skip creating the secret (set it in the console instead)."
  type        = string
  sensitive   = true
  default     = ""
}

# ---- pleye ------------------------------------------------------------------

variable "pleye_image_repository" {
  type    = string
  default = "ghcr.io/gwennlbh/pleye"
}

variable "pleye_image_tag" {
  type    = string
  default = "latest"
}

variable "pleye_tier" {
  type    = string
  default = "small"
}

variable "pleye_replicas" {
  type    = number
  default = 3
}
