source "nutanix" "node" {
  boot_type              = var.boot_type
  cluster_name           = var.nutanix_cluster_name
  cpu                    = var.cpus
  force_deregister       = var.force_deregister
  image_delete           = var.image_delete
  image_description      = "kube image-builder packer"
  image_export           = var.image_export
  image_name             = local.image_name
  memory_mb              = var.memory
  nutanix_endpoint       = var.nutanix_endpoint
  nutanix_insecure       = local.nutanix_insecure
  nutanix_password       = var.nutanix_password
  nutanix_port           = local.nutanix_port
  nutanix_username       = var.nutanix_username
  os_type                = var.guest_os_type
  shutdown_command       = "echo '${var.ssh_password}' | sudo -S -E sh -c 'userdel -f -r ${var.ssh_username} && rm -f /etc/sudoers.d/${var.ssh_username} && rm -f /etc/sudoers.d/90-cloud-init-users && ${var.shutdown_command}'"
  ssh_handshake_attempts = 100
  ssh_password           = var.ssh_password
  ssh_timeout            = "20m"
  ssh_username           = var.ssh_username
  user_data              = var.user_data

  vm_disks {
    disk_size_gb        = var.disk_size_gb
    image_type          = "DISK_IMAGE"
    source_image_delete = var.source_image_delete
    source_image_force  = var.source_image_force
    source_image_uri    = var.image_url
  }

  vm_force_delete = var.vm_force_delete
  # NOTE: intentional behavior change from the legacy template, where
  # vm_name and image_name were two independently-computed fields that just
  # happened to share the same default formula -- overriding image_name (e.g.
  # for a custom naming convention) left vm_name unaffected. Here they're
  # coupled, so an image_name override also renames the build VM -- almost
  # certainly what you want in practice (a mismatched VM/image name is
  # confusing), but flagging it since it's not byte-for-byte identical.
  vm_name = local.image_name

  vm_nics {
    subnet_name = var.nutanix_subnet_name
  }
}
