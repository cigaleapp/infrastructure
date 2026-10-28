variable "name_prefix" {
  description = "Prefix for every resource name."
  type        = string
  default     = "ecosignal"
}

# ---- Network -------------------------------------------------------------------

variable "ecosignal_domain" {
  description = "Domain where the ecosignal frontend can be accessed via Internet"
  type        = string
  default     = "ecosignal-frontend-biodimedia-data-terra.ai.meso.umontpellier.fr"
}

# ---- Images -----------------------------------------------------------------
# The repo publishes no images (docker-compose.yml builds ./backend and
# ./frontend locally), so build and push them to a registry Hyperfluid can pull
# from, then point these variables at them.

variable "backend_image_repository" {
  description = "Repository of the image built from ./backend."
  type        = string
  #   default = "data-terra.rg.ai.meso.umontpellier.fr/default/terraforma-biodimedia/ecosignal-backend"
  default = "ghcr.io/cigaleapp/infrastructure/ecosignal-backend"
}

variable "frontend_image_repository" {
  description = "Repository of the image built from ./frontend."
  type        = string
  #   default = "data-terra.rg.ai.meso.umontpellier.fr/default/terraforma-biodimedia/ecosignal-frontend"
  default = "ghcr.io/cigaleapp/infrastructure/ecosignal-frontend"
}

variable "backend_image_tag" {
  type    = string
  default = "s3"
}

variable "frontend_image_tag" {
  type    = string
  default = "s3"
}

variable "app_containers_enabled" {
  description = <<-EOT
    Whether backend, workers and frontend actually run. Leave false until the
    provider's container app can set env vars, a start command and a shared
    media volume (see README notes in main.tf) - without them these containers
    cannot start correctly.
  EOT
  type        = bool
  default     = true
}

# ---- Databases --------------------------------------------------------------

variable "postgres_node_tier" {
  description = "Tier for the main PostGIS cluster: nano, micro, small, medium, large, xlarge."
  type        = string
  default     = "small"
}

variable "postgres_storage_gb" {
  description = "Storage for the main database in GB (platform limit 1-30)."
  type        = number
  default     = 20
}

variable "geo_db_node_tier" {
  type    = string
  default = "small"
}

variable "geo_db_storage_gb" {
  description = "Storage for the geographical reference database in GB (platform limit 1-30)."
  type        = number
  default     = 20
}

variable "postgres_configuration" {
  description = "standalone or high-availability."
  type        = string
  default     = "standalone"
}

variable "expose_databases_to_internet" {
  description = "Publish external endpoints for both databases. Only turn on temporarily, e.g. to load the geo reference data."
  type        = bool
  default     = false
}

# ---- App sizing (guesses; tune after observing real load) --------------------

variable "backend_tier" {
  type    = string
  default = "medium"
}

variable "worker_tier" {
  description = "Workers run BirdNET / torch inference, so they get the most CPU/memory."
  type        = string
  default     = "large"
}

variable "frontend_tier" {
  type    = string
  default = "nano"
}

variable "rabbitmq_tier" {
  type    = string
  default = "small"
}

# ---- Secrets (write-only: never stored in Terraform state) ------------------

variable "secret_path_secret_key" {
  description = "Path to SECRET_KEY secret, relative to the env's folder (don't include the env prefix)"
  type        = string
  default     = "ecosignal/secret-key"
}

variable "secret_path_first_superuser_password" {
  description = "Path to FIRST_SUPERUSER_PASSWORD secret, relative to the env's folder (don't include the env prefix)"
  type        = string
  default     = "ecosignal/first-superuser-password"
}

variable "sentry_dsn" {
  description = "Optional Sentry DSN. Leave empty to skip."
  type        = string
  sensitive   = true
  default     = ""
}

variable "secrets_version" {
  description = "Bump together with the secret values above to rotate them."
  type        = string
  default     = "1"
}
