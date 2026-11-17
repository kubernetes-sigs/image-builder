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

## Dependabot tracking manifests

The matrix YAML is not a format Dependabot understands, so the generator also
writes one manifest per entry under
`images/capi/packer/config/kubernetes-version-dependencies/`:

```text
kubernetes-version-dependencies/
  latest/.pre-commit-config.yaml
  release-1-31/.pre-commit-config.yaml
  ...
  release-1-36/.pre-commit-config.yaml
```

Each manifest lists the five upstream repositories the matrix pins, with the
release tag in the `rev` field:

```yaml
repos:
  - repo: https://github.com/containerd/containerd
    rev: v2.3.2
    hooks: []
```

Dependabot's `pre-commit` ecosystem tracks any git repository named in a
`repos[].repo` entry, follows its tags and rewrites the matching `rev` line.
That is the only reason these files exist. The `pre-commit` tool itself never
runs them, the hook lists are deliberately empty, and no repository listed here
has to ship a `.pre-commit-hooks.yaml`. Using pre-commit configs keeps the
tracked version in the file that names it, so the mapping between a matrix key
and the version Dependabot maintains is a single `rev` line.

Release-pinned entries accept patch updates only. The rolling `latest` entry
can move to newer minor versions. Kubernetes releases are tracked through
`kubernetes/kubernetes` tags directly, so a `rev` is the same `v1.x.y` string
the matrix stores.

When Dependabot updates a manifest, the `Update Kubernetes version matrix`
workflow folds the new revs back into the matrix YAML with:

```sh
images/capi/hack/kubernetes-version-matrix.py sync-tracking --write
images/capi/hack/kubernetes-version-matrix.py verify
```

`sync-tracking` reads only the `repo` and `rev` pairs, so reordering or
reformatting a manifest does not break it, and it refuses a rev that leaves the
pin policy of its directory.

Regenerate the manifests from the matrix, without network access, with:

```sh
images/capi/hack/kubernetes-version-matrix.py render-tracking --write
```

Run `update --write` when refreshing directly from upstream release and package
metadata. It updates the YAML files and regenerates the tracking manifests. It
leaves `containerd_version`, `runc_version` and `kubernetes_cni_semver` alone,
because Dependabot owns those three.

## How the pin policy is enforced

`.github/dependabot.yml` carries one `pre-commit` entry per tracking directory,
each naming its directory exactly. Every entry ignores each of the five
repositories above a single explicit bound: the next minor of the pinned
version for a release pin, the next major for `latest`.

```yaml
  ignore:
    # Release pins take patch updates only.
    - dependency-name: "https://github.com/containerd/containerd"
      versions: [ ">= 2.4.0" ]
```

The entries cannot be collapsed into one globbed entry, because the bounds
differ per directory.

`update-types` conditions are not used, and `verify` rejects them. They have no
effect on a pre-commit dependency: dependabot-core resolves them through
`Dependabot::Config::IgnoreCondition`, which parses the current version with
`Dependabot::PreCommit::Version`, and that class does not strip the leading `v`
of a git tag the way the gomod and github-actions version classes do, so the
condition yields no range at all. Were only that half fixed, `update-types`
would start producing a two-clause range such as `">= 2.4.a, < 3"`, and
`Dependabot::PreCommit::Requirement.requirements_array` hands the whole string
to `Gem::Requirement` without splitting on commas, which raises
`Gem::Requirement::BadRequirementError` and fails the update job. A
single-clause `versions` bound avoids both problems.

`verify` checks that every tracking directory has its own entry and that each
entry's bounds are exactly what the matrix implies, so a pin that crosses a
minor, however it lands, fails until the bounds are updated. The error names
the value to write. `sync-tracking` then applies the same policy to the revs
themselves, as a second guard for anything the bounds miss.
