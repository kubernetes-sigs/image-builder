# Image Builder Releases

The current release of Image Builder is [v0.1.47][] (August 25, 2025). The corresponding container image is `registry.k8s.io/scl-image-builder/cluster-node-image-builder-amd64:v0.1.47`.

## Release Process

Releasing image-builder is a simple process: project maintainers should be able to follow the steps below in order to create a new release.

### Create a tag

Releases in image-builder follow [semantic versioning][semver] conventions. Currently the project tags only patch releases on the main branch.

- Check out the existing branch and make sure you have the latest changes:
  - `git checkout main`
  - `git fetch upstream`
    - *This assumes you have an "upstream" git remote pointing at github.com/kubernetes-sigs/image-builder*
  - `git rebase upstream/main`
    - *If the HEAD commit isn't meant for release, reset to the intended commit before proceeding.*
- Ensure you can sign tags:
  - Set up GPG, SSH, or S/MIME [at GitHub](https://docs.github.com/authentication/managing-commit-signature-verification/about-commit-signature-verification) if you haven't already.
  - `export GPG_TTY=$(tty)`
    - *If signing tags with GPG, makes your key available to the `git tag` command.*
- Create a new tag:
  - `export IB_VERSION=v0.1.x`
    - *Replace `x` with the next patch version. For example: `v0.1.47`.*
  - `git tag -s -m "Image Builder ${IB_VERSION}" ${IB_VERSION}`
  - `git push upstream ${IB_VERSION}`

### Promote Image to Production

Pushing the tag in the previous step triggered a job to build the container image and publish it to the staging registry.

- Images are built by the [post-image-builder-push-images][] job. This will push the image to a [staging repository][].
- Wait for the above post-image-builder-push-images job to complete and for the tagged image to exist in the staging directory.
- If you don't have a GitHub token, create one via [Personal access tokens][]. Make sure you give the token the `repo` scope.
- Make sure you have a clone of [k8s.io](https://github.com/kubernetes/k8s.io) otherwise the next step will not work.
- Create a GitHub pull request to promote the image:
  - `export GITHUB_TOKEN=<your GH token>`
  - `make -C images/capi promote-image`
  - Note: If your own fork isn't used as the `origin` remote you'll need to set the `USER_FORK` variable, e.g. `make -C images/capi promote-image USER_FORK=AverageMarcus`

This will create a PR in [k8s.io](https://github.com/kubernetes/k8s.io) and assign the image-builder maintainers. Example PR: [https://github.com/kubernetes/k8s.io/pull/5262](https://github.com/kubernetes/k8s.io/pull/5262).

When reviewing this PR, confirm that the addition matches the SHA in the [staging repository][].

### Publish GitHub Release

While waiting for the above PR to merge, create a GitHub draft release for the tag you created in the first step.

- Visit the [releases page][] and click the "Draft a new release" button.
  - *If you don't see that button, you don't have all maintainer permissions.*
- Choose the new tag from the drop-down list, and type it in as the release title too.
- Click the "Generate release notes" button to auto-populate the release description.
- At the top, before `## What's Changed`, insert a reference to the container artifact, replacing `x` with the patch version:

    ```
    This release of the image-builder container is available at:

    `registry.k8s.io/scl-image-builder/cluster-node-image-builder-amd64:v0.1.x`
    ```
- Proofread the release notes and make any necessary edits.
- Click the "Save draft" button.
- When the pull request from the previous step has merged, check that the image-builder container is actually available. This may take up to an hour after the PR merges.
  - `docker pull registry.k8s.io/scl-image-builder/cluster-node-image-builder-amd64:${IB_VERSION}`
- When `docker pull` succeeds, return to the GitHub draft release, ensure "Set as the latest release" is true, and click the "Publish release" button.

### Update Documentation

There are several files in image-builder itself that refer to the latest release (including this one).

Run `make update-release-docs` and then create a pull request with the generated changes.

Wait for this PR to merge before communicating the release to users, so image-builder documentation is consistent.

### Publicize Release

In the [#image-builder channel][] on the Kubernetes Slack, post a message announcing the new release. Include a link to the GitHub release and a thanks to the contributors:

```
Image-builder v0.1.47 is now available: https://github.com/kubernetes-sigs/image-builder/releases/tag/v0.1.47
Thanks to all contributors!
```

[v0.1.47]: https://github.com/kubernetes-sigs/image-builder/releases/tag/v0.1.47
[#image-builder channel]: https://kubernetes.slack.com/archives/C01E0Q35A8J
[Personal access tokens]: https://github.com/settings/tokens
[post-image-builder-push-images]: https://prow.k8s.io/?repo=kubernetes-sigs%2Fimage-builder&type=postsubmit&job=post-image-builder-push-images
[releases page]: https://github.com/kubernetes-sigs/image-builder/releases
[semver]: https://semver.org/#semantic-versioning-200
[staging repository]: https://console.cloud.google.com/gcr/images/k8s-staging-scl-image-builder/GLOBAL/cluster-node-image-builder-amd64
