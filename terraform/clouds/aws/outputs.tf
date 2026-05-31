output "ansible_inventory_path" {
  description = "Path to the rendered Ansible inventory file (INI, compatibility)."
  value       = module.inventory.inventory_path
}

output "ansible_inventory_yaml_path" {
  description = "Path to the rendered Ansible inventory file (YAML, primary)."
  value       = module.inventory.inventory_yaml_path
}

output "vm_ips" {
  description = "Map of vm name → public IP."
  value       = module.vms.vm_ips
}

output "resolved_etcd_hosts" {
  description = "etcd cluster members after fallback resolution."
  value       = local.resolved_etcd_hosts
}

output "haproxy_hosts" {
  description = "VMs in the HAProxy tier (empty when unused)."
  value       = var.haproxy_hosts
}

output "backup_hosts" {
  description = "VMs acting as dedicated pgBackRest backup server(s) (empty when unused)."
  value       = var.backup_hosts
}

output "credentials" {
  description = "SSH/connection credentials used by Ansible. Also written to credentials.json."
  value       = module.inventory.credentials
  sensitive   = true
}
