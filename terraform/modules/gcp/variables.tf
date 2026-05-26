variable "vms" {
  description = "VM definitions inherited from root."
  type = list(object({
    name          = string
    instance_type = string
    storage_gb    = number
  }))
}

variable "region" {
  type = string
}

variable "zone" {
  type = string
}

variable "image" {
  description = "Boot image (family or full self-link)."
  type        = string
}

variable "ssh_user" {
  type = string
}

variable "ssh_public_key" {
  description = "Contents of the SSH public key authorized on each VM."
  type        = string
}
