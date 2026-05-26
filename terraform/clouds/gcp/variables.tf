# ── Shared variables (same shape across all clouds) ──────────────────────────

variable "vms" {
  description = "List of VMs to provision."
  type = list(object({
    name          = string
    instance_type = string
    storage_gb    = number
  }))

  validation {
    condition     = length(var.vms) >= 1
    error_message = "vms must contain at least one entry"
  }

  validation {
    condition     = length(var.vms) == length(distinct([for v in var.vms : v.name]))
    error_message = "Duplicate vm name: vms[*].name must be unique"
  }
}

variable "database_hosts" {
  description = "Subset of vms[*].name in the database tier."
  type        = list(string)

  validation {
    condition     = length(var.database_hosts) >= 1
    error_message = "database_hosts must contain at least one entry"
  }
}

variable "etcd_hosts" {
  description = "Optional explicit etcd cluster members. Empty list falls back to database_hosts."
  type        = list(string)
  default     = []
}

variable "enable_ha" {
  description = "When true, enforces a quorum of >= 3 resolved etcd members."
  type        = bool
  default     = false
}

variable "ssh_user" {
  type    = string
  default = "ubuntu"
}

variable "ssh_public_key_path" {
  type    = string
  default = "~/.ssh/id_rsa.pub"
}

variable "ssh_private_key_path" {
  type    = string
  default = "~/.ssh/id_rsa"
}

variable "inventory_output_path" {
  type    = string
  default = "./ansible_inventory.ini"
}

variable "credentials_output_path" {
  type    = string
  default = "./credentials.json"
}

# ── GCP-specific ─────────────────────────────────────────────────────────────

variable "gcp_project" {
  description = "GCP project ID. Required."
  type        = string
  default     = ""
}

variable "gcp_region" {
  type    = string
  default = "us-central1"
}

variable "gcp_zone" {
  type    = string
  default = "us-central1-a"
}

variable "gcp_image" {
  description = "Boot image for GCP VMs."
  type        = string
  default     = "ubuntu-os-cloud/ubuntu-2204-lts"
}
