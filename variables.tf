# Shared variables used by every deployment in this module.

variable "env_name" {
  description = "Name (slug) of the existing Hyperfluid environment to deploy into."
  type        = string
  default     = "terraforma"
}
