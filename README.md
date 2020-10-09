# Image Builder

## Please see our [Book](https://image-builder.sigs.k8s.io) for more in-depth documentation.

## What is the Image Builder?

The Image Builder is a collection of cross-provider Kubernetes virtual machine image building utilities.

There are currently 3 distinct tools in this repo:

- [Image builder for Cluster API](https://github.com/kubernetes-sigs/image-builder/tree/master/images/capi)
- [kube-deploy/imagebuilder](https://github.com/kubernetes-sigs/image-builder/tree/master/images/kube-deploy/imagebuilder)
- [konfigadm](https://github.com/kubernetes-sigs/image-builder/tree/master/images/konfigadm)

Each project is independent from each other, with the goal of eventually merging into a single tool.

The `konfigadm` directory contains manifests for use with the `konfigadm CLI`.

### Useful links
- [Quick Start for Cluster API Image Builder](https://image-builder.sigs.k8s.io/capi/quickstart.html)
- [konfigadm CLI](https://github.com/flanksource/konfigadm)

## Community, discussion, contribution, and support

Learn how to engage with the Kubernetes community on the [community page](http://kubernetes.io/community/).

You can reach the maintainers of this project at:

- Image Builder office hours: [Thursdays at 08:00 PT (Pacific Time)](https://docs.google.com/document/d/1YIOD0Nnid_0h6rKlDxcbfJaoIRNO6mQd9Or5vKRNxaU/edit) (biweekly). [Convert to your timezone](http://www.thetimezoneconverter.com/?t=08:00&tz=PT%20%28Pacific%20Time%29).
  - [Meeting recordings](https://www.youtube.com/playlist?list=PL69nYSiGNLP29D0nYgAGWt1ZFqS9Z7lw4).
- [Slack channel](https://kubernetes.slack.com/messages/sig-cluster-lifecycle)
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

## Roadmap

- [x] Centralize the various image builders into this repository
- [ ] Create a binary that simplifies the consumption of image-builder
- [ ] Create a versioning policy
- [ ] Automate the building of images
- [ ] Publish images off master to facilitate E2E testing and the removal of `k/k/cluster`
- [ ] Create a bill of materials for each image and allow it to be used to recreate an image
- [ ] Automate the testing of images for kubernetes node conformance
- [ ] Automate the security scanning of images for CVE's
- [ ] Publish Demo / POC images to coincide with each new patch version of kubernetes to facilitate Cluster API adoption
- [ ] Automate the periodic scanning of images for new CVE's
- [ ] (Stretch Goal) Publish Production ready images with a clear support contract for handling CVE's.
  *Due to the high-level of commitment and effort required to support production images, this will only be done once all the pre-conditions are met including:*
  - [ ] Create an on-call rotation with sufficient volunteers to provide 365/24/7 coverage
  - [ ] Ensure all licensing requirements are met
