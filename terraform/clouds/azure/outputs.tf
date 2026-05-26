output "ansible_inventory_path" {
  description = "Path to the rendered Ansible inventory file."
  value       = module.inventory.inventory_path
}

output "vm_ips" {
  description = "Map of vm name → public IP."
  value       = module.vms.vm_ips
}

output "resolved_etcd_hosts" {
  description = "etcd cluster members after fallback resolution."
  value       = local.resolved_etcd_hosts
}

output "credentials" {
  description = "SSH/connection credentials used by Ansible. Also written to credentials.json."
  value       = module.inventory.credentials
  sensitive   = true
}
