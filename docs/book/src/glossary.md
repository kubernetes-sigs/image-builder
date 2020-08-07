# Table of Contents

[A](#a) | [C](#c) | [E](#e) | [G](#g) | [K](#k) | [O](#o) | [V](#v)

# A
---

## AWS

Amazon Web Services

## AMI

[Amazon Machine Image](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/AMIs.html)

# C
---

## CAPA

[Cluster API Provider AWS](https://github.com/kubernetes-sigs/cluster-api-provider-aws)

## CAPG

[Cluster API Provider GCP](https://github.com/kubernetes-sigs/cluster-api-provider-gcp)

## CAPI

The Cluster API is a Kubernetes project to bring declarative, Kubernetes-style APIs to cluster creation, configuration, and management. It provides optional, additive functionality on top of core Kubernetes.

[source](https://github.com/kubernetes-sigs/cluster-api)

## CAPV

[Cluster API Provider vSphere](https://github.com/kubernetes-sigs/cluster-api-provider-vsphere)

## CAPZ

[Cluster API Prover Azure](https://github.com/kubernetes-sigs/cluster-api-provider-azure)


# E
---

## ESXi

ESXi (formerly ESX) is an enterprise-class, type-1 hypervisor developed by VMware. ESXi provides strong separation between VMs and itself, providing strong security boundaries between the guest and host operating systems. ESXi can be used as a standalone entity, without vCenter but this is extremely uncommon and feature limited as without a higher level manager (vCenter). ESXi cannot provide its most valuable features, like High Availability, vMotion, workload balancing and vSAN (a software defined storage stack).

# G
---

## GOSS

[Goss](https://github.com/aelsabbahy/goss) is a YAML based serverspec alternative tool for validating a server’s configuration.  It is used in conjunction with [packer-provisioner-goss](https://github.com/YaleUniversity/packer-provisioner-goss/releases) to test if the images have all requisite components to work with cluster API.

# K
---

## K8s

Kubernetes

## Kubernetes

Kubernetes (K8s) is an open-source system for automating deployment, scaling, and management of containerized applications.

[source](https://kubernetes.io)

# O
---

## OVA

Open Virtual Appliance

A single package containing a pre-configured virtual machine, usually based on OVF.

## OVF

Open Virtualization Format

An open standard for packaging and distributing virtual appliances or, more generally, software to be run in virtual machines.

[source](https://en.wikipedia.org/wiki/Open_Virtualization_Format)

# V
---

## vCenter

vCenter can be thought of as the management layer for ESXi hosts. Hosts can be arranged into Datacenters, Clusters or resources pools, vCenter is the centralized monitoring and management control plane for ESXi hosts allow centralized management, integration points for other products in the VMware SDDC stack and third party solutions, like backup, DR or networking overlay applications, such as NSX. vCenter also provides all of the higher level features of vSphere such as vMotion, vSAN, HA, DRS, Distributed Switches and more.

## VM

A VM is an abstraction of an operating system from the physical machine by creating a "virtual" representation of the physical hardware the OS expects to interact with, this includes but is not limited to CPU instruction sets, memory, BIOS, PCI buses, etc. A VM is an entirely self-contained entity and shares no components with the host OS. In the case of vSphere the host OS is ESXi (see below).

## vSphere

vSphere is the product name of the two core components of the VMware Software Defined Datacenter (SDDC) stack, they are vCenter and ESXi.
