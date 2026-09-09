build {
  sources = ["source.nutanix.node"]

  post-processor "shell-local" {
    environment_vars = [
      "CUSTOM_POST_PROCESSOR=${var.custom_post_processor}"
    ]
    inline = [
      "if [ \"$CUSTOM_POST_PROCESSOR\" != \"true\" ]; then exit 0; fi",
      var.custom_post_processor_command,
    ]
  }

  provisioner "shell" {
    environment_vars = [
      "BUILD_NAME=${var.build_name}",
      "PYPY_HTTP_SOURCE=${var.pypy_http_source}",
    ]
    execute_command = "BUILD_NAME=${var.build_name}; if [[ \"$${BUILD_NAME}\" == *\"flatcar\"* ]]; then sudo {{.Vars}} -S -E bash '{{.Path}}'; fi"
    script          = "./packer/files/flatcar/scripts/bootstrap-flatcar.sh"
  }

  provisioner "ansible" {
    ansible_env_vars = [
      "ANSIBLE_SSH_ARGS='${var.existing_ansible_ssh_args} -o IdentitiesOnly=yes'"
    ]
    extra_arguments = [
      "--extra-vars", local.ansible_common_vars,
      "--extra-vars", var.ansible_extra_vars,
      "--extra-vars", var.ansible_user_vars,
      "--scp-extra-args=${local.ansible_scp_extra_args}",
    ]
    playbook_file = "./ansible/node.yml"
    user          = "builder"
  }

  provisioner "goss" {
    arch           = var.goss_arch
    format         = var.goss_format
    format_options = var.goss_format_options
    goss_file      = var.goss_entry_file
    inspect        = var.goss_inspect_mode
    tests          = [var.goss_tests_dir]
    url            = var.goss_url
    use_sudo       = true
    vars_file      = var.goss_vars_file
    vars_inline = {
      ARCH                                   = "amd64"
      OS                                     = lower(var.distro_name)
      OS_VERSION                             = lower(var.distribution_version)
      PROVIDER                               = "nutanix"
      containerd_enable_limit_no_file        = var.containerd_enable_limit_no_file
      containerd_gvisor_runtime              = var.containerd_gvisor_runtime
      containerd_gvisor_version              = var.containerd_gvisor_version
      containerd_image_pull_progress_timeout = (var.containerd_image_pull_progress_timeout != null ? var.containerd_image_pull_progress_timeout : "")
      containerd_version                     = var.containerd_version
      kubernetes_cni_deb_version             = (var.kubernetes_cni_deb_version != null ? var.kubernetes_cni_deb_version : "")
      kubernetes_cni_rpm_version             = split("-", var.kubernetes_cni_rpm_version != null ? var.kubernetes_cni_rpm_version : "")[0]
      kubernetes_cni_source_type             = var.kubernetes_cni_source_type
      kubernetes_cni_version                 = replace(var.kubernetes_cni_semver, "v", "")
      kubernetes_deb_version                 = var.kubernetes_deb_version
      kubernetes_rpm_version                 = split("-", var.kubernetes_rpm_version)[0]
      kubernetes_source_type                 = var.kubernetes_source_type
      kubernetes_version                     = replace(var.kubernetes_semver, "v", "")
    }
    version = var.goss_version
  }
}
