variable "vms" {
  type = list(object({
    name          = string
    instance_type = string
    storage_gb    = number
  }))
}

variable "location" {
  type = string
}

variable "resource_group" {
  type = string
}

variable "image" {
  description = "publisher:offer:sku:version reference."
  type        = string
}

variable "ssh_user" {
  type = string
}

variable "ssh_public_key" {
  type = string
}
