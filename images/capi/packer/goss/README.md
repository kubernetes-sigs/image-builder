# Imagebuilder Goss validation

The Imagebuilder project uses [Goss](https://github.com/aelsabbahy/goss) in the post-build stage
to validate that the built images conform to the specified CAPI requirements in terms of installed packages,
running services, files, etc.

Refer to the [Goss documentation](https://image-builder.sigs.k8s.io/capi/goss/goss.html) in the Imagebuilder book for more information.

## Testing package installation across versions of an OS distribution

Verifying packages installation is a common usecase for Goss. Imagebuilder provides support for building multiple versions of the same OS, for example, RHEL 7 and RHEL 8 for the OVA provider. Often, the packages installed in one version will be different from those in the other. To add Goss validations for such cases, you can use the `versioned` field in `goss-vars.yaml` to separate the package listing for each supported distro versions, and Goss will pick the appropriate list of packages depending upon the provider, OS and version you are building.

### Example

Using the following configuration, RHEL 7 and RHEL 8 ova builds can validate a different set of package requirements, in
addition to common packages that both are expected to have.

```yaml
# This defines a set of RPMs to test for RHEL 7 builds
rh7_rpms: &rh7_rpms
  ebtables:
  python2-pip:
  python-netifaces:
  python-requests:

# This defines a set of RPMs to test for RHEL 8 builds
rh8_rpms: &rh8_rpms
  nftables:
  python3-pip:
  python3-netifaces:
  python3-requests:

rhel:
  ova:
    package: # These are common packages that both versions of RHEL OVA must have installed
      open-vm-tools:
      yum-utils:
      vim:
    versioned:
    - distro_version: "7"
      package:
        <<: *rh7_rpms # This will be populated with the above RPMs for RHEL 7
    - distro_version: "8"
      package:
        <<: *rh8_rpms # This will be populated with the above RPMs for RHEL 8
```
