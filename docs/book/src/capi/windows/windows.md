# Windows

## Configuration

The `images/capi/packer/config/windows` directory includes several JSON files that define the default configuration for the Windows images:

| File | Description |
|------|-------------|
| `packer/config/windows/ansible-args.json` | A common set of variables that are sent to the Ansible playbook |
| `packer/config/windows/cloudbase-init.json` | The version of [Cloudbase Init](https://github.com/cloudbase/cloudbase-init) to install |
| `packer/config/windows/common.json` | Settings for things like which runtime (Docker or Containerd), pause image and other configuration |
| `packer/config/windows/kubernetes.json` | The version of Kubernetes to install and its install path |
| `packer/config/windows/containerd.json` | The version of containerd to install |

## Service Manager

Image-builder provides you two ways to configure Windows services. The default is setup using [nssm](https://nssm.cc/) which configures a Windows service for kubelet by running `{{ kubernetes_install_path }}\StartKubelet.ps1` allowing easy editing of command arguments in the startup file.  The alternate is to use the Windows native [sc.exe](https://learn.microsoft.com/windows-server/administration/windows-commands/sc-config) which uses the kubelet argument `--windows-service` to install kubelet as a native Windows service with the command line arguments configured on the service. Nssm handles service restarts, if you are using sc.exe you may wish to configure the service restart options on kubelet. To avoid starting kubelet to early, image-builder sets the kubelet service to *manual* which you should consider changing once the node has joined a cluster.

**Important: sc.exe does not support kubeadm KUBELET_KUBEADM_ARGS which is used by Cluster API to pass extra user args**


## Windows Updates

When building Windows images it is necessary to install OS and Security updates.  Image Builder provides two variables to allow choosing which updates get installed which can be used together or separately (with individual KBs installed first).

To specify the update categories to check, provide a value for `windows_updates_categories` in `packer/config/windows/common.json`.

Example:
Install all available updates from *all categories*.
`"windows_updates_categories": "CriticalUpdates SecurityUpdates UpdateRollups"`

Published Cloud Provider images such as Azure or AWS are regularly updated so it may be preferable to specify individual patches to install.  This can be achieved by specifying the KB numbers of required updates.

To choose individual updates, provide a value for `windows_updates_kbs` in `packer/config/windows/common.json`.

Example:
`"windows_updates_kbs": "KB4580390 KB4471332"`.

## OpenSSH Server

If a connection to the Microsoft Updates server is not possible, you may use the Win32 port of OpenSSH located on [GitHub](https://github.com/PowerShell/Win32-OpenSSH). To do this, you can set the ssh_source_url to the location of the desired OpenSSH Version from https://github.com/PowerShell/Win32-OpenSSH/releases/

Example:
`"ssh_source_url": "https://github.com/PowerShell/Win32-OpenSSH/releases/download/V8.6.0.0p1-Beta/OpenSSH-Win64.zip"`

## Using the Ansible Scripts directly

Ansible doesn't run on directly on Windows (wsl works) but can used to configure a remote Windows host.  For faster development you can create a VM and run Ansible against the Windows VM directly without using Packer. This document gives the high level steps to use Ansible from Linux machines.

## Set up Windows machine
Follow the [WinRM Setup](https://docs.ansible.com/ansible/latest/os_guide/windows_setup.html) in the Ansible documentation for configuring WinRM on the Windows machine. Note the [ConfigureRemotingForAnsible.ps1](https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1) is for development only. Refer to [Ansible WinRM documentation](https://docs.ansible.com/ansible/latest/user_guide/windows_winrm.html) for details for advance configuration.

After WinRM is installed you can edit the `/etc/ansible/hosts` file with the following:

```
[winhost]
<windows ip>

[winhost:vars]
ansible_user=username
ansible_password=<your password>
ansible_connection=winrm
ansible_winrm_server_cert_validation=ignore
```

Then run: `ansible-playbook -vvv playbooks/node_windows.yml --extra-vars "@example.vars.yml`

## macOS with ansible
The WinRM connection plugin for Ansible on macOS causes connection issues which can result in `ERROR! A worker was found in a dead state`. See https://docs.ansible.com/ansible/latest/user_guide/windows_winrm.html#what-is-winrm for more details.

To fix the issue on macOS is to set the no_proxy environment variable. Example:

```
'no_proxy=* make build-azure-vhd-windows-2019'
```

## Annual Channel
The [Windows Server Annual](https://techcommunity.microsoft.com/t5/windows-server-news-and-best/windows-server-annual-channel-for-containers/ba-p/3866248) channel licensing  requires users to host their own image.

In Azure this can be uploaded to an [Azure SIG](https://learn.microsoft.com/en-us/azure/virtual-machines/azure-compute-gallery), and the following environment variables should be set to use the source [shared image gallery](https://developer.hashicorp.com/packer/integrations/hashicorp/azure/v1.4.5/components/builder/arm#shared-image-gallery).

```
export SOURCE_SIG_SUB_ID=<azure sub>
export SOURCE_SIG_RESOURCE_GROUP=<resource group>
export SOURCE_SIG_NAME=<sig name>
export SOURCE_SIG_IMAGE_NAME=<image name>
export SOURCE_SIG_IMAGE_VERSION=<image version>
```
