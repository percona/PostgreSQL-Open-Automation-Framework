output "vm_ips" {
  description = "Map of vm name → public IP."
  value       = { for k, v in aws_instance.vm : k => v.public_ip }
}

output "vm_facts" {
  description = "Per-VM facts surfaced into the Ansible inventory."
  value = {
    for k, v in aws_instance.vm : k => {
      public_ip         = v.public_ip
      private_ip        = v.private_ip
      zone              = v.availability_zone
      instance_type     = v.instance_type
      data_disk_size_gb = local.vms_by_name[k].storage_gb
      # On Nitro instances (m5/m6/c6/t3/t4g/etc.) the kernel ignores the
      # device_name we set on the attachment and exposes EBS volumes via
      # /dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_<volid-no-dashes>.
      # On older Xen instances the device_name (/dev/sdf) is honored and the
      # kernel renames it to /dev/xvdf — operators on those instances should
      # override data_disk_device via host_vars or fall back to matching the
      # disk by size_gb in the playbook.
      data_disk_device = "/dev/disk/by-id/nvme-Amazon_Elastic_Block_Store_${replace(aws_ebs_volume.data[k].id, "-", "")}"
    }
  }
}

output "vms" {
  value = {
    for k, v in aws_instance.vm : k => {
      name       = v.tags["Name"]
      public_ip  = v.public_ip
      private_ip = v.private_ip
      az         = v.availability_zone
    }
  }
}
