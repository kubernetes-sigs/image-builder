# Copyright 2019 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# If you update this file, please follow
# https://suva.sh/posts/well-documented-makefiles

# Ensure Make is run with bash shell as some syntax below is bash-specific
SHELL := /usr/bin/env bash

.DEFAULT_GOAL := help

export IB_VERSION ?= $(shell git describe --dirty)

## --------------------------------------
## Help
## --------------------------------------
##@ Helpers
help: ## Display this help
	@echo NOTE
	@echo '  The "build-node-ova" targets have analogue "clean-node-ova" targets for'
	@echo '  cleaning artifacts created from building OVAs using a local'
	@echo '  hypervisor.'
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-35s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

.PHONY: version
version: ## Display version of image-builder
	@echo $(IB_VERSION)

## --------------------------------------
## Dependencies
## --------------------------------------
##@ Dependencies

.PHONY: deps
deps: ## Installs/checks all dependencies
deps: deps-ami deps-azure deps-do deps-gce deps-ova

.PHONY: deps-ami
deps-ami: ## Installs/checks dependencies for AMI builds
deps-ami:
	hack/ensure-ansible.sh
	hack/ensure-packer.sh
	hack/ensure-goss.sh

.PHONY: deps-azure
deps-azure: ## Installs/checks dependencies for Azure builds
deps-azure:
	hack/ensure-ansible.sh
	hack/ensure-packer.sh
	hack/ensure-jq.sh
	hack/ensure-azure-cli.sh
	hack/ensure-goss.sh


.PHONY: deps-do
deps-do: ## Installs/checks dependencies for DigitalOcean builds
deps-do:
	hack/ensure-ansible.sh
	hack/ensure-packer.sh

.PHONY: deps-gce
deps-gce: ## Installs/checks dependencies for GCE builds
deps-gce:
	hack/ensure-ansible.sh
	hack/ensure-packer.sh

.PHONY: deps-ova
deps-ova: ## Installs/checks dependencies for OVA builds
deps-ova:
	hack/ensure-ansible.sh
	hack/ensure-packer.sh
	hack/ensure-goss.sh

.PHONY: deps-qemu
deps-qemu: ## Installs/checks dependencies for QEMU builds
deps-qemu:
	hack/ensure-ansible.sh
	hack/ensure-packer.sh

## --------------------------------------
## Container variables
## --------------------------------------
REGISTRY ?= gcr.io/$(shell gcloud config get-value project)
IMAGE_NAME ?= cluster-node-image-builder
CONTROLLER_IMG ?= $(REGISTRY)/$(IMAGE_NAME)
TAG ?= dev
ARCH ?= amd64

## --------------------------------------
## Packer flags
## --------------------------------------

# Set Packer color to true if not already set in env variables
# Only valid for builds
ifneq (,$(findstring build-, $(MAKECMDGOALS)))
	# A build target
	PACKER_COLOR ?= true
	PACKER_FLAGS += -color=$(PACKER_COLOR)
endif

# If FOREGROUND=1 then Packer will set headless to false, causing local builds
# to build in the foreground, with a UI. This is very useful when debugging new
# platforms or issues with existing ones.
ifeq (1,$(strip $(FOREGROUND)))
PACKER_FLAGS += -var="headless=false"
endif

# If ON_ERROR_ASK=1 then Packer will set -on-error to ask, causing the Packer
# build to pause when any error happens, instead of simply exiting. This is
# useful when debugging unknown issues logging into the remote machine via ssh.
ifeq (1,$(strip $(ON_ERROR_ASK)))
PACKER_FLAGS += -on-error=ask
endif

# We want the var files passed to Packer to have a specific order, because the
# precenence of the variables they contain depends on the order. Files listed
# later on the CLI have higher precedence. We want the common var files found in
# packer/config to be listed first, then the var files that specific to the
# provider, then any user-supplied var files so that a user can override what
# they need to.

# A list of variable files given to Packer to configure things like the versions
# of Kubernetes, CNI, and ContainerD to install. Any additional files from the
# environment are appended.
COMMON_NODE_VAR_FILES :=	packer/config/kubernetes.json \
					packer/config/cni.json \
					packer/config/containerd.json \
					packer/config/ansible-args.json \
					packer/config/goss-args.json \
					packer/config/common.json

COMMON_HAPROXY_VAR_FILES := packer/ova/packer-common.json \
					packer/config/ansible-args.json \
					packer/config/common.json

# Initialize a list of flags to pass to Packer. This includes any existing flags
# specified by PACKER_FLAGS, as well as prefixing the list with the variable
# files from COMMON_VAR_FILES, with each file prefixed by -var-file=.
#
# Any existing values from PACKER_FLAGS take precendence over variable files.
PACKER_NODE_FLAGS := $(foreach f,$(abspath $(COMMON_NODE_VAR_FILES)),-var-file="$(f)" ) \
				$(PACKER_FLAGS)
PACKER_HAPROXY_FLAGS := $(foreach f,$(abspath $(COMMON_HAPROXY_VAR_FILES)),-var-file="$(f)" ) \
				$(PACKER_FLAGS)
ABSOLUTE_PACKER_VAR_FILES := $(foreach f,$(abspath $(PACKER_VAR_FILES)),-var-file="$(f)" )

## --------------------------------------
## Platform and version combinations
## --------------------------------------
CENTOS_VERSIONS			:=	centos-7
PHOTON_VERSIONS			:=	photon-3
RHEL_VERSIONS				:=	rhel-7
UBUNTU_VERSIONS			:=	ubuntu-1804 ubuntu-2004

PLATFORMS_AND_VERSIONS	:=	$(CENTOS_VERSIONS) \
							$(PHOTON_VERSIONS) \
							$(RHEL_VERSIONS) \
							$(UBUNTU_VERSIONS)

NODE_OVA_LOCAL_BUILD_NAMES			:=	$(addprefix node-ova-local-,$(PLATFORMS_AND_VERSIONS))
NODE_OVA_LOCAL_VMX_BUILD_NAMES		:=	$(addprefix node-ova-local-vmx-,$(PLATFORMS_AND_VERSIONS))
NODE_OVA_LOCAL_BASE_BUILD_NAMES		:=	$(addprefix node-ova-local-base-,$(PLATFORMS_AND_VERSIONS))
NODE_OVA_ESX_BUILD_NAMES			:=	$(addprefix node-ova-esx-,$(PLATFORMS_AND_VERSIONS))
NODE_OVA_VSPHERE_BUILD_NAMES		:=	$(addprefix node-ova-vsphere-,$(PLATFORMS_AND_VERSIONS))
NODE_OVA_VSPHERE_BASE_BUILD_NAMES		:=	$(addprefix node-ova-vsphere-base-,$(PLATFORMS_AND_VERSIONS))
NODE_OVA_VSPHERE_CLONE_BUILD_NAMES		:=	$(addprefix node-ova-vsphere-clone-,$(PLATFORMS_AND_VERSIONS))
HAPROXY_OVA_LOCAL_BUILD_NAMES			:=	$(addprefix haproxy-ova-local-,$(PHOTON_VERSIONS))
HAPROXY_OVA_ESX_BUILD_NAMES			:=	$(addprefix haproxy-ova-esx-,$(PHOTON_VERSIONS))
HAPROXY_OVA_VSPHERE_BUILD_NAMES		:=	$(addprefix haproxy-ova-vsphere-,$(PHOTON_VERSIONS))

AMI_BUILD_NAMES			?=	ami-centos-7 ami-ubuntu-1804 ami-ubuntu-2004 ami-amazon-2
GCE_BUILD_NAMES			?=	gce-default
AZURE_BUILD_VHD_NAMES		?=	azure-vhd-ubuntu-1804 azure-vhd-ubuntu-2004 azure-vhd-centos-7
AZURE_BUILD_SIG_NAMES		?=	azure-sig-ubuntu-1804 azure-sig-ubuntu-2004 azure-sig-centos-7

DO_BUILD_NAMES 			?=	do-centos-7 do-ubuntu-1804 do-ubuntu-2004

QEMU_BUILD_NAMES			?=	qemu-ubuntu-1804 qemu-ubuntu-2004

## --------------------------------------
## Dynamic build targets
## --------------------------------------
NODE_OVA_LOCAL_BUILD_TARGETS	:= $(addprefix build-,$(NODE_OVA_LOCAL_BUILD_NAMES))
NODE_OVA_LOCAL_VMX_BUILD_TARGETS	:= $(addprefix build-,$(NODE_OVA_LOCAL_VMX_BUILD_NAMES))
NODE_OVA_LOCAL_BASE_BUILD_TARGETS	:= $(addprefix build-,$(NODE_OVA_LOCAL_BASE_BUILD_NAMES))
NODE_OVA_LOCAL_VALIDATE_TARGETS	:= $(addprefix validate-,$(NODE_OVA_LOCAL_BUILD_NAMES))
NODE_OVA_ESX_BUILD_TARGETS	:= $(addprefix build-,$(NODE_OVA_ESX_BUILD_NAMES))
NODE_OVA_VSPHERE_BUILD_TARGETS	:= $(addprefix build-,$(NODE_OVA_VSPHERE_BUILD_NAMES))
NODE_OVA_VSPHERE_BASE_BUILD_TARGETS	:= $(addprefix build-,$(NODE_OVA_VSPHERE_BASE_BUILD_NAMES))
NODE_OVA_VSPHERE_CLONE_BUILD_TARGETS	:= $(addprefix build-,$(NODE_OVA_VSPHERE_CLONE_BUILD_NAMES))
HAPROXY_OVA_LOCAL_BUILD_TARGETS	:= $(addprefix build-,$(HAPROXY_OVA_LOCAL_BUILD_NAMES))
HAPROXY_OVA_LOCAL_VALIDATE_TARGETS	:= $(addprefix validate-,$(HAPROXY_OVA_LOCAL_BUILD_NAMES))
HAPROXY_OVA_ESX_BUILD_TARGETS	:= $(addprefix build-,$(HAPROXY_OVA_ESX_BUILD_NAMES))
HAPROXY_OVA_VSPHERE_BUILD_TARGETS	:= $(addprefix build-,$(HAPROXY_OVA_VSPHERE_BUILD_NAMES))
AMI_BUILD_TARGETS	:= $(addprefix build-,$(AMI_BUILD_NAMES))
AMI_VALIDATE_TARGETS	:= $(addprefix validate-,$(AMI_BUILD_NAMES))
GCE_BUILD_TARGETS	:= $(addprefix build-,$(GCE_BUILD_NAMES))
GCE_VALIDATE_TARGETS	:= $(addprefix validate-,$(GCE_BUILD_NAMES))
AZURE_BUILD_VHD_TARGETS	:= $(addprefix build-,$(AZURE_BUILD_VHD_NAMES))
AZURE_VALIDATE_VHD_TARGETS	:= $(addprefix validate-,$(AZURE_BUILD_VHD_NAMES))
AZURE_BUILD_SIG_TARGETS	:= $(addprefix build-,$(AZURE_BUILD_SIG_NAMES))
AZURE_VALIDATE_SIG_TARGETS	:= $(addprefix validate-,$(AZURE_BUILD_SIG_NAMES))
DO_BUILD_TARGETS 	:= $(addprefix build-,$(DO_BUILD_NAMES))
DO_VALIDATE_TARGETS 	:= $(addprefix validate-,$(DO_BUILD_NAMES))
QEMU_BUILD_TARGETS	:= $(addprefix build-,$(QEMU_BUILD_NAMES))
QEMU_VALIDATE_TARGETS	:= $(addprefix validate-,$(QEMU_BUILD_NAMES))

.PHONY: $(NODE_OVA_LOCAL_BUILD_TARGETS)
$(NODE_OVA_LOCAL_BUILD_TARGETS): deps-ova
	packer build $(PACKER_NODE_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-node-ova-local-,,$@).json)" -except=esx -except=vsphere -only=vmware-iso $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-node.json

.PHONY: $(NODE_OVA_LOCAL_VALIDATE_TARGETS)
$(NODE_OVA_LOCAL_VALIDATE_TARGETS): deps-ova
	packer validate $(PACKER_NODE_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst validate-node-ova-local-,,$@).json)" -except=esx -except=vsphere -only=vmware-iso $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-node.json

.PHONY: $(NODE_OVA_LOCAL_VMX_BUILD_TARGETS)
$(NODE_OVA_LOCAL_VMX_BUILD_TARGETS): deps-ova
	packer build $(PACKER_NODE_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-node-ova-local-vmx-,,$@).json)" -var-file="packer/ova/vmx.json" -except=esx -except=vsphere -except=vmware-iso -only=vmware-vmx $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-node.json

.PHONY: $(NODE_OVA_LOCAL_BASE_BUILD_TARGETS)
$(NODE_OVA_LOCAL_BASE_BUILD_TARGETS): deps-ova
	packer build $(PACKER_NODE_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-node-ova-local-base-,,$@).json)" -except=esx -except=vsphere -except=vmware-iso -except=vmware-vmx -only=vmware-iso-base $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-node.json

.PHONY: $(NODE_OVA_ESX_BUILD_TARGETS)
$(NODE_OVA_ESX_BUILD_TARGETS): deps-ova
	packer build $(PACKER_NODE_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-node-ova-esx-,,$@).json)" -var-file="packer/ova/esx.json" -except=local -except=vsphere -only=vmware-iso $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-node.json

.PHONY: $(NODE_OVA_VSPHERE_BUILD_TARGETS)
$(NODE_OVA_VSPHERE_BUILD_TARGETS): deps-ova
	packer build $(PACKER_NODE_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-node-ova-vsphere-,,$@).json)" -var-file="packer/ova/vsphere.json" -except=esx -except=local -only=vsphere-iso $(ABSOLUTE_PACKER_VAR_FILES) -only=vsphere packer/ova/packer-node.json

.PHONY: $(NODE_OVA_VSPHERE_BASE_BUILD_TARGETS)
$(NODE_OVA_VSPHERE_BASE_BUILD_TARGETS): deps-ova
	packer build $(PACKER_NODE_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-node-ova-vsphere-base-,,$@).json)" -var-file="packer/ova/vsphere.json" -except=esx -except=local -except=manifest -except=vsphere -only=vsphere-iso-base $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-node.json

.PHONY: $(NODE_OVA_VSPHERE_CLONE_BUILD_TARGETS)
$(NODE_OVA_VSPHERE_CLONE_BUILD_TARGETS): deps-ova
	packer build $(PACKER_NODE_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-node-ova-vsphere-clone-,,$@).json)" -var-file="packer/ova/vsphere.json" -except=esx -except=local -only=vsphere-clone $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-node.json

.PHONY: $(HAPROXY_OVA_LOCAL_BUILD_TARGETS)
$(HAPROXY_OVA_LOCAL_BUILD_TARGETS): deps-ova
	packer build $(PACKER_HAPROXY_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-haproxy-ova-local-,,$@).json)" -except=esx -except=vsphere -only=vmware-iso $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-haproxy.json

.PHONY: $(HAPROXY_OVA_LOCAL_VALIDATE_TARGETS)
$(HAPROXY_OVA_LOCAL_VALIDATE_TARGETS): deps-ova
	packer validate $(PACKER_HAPROXY_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst validate-haproxy-ova-local-,,$@).json)" -except=esx -except=vsphere -only=vmware-iso $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-haproxy.json

.PHONY: $(HAPROXY_OVA_ESX_BUILD_TARGETS)
$(HAPROXY_OVA_ESX_BUILD_TARGETS): deps-ova
	packer build $(PACKER_HAPROXY_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-haproxy-ova-esx-,,$@).json)" -var-file="packer/ova/esx.json" -except=local -except=vsphere -only=vmware-iso $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-haproxy.json

.PHONY: $(HAPROXY_OVA_VSPHERE_BUILD_TARGETS)
$(HAPROXY_OVA_VSPHERE_BUILD_TARGETS): deps-ova
	packer build $(PACKER_HAPROXY_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-haproxy-ova-vsphere-,,$@).json)" -var-file="packer/ova/vsphere.json" -except=esx -except=local -only=vsphere-iso $(ABSOLUTE_PACKER_VAR_FILES) -only=vsphere packer/ova/packer-haproxy.json

.PHONY: $(AMI_BUILD_TARGETS)
$(AMI_BUILD_TARGETS): deps-ami
	packer build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/ami/$(subst build-ami-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/ami/packer.json

.PHONY: $(AMI_VALIDATE_TARGETS)
$(AMI_VALIDATE_TARGETS): deps-ami
	packer validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/ami/$(subst validate-ami-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/ami/packer.json

.PHONY: $(GCE_BUILD_TARGETS)
$(GCE_BUILD_TARGETS): deps-gce
	packer build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/gce/$(subst build-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/gce/packer.json

.PHONY: $(GCE_VALIDATE_TARGETS)
$(GCE_VALIDATE_TARGETS): deps-gce
	packer validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/gce/$(subst validate-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/gce/packer.json

.PHONY: $(AZURE_BUILD_VHD_TARGETS)
$(AZURE_BUILD_VHD_TARGETS): deps-azure
	. $(abspath packer/azure/scripts/init-vhd.sh) && packer build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/azure/azure-config.json)" -var-file="$(abspath packer/azure/azure-vhd.json)" -var-file="$(abspath packer/azure/$(subst build-azure-vhd-,,$@).json)" -only="$(subst build-azure-,,$@)" $(ABSOLUTE_PACKER_VAR_FILES) packer/azure/packer.json

.PHONY: $(AZURE_VALIDATE_VHD_TARGETS)
$(AZURE_VALIDATE_VHD_TARGETS): deps-azure
	packer validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/azure/azure-config.json)" -var-file="$(abspath packer/azure/azure-vhd.json)" -var-file="$(abspath packer/azure/$(subst validate-azure-vhd-,,$@).json)" -only="$(subst validate-azure-,,$@)" $(ABSOLUTE_PACKER_VAR_FILES) packer/azure/packer.json

.PHONY: $(AZURE_BUILD_SIG_TARGETS)
$(AZURE_BUILD_SIG_TARGETS): deps-azure
	. $(abspath packer/azure/scripts/init-sig.sh) && packer build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/azure/azure-config.json)" -var-file="$(abspath packer/azure/azure-sig.json)" -var-file="$(abspath packer/azure/$(subst build-azure-sig-,,$@).json)" -only="$(subst build-azure-,,$@)" $(ABSOLUTE_PACKER_VAR_FILES) packer/azure/packer.json

.PHONY: $(AZURE_VALIDATE_SIG_TARGETS)
$(AZURE_VALIDATE_SIG_TARGETS): deps-azure
	packer validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/azure/azure-config.json)" -var-file="$(abspath packer/azure/azure-sig.json)" -var-file="$(abspath packer/azure/$(subst validate-azure-sig-,,$@).json)" -only="$(subst validate-azure-,,$@)" $(ABSOLUTE_PACKER_VAR_FILES) packer/azure/packer.json

.PHONY: $(DO_BUILD_TARGETS)
$(DO_BUILD_TARGETS): deps-do
	packer build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/digitalocean/$(subst build-do-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/digitalocean/packer.json

.PHONY: $(DO_VALIDATE_TARGETS)
$(DO_VALIDATE_TARGETS): deps-do
	packer validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/digitalocean/$(subst validate-do-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/digitalocean/packer.json

.PHONY: $(QEMU_BUILD_TARGETS)
$(QEMU_BUILD_TARGETS): deps-qemu
	packer build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/qemu/$(subst build-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/qemu/packer.json

.PHONY: $(QEMU_VALIDATE_TARGETS)
$(QEMU_VALIDATE_TARGETS): deps-qemu
	packer validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/qemu/$(subst validate-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/qemu/packer.json

## --------------------------------------
## Dynamic clean targets
## --------------------------------------
NODE_OVA_LOCAL_CLEAN_TARGETS := $(subst build-,clean-,$(NODE_OVA_LOCAL_BUILD_TARGETS))
.PHONY: $(NODE_OVA_LOCAL_CLEAN_TARGETS)
$(NODE_OVA_LOCAL_CLEAN_TARGETS):
	rm -fr output/$(subst clean-node-ova-local-,,$@)-kube*

HAPROXY_OVA_LOCAL_CLEAN_TARGETS := $(subst build-,clean-,$(HAPROXY_OVA_LOCAL_BUILD_TARGETS))
.PHONY: $(HAPROXY_OVA_LOCAL_CLEAN_TARGETS)
$(HAPROXY_OVA_LOCAL_CLEAN_TARGETS):
	rm -fr output/$(subst clean-haproxy-ova-local-,,$@)-haproxy*

QEMU_CLEAN_TARGETS := $(subst build-,clean-,$(QEMU_BUILD_TARGETS))
.PHONY: $(QEMU_CLEAN_TARGETS)
$(QEMU_CLEAN_TARGETS):
	rm -fr output/$(subst clean-qemu-,,$@)-kube*

## --------------------------------------
## Document dynamic build targets
## --------------------------------------
##@ Builds
build-ami-amazon-2: ## Builds Amazon-2 Linux AMI
build-ami-centos-7: ## Builds CentOS 7 AMI
build-ami-ubuntu-1804: ## Builds Ubuntu 18.04 AMI
build-ami-ubuntu-2004: ## Builds Ubuntu 20.04 AMI
build-ami-all: $(AMI_BUILD_TARGETS) ## Builds all AMIs

build-azure-sig-ubuntu-1804: ## Builds Ubuntu 18.04 Azure managed image in Shared Image Gallery
build-azure-sig-ubuntu-2004: ## Builds Ubuntu 20.04 Azure managed image in Shared Image Gallery
build-azure-vhd-ubuntu-1804: ## Builds Ubuntu 18.04 VHD image for Azure
build-azure-vhd-ubuntu-2004: ## Builds Ubuntu 20.04 VHD image for Azure
build-azure-sig-centos-7: ## Builds CentOS 7 Azure managed image in Shared Image Gallery
build-azure-vhd-centos-7: ## Builds CentOS 7 VHD image for Azure
build-azure-all: $(AZURE_BUILD_VHD_TARGETS) ## Builds all Azure VHDs

build-do-ubuntu-1804: ## Builds Ubuntu 18.04 DigitalOcean Snapshot
build-do-ubuntu-2004: ## Builds Ubuntu 20.04 DigitalOcean Snapshot
build-do-centos-7: ## Builds Centos 7 DigitalOcean Snapshot
build-do-all: $(DO_BUILD_TARGETS) ## Builds all DigitalOcean Snapshot

build-gce-default: ## Builds the GCE default image

build-node-ova-local-centos-7: ## Builds CentOS 7 Node OVA w local hypervisor
build-node-ova-local-photon-3: ## Builds Photon 3 Node OVA w local hypervisor
build-node-ova-local-rhel-7: ## Builds RHEL 7 Node OVA w local hypervisor
build-node-ova-local-ubuntu-1804: ## Builds Ubuntu 18.04 Node OVA w local hypervisor
build-node-ova-local-ubuntu-2004: ## Builds Ubuntu 20.04 Node OVA w local hypervisor
build-node-ova-local-all: $(NODE_OVA_LOCAL_BUILD_TARGETS) ## Builds all Node OVAs w local hypervisor
build-haproxy-ova-local-photon-3: ## Builds Photon 3 HAProxy OVA w local hypervisor

build-node-ova-esx-centos-7: ## Builds CentOS 7 Node OVA w remote hypervisor
build-node-ova-esx-photon-3: ## Builds Photon 3 Node OVA w remote hypervisor
build-node-ova-esx-rhel-7: ## Builds RHEL 7 Node OVA w remote hypervisor
build-node-ova-esx-ubuntu-1804: ## Builds Ubuntu 18.04 Node OVA w remote hypervisor
build-node-ova-esx-ubuntu-2004: ## Builds Ubuntu 20.04 Node OVA w remote hypervisor
build-node-ova-esx-all: $(NODE_OVA_ESX_BUILD_TARGETS) ## Builds all Node OVAs w remote hypervisor
build-haproxy-ova-esx-photon-3: ## Builds Photon 3 HAProxy OVA w remote hypervisor

build-node-ova-vsphere-centos-7: ## Builds CentOS 7 Node OVA and template on vSphere
build-node-ova-vsphere-photon-3: ## Builds Photon 3 Node OVA and template on vSphere
build-node-ova-vsphere-rhel-7: ## Builds RHEL 7 Node OVA and template on vSphere
build-node-ova-vsphere-ubuntu-1804: ## Builds Ubuntu 18.04 Node OVA and template on vSphere
build-node-ova-vsphere-ubuntu-2004: ## Builds Ubuntu 20.04 Node OVA and template on vSphere
build-node-ova-vsphere-all: $(NODE_OVA_VSPHERE_BUILD_TARGETS) ## Builds all Node OVAs and templates on vSphere
build-haproxy-ova-vsphere-photon-3: ## Builds Photon 3 HAProxy OVA and template on vSphere

build-node-ova-vsphere-clone-centos-7: ## Builds CentOS 7 Node OVA and template on vSphere
build-node-ova-vsphere-clone-photon-3: ## Builds Photon 3 Node OVA and template on vSphere
build-node-ova-vsphere-clone-rhel-7: ## Builds RHEL 7 Node OVA and template on vSphere
build-node-ova-vsphere-clone-ubuntu-1804: ## Builds Ubuntu 18.04 Node OVA and template on vSphere
build-node-ova-vsphere-clone-ubuntu-2004: ## Builds Ubuntu 20.04 Node OVA and template on vSphere
build-node-ova-vsphere-clone-all: $(NODE_OVA_VSPHERE_CLONE_BUILD_TARGETS) ## Builds all Node OVAs and templates on vSphere

build-node-ova-vsphere-base-centos-7: ## Builds CentOS 7 Node OVA and template on vSphere
build-node-ova-vsphere-base-photon-3: ## Builds Photon 3 Node OVA and template on vSphere
build-node-ova-vsphere-base-rhel-7: ## Builds RHEL 7 Node OVA and template on vSphere
build-node-ova-vsphere-base-ubuntu-1804: ## Builds Ubuntu 18.04 Node OVA and template on vSphere
build-node-ova-vsphere-base-ubuntu-2004: ## Builds Ubuntu 20.04 Node OVA and template on vSphere
build-node-ova-vsphere-base-all: $(NODE_OVA_VSPHERE_BASE_BUILD_TARGETS) ## Builds all Node OVAs and templates on vSphere


build-node-ova-local-vmx-photon-3: ## Builds Photon 3 Node OVA from VMX file w local hypervisor
build-node-ova-local-vmx-centos-7: ## Builds Centos 7 Node OVA from VMX file w local hypervisor
build-node-ova-local-vmx-rhel-7: ## Builds RHEL 7 Node OVA from VMX file w local hypervisor
build-node-ova-local-vmx-ubuntu-1804: ## Builds Ubuntu 18.04 Node OVA from VMX file w local hypervisor
build-node-ova-local-vmx-ubuntu-2004: ## Builds Ubuntu 20.04 Node OVA from VMX file w local hypervisor

build-node-ova-local-base-photon-3: ## Builds Photon 3 Base Node OVA w local hypervisor
build-node-ova-local-base-centos-7: ## Builds Centos 7 Base Node OVA w local hypervisor
build-node-ova-local-base-rhel-7: ## Builds RHEL 7 Base Node OVA w local hypervisor
build-node-ova-local-base-ubuntu-1804: ## Builds Ubuntu 18.04 Base Node OVA w local hypervisor
build-node-ova-local-base-ubuntu-2004: ## Builds Ubuntu 20.04 Base Node OVA w local hypervisor

build-qemu-ubuntu-1804: ## Builds Ubuntu 18.04 QEMU image
build-qemu-ubuntu-2004: ## Builds Ubuntu 20.04 QEMU image
build-qemu-all: $(QEMU_BUILD_TARGETS) ## Builds all Qemu images

## --------------------------------------
## Document dynamic validate targets
## --------------------------------------
##@ Validate packer config
validate-ami-amazon-2: ## Validates Amazon-2 Linux AMI Packer config
validate-ami-centos-7: ## Validates CentOS 7 AMI Packer config
validate-ami-ubuntu-1804: ## Validates Ubuntu 18.04 AMI Packer config
validate-ami-ubuntu-2004: ## Validates Ubuntu 20.04 AMI Packer config
validate-ami-all: $(AMI_VALIDATE_TARGETS) ## Validates all AMIs Packer config

validate-azure-sig-centos-7: ## Validates CentOS 7 Azure managed image in Shared Image Gallery Packer config
validate-azure-sig-ubuntu-1804: ## Validates Ubuntu 18.04 Azure managed image in Shared Image Gallery Packer config
validate-azure-sig-ubuntu-2004: ## Validates Ubuntu 20.04 Azure managed image in Shared Image Gallery Packer config
validate-azure-vhd-centos-7: ## Validates CentOS 7 VHD image Azure Packer config
validate-azure-vhd-ubuntu-1804: ## Validates Ubuntu 18.04 VHD image Azure Packer config
validate-azure-vhd-ubuntu-2004: ## Validates Ubuntu 20.04 VHD image Azure Packer config
validate-azure-all: $(AZURE_VALIDATE_SIG_TARGETS) $(AZURE_VALIDATE_VHD_TARGETS) ## Validates all VHD images Azure Packer config

validate-do-ubuntu-1804: ## Valdiates Ubuntu 18.04 DigitalOcean Snapshot Packer config
validate-do-ubuntu-2004: ## Valdiates Ubuntu 20.04 DigitalOcean Snapshot Packer config
validate-do-centos-7: ## Valdiates Centos 7 DigitalOcean Snapshot Packer config
validate-do-all: $(DO_VALIDATE_TARGETS) ## Valdiates all DigitalOcean Snapshot Packer config

validate-gce-default: ## Validates the GCE default image packer config

validate-node-ova-local-centos-7: ## Validates CentOS 7 Node OVA Packer config w local hypervisor
validate-node-ova-local-photon-3: ## Validates Photon 3 Node OVA Packer config w local hypervisor
validate-node-ova-local-rhel-7: ## Validates RHEL 7 Node OVA Packer config w local hypervisor
validate-node-ova-local-ubuntu-1804: ## Validates Ubuntu 18.04 Node OVA Packer config w local hypervisor
validate-node-ova-local-ubuntu-2004: ## Validates Ubuntu 20.04 Node OVA Packer config w local hypervisor
validate-node-ova-local-all: $(NODE_OVA_LOCAL_VALIDATE_TARGETS) ## Validates all Node OVAs Packer config w local hypervisor
validate-haproxy-ova-local-photon-3: ## Validates Photon 3 HAProxy OVA Packer config w local hypervisor

validate-node-ova-local-vmx-photon-3: ## Validates Photon 3 Node OVA from VMX file w local hypervisor
validate-node-ova-local-vmx-centos-7: ## Validates Centos 7 Node OVA from VMX file w local hypervisor
validate-node-ova-local-vmx-rhel-7: ## Validates RHEL 7 Node OVA from VMX file w local hypervisor
validate-node-ova-local-vmx-ubuntu-1804: ## Validates Ubuntu 18.04 Node OVA from VMX file w local hypervisor
validate-node-ova-local-vmx-ubuntu-2004: ## Validates Ubuntu 20.04 Node OVA from VMX file w local hypervisor

validate-node-ova-local-base-photon-3: ## Validates Photon 3 Base Node OVA w local hypervisor
validate-node-ova-local-base-centos-7: ## Validates Centos 7 Base Node OVA w local hypervisor
validate-node-ova-local-base-rhel-7: ## Validates RHEL 7 Base Node OVA w local hypervisor
validate-node-ova-local-base-ubuntu-1804: ## Validates Ubuntu 18.04 Base Node OVA w local hypervisor
validate-node-ova-local-base-ubuntu-2004: ## Validates Ubuntu 20.04 Base Node OVA w local hypervisor

validate-qemu-ubuntu-1804: ## Validates Ubuntu 18.04 QEMU image packer config
validate-qemu-ubuntu-2004: ## Validates Ubuntu 20.04 QEMU image packer config
validate-qemu-all: $(QEMU_VALIDATE_TARGETS) ## Validates all Qemu Packer config

validate-all: validate-ami-all \
	validate-azure-all \
	validate-do-all \
	validate-gce-default \
	validate-node-ova-local-all \
	validate-haproxy-ova-local-photon-3 \
	validate-qemu-all
validate-all: ## Validates the Packer config for all build targets

## --------------------------------------
## Clean targets
## --------------------------------------
##@ Cleaning
.PHONY: clean
clean: ## Removes all image output directories and packer image cache
clean: $(NODE_OVA_LOCAL_CLEAN_TARGETS) $(HAPROXY_OVA_LOCAL_CLEAN_TARGETS) $(QEMU_CLEAN_TARGETS) clean-packer-cache

.PHONY: clean-ova
clean-ova: ## Removes all ova image output directories (see NOTE at top of help)
clean-ova: $(NODE_OVA_LOCAL_CLEAN_TARGETS) $(HAPROXY_OVA_LOCAL_CLEAN_TARGETS)

.PHONY: clean-qemu
clean-qemu: ## Removes all qemu image output directories (see NOTE at top of help)
clean-qemu: $(QEMU_CLEAN_TARGETS)

.PHONY: clean-packer-cache
clean-packer-cache: ## Removes the packer cache
clean-packer-cache:
	rm -fr packer_cache/*

## --------------------------------------
## Docker targets
## --------------------------------------
##@ Docker
.PHONY: docker-build
docker-build: ## Build the docker image for controller-manager
	docker build --pull --build-arg PASSED_IB_VERSION=$(IB_VERSION) --build-arg ARCH=$(ARCH) . -t $(CONTROLLER_IMG)-$(ARCH):$(TAG)

.PHONY: docker-push
docker-push: ## Push the docker image
	docker push $(CONTROLLER_IMG)-$(ARCH):$(TAG)

## --------------------------------------
## Test targets
## --------------------------------------
##@ Testing
.PHONY: test-azure
test-azure: ## Run the tests for Azure builders
	$(abspath packer/azure/scripts/ci-azure-e2e.sh)
