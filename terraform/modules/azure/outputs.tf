output "vm_ips" {
  description = "Map of vm name → public IP."
  value       = { for k, v in azurerm_public_ip.pip : k => v.ip_address }
}

output "vm_facts" {
  description = "Per-VM facts surfaced into the Ansible inventory: public IP, data-disk size, stable device path."
  value = {
    for k, v in azurerm_linux_virtual_machine.vm : k => {
      public_ip         = azurerm_public_ip.pip[k].ip_address
      data_disk_size_gb = local.vms_by_name[k].storage_gb
      # Azure data disks are attached on the SCSI controller at the LUN we set
      # in main.tf (LUN 10). The kernel exposes them under /dev/disk/azure/.
      data_disk_device = "/dev/disk/azure/scsi1/lun10"
    }
  }
}

output "vms" {
  value = {
    for k, v in azurerm_linux_virtual_machine.vm : k => {
      name       = v.name
      public_ip  = azurerm_public_ip.pip[k].ip_address
      private_ip = v.private_ip_address
      location   = v.location
    }
  }
}
