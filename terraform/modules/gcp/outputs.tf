output "vm_ips" {
  description = "Map of vm name → public IP."
  value = {
    for k, v in google_compute_instance.vm :
    k => v.network_interface[0].access_config[0].nat_ip
  }
}

output "vm_facts" {
  description = "Per-VM facts surfaced into the Ansible inventory."
  value = {
    for k, v in google_compute_instance.vm : k => {
      public_ip         = v.network_interface[0].access_config[0].nat_ip
      private_ip        = v.network_interface[0].network_ip
      zone              = v.zone
      instance_type     = local.vms_by_name[k].instance_type
      data_disk_size_gb = local.vms_by_name[k].storage_gb
      # GCP exposes attached disks at /dev/disk/by-id/google-<device_name>,
      # where device_name is set in the attached_disk block (see main.tf).
      data_disk_device = "/dev/disk/by-id/google-${k}-data"
    }
  }
}

output "vms" {
  description = "Full instance objects keyed by vm name."
  value = {
    for k, v in google_compute_instance.vm : k => {
      name       = v.name
      public_ip  = v.network_interface[0].access_config[0].nat_ip
      private_ip = v.network_interface[0].network_ip
      zone       = v.zone
    }
  }
}
