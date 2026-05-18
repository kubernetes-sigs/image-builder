# Customizing containerd

## Running sandboxed containers using gVisor

For additional security in a Kubernetes cluster it can be useful to run certain
containers in a restricted runtime environment known as a sandbox. One option for this
is to use [gVisor](https://gvisor.dev/docs/) which provides a layer
of separation between a running container and the host kernel.

To use gVisor, the necessary executables and [containerd configuration](https://github.com/containerd/containerd/blob/main/docs/cri/config.md#runtime-classes) can be added
to the image generated with image-builder by setting the `containerd_gvisor_runtime`
flag to `true`. For example, in a packer configuration file:

```json
{
    "containerd_gvisor_runtime": "true",
    "containerd_gvisor_version": "yyyymmdd",
}
```

This will tell image_builder to install `runsc`, the executable for gVisor, as well as
the necessary configuration for containerd. Note that `containerd_gvisor_version: yyyymmdd` can be used to install a specific 
[point release](https://github.com/google/gvisor/releases) version. The version defaults to `latest`.

Once you have built your cluster using the new image, you can then create a `RuntimeClass` object
as follows:

```yaml
apiVersion: node.k8s.io/v1
kind: RuntimeClass
metadata:
  # The name the RuntimeClass will be referenced by.
  # RuntimeClass is a non-namespaced resource.
  name: gvisor
handler: gvisor
```

Now, to run a pod in the sandboxed environment you just need to specify the name of the RuntimeClass
using `runtimeClassName` in the Pod spec:

```yaml
apiVersion: v1
kind: Pod
metadata:
  name: test-sandboxed-pod
spec:
  runtimeClassName: gvisor
  containers:
    - name: sandboxed-container
      image: nginx
```

Once the pod is up and running, you can verify by using `kubectl exec` to start a shell on the
pod and run `dmesg`. If the container sandbox is running correctly you should see output similar
to the following:

```
root@sandboxed-container:/# dmesg
[    0.000000] Starting gVisor...
[    0.511752] Digging up root...
[    0.910192] Recruiting cron-ies...
[    1.075793] Rewriting operating system in Javascript...
[    1.351495] Mounting deweydecimalfs...
[    1.648946] Searching for socket adapter...
[    2.115789] Checking naughty and nice process list...
[    2.351749] Granting licence to kill(2)...
[    2.627640] Creating bureaucratic processes...
[    2.954404] Constructing home...
[    3.396065] Segmenting fault lines...
[    3.812981] Setting up VFS...
[    4.164302] Setting up FUSE...
[    4.224418] Ready!
```

You are running a sandboxed container.

## Additional Customizations

Containerd can be further customized in a couple of ways. One option that is directly inserted into the containerd
[`config.toml`](https://github.com/kubernetes-sigs/image-builder/blob/main/images/capi/ansible/roles/containerd/templates/etc/containerd/config.toml#L14)
is to override the image pull progress timeout. This can be done using `containerd_image_pull_progress_timeout`.

You can also add further configuration by adding values for `containerd_additional_settings`. This is rendered at the
end of the
[`config.toml`](https://github.com/kubernetes-sigs/image-builder/blob/main/images/capi/ansible/roles/containerd/templates/etc/containerd/config.toml#L86)
default template. 

## Overriding `LimitNOFILE`

By default a `LimitNOFILE` systemd drop-in (capping the value at `1048576`) is only deployed on
Common Base Linux Mariner, Flatcar, and Microsoft Azure Linux, where the upstream `infinity` value
has been known to cause issues with some containerized software. To opt-in to deploying the same
drop-in on other operating systems, set `containerd_enable_limit_no_file` to `true`. It defaults to
`false`.
