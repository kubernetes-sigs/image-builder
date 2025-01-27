# Multipath Configuration

This role is designed to configure the Multipath service on the system, ensuring that the configuration file (`/etc/multipath.conf`) is properly managed.

## Usage

The environment variable `PACKER_FLAGS` is used to set a Packer variable named `ansible_extra_vars`. In Ansible, the variable `custom_role_names` must be set to the role name, which in this case is `multipathd`. 

Additionally, another variable, `multipathd_custom_conf_file_path`, must be defined. This variable specifies the path to the configuration file that you want to include in the image.

At first glance, this setup might seem a bit complex, but it can be summarized as follows:

```bash
export PACKER_FLAGS="--var 'ansible_extra_vars=custom_role_names=multipathd multipathd_custom_conf_file_path=path/to/multipath.conf'"
```

## Behavior
If you only set the Ansible variable `custom_role_names=multipathd`, a default configuration file will be copied (which contains minimal configuration) with the following content:

```
defaults {
    user_friendly_names yes
}
```