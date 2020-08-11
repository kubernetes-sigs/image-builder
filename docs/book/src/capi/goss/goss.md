# Testing CAPI Images

## GOSS

[Goss](https://github.com/aelsabbahy/goss) is a YAML based serverspec alternative
tool for validating a server’s configuration. It is used in conjunction with 
[packer-provisioner-goss](https://github.com/YaleUniversity/packer-provisioner-goss/releases)
to test if the images have all requisite components to work with cluster API.

### Support Matrix 
*For stock server-specs shipped with repo

| OS | Builder | 
|----|---------|
| Amazon Linux | aws
| PhotonOS | ova
| Ubuntu | aws , ova, azure
| CentOS | aws, ova 


### Prerequisites for Running GOSS
GOSS runs as a part of image building through a packer provisioner.
Supported arguments are passed through file: `packer/config/goss-args.json`
```json
{
  "goss_arch": "amd64",
  "goss_entry_file": "goss/goss.yaml",
  "goss_format": "json",
  "goss_inspect_mode": "true",
  "goss_tests_dir": "packer/goss",
  "goss_url": "",
  "goss_format_options": "pretty",
  "goss_vars_file": "packer/goss/goss-vars.yaml",
  "goss_version": "0.3.13"
}
```
##### Supported values for some of the arguments can be found [here](https://github.com/aelsabbahy/goss).
> Enabling the `goss_inspect_mode` lets you build image even if goss tests fail.

#### Manually setup GOSS
- Start a VM from capi image
- Copy complete goss dir `packer/goss` to remote machine
- Download and setup GOSS (use version from goss-args) on the remote machine. [Instructions](https://github.com/aelsabbahy/goss#latest) 
- Custom goss version can be installed if testing custom server-specs supported by higher version of GOSS.
- All the variables used in GOSS are declared in `packer/goss/goss-vars.yaml`
- Add more custom serverspec to corresponding GOSS files. Like, `goss-command.yaml` or `goss-kernel-params.yaml`
    ```yaml
      some_cli --version:
        exit-status: 0
        stdout: [{{ .Vars.some_cli_version }}]
        stderr: []
        timeout: 0
    ```
- Add more custom variables to corresponding GOSS file `goss-vars.yaml`.
    ```yaml
    some_cli_version: "1.4.5+k8s-1"
    ```
- Fill the variable values in `goss-vars.yaml` or specify in `--vars-inline` while executing GOSS in below steps
- Render the goss template to fix any problems with parsing variable and serverspec yamls
  ```bash
    sudo goss -g goss/goss.yaml --vars /tmp/goss/goss-vars.yaml --vars-inline '{"ARCH":"amd64","OS":"Ubuntu","PROVIDER":"aws", some_cli_version":"1.3.4"}' render
  ```     
- Run the GOSS tests  
  ```bash
    sudo goss -g goss/goss.yaml --vars /tmp/goss/goss-vars.yaml --vars-inline '{"ARCH":"amd64","OS":"Ubuntu","PROVIDER":"aws", some_cli_version":"1.3.4"}' validate --retry-timeout 0s --sleep 1s -f json -o pretty
  ```
