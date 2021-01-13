# Windows

## Configuration

The `images/capi/packer/config/windows` directory includes several JSON files that define the default configuration for the Windows images:

| File | Description |
|------|-------------|
| `packer/config/windows/ansible-args.json` | A common set of variables that are sent to the Ansible playbook |
| `packer/config/windows/cloudbase-init.json` | The version of [Cloudbase Init](https://github.com/cloudbase/cloudbase-init) to install |
| `packer/config/windows/common.json` | Settings for things like which runtime (Docker or Containerd), pause image and other configuration |
| `packer/config/windows/kubernetes.json` | The version of Kubernetes to install and it's install path |
| `packer/config/windows/containerd.json` | The version of containerd to install |

## Windows Updates

When building Windows images it is necessary to install OS and Security updates.  Image Builder provides two variables to allow choosing which updates get installed which can be used together or seperately (with individual KBs installed first).

To specify the update categories to check, provide a value for `windows_updates_categories` in `packer/config/windows/common.json`.

Example:
Install all available updates from *all categories*.    
`"windows_updates_categories": "CriticalUpdates SecurityUpdates UpdateRollups"` 

Published Cloud Provider images such as Azure or AWS are regularly updated so it may be preferable to specify individual patches to install.  This can be achieved by specifying the KB numbers of required updates.

To choose individual updates, provide a value for `windows_updates_kbs` in `packer/config/windows/common.json`. 

Example: 
`"windows_updates_kbs": "KB4580390 KB4471332"`.  

## Using the Ansible Scripts directly

Ansible doesn't run on directly on Windows (wsl works) but can used to configure a remote Windows host.  For faster development you can create a VM and run Ansible against the Windows VM directly with out using packer. This document gives the high level steps to use Ansible from Linux machine.

## Set up Windows machine
Follow the documentation for configuring WinRm on the Windows machine: https://docs.ansible.com/ansible/latest/user_guide/windows_setup.html#winrm-setup. Note the [ConfigureRemotingForAnsible.ps1](https://raw.githubusercontent.com/ansible/ansible/devel/examples/scripts/ConfigureRemotingForAnsible.ps1) is for development only.  Refer to [Ansible WinRM documentation](https://docs.ansible.com/ansible/latest/user_guide/windows_winrm.html) for details for advance configuration.

After WinRM is installed you can edit or `/etc/ansible/hosts` file with the following:

```
[winhost]    
<windows ip>

[winhost:vars]
ansible_user=username
ansible_password=<your password>
ansible_connection=winrm
ansible_winrm_server_cert_validation=ignore
```

Then run: `ansible-playbook -vvv node_windows.yml --extra-vars "@example.vars.yml`

## MacOS with ansible
The Winrm connection plugin for Ansible on MacOS causes connection issues which can result in `ERROR! A worker was found in a dead state`. See https://docs.ansible.com/ansible/latest/user_guide/windows_winrm.html#what-is-winrm for more details.

To fix the issue on MacOS is to set the no_proxy environment variable. Example:

```
'no_proxy=* make build-azure-vhd-windows-2019'
```