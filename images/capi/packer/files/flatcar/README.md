# Flatcar-Related Build Files

This directory contains files needed for building Flatcar Container Linux CAPI images.

The following subdirectories exist:

- `clc` - contains [Container Linux Config][1] files.
- `ignition` - contains [Ignition][2] files generated from the CLC files in the `clc` directory.
- `scripts` - contains scripts which are used by the various Flatcar builds.

## Ignition Files

Some Flatcar builds (e.g. QEMU) require Ignition files during OS installation. These files can be
consumed directly from the `ignition` directory. Ignition files are generated from CLC files by the
[Container Linux Config Transpiler][3].

### Adding New Files

To add a new Ignition file, do the following:

1. Place a CLC YAML file with the desired config in `clc`.
1. Add the name of the file without an extension to the `ignition_files` variable under the
  `gen-ignition` target in the [Makefile](../../../Makefile). For example, for a CLC file named
  `foo.yaml`, add `foo` to the Make target.
1. Run `make gen-ignition` under `images/capi`. A new Ignition file is generated under `ignition`.
1. Commit both the CLC file and the resulting Ignition file and open a PR to merge the changes.

Once the changes are merged, the new Ignition file can be referenced in Flatcar builds and consumed
as a raw file directly from GitHub.

### Changing Existing Files

To change an existing Ignition file, do the following:

1. Edit the relevant CLC YAML file in `clc`.
1. Run `make gen-ignition` under `images/capi`. The corresponding Ignition file is updated under
  `ignition`.
1. Commit the changes and open a PR to merge them.

[1]: https://flatcar.org/docs/latest/provisioning/cl-config/
[2]: https://flatcar.org/docs/latest/provisioning/ignition/
[3]: https://flatcar.org/docs/latest/provisioning/config-transpiler/
