# Building Images for VirtualBox

## Hypervisor

The image is built using Oracle VM VirtualBox hypervisor.

### Installing VirtualBox package

Oracle VirtualBox install instructions and packages are available at the [official page](https://www.virtualbox.org/wiki/Downloads).

## Building Images

### Validating

The build [prerequisites](../capi.md#prerequisites) for using `image-builder` for
building vbox images are managed by running:

```bash
cd image-builder/images/capi
make deps-vbox
```

### Generating a VirtualBox image

Only Windows 2019 images are available for VirtualBox hypervisor for now, to build local images
for development are made by running:

```bash
cd image-builder/images/capi
make build-node-vbox-local-windows-2019
```

#### Windows ISO download

This field should point to a Windows evaluation ISO, it can be found at [Microsoft Evaluation Center](https://www.microsoft.com/en-us/evalcenter/evaluate-windows-server-2019) page. Make sure you have the correct Windows Server version.

```json
{
  "os_iso_url": "file:/path/en_windows_server_2019_x64_dvd_4cb967d8.iso"
}
```