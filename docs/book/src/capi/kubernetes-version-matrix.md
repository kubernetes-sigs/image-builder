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

Dependabot tracks the same versions as Go module dependencies. Every tracked
dependency gets its own synthetic module under
`images/capi/packer/config/kubernetes-version-dependencies/`:

```text
kubernetes-version-dependencies/
  latest/            # rolling entry
    cni-plugins/     # github.com/containernetworking/plugins
    containerd/      # github.com/containerd/containerd/v2
    cri-tools/       # sigs.k8s.io/cri-tools
    kubernetes/      # k8s.io/client-go
    runc/            # github.com/opencontainers/runc
  release-1-31/      # one directory per release pin, same five modules
  ...
```

Each module requires exactly one dependency, so minimal version selection
cannot let one tracked dependency raise the pin of another. Release-pinned
entries accept patch updates only. The rolling `latest` entry can move to newer
minor versions. Kubernetes releases are tracked through `k8s.io/client-go`
module tags and then mapped back to Kubernetes `v1.x.y` versions in the matrix.

Each module also has a `tools.go` file with a single blank import. Dependabot
always runs `go mod tidy` after an update, and tidy drops requirements that no
package imports, which would empty the manifest. The imported package is the
lightest one in the tracked module so that tidy records no indirect
requirements. Because tidy also rewrites the `go` directive and may add a
`toolchain` line, `verify` checks the required module and version rather than
comparing the whole file against a template. It also checks that go.sum carries
both `h1:` checksums for the pinned version, so a go.mod left ahead of its
go.sum fails instead of passing quietly.

`kubernetes_cni_semver` pins the CNI plugins tarball and is tracked
independently of `kubernetes_cni_deb_version` and
`kubernetes_cni_rpm_version`, which pin the distro `kubernetes-cni` package.
The two are versioned separately upstream, so `update --write` refreshes the
package versions and carries the tarball version over unchanged. A CNI module
update can therefore advance `kubernetes_cni_semver` before the matching
`kubernetes-cni` package is published: URL-based targets then install the newer
tarball while package-based targets keep the pinned package version.

More generally, `update --write` only rewrites what it resolves from upstream
release metadata: the Kubernetes version fields, the kubernetes-cni package
versions and crictl. `containerd_version`, `runc_version` and
`kubernetes_cni_semver` are carried over. This holds for the rolling `latest`
entry too, which is refreshed from its own values rather than from the release
pin for the same minor, so a version Dependabot moved ahead on `latest` is
never rolled back by a refresh.

When Dependabot updates the modules, the `Update Kubernetes version matrix`
workflow regenerates the YAML files with:

```sh
images/capi/hack/kubernetes-version-matrix.py sync-tracking --write
images/capi/hack/kubernetes-version-matrix.py verify
```

Run `update --write` when refreshing directly from upstream release and package
metadata. It updates the YAML files and then rewrites and tidies any tracking
module whose version changed.

Bootstrap the tracking modules for a new release selector after adding its
entry to the matrix with:

```sh
images/capi/hack/kubernetes-version-matrix.py render-tracking --write
```

`render-tracking --write` and `update --write` need the `go` command because
they regenerate each changed module with `go mod tidy`. Both check for it up
front and exit before touching a file, so a missing toolchain cannot leave a
go.mod ahead of its go.sum. `verify` and `sync-tracking` do not need `go`.
`verify` needs no network access beyond a `yq` binary, which `hack/ensure-yq.sh`
downloads when one is not already installed. `sync-tracking` only reaches the
network when the tracked Kubernetes version moved and the Debian package
revision has to be resolved again.
