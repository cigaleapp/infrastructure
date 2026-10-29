# Shared variables used by every deployment in this module.

variable "env_name" {
  description = "Name (slug) of the existing Hyperfluid environment to deploy into."
  type        = string
  default     = "biodimedia"
}

variable "autoscaling_1_3" {
  description = "Autoscaling strategy that allows for 1-3 replicas, with a threshold on CPU usage (70%) and on RAM usage (80%)"
  type = object({
    min_replicas              = number
    max_replicas              = number
    target_cpu_utilization    = number
    target_memory_utilization = number
  })

  default = {
    min_replicas              = 1
    max_replicas              = 3
    target_cpu_utilization    = 70
    target_memory_utilization = 80
  }
}

variable "autoscaling_1_5" {
  description = "Autoscaling strategy that allows for 1-5 replicas, with a threshold on CPU usage (70%) and on RAM usage (60%)"
  type = object({
    min_replicas              = number
    max_replicas              = number
    target_cpu_utilization    = number
    target_memory_utilization = number
  })

  default = {
    min_replicas              = 1
    max_replicas              = 5
    target_cpu_utilization    = 70
    target_memory_utilization = 60
  }
}
