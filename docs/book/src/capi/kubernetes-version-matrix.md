# Kubernetes Version Matrix

The CAPI image build has a Kubernetes minor dependency matrix in
`images/capi/packer/config/kubernetes-version-matrix.yaml`. It records pinned
dependency versions for release minors. The rolling latest entry is stored in
`images/capi/packer/config/kubernetes-version-latest.yaml`.

Render either form to a Packer var file before a build:

```sh
images/capi/hack/kubernetes-version-matrix.py render 1.35 > /tmp/kubernetes-1.35.json
PACKER_VAR_FILES=/tmp/kubernetes-1.35.json make ...
```

Use `latest` for the rolling entry:

```sh
images/capi/hack/kubernetes-version-matrix.py render latest > /tmp/kubernetes-latest.json
```

The rendered JSON can be passed through `PACKER_VAR_FILES`, so it overrides the
default values from `packer/config/kubernetes.json`, `packer/config/cni.json`,
and `packer/config/containerd.json` without editing those files directly.

The matrix intentionally omits `kubernetes_source_type` and
`kubernetes_cni_source_type`. Those fields select how a target installs
Kubernetes and CNI (package manager vs. URL download) and some targets, such
as Flatcar, require `http` while most other targets use `pkg`. Because
`PACKER_VAR_FILES` is applied after the target var file, rendering those
fields into the matrix would override a target's own source-type choice.
Leave the source type in the target-specific var file and let it take
precedence over the matrix values.

Refresh the Kubernetes and package-manager pins from the upstream release and
package repositories with:

```sh
images/capi/hack/kubernetes-version-matrix.py update --write
images/capi/hack/kubernetes-version-matrix.py verify
```

Generated Go module manifests under
`images/capi/packer/config/kubernetes-version-dependencies/` let Dependabot
track the same versions as module dependencies. Release-pinned entries accept
patch updates only. The rolling `latest` entry can move to newer minor versions.
Kubernetes releases are tracked through `k8s.io/client-go` module tags and then
mapped back to Kubernetes `v1.x.y` versions in the matrix.

When Dependabot updates those manifests, the
`Update Kubernetes version matrix` workflow regenerates the YAML files with:

```sh
images/capi/hack/kubernetes-version-matrix.py sync-tracking --write
images/capi/hack/kubernetes-version-matrix.py verify
```

Run `update --write` when refreshing directly from upstream release and package
metadata. It updates the YAML files and regenerates the Dependabot tracking
manifests.

## Updating containerd and runc

For runtime-only updates, change the containerd and runc versions in the tracking
manifests, then run `sync-tracking --write` and `verify` as above. Keep Kubernetes,
CNI, and cri-tools versions unchanged, and align runc with the version tested by
the selected containerd release.

Also update `images/capi/packer/config/containerd.json`, the runc default in
`images/capi/ansible/roles/containerd/defaults/main.yml`, and the Nutanix HCL defaults
in `images/capi/packer/nutanix/variables.pkr.hcl`. Update the PowerPC version and
checksum in `images/capi/packer/config/ppc64le/containerd.json` using the official
release's `.sha256sum` asset. Other downloads already resolve release checksum
URLs.

Refresh and verify the bundled systemd unit from the repository root:

```sh
make update-containerd-service-template
make verify-containerd-service-template
```

The updater refreshes the supported-version marker even when the upstream unit
itself has not changed.
