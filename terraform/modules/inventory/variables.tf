variable "provider_name" {
  description = "Cloud provider name written into the inventory header (e.g. \"gcp\", \"aws\", \"azure\")."
  type        = string
}

variable "vm_facts" {
  description = "Per-VM facts emitted by the cloud module. Keyed by vm name."
  type = map(object({
    public_ip         = string
    private_ip        = string
    zone              = string
    instance_type     = string
    data_disk_size_gb = number
    data_disk_device  = string
  }))
}

variable "database_hosts" {
  description = "Subset of vms[*].name in the database tier."
  type        = list(string)
}

variable "resolved_etcd_hosts" {
  description = "etcd cluster members after fallback resolution."
  type        = list(string)
}

variable "etcd_hosts_external" {
  description = "etcd members not provisioned by this apply (external infra)."
  type        = list(string)
  default     = []
}

variable "ssh_user" {
  type = string
}

variable "ssh_private_key_path" {
  type = string
}

variable "ssh_public_key_path" {
  type = string
}

variable "inventory_output_path" {
  description = "Path to the rendered Ansible inventory in INI format (compatibility)."
  type        = string
}

variable "inventory_yaml_output_path" {
  description = "Path to the rendered Ansible inventory in YAML format (primary, consumed by playbooks)."
  type        = string
}

variable "credentials_output_path" {
  type = string
}
