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
