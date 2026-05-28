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

variable "image_plan" {
  description = <<-EOT
    Marketplace plan info, required for images that need terms acceptance
    (e.g. Rocky Linux, AlmaLinux). Leave null for images that don't need it
    (Canonical Ubuntu, RHEL pay-as-you-go via `RedHat` publisher, etc.).
    For Rocky 9: { publisher = "resf", product = "rockylinux-x86_64", name = "9-base" }.
  EOT
  type = object({
    publisher = string
    product   = string
    name      = string
  })
  default = null
}

variable "ssh_user" {
  type = string
}

variable "ssh_public_key" {
  type = string
}
