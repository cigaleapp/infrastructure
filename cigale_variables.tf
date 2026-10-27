# Variables for the Cigale platform deployment (see cigale.tf).
#
# Defaults mirror the apps as they run in the "default" environment. Override
# in terraform.tfvars (or the environment) to change images, sizing or
# replica counts.

# ---- Global -----------------------------------------------------------------

variable "apps_enabled" {
  description = <<-EOT
    Whether the container apps actually run. Leave false until their env vars
    and secret_refs are configured in the Hyperfluid console (the provider
    cannot set them yet) - otherwise the apps start but fail to connect to
    their databases or storage.
  EOT
  type        = bool
  default     = false
}

# ---- Databases --------------------------------------------------------------

variable "beamup_db_node_tier" {
  description = "Tier for the cigale-beamup-db cluster: nano, micro, small, medium, large, xlarge."
  type        = string
  default     = "small"
}

variable "beamup_db_storage_gb" {
  description = "Storage for cigale-beamup-db in GB (platform limit 1-30)."
  type        = number
  default     = 10
}

# ---- cigale-app -------------------------------------------------------------

variable "cigale_app_image_repository" {
  type    = string
  default = "ghcr.io/cigaleapp/cigale"
}

variable "cigale_app_image_tag" {
  type    = string
  default = "latest"
}

variable "cigale_app_tier" {
  type    = string
  default = "nano"
}

variable "cigale_app_replicas" {
  type    = number
  default = 1
}

# ---- cigale-dev -------------------------------------------------------------

variable "cigale_dev_image_repository" {
  type    = string
  default = "data-terra.rg.ai.meso.umontpellier.fr/default/terraforma-biodimedia/dev-deployments-server"
}

variable "cigale_dev_image_tag" {
  type    = string
  default = "latest"
}

variable "cigale_dev_tier" {
  type    = string
  default = "nano"
}

variable "cigale_dev_replicas" {
  type    = number
  default = 3
}

# ---- cigale-beamup ----------------------------------------------------------

variable "cigale_beamup_image_repository" {
  type    = string
  default = "ghcr.io/cigaleapp/beamup"
}

variable "cigale_beamup_image_tag" {
  type    = string
  default = "latest"
}

variable "cigale_beamup_tier" {
  type    = string
  default = "micro"
}

variable "cigale_beamup_replicas" {
  type    = number
  default = 1
}

# ---- cigale-beamup-smtp -----------------------------------------------------

variable "cigale_beamup_smtp_image_repository" {
  type    = string
  default = "namshi/smtp"
}

variable "cigale_beamup_smtp_image_tag" {
  type    = string
  default = "latest"
}

variable "cigale_beamup_smtp_tier" {
  type    = string
  default = "nano"
}

variable "cigale_beamup_smtp_replicas" {
  type    = number
  default = 1
}

# ---- cigale-cors-proxy ------------------------------------------------------

variable "cigale_cors_proxy_image_repository" {
  type    = string
  default = "data-terra.rg.ai.meso.umontpellier.fr/default/terraforma-biodimedia/cigale-cors-proxy"
}

variable "cigale_cors_proxy_image_tag" {
  type    = string
  default = "main"
}

variable "cigale_cors_proxy_tier" {
  type    = string
  default = "nano"
}

variable "cigale_cors_proxy_replicas" {
  type    = number
  default = 5
}

# ---- cigale-github-actions-runner -------------------------------------------

variable "cigale_runner_image_repository" {
  type    = string
  default = "myoung34/github-runner"
}

variable "cigale_runner_image_tag" {
  type    = string
  default = "latest"
}

variable "cigale_runner_tier" {
  description = "Tier for the GitHub Actions runner. The provider only accepts up to xlarge; the platform supports 4xlarge (8 CPU / 8Gi) which the runner needs - bump it in the console after apply."
  type    = string
  default = "xlarge"
}

variable "cigale_runner_replicas" {
  type    = number
  default = 1
}
