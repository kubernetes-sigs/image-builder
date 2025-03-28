# Testing CAPI Images

## Goss

[Goss](https://github.com/goss-org/goss) is a YAML based serverspec alternative
tool for validating a server’s configuration. It is used in conjunction with 
[packer-provisioner-goss](https://github.com/YaleUniversity/packer-provisioner-goss/releases)
to test if the images have all requisite components to work with cluster API.

### Support Matrix 
*For stock server-specs shipped with repo

| OS                      | Builder              |
|-------------------------|----------------------|
| Amazon Linux            | aws                  |
| Azure Linux             | azure                |
| CentOS                  | aws, ova             |
| Flatcar Container Linux | aws, azure, ova      |
| PhotonOS                | ova                  |
| Ubuntu                  | aws, azure, gcp, ova |
| Windows                 | aws, azure, ova      |


### Prerequisites for Running Goss
Goss runs as a part of image building through a Packer provisioner.
Supported arguments are passed through file: `packer/config/goss-args.json`
```json
{
  "goss_arch": "amd64",
  "goss_download_path": "",
  "goss_entry_file": "goss/goss.yaml",
  "goss_format": "json",
  "goss_inspect_mode": "true",
  "goss_remote_folder": "",
  "goss_remote_path": "",
  "goss_skip_install": "",
  "goss_tests_dir": "packer/goss",
  "goss_url": "",
  "goss_format_options": "pretty",
  "goss_vars_file": "packer/goss/goss-vars.yaml",
  "goss_version": "0.3.23"
}
```
##### Supported values for some of the arguments can be found [here](https://github.com/goss-org/goss).
> Enabling the `goss_inspect_mode` lets you build image even if Goss tests fail.

#### Manually setup Goss
- Start a VM from CAPI image
- Copy complete Goss dir `packer/goss` to remote machine
- Download and setup Goss (use version from goss-args) on the remote machine. [Instructions](https://github.com/goss-org/goss#latest) 
- Custom Goss version can be installed if testing custom server-specs supported by higher version of Goss.
- All the variables used in Goss are declared in `packer/goss/goss-vars.yaml`
- Add more custom serverspec to corresponding Goss files. Like, `goss-command.yaml` or `goss-kernel-params.yaml`
    ```yaml
      some_cli --version:
        exit-status: 0
        stdout: [{{ .Vars.some_cli_version }}]
        stderr: []
        timeout: 0
    ```
- Add more custom variables to corresponding Goss file `goss-vars.yaml`.
    ```yaml
    some_cli_version: "1.4.5+k8s-1"
    ```
- Fill the variable values in `goss-vars.yaml` or specify in `--vars-inline` while executing Goss in below steps
- Render the Goss template to fix any problems with parsing variable and serverspec YAMLs
  ```bash
    sudo goss -g goss/goss.yaml --vars /tmp/goss/goss-vars.yaml --vars-inline '{"ARCH":"amd64","OS":"Ubuntu","PROVIDER":"aws", some_cli_version":"1.3.4"}' render
  ```     
- Run the Goss tests  
  ```bash
    sudo goss -g goss/goss.yaml --vars /tmp/goss/goss-vars.yaml --vars-inline '{"ARCH":"amd64","OS":"Ubuntu","PROVIDER":"aws", some_cli_version":"1.3.4"}' validate --retry-timeout 0s --sleep 1s -f json -o pretty
  ```
