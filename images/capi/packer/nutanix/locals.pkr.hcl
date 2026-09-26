// Values that were derived from other user variables via nested `{{user ...}}`
// interpolation inside packer/config/*.json var-files (or in this template's
// own JSON "variables" block). HCL2 variable defaults must be constant
// expressions, so these become locals computed from the variables declared
// in variables.pkr.hcl instead.

locals {
  # packer/config/kubernetes.json
  kubernetes_deb_gpg_key = "https://pkgs.k8s.io/core:/stable:/${var.kubernetes_series}/deb/Release.key"
  kubernetes_deb_repo    = "https://pkgs.k8s.io/core:/stable:/${var.kubernetes_series}/deb/"
  kubernetes_rpm_gpg_key = "https://pkgs.k8s.io/core:/stable:/${var.kubernetes_series}/rpm/repodata/repomd.xml.key"
  kubernetes_rpm_repo    = "https://pkgs.k8s.io/core:/stable:/${var.kubernetes_series}/rpm/"

  # packer/config/wasm-shims.json
  containerd_wasm_shims_url = "https://github.com/deislabs/containerd-wasm-shims/releases/download/${var.containerd_wasm_shims_version}/containerd-wasm-shims-<RTVERSION>-<SHIM>-linux-x86_64.tar.gz"

  # JSON-encoded blobs, kept as readable HCL maps here rather than escaped
  # string literals (see the override note on the two variables in
  # variables.pkr.hcl).
  containerd_wasm_shims_runtime_versions = var.containerd_wasm_shims_runtime_versions != "" ? var.containerd_wasm_shims_runtime_versions : jsonencode({
    lunatic = "v1"
    slight  = "v1"
    spin    = "v2"
    wws     = "v1"
  })
  containerd_wasm_shims_sha256 = var.containerd_wasm_shims_sha256 != "" ? var.containerd_wasm_shims_sha256 : jsonencode({
    lunatic = "7054bc882db755ce5f3ded46d114bfd4e0a318e437fa18a2601295d20b616b32"
    slight  = "a6ea87d965037933a7d9edb5e20cfc175265c8e1ca92a16535f1f3c3f376f5b0"
    spin    = "dcffedb8e4d2f585a851b3de489fa1e8a0054ec0ad72cf111c623623919245d0"
    wws     = "e917f90692d798d80873aa0f37990c7d652f2846129d64fecbfd41ffa77799b8"
  })

  # containerd.service is now rendered locally rather than fetched at build
  # time, matching every other cloud's packer.json (#2102).
  containerd_service_url = ""

  # packer/config/ansible-args.json: legacy value is the literal string
  # "{{env `ANSIBLE_SCP_EXTRA_ARGS`}}". Declaring this as a `variable` of the
  # same name would still get clobbered by that raw, never-interpolated string
  # via -var-file=ansible-args.json, so it's a local backed by the
  # differently-named ansible_scp_extra_args_env variable instead.
  ansible_scp_extra_args = var.ansible_scp_extra_args_env

  # image_name: kept overridable under its ORIGINAL name (see variables.pkr.hcl)
  # so any existing downstream var-file setting it keeps working, falling back
  # to the same "<build_name>-kube-<kubernetes_semver>" default as before.
  image_name = var.image_name != "" ? var.image_name : "${var.build_name}-kube-${var.kubernetes_semver}"

  # nutanix_port/nutanix_insecure are native number/bool variables (see
  # variables.pkr.hcl), so a JSON var-file/-var flag setting e.g.
  # "9440"/"true" auto-converts fine. `env()` can't produce a non-empty
  # number/bool default directly though, so fall back to the legacy
  # NUTANIX_PORT/NUTANIX_INSECURE env vars (via the *_env string variables)
  # whenever the typed variable itself is left unset.
  nutanix_port     = var.nutanix_port != null ? var.nutanix_port : (var.nutanix_port_env != "" ? var.nutanix_port_env : null)
  nutanix_insecure = var.nutanix_insecure != null ? var.nutanix_insecure : (var.nutanix_insecure_env != "" ? var.nutanix_insecure_env : null)

  # packer/config/ansible-args.json: single space-separated string of
  # extra-vars passed to the ansible provisioner, reproduced verbatim from the
  # legacy var-file. A few of these (containerd_additional_settings,
  # containerd_image_pull_progress_timeout, kubernetes_cni_deb_version,
  # kubernetes_cni_rpm_version) are still shipped as JSON `null` in
  # packer/config/cni.json / containerd.json, and that null reaches this local
  # via -var-file, overriding the ""-default declared in variables.pkr.hcl at
  # RUNTIME (not just at declaration time). HCL2 can't interpolate a null into
  # a string template, so those four get an explicit `!= null ? x : ""` guard.
  ansible_common_vars = join(" ", [
    "containerd_gvisor_runtime=${var.containerd_gvisor_runtime}",
    "containerd_gvisor_version=${var.containerd_gvisor_version}",
    "containerd_sha256=${var.containerd_sha256}",
    "pause_image=${var.pause_image}",
    "containerd_additional_settings=${(var.containerd_additional_settings != null ? var.containerd_additional_settings : "")}",
    "containerd_cri_socket=${var.containerd_cri_socket}",
    "containerd_version=${var.containerd_version}",
    "containerd_image_pull_progress_timeout=${(var.containerd_image_pull_progress_timeout != null ? var.containerd_image_pull_progress_timeout : "")}",
    "containerd_enable_limit_no_file=${var.containerd_enable_limit_no_file}",
    "containerd_wasm_shims_url=${local.containerd_wasm_shims_url}",
    "containerd_wasm_shims_version=${var.containerd_wasm_shims_version}",
    "containerd_wasm_shims_sha256=${local.containerd_wasm_shims_sha256}",
    "containerd_wasm_shims_runtimes=\"${var.containerd_wasm_shims_runtimes}\"",
    "containerd_wasm_shims_runtime_versions=\"${local.containerd_wasm_shims_runtime_versions}\"",
    "crictl_version=${var.crictl_version}",
    "custom_role_names=\"${var.custom_role_names}\"",
    "firstboot_custom_roles_pre=\"${var.firstboot_custom_roles_pre}\"",
    "firstboot_custom_roles_post=\"${var.firstboot_custom_roles_post}\"",
    "node_custom_roles_pre=\"${var.node_custom_roles_pre}\"",
    "node_custom_roles_post=\"${var.node_custom_roles_post}\"",
    "node_custom_roles_post_sysprep=\"${var.node_custom_roles_post_sysprep}\"",
    "node_ansible_tmpdir=\"${var.node_ansible_tmpdir}\"",
    "disable_public_repos=${var.disable_public_repos}",
    "extra_debs=\"${var.extra_debs}\"",
    "extra_kernel_boot_params=\"${var.extra_kernel_boot_params}\"",
    "extra_repos=\"${var.extra_repos}\"",
    "extra_rpms=\"${var.extra_rpms}\"",
    "http_proxy=${var.http_proxy}",
    "https_proxy=${var.https_proxy}",
    "kubeadm_template=${var.kubeadm_template}",
    "kubernetes_apiserver_port=${var.kubernetes_apiserver_port}",
    "kubernetes_cni_http_source=${var.kubernetes_cni_http_source}",
    "kubernetes_http_source=${var.kubernetes_http_source}",
    "kubernetes_container_registry=${var.kubernetes_container_registry}",
    "kubernetes_rpm_repo=${local.kubernetes_rpm_repo}",
    "kubernetes_rpm_gpg_key=${local.kubernetes_rpm_gpg_key}",
    "kubernetes_rpm_gpg_check=${var.kubernetes_rpm_gpg_check}",
    "kubernetes_deb_repo=${local.kubernetes_deb_repo}",
    "kubernetes_deb_gpg_key=${local.kubernetes_deb_gpg_key}",
    "kubernetes_cni_deb_version=${(var.kubernetes_cni_deb_version != null ? var.kubernetes_cni_deb_version : "")}",
    "kubernetes_cni_rpm_version=${(var.kubernetes_cni_rpm_version != null ? var.kubernetes_cni_rpm_version : "")}",
    "kubernetes_cni_semver=${var.kubernetes_cni_semver}",
    "kubernetes_cni_source_type=${var.kubernetes_cni_source_type}",
    "kubernetes_semver=${var.kubernetes_semver}",
    "kubernetes_source_type=${var.kubernetes_source_type}",
    "kubernetes_load_additional_imgs=${var.kubernetes_load_additional_imgs}",
    "kubernetes_deb_version=${var.kubernetes_deb_version}",
    "kubernetes_rpm_version=${var.kubernetes_rpm_version}",
    "no_proxy=${var.no_proxy}",
    "pip_conf_file=${var.pip_conf_file}",
    "python_path=${var.python_path}",
    "redhat_epel_rpm=${var.redhat_epel_rpm}",
    "epel_rpm_gpg_key=${var.epel_rpm_gpg_key}",
    "reenable_public_repos=${var.reenable_public_repos}",
    "remove_extra_repos=${var.remove_extra_repos}",
    "systemd_prefix=${var.systemd_prefix}",
    "sysusr_prefix=${var.sysusr_prefix}",
    "sysusrlocal_prefix=${var.sysusrlocal_prefix}",
    "load_additional_components=${var.load_additional_components}",
    "additional_registry_images=${var.additional_registry_images}",
    "additional_registry_images_list=${var.additional_registry_images_list}",
    "ecr_credential_provider=${var.ecr_credential_provider}",
    "additional_url_images=${var.additional_url_images}",
    "additional_url_images_list=${var.additional_url_images_list}",
    "additional_executables=${var.additional_executables}",
    "additional_executables_list=${var.additional_executables_list}",
    "additional_executables_destination_path=${var.additional_executables_destination_path}",
    "additional_s3=${var.additional_s3}",
    "build_target=${var.build_target}",
    "amazon_ssm_agent_rpm=${var.amazon_ssm_agent_rpm}",
    "enable_containerd_audit=${var.enable_containerd_audit}",
    "kubernetes_enable_automatic_resource_sizing=${var.kubernetes_enable_automatic_resource_sizing}",
    "debug_tools=${var.debug_tools}",
    "ubuntu_repo=${var.ubuntu_repo}",
    "ubuntu_security_repo=${var.ubuntu_security_repo}",
    "gpu_block_nouveau_loading=${var.block_nouveau_loading}",
    "runc_version=${var.runc_version}",
    "containerd_service_url=${local.containerd_service_url}",
    "netplan_removal_excludes=\"${var.netplan_removal_excludes}\"",
    "image_builder_version=${var.ib_version}",
  ])
}
