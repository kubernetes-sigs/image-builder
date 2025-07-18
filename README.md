# Image Builder

## Please see our [Book](https://image-builder.sigs.k8s.io) for more in-depth documentation.

## What is Image Builder?

Image Builder is a tool for building Kubernetes virtual machine images across multiple infrastructure providers. The resulting VM images are specifically intended to be used with [Cluster API](https://github.com/kubernetes-sigs/cluster-api) but should be suitable for other setups that rely on Kubeadm.

### Useful links

- [Quick Start for Cluster API Image Builder](https://image-builder.sigs.k8s.io/capi/quickstart.html)

## Provider / OS Matrix

The table below shows the currently provided operating systems for each provider built-in to image builder. (Note: This doesn't mean this is an exhaustive list of OSs each provider can support, only which are currently available within image-builder by default)

**Legend:**

- 💙: Image is available and is covered by CI tests
- ✅: Image is available for the provider
- ❌: Image is not available for the provider

| OS                | ami | azure | digitalocean | gce | hcloud | huaweicloud | maas | nutanix | oci | openstack | outscale | ova | powervs | proxmox | qemu | raw | scaleway | vultr |
|-------------------|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|----|
| Amazon Linux 2    | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Amazon Linux 2023 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Azure Linux 3     | ❌ | 💙 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| CentOS 8          | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| CentOS 9          | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | ❌ | ❌ |
| Flatcar           | ✅ | 💙 | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | 💙 | ❌ | ✅ | ✅ | ✅ | ❌ | ❌ |
| Oracle Linux 8    | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Oracle Linux 9    | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Photon 4          | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Photon 5          | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | 💙 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| RHEL 7            | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| RHEL 8            | ✅ | ✅ | ❌ | 💙 | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| RHEL 9            | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| Rocky Linux 8     | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ |
| Rocky Linux 9     | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ✅ | ❌ | 💙 | ❌ | ✅ | ✅ | ❌ | ✅ | ❌ |
| Ubuntu 20.04      | ✅ | 💙 | ✅ | ❌ | ✅ | ❌ | ❌ | ✅ | ✅ | ✅ | ✅ | 💙 | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ |
| Ubuntu 22.04      | ✅ | 💙 | ✅ | 💙 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ | 💙 | ❌ | ✅ | ✅ | ✅ | ✅ | ✅ |
| Ubuntu 24.04      | ✅ | 💙 | ✅ | 💙 | ✅ | ❌ | ✅ | ✅ | ❌ | ✅ | ✅ | 💙 | ❌ | ✅ | ✅ | ✅ | ✅ | ❌ |
| Windows 2019      | ✅ | 💙 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Windows 2022      | ❌ | 💙 | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ | ✅ | ❌ | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Windows 2025      | ❌ | 💙 | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Windows Annual    | ❌ | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ | ❌ |

## Community, discussion, contribution, and support

Learn how to engage with the Kubernetes community on the [community page](http://kubernetes.io/community/).

You can reach the maintainers of this project at:

- Image Builder office hours: **Mondays (biweekly) at 08:30 PT (Pacific Time)** (biweekly). [Convert to your timezone](http://www.thetimezoneconverter.com/?t=08:30&tz=PT%20%28Pacific%20Time%29).
  - [Meeting Agenda / Notes](https://docs.google.com/document/d/100uv2GmlgWyLBVP65W6ABNJ_EqbvVYTYtTilCLbnVYI/edit) (access is restricted to members of the [sig-cluster-lifecycle](https://groups.google.com/a/kubernetes.io/g/sig-cluster-lifecycle) mailing list).
  - [Meeting recordings](https://www.youtube.com/playlist?list=PL69nYSiGNLP29D0nYgAGWt1ZFqS9Z7lw4).
- [Slack channel](https://kubernetes.slack.com/messages/image-builder)
- [Mailing list](https://groups.google.com/forum/#!forum/kubernetes-sig-cluster-lifecycle)

### Code of conduct

Participation in the Kubernetes community is governed by the [Kubernetes Code of Conduct](code-of-conduct.md).

## Goals

- To build images for Kubernetes-conformant clusters in a consistent way across infrastructures, providers, and business needs.
  - To install all software, containers, and configuration needed by downstream tools such as Cluster API providers, to enable them to pass conformance tests
  - Support end users requirements to customize images for their business needs.
- To provide assurances in the binaries and configuration in images for purposes of security auditing and operational stability.
  - Allow introspection of artifacts, software versions, and configurations in a given image.
  - Support repeatable build processes where the same inputs of requested install versions result in the same installed binaries.
- To ensure that the creation of images is performed via well defined phases.  Where users could choose specific phases that they needed.

## Non-Goals

- To provide upgrade or downgrade semantics.
- To provide guarantees that the software installed provides a fully functional system.
- To prescribe the hardware architecture of the build system.
