variable "vms" {
  type = list(object({
    name          = string
    instance_type = string
    storage_gb    = number
  }))
}

variable "region" {
  type = string
}

variable "ami" {
  description = "AMI ID. Leave empty to auto-select latest Ubuntu 22.04 LTS."
  type        = string
  default     = ""
}

variable "vpc_id" {
  type    = string
  default = ""
}

variable "subnet_id" {
  type    = string
  default = ""
}

variable "ssh_user" {
  type = string
}

variable "ssh_public_key" {
  type = string
}
