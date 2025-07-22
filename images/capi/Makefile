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

# This option is for running docker manifest command
export DOCKER_CLI_EXPERIMENTAL := enabled
export PATH := $(PATH):$(CURDIR)/.local/bin
# Defining the canonical location of the Packer binary which will be used for
# `packer init`, `packer build` and `packer validate` commands.
PACKER=$(shell if [ $$(command -v packer | grep -v sbin) ]; then echo $$(command -v packer); else echo $(CURDIR)/.local/bin/packer; fi)

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

GET_UBUNTU_DOTTED_SEMVER=$(strip \
	$(eval _UBUNTU_SEMVER:=$1) \
	$(eval _UBUNTU_SEMVER:=$(subst ubuntu-2004,ubuntu-20.04,$(_UBUNTU_SEMVER))) \
	$(eval _UBUNTU_SEMVER:=$(subst ubuntu-2204,ubuntu-22.04,$(_UBUNTU_SEMVER))) \
	$(eval _UBUNTU_SEMVER:=$(subst ubuntu-2404,ubuntu-24.04,$(_UBUNTU_SEMVER))) \
	$(_UBUNTU_SEMVER) \
)

## --------------------------------------
## Dependencies
## --------------------------------------
##@ Dependencies

.PHONY: deps
deps: ## Installs/checks all dependencies
deps: deps-ami deps-azure deps-do deps-gce deps-ova deps-openstack deps-qemu deps-raw deps-oci deps-osc deps-powervs deps-nutanix deps-hcloud

.PHONY: deps-common
deps-common: ## Installs/checks dependencies common to most builds
deps-common:
	hack/ensure-python.sh
	hack/ensure-ansible.sh
	hack/ensure-packer.sh

.PHONY: deps-ami
deps-ami: ## Installs/checks dependencies for AMI builds
deps-ami: deps-common
	hack/ensure-ansible-windows.sh
	$(PACKER) init packer/config.pkr.hcl

.PHONY: deps-azure
deps-azure: ## Installs/checks dependencies for Azure builds
deps-azure: deps-common
	hack/ensure-ansible-windows.sh
	hack/ensure-jq.sh
	hack/ensure-azure-cli.sh
	$(PACKER) init packer/config.pkr.hcl
	$(PACKER) init packer/azure/config.pkr.hcl

.PHONY: deps-do
deps-do: ## Installs/checks dependencies for DigitalOcean builds
deps-do: deps-common
	$(PACKER) init packer/config.pkr.hcl
	$(PACKER) init packer/digitalocean/config.pkr.hcl

.PHONY: deps-osc
deps-osc: ## Installs/checks dependencies for Outscale builds
deps-osc: deps-common
	$(PACKER) init packer/config.pkr.hcl
	$(PACKER) init packer/outscale/config.pkr.hcl

.PHONY: deps-gce
deps-gce: ## Installs/checks dependencies for GCE builds
deps-gce: deps-common
	$(PACKER) init packer/config.pkr.hcl
	$(PACKER) init packer/gce/config.pkr.hcl

.PHONY: deps-ova
deps-ova: ## Installs/checks dependencies for OVA builds
deps-ova: deps-common
	hack/ensure-ansible-windows.sh
	hack/ensure-ovftool.sh
	$(PACKER) init packer/config.pkr.hcl
	$(PACKER) init packer/ova/config.pkr.hcl

.PHONY: deps-openstack
deps-openstack: ## Installs/checks dependencies for OpenStack builds
deps-openstack: deps-common
	hack/ensure-s3.sh
	$(PACKER) init packer/config.pkr.hcl
	$(PACKER) init packer/openstack/config.pkr.hcl

.PHONY: deps-qemu
deps-qemu: ## Installs/checks dependencies for QEMU builds
deps-qemu: deps-common
	$(PACKER) init packer/config.pkr.hcl
	$(PACKER) init packer/qemu/config.pkr.hcl

.PHONY: deps-raw
deps-raw: ## Installs/checks dependencies for RAW builds
deps-raw: deps-common
	$(PACKER) init packer/config.pkr.hcl

.PHONY: deps-oci
deps-oci: ## Installs/checks dependencies for OCI builds
deps-oci: deps-common
	hack/ensure-ansible-windows.sh
	$(PACKER) init packer/config.pkr.hcl
	$(PACKER) init packer/oci/config.pkr.hcl

.PHONY: deps-powervs
deps-powervs: ## Installs/checks dependencies for PowerVS builds
deps-powervs: deps-common
	hack/ensure-powervs.sh
	$(PACKER) init packer/config.pkr.hcl

.PHONY: deps-ignition
deps-ignition: ## Installs/checks dependencies for generating Ignition files
deps-ignition:
	hack/ensure-jq.sh
	hack/ensure-ct.sh

.PHONY: deps-nutanix
deps-nutanix: ## Installs/checks dependencies for Nutanix builds
deps-nutanix: deps-common
	$(PACKER) init packer/config.pkr.hcl
	$(PACKER) init packer/nutanix/config.pkr.hcl

.PHONY: deps-release
deps-release: ## Installs/checks dependencies for project releases
	hack/ensure-go.sh
	hack/ensure-jq.sh
	hack/ensure-kpromo.sh
	hack/ensure-yq.sh

.PHONY: deps-hcloud
deps-hcloud: ## Installs/checks dependencies for Hetznercloud builds
deps-hcloud: deps-common
	$(PACKER) init packer/config.pkr.hcl
	$(PACKER) init packer/hcloud/config.pkr.hcl

.PHONY: deps-huaweicloud
deps-huaweicloud: ## Installs/checks dependencies for HuaweiCloud builds
deps-huaweicloud: deps-common
	$(PACKER) init packer/config.pkr.hcl
	$(PACKER) init packer/huaweicloud/config.pkr.hcl

.PHONY: deps-proxmox
deps-proxmox: ## Installs/checks dependencies for Proxmox builds
deps-proxmox: deps-common
	$(PACKER) init packer/config.pkr.hcl
	$(PACKER) init packer/proxmox/config.pkr.hcl

.PHONY: deps-lint
deps-lint: ## Installs/checks dependencies for image-builder code linting
deps-lint: deps-common
	hack/ensure-ansible-windows.sh
	hack/ensure-ansible-lint.sh
	hack/ensure-shellcheck.sh

.PHONY: deps-vultr
deps-vultr: ## Installs/checks dependencies for Vultr builds
deps-vultr: deps-common
	$(PACKER) init packer/config.pkr.hcl
	$(PACKER) init packer/vultr/config.pkr.hcl

.PHONY: deps-scaleway
deps-scaleway: ## Installs/checks dependencies for Scaleway builds
deps-scaleway: deps-common
	$(PACKER) init packer/config.pkr.hcl
	$(PACKER) init packer/scaleway/config.pkr.hcl

## --------------------------------------
## Packer Configuration
## --------------------------------------

.PHONY: set-ssh-password
set-ssh-password:
	hack/set-ssh-password.sh

## --------------------------------------
## Container variables
## --------------------------------------
REGISTRY ?= gcr.io/$(or $(shell gcloud config get-value project),scl-image-builder)
STAGING_REGISTRY := gcr.io/k8s-staging-scl-image-builder
IMAGE_NAME ?= cluster-node-image-builder
CONTROLLER_IMG ?= $(REGISTRY)/$(IMAGE_NAME)
TAG ?= dev
ARCH ?= amd64
BASE_IMAGE ?= docker.io/library/ubuntu:jammy
BUILDKIT_SYNTAX ?= docker/dockerfile:1.14

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

# ssh_private_key_file and ssh_public_key are needed to pass ssh keypair
# from its host to the packer guest machine, so boot managers like ignition
# could make use of the key in its config.
# SSH_PRIVATE_KEY_FILE is name of the file that contains the private key.
# SSH_PUBLIC_KEY_FILE is name of the file that contains the public key.
ifneq (,$(strip $(SSH_PRIVATE_KEY_FILE)))
PACKER_FLAGS += -var ssh_private_key_file="$(SSH_PRIVATE_KEY_FILE)"
endif

ifneq (,$(strip $(SSH_PUBLIC_KEY_FILE)))
PACKER_FLAGS += -var ssh_public_key="$(shell cat ${SSH_PUBLIC_KEY_FILE})"
endif

# Since OpenSSH 9.0+ 'scp' uses SFTP protocol instead of legacy SCP protocol, which causes building errors like:
#
# bash: line 1: /usr/lib/sftp-server: No such file or directory\nscp: Connection closed\r\n""
#
# However, -O option is not available in older OpenSSH version, so we cannot always set it as an option to use.
# To provide better out-of-the-box experience for users with newer versions of OpenSSH, we conditionally ensure
# -O is used when used OpenSSH version requires it.
#
# See https://github.com/kubernetes-sigs/image-builder/issues/859 and
# https://github.com/hashicorp/packer-plugin-ansible/issues/100 for more details.
ifeq ($(shell test $$(ssh -V 2>&1 | cut -d _ -f2 | cut -d . -f1) -ge 9; echo $$?),0)
	# Use ?= to retain possible existing value of environment variable. If it is already declared, we assume user to be
	# aware of OpenSSH version they use and it is up to the user to specify "-O" option as well if needed.
  export ANSIBLE_SCP_EXTRA_ARGS ?= "-O"
endif

# If DEBUG=1 then Packer will set -debug, enabling debug mode for builds, providing
# more verbose logging
ifeq (1,$(strip $(DEBUG)))
PACKER_FLAGS += -debug
endif

# We want the var files passed to Packer to have a specific order, because the
# precedence of the variables they contain depends on the order. Files listed
# later on the CLI have higher precedence. We want the common var files found in
# packer/config to be listed first, then the var files that specific to the
# provider, then any user-supplied var files so that a user can override what
# they need to.

# A list of variable files given to Packer to configure things like the versions
# of Kubernetes, CNI, and ContainerD to install. Any additional files from the
# environment are appended.
COMMON_NODE_VAR_FILES := packer/config/kubernetes.json \
					packer/config/cni.json \
					packer/config/containerd.json \
					packer/config/wasm-shims.json \
					packer/config/ansible-args.json \
					packer/config/goss-args.json \
					packer/config/common.json \
					packer/config/additional_components.json \
					packer/config/ecr_credential_provider.json

COMMON_WINDOWS_VAR_FILES :=	packer/config/kubernetes.json \
					packer/config/windows/kubernetes.json \
					packer/config/containerd.json \
					packer/config/windows/containerd.json \
					packer/config/windows/ansible-args-windows.json \
					packer/config/common.json \
					packer/config/windows/common.json \
					packer/config/windows/cloudbase-init.json \
					packer/config/goss-args.json \
					packer/config/additional_components.json \
					packer/config/ecr_credential_provider.json

COMMON_POWERVS_VAR_FILES := packer/config/kubernetes.json \
					packer/config/ppc64le/kubernetes.json \
					packer/config/cni.json \
					packer/config/ppc64le/cni.json \
					packer/config/containerd.json \
					packer/config/wasm-shims.json \
					packer/config/ppc64le/containerd.json \
					packer/config/ansible-args.json \
					packer/config/goss-args.json \
					packer/config/common.json \
					packer/config/ppc64le/common.json \
					packer/config/additional_components.json \
					packer/config/ecr_credential_provider.json

# Initialize a list of flags to pass to Packer. This includes any existing flags
# specified by PACKER_FLAGS, as well as prefixing the list with the variable
# files from COMMON_VAR_FILES, with each file prefixed by -var-file=.
#
# Any existing values from PACKER_FLAGS take precendence over variable files.
PACKER_NODE_FLAGS := $(foreach f,$(abspath $(COMMON_NODE_VAR_FILES)),-var-file="$(f)" ) \
				$(PACKER_FLAGS)
ABSOLUTE_PACKER_VAR_FILES := $(foreach f,$(abspath $(PACKER_VAR_FILES)),-var-file="$(f)" )
PACKER_WINDOWS_NODE_FLAGS := $(foreach f,$(abspath $(COMMON_WINDOWS_VAR_FILES)),-var-file="$(f)" ) \
				$(PACKER_FLAGS)
PACKER_POWERVS_NODE_FLAGS := $(foreach f,$(abspath $(COMMON_POWERVS_VAR_FILES)),-var-file="$(f)" ) \
				$(PACKER_FLAGS)

## --------------------------------------
## Platform and version combinations
## --------------------------------------
FLATCAR_VERSIONS		:=	flatcar
PHOTON_VERSIONS			:=	photon-4 photon-5
RHEL_VERSIONS			:=	rhel-7 rhel-8 rhel-9
ROCKYLINUX_VERSIONS		:=  rockylinux-8 rockylinux-9
UBUNTU_VERSIONS			:=	ubuntu-2004 ubuntu-2004-efi ubuntu-2204 ubuntu-2204-efi ubuntu-2404 ubuntu-2404-efi
WINDOWS_VERSIONS		:=	windows-2019 windows-2019-efi windows-2022 windows-2022-efi

# Set Flatcar Container Linux channel and version if not supplied
FLATCAR_CHANNEL ?= stable
FLATCAR_VERSION ?= current
ifeq ($(FLATCAR_VERSION),current)
override FLATCAR_VERSION := $(shell hack/image-grok-latest-flatcar-version.sh $(FLATCAR_CHANNEL))
endif

export FLATCAR_CHANNEL FLATCAR_VERSION

PLATFORMS_AND_VERSIONS	:=	$(PHOTON_VERSIONS) \
							$(RHEL_VERSIONS) \
							$(ROCKYLINUX_VERSIONS) \
							$(UBUNTU_VERSIONS) \
							$(FLATCAR_VERSIONS) \
							$(WINDOWS_VERSIONS)

NODE_OVA_LOCAL_BUILD_NAMES			:=	$(addprefix node-ova-local-,$(PLATFORMS_AND_VERSIONS))
NODE_OVA_LOCAL_VMX_BUILD_NAMES		:=	$(addprefix node-ova-local-vmx-,$(PLATFORMS_AND_VERSIONS))
NODE_OVA_LOCAL_BASE_BUILD_NAMES		:=	$(addprefix node-ova-local-base-,$(PLATFORMS_AND_VERSIONS))
NODE_OVA_VSPHERE_BUILD_NAMES		:=	$(addprefix node-ova-vsphere-,$(PLATFORMS_AND_VERSIONS))
NODE_OVA_VSPHERE_BASE_BUILD_NAMES		:=	$(addprefix node-ova-vsphere-base-,$(PLATFORMS_AND_VERSIONS))
NODE_OVA_VSPHERE_CLONE_BUILD_NAMES		:=	$(addprefix node-ova-vsphere-clone-,$(PLATFORMS_AND_VERSIONS))

AMI_BUILD_NAMES			   ?= ami-ubuntu-2004 ami-ubuntu-2204 ami-ubuntu-2404 ami-amazon-2 ami-amazon-2023 ami-flatcar ami-flatcar-arm64 ami-windows-2019 ami-rockylinux-8 ami-rhel-8
HUAWEICLOUD_BUILD_NAMES ?= huaweicloud-ubuntu-2204
GCE_BUILD_NAMES			   ?= gce-ubuntu-2204 gce-ubuntu-2404 gce-rhel-8

# Make needs these lists to be space delimited, no quotes
VHD_TARGETS := $(shell grep VHD_TARGETS azure_targets.sh | sed 's/VHD_TARGETS=//' | tr -d \")
SIG_TARGETS := $(shell grep SIG_TARGETS azure_targets.sh | sed 's/SIG_TARGETS=//' | tr -d \")
SIG_GEN2_TARGETS := $(shell grep SIG_GEN2_TARGETS azure_targets.sh | sed 's/SIG_GEN2_TARGETS=//' | tr -d \")
SIG_CVM_TARGETS := $(shell grep SIG_CVM_TARGETS azure_targets.sh | sed 's/SIG_CVM_TARGETS=//' | tr -d \")
AZURE_BUILD_VHD_NAMES	   ?= $(addprefix azure-vhd-,$(VHD_TARGETS))
AZURE_BUILD_SIG_NAMES	   ?= $(addprefix azure-sig-,$(SIG_TARGETS))
AZURE_BUILD_SIG_GEN2_NAMES ?= $(addsuffix -gen2,$(addprefix azure-sig-,$(SIG_GEN2_TARGETS)))
AZURE_BUILD_SIG_CVM_NAMES ?= $(addsuffix -cvm,$(addprefix azure-sig-,$(SIG_CVM_TARGETS)))

OCI_BUILD_NAMES				?= oci-ubuntu-2004 oci-ubuntu-2204 oci-oracle-linux-8 oci-oracle-linux-9 oci-windows-2019 oci-windows-2022

DO_BUILD_NAMES 				?=	do-ubuntu-2004 do-ubuntu-2204 do-ubuntu-2404

OPENSTACK_BUILD_NAMES		?=	openstack-ubuntu-2004 openstack-ubuntu-2204 openstack-ubuntu-2404 openstack-flatcar openstack-rockylinux-9

OSC_BUILD_NAMES 			?=	osc-ubuntu-2004 osc-ubuntu-2204 osc-ubuntu-2404

QEMU_BUILD_NAMES			?=	qemu-ubuntu-2004 qemu-ubuntu-2204 qemu-ubuntu-2204-cloudimg qemu-ubuntu-2404 qemu-ubuntu-2404-efi qemu-ubuntu-2204-efi qemu-centos-9 qemu-ubuntu-2004-efi qemu-rhel-8 qemu-rhel-9 qemu-rockylinux-8 qemu-rockylinux-8-cloudimg qemu-rockylinux-9 qemu-rockylinux-9-cloudimg qemu-flatcar

QEMU_KUBEVIRT_BUILD_NAMES	:= $(addprefix kubevirt-,$(QEMU_BUILD_NAMES))

RAW_BUILD_NAMES				?=	raw-ubuntu-2004 raw-ubuntu-2004-efi raw-ubuntu-2204 raw-ubuntu-2204-efi raw-ubuntu-2404 raw-ubuntu-2404-efi raw-flatcar raw-rhel-8 raw-rhel-9 raw-rhel-9-efi

POWERVS_BUILD_NAMES         ?= powervs-centos-8 powervs-centos-9

NUTANIX_BUILD_NAMES ?= nutanix-ubuntu-2004 nutanix-ubuntu-2204 nutanix-ubuntu-2404 nutanix-rhel-8 nutanix-rhel-9 nutanix-rockylinux-8 nutanix-rockylinux-9 nutanix-flatcar nutanix-windows-2022

HCLOUD_BUILD_NAMES ?= hcloud-ubuntu-2004 hcloud-ubuntu-2204 hcloud-ubuntu-2404 hcloud-rockylinux-8 hcloud-rockylinux-9 hcloud-flatcar hcloud-flatcar-arm64

PROXMOX_BUILD_NAMES 		?= proxmox-ubuntu-2204 proxmox-ubuntu-2404 proxmox-ubuntu-2404-efi proxmox-rockylinux-9 proxmox-flatcar

VULTR_BUILD_NAMES 				?=	vultr-ubuntu-2204

MAAS_BUILD_NAMES 			?= maas-ubuntu-2204-efi maas-ubuntu-2404-efi

SCALEWAY_BUILD_NAMES 				?=	scaleway-rockylinux-9 scaleway-ubuntu-2204 scaleway-ubuntu-2404

## --------------------------------------
## Dynamic build targets
## --------------------------------------
NODE_OVA_LOCAL_BUILD_TARGETS	:= $(addprefix build-,$(NODE_OVA_LOCAL_BUILD_NAMES))
NODE_OVA_LOCAL_VMX_BUILD_TARGETS	:= $(addprefix build-,$(NODE_OVA_LOCAL_VMX_BUILD_NAMES))
NODE_OVA_LOCAL_BASE_BUILD_TARGETS	:= $(addprefix build-,$(NODE_OVA_LOCAL_BASE_BUILD_NAMES))
NODE_OVA_LOCAL_VALIDATE_TARGETS	:= $(addprefix validate-,$(NODE_OVA_LOCAL_BUILD_NAMES))
NODE_OVA_VSPHERE_BUILD_TARGETS	:= $(addprefix build-,$(NODE_OVA_VSPHERE_BUILD_NAMES))
NODE_OVA_VSPHERE_BASE_BUILD_TARGETS	:= $(addprefix build-,$(NODE_OVA_VSPHERE_BASE_BUILD_NAMES))
NODE_OVA_VSPHERE_CLONE_BUILD_TARGETS	:= $(addprefix build-,$(NODE_OVA_VSPHERE_CLONE_BUILD_NAMES))
AMI_BUILD_TARGETS	:= $(addprefix build-,$(AMI_BUILD_NAMES))
AMI_VALIDATE_TARGETS	:= $(addprefix validate-,$(AMI_BUILD_NAMES))
GCE_BUILD_TARGETS	:= $(addprefix build-,$(GCE_BUILD_NAMES))
GCE_VALIDATE_TARGETS	:= $(addprefix validate-,$(GCE_BUILD_NAMES))
AZURE_BUILD_VHD_TARGETS	:= $(addprefix build-,$(AZURE_BUILD_VHD_NAMES))
AZURE_VALIDATE_VHD_TARGETS	:= $(addprefix validate-,$(AZURE_BUILD_VHD_NAMES))
AZURE_BUILD_SIG_TARGETS	:= $(addprefix build-,$(AZURE_BUILD_SIG_NAMES))
AZURE_BUILD_SIG_GEN2_TARGETS	:= $(addprefix build-,$(AZURE_BUILD_SIG_GEN2_NAMES))
AZURE_BUILD_SIG_CVM_TARGETS	:= $(addprefix build-,$(AZURE_BUILD_SIG_CVM_NAMES))
AZURE_VALIDATE_SIG_TARGETS	:= $(addprefix validate-,$(AZURE_BUILD_SIG_NAMES))
AZURE_VALIDATE_SIG_GEN2_TARGETS	:= $(addprefix validate-,$(AZURE_BUILD_SIG_GEN2_NAMES))
AZURE_VALIDATE_SIG_CVM_TARGETS	:= $(addprefix validate-,$(AZURE_BUILD_SIG_CVM_NAMES))
DO_BUILD_TARGETS 	:= $(addprefix build-,$(DO_BUILD_NAMES))
DO_VALIDATE_TARGETS 	:= $(addprefix validate-,$(DO_BUILD_NAMES))
OPENSTACK_BUILD_TARGETS	:= $(addprefix build-,$(OPENSTACK_BUILD_NAMES))
HUAWEICLOUD_BUILD_TARGETS 	:= $(addprefix build-,$(HUAWEICLOUD_BUILD_NAMES))
HUAWEICLOUD_VALIDATE_TARGETS	:= $(addprefix validate-,$(HUAWEICLOUD_BUILD_NAMES))
OPENSTACK_VALIDATE_TARGETS := $(addprefix validate-,$(OPENSTACK_BUILD_NAMES))
QEMU_BUILD_TARGETS	:= $(addprefix build-,$(QEMU_BUILD_NAMES))
QEMU_VALIDATE_TARGETS	:= $(addprefix validate-,$(QEMU_BUILD_NAMES))
QEMU_KUBEVIRT_BUILD_TARGETS := $(addprefix build-,$(QEMU_KUBEVIRT_BUILD_NAMES))
QEMU_KUBEVIRT_VALIDATE_TARGETS := $(addprefix validate-,$(QEMU_KUBEVIRT_BUILD_NAMES))
RAW_BUILD_TARGETS      := $(addprefix build-,$(RAW_BUILD_NAMES))
RAW_VALIDATE_TARGETS   := $(addprefix validate-,$(RAW_BUILD_NAMES))
OCI_BUILD_TARGETS	:= $(addprefix build-,$(OCI_BUILD_NAMES))
OCI_VALIDATE_TARGETS	:= $(addprefix validate-,$(OCI_BUILD_NAMES))
OSC_BUILD_TARGETS 	:= $(addprefix build-,$(OSC_BUILD_NAMES))
OSC_VALIDATE_TARGETS       := $(addprefix validate-,$(OSC_BUILD_NAMES))
POWERVS_BUILD_TARGETS      := $(addprefix build-,$(POWERVS_BUILD_NAMES))
POWERVS_VALIDATE_TARGETS   := $(addprefix validate-,$(POWERVS_BUILD_NAMES))
NUTANIX_BUILD_TARGETS		:= $(addprefix build-,$(NUTANIX_BUILD_NAMES))
NUTANIX_VALIDATE_TARGETS	:= $(addprefix validate-,$(NUTANIX_BUILD_NAMES))
HCLOUD_BUILD_TARGETS		:= $(addprefix build-,$(HCLOUD_BUILD_NAMES))
HCLOUD_VALIDATE_TARGETS		:= $(addprefix validate-,$(HCLOUD_BUILD_NAMES))
PROXMOX_BUILD_TARGETS		:= $(addprefix build-,$(PROXMOX_BUILD_NAMES))
PROXMOX_VALIDATE_TARGETS	:= $(addprefix validate-,$(PROXMOX_BUILD_NAMES))
VULTR_BUILD_TARGETS 	:= $(addprefix build-,$(VULTR_BUILD_NAMES))
VULTR_VALIDATE_TARGETS 	:= $(addprefix validate-,$(VULTR_BUILD_NAMES))
MAAS_BUILD_TARGETS 	:= $(addprefix build-,$(MAAS_BUILD_NAMES))
MAAS_VALIDATE_TARGETS 	:= $(addprefix validate-,$(MAAS_BUILD_NAMES))
SCALEWAY_BUILD_TARGETS		:= $(addprefix build-,$(SCALEWAY_BUILD_NAMES))
SCALEWAY_VALIDATE_TARGETS	:= $(addprefix validate-,$(SCALEWAY_BUILD_NAMES))

.PHONY: $(NODE_OVA_LOCAL_BUILD_TARGETS)
$(NODE_OVA_LOCAL_BUILD_TARGETS): deps-ova set-ssh-password
    # This uses a packer file builder to input unattend variables into a JSON file to be consumed by the python script before running the vmware-iso provisioner
	$(if $(findstring windows,$@),$(PACKER) build $(PACKER_WINDOWS_NODE_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-node-ova-local-,,$@).json)" -only=file $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-windows.json,)
	$(if $(findstring windows,$@),hack/windows-unattend.py --unattend-file='./packer/ova/windows/$(subst build-node-ova-local-,,$@)/autounattend.xml',)
	$(PACKER) build $(if $(findstring windows,$@),$(PACKER_WINDOWS_NODE_FLAGS),$(PACKER_NODE_FLAGS)) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-node-ova-local-,,$@).json)" -except=vsphere -only=vmware-iso $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-$(if $(findstring windows,$@),windows,node).json

.PHONY: $(NODE_OVA_LOCAL_VALIDATE_TARGETS)
$(NODE_OVA_LOCAL_VALIDATE_TARGETS): deps-ova set-ssh-password
	$(PACKER) validate $(if $(findstring windows,$@),$(PACKER_WINDOWS_NODE_FLAGS),$(PACKER_NODE_FLAGS)) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst validate-node-ova-local-,,$@).json)" -except=vsphere -only=vmware-iso $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-$(if $(findstring windows,$@),windows,node).json

.PHONY: $(NODE_OVA_LOCAL_VMX_BUILD_TARGETS)
$(NODE_OVA_LOCAL_VMX_BUILD_TARGETS): deps-ova set-ssh-password
	$(PACKER) build $(PACKER_NODE_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-node-ova-local-vmx-,,$@).json)" -var-file="packer/ova/vmx.json" -except=vsphere -except=vmware-iso -only=vmware-vmx $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-node.json

.PHONY: $(NODE_OVA_LOCAL_BASE_BUILD_TARGETS)
$(NODE_OVA_LOCAL_BASE_BUILD_TARGETS): deps-ova set-ssh-password
	$(PACKER) build $(PACKER_NODE_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-node-ova-local-base-,,$@).json)"  -except=vsphere -except=vmware-iso -except=vmware-vmx -only=vmware-iso-base $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-node.json

.PHONY: $(NODE_OVA_VSPHERE_BUILD_TARGETS)
$(NODE_OVA_VSPHERE_BUILD_TARGETS): deps-ova set-ssh-password
    # This uses a packer file builder to input unattend variables into a JSON file to be consumed by the python script before running the vsphere provisioner
	$(if $(findstring windows,$@),$(PACKER) build $(PACKER_WINDOWS_NODE_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-node-ova-vsphere-,,$@).json)" -only=file $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-windows.json,)
	$(if $(findstring windows,$@),hack/windows-unattend.py --unattend-file='./packer/ova/windows/$(subst build-node-ova-vsphere-,,$@)/autounattend.xml',)
	$(PACKER) build $(if $(findstring windows,$@),$(PACKER_WINDOWS_NODE_FLAGS),$(PACKER_NODE_FLAGS))  -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-node-ova-vsphere-,,$@).json)" -var-file="packer/ova/vsphere.json"  -except=local -only=vsphere-iso $(ABSOLUTE_PACKER_VAR_FILES) -only=vsphere packer/ova/packer-$(if $(findstring windows,$@),windows,node).json

.PHONY: $(NODE_OVA_VSPHERE_BASE_BUILD_TARGETS)
$(NODE_OVA_VSPHERE_BASE_BUILD_TARGETS): deps-ova set-ssh-password
	$(PACKER) build $(PACKER_NODE_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-node-ova-vsphere-base-,,$@).json)" -var-file="packer/ova/vsphere.json" -except=local -except=manifest -except=vsphere -only=vsphere-iso-base $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-node.json

.PHONY: $(NODE_OVA_VSPHERE_CLONE_BUILD_TARGETS)
$(NODE_OVA_VSPHERE_CLONE_BUILD_TARGETS): deps-ova set-ssh-password
	$(PACKER) build $(PACKER_NODE_FLAGS) -var-file="packer/ova/packer-common.json" -var-file="$(abspath packer/ova/$(subst build-node-ova-vsphere-clone-,,$@).json)" -var-file="packer/ova/vsphere.json" -except=local -only=vsphere-clone $(ABSOLUTE_PACKER_VAR_FILES) packer/ova/packer-node.json

.PHONY: $(AMI_BUILD_TARGETS)
$(AMI_BUILD_TARGETS): deps-ami
	$(PACKER) build $(if $(findstring windows,$@),$(PACKER_WINDOWS_NODE_FLAGS),$(PACKER_NODE_FLAGS)) -var-file="$(abspath packer/ami/$(subst build-ami-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/ami/packer$(if $(findstring windows,$@),-windows,).json

.PHONY: $(AMI_VALIDATE_TARGETS)
$(AMI_VALIDATE_TARGETS): deps-ami
	$(PACKER) validate $(if $(findstring windows,$@),$(PACKER_WINDOWS_NODE_FLAGS),$(PACKER_NODE_FLAGS)) -var-file="$(abspath packer/ami/$(subst validate-ami-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/ami/packer$(if $(findstring windows,$@),-windows,).json

.PHONY: $(GCE_BUILD_TARGETS)
$(GCE_BUILD_TARGETS): deps-gce
	$(PACKER) build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/gce/$(subst build-gce-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/gce/packer.json

.PHONY: $(GCE_VALIDATE_TARGETS)
$(GCE_VALIDATE_TARGETS): deps-gce
	$(PACKER) validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/gce/$(subst validate-gce-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/gce/packer.json

.PHONY: $(AZURE_BUILD_VHD_TARGETS)
$(AZURE_BUILD_VHD_TARGETS): deps-azure
	. $(abspath packer/azure/scripts/init-vhd.sh) && $(PACKER) build $(if $(findstring windows,$@),$(PACKER_WINDOWS_NODE_FLAGS),$(PACKER_NODE_FLAGS)) -var-file="$(abspath packer/azure/azure-config.json)" -var-file="$(abspath packer/azure/azure-vhd.json)" -var-file="$(abspath packer/azure/$(subst build-azure-vhd-,,$@).json)" -only="$(subst build-azure-,,$@)" $(ABSOLUTE_PACKER_VAR_FILES) packer/azure/packer$(findstring -windows,$@).json

.PHONY: $(AZURE_VALIDATE_VHD_TARGETS)
$(AZURE_VALIDATE_VHD_TARGETS): deps-azure
	$(PACKER) validate $(if $(findstring windows,$@),$(PACKER_WINDOWS_NODE_FLAGS),$(PACKER_NODE_FLAGS)) -var-file="$(abspath packer/azure/azure-config.json)" -var-file="$(abspath packer/azure/azure-vhd.json)" -var-file="$(abspath packer/azure/$(subst validate-azure-vhd-,,$@).json)" -only="$(subst validate-azure-,,$@)" $(ABSOLUTE_PACKER_VAR_FILES) packer/azure/packer$(findstring -windows,$@).json

.PHONY: $(AZURE_BUILD_SIG_TARGETS)
$(AZURE_BUILD_SIG_TARGETS): deps-azure
	. $(abspath packer/azure/scripts/init-sig.sh) $(subst build-azure-sig-,,$@) && $(PACKER) build $(if $(findstring windows,$@),$(PACKER_WINDOWS_NODE_FLAGS),$(PACKER_NODE_FLAGS)) -var-file="$(abspath packer/azure/azure-config.json)" -var-file="$(abspath packer/azure/azure-sig.json)" -var-file="$(abspath packer/azure/$(subst build-azure-sig-,,$@).json)" -only="$(subst build-azure-,,$@)" $(ABSOLUTE_PACKER_VAR_FILES) packer/azure/packer$(findstring -windows,$@).json

.PHONY: $(AZURE_BUILD_SIG_GEN2_TARGETS)
$(AZURE_BUILD_SIG_GEN2_TARGETS): deps-azure
	. $(abspath packer/azure/scripts/init-sig.sh) $(subst build-azure-sig-,,$@) && $(PACKER) build $(if $(findstring windows,$@),$(PACKER_WINDOWS_NODE_FLAGS),$(PACKER_NODE_FLAGS)) -var-file="$(abspath packer/azure/azure-config.json)" -var-file="$(abspath packer/azure/azure-sig-gen2.json)" -var-file="$(abspath packer/azure/$(subst build-azure-sig-,,$@).json)" -only="$(subst build-azure-,,$@)" $(ABSOLUTE_PACKER_VAR_FILES) packer/azure/packer$(findstring -windows,$@).json

.PHONY: $(AZURE_BUILD_SIG_CVM_TARGETS)
$(AZURE_BUILD_SIG_CVM_TARGETS): deps-azure
	. $(abspath packer/azure/scripts/init-sig.sh) $(subst build-azure-sig-,,$@) && $(PACKER) build $(if $(findstring windows,$@),$(PACKER_WINDOWS_NODE_FLAGS),$(PACKER_NODE_FLAGS)) -var-file="$(abspath packer/azure/azure-config.json)" -var-file="$(abspath packer/azure/azure-sig-cvm.json)" -var-file="$(abspath packer/azure/$(subst build-azure-sig-,,$@).json)" -only="$(subst build-azure-,,$@)" $(ABSOLUTE_PACKER_VAR_FILES) packer/azure/packer$(findstring -windows,$@).json

.PHONY: $(AZURE_VALIDATE_SIG_TARGETS)
$(AZURE_VALIDATE_SIG_TARGETS): deps-azure
	$(PACKER) validate $(if $(findstring windows,$@),$(PACKER_WINDOWS_NODE_FLAGS),$(PACKER_NODE_FLAGS)) -var-file="$(abspath packer/azure/azure-config.json)" -var-file="$(abspath packer/azure/azure-sig.json)" -var-file="$(abspath packer/azure/$(subst validate-azure-sig-,,$@).json)" -only="$(subst validate-azure-,,$@)" $(ABSOLUTE_PACKER_VAR_FILES) packer/azure/packer$(findstring -windows,$@).json

.PHONY: $(AZURE_VALIDATE_SIG_GEN2_TARGETS)
$(AZURE_VALIDATE_SIG_GEN2_TARGETS): deps-azure
	$(PACKER) validate $(if $(findstring windows,$@),$(PACKER_WINDOWS_NODE_FLAGS),$(PACKER_NODE_FLAGS)) -var-file="$(abspath packer/azure/azure-config.json)" -var-file="$(abspath packer/azure/azure-sig-gen2.json)" -var-file="$(abspath packer/azure/$(subst validate-azure-sig-,,$@).json)" -only="$(subst validate-azure-,,$@)" $(ABSOLUTE_PACKER_VAR_FILES) packer/azure/packer$(findstring windows,$@).json

.PHONY: $(AZURE_VALIDATE_SIG_CVM_TARGETS)
$(AZURE_VALIDATE_SIG_CVM_TARGETS): deps-azure
	packer validate $(if $(findstring windows,$@),$(PACKER_WINDOWS_NODE_FLAGS),$(PACKER_NODE_FLAGS)) -var-file="$(abspath packer/azure/azure-config.json)" -var-file="$(abspath packer/azure/azure-sig-cvm.json)" -var-file="$(abspath packer/azure/$(subst validate-azure-sig-,,$@).json)" -only="$(subst validate-azure-,,$@)" $(ABSOLUTE_PACKER_VAR_FILES) packer/azure/packer$(findstring -windows,$@).json

.PHONY: $(DO_BUILD_TARGETS)
$(DO_BUILD_TARGETS): deps-do
	$(PACKER) build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/digitalocean/$(subst build-do-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/digitalocean/packer.json

.PHONY: $(DO_VALIDATE_TARGETS)
$(DO_VALIDATE_TARGETS): deps-do
	$(PACKER) validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/digitalocean/$(subst validate-do-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/digitalocean/packer.json

.PHONY: $(HUAWEICLOUD_BUILD_TARGETS)
$(HUAWEICLOUD_BUILD_TARGETS): deps-huaweicloud
	$(PACKER) build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/huaweicloud/$(subst build-huaweicloud-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/huaweicloud/packer.json

.PHONY: $(HUAWEICLOUD_VALIDATE_TARGETS)
$(HUAWEICLOUD_VALIDATE_TARGETS): deps-huaweicloud
	$(PACKER) validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/huaweicloud/$(subst validate-huaweicloud-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/huaweicloud/packer.json

.PHONY: $(OPENSTACK_BUILD_TARGETS)
$(OPENSTACK_BUILD_TARGETS): deps-openstack
	packer build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/openstack/$(subst build-openstack-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/openstack/packer.json

.PHONY: $(OPENSTACK_VALIDATE_TARGETS)
$(OPENSTACK_VALIDATE_TARGETS): deps-openstack
	packer validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/openstack/$(subst validate-openstack-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/openstack/packer.json

.PHONY: $(QEMU_BUILD_TARGETS)
$(QEMU_BUILD_TARGETS): deps-qemu set-ssh-password
	$(PACKER) build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/qemu/$(subst build-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/qemu/packer.json

.PHONY: $(QEMU_VALIDATE_TARGETS)
$(QEMU_VALIDATE_TARGETS): deps-qemu set-ssh-password
	$(PACKER) validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/qemu/$(subst validate-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/qemu/packer.json

.PHONY: $(QEMU_KUBEVIRT_BUILD_TARGETS)
$(QEMU_KUBEVIRT_BUILD_TARGETS): deps-qemu set-ssh-password
	$(PACKER) build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/qemu/$(subst build-kubevirt-,,$@).json)" --var 'kubevirt=true' $(ABSOLUTE_PACKER_VAR_FILES) packer/qemu/packer.json

.PHONY: $(QEMU_KUBEVIRT_VALIDATE_TARGETS)
$(QEMU_KUBEVIRT_VALIDATE_TARGETS): deps-qemu set-ssh-password
	$(PACKER) validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/qemu/$(subst validate-kubevirt-,,$@).json)" --var 'kubevirt=true' $(ABSOLUTE_PACKER_VAR_FILES) packer/qemu/packer.json

.PHONY: $(RAW_BUILD_TARGETS)
$(RAW_BUILD_TARGETS): deps-raw set-ssh-password
	$(PACKER) build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/raw/$(subst build-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/raw/packer.json

.PHONY: $(RAW_VALIDATE_TARGETS)
$(RAW_VALIDATE_TARGETS): deps-raw set-ssh-password
	$(PACKER) validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/raw/$(subst validate-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/raw/packer.json

.PHONY: $(OCI_BUILD_TARGETS)
$(OCI_BUILD_TARGETS): deps-oci
	$(if $(findstring windows,$@),./packer/oci/scripts/set_bootstrap.sh,)
	$(PACKER) build $(if $(findstring windows,$@),$(PACKER_WINDOWS_NODE_FLAGS),$(PACKER_NODE_FLAGS)) -var-file="$(abspath packer/oci/$(subst build-oci-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/oci/packer$(findstring -windows,$@).json
	$(if $(findstring windows,$@),./packer/oci/scripts/unset_bootstrap.sh,)

.PHONY: $(OCI_VALIDATE_TARGETS)
$(OCI_VALIDATE_TARGETS): deps-oci
	$(PACKER) validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/oci/$(subst validate-oci-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/oci/packer.json

.PHONY: $(OSC_BUILD_TARGETS)
$(OSC_BUILD_TARGETS): deps-osc
	$(PACKER) build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/outscale/$(subst build-osc-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/outscale/packer.json

.PHONY: $(OSC_VALIDATE_TARGETS)
$(OSC_VALIDATE_TARGETS): deps-osc
	$(PACKER) validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/outscale/$(subst validate-osc-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/outscale/packer.json

.PHONY: $(POWERVS_BUILD_TARGETS)
$(POWERVS_BUILD_TARGETS): deps-powervs
	$(PACKER) build $(PACKER_POWERVS_NODE_FLAGS) -var-file="$(abspath packer/powervs/$(subst build-powervs-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) -except=flatcar packer/powervs/packer.json

.PHONY: $(POWERVS_VALIDATE_TARGETS)
$(POWERVS_VALIDATE_TARGETS): deps-powervs
	$(PACKER) validate $(PACKER_POWERVS_NODE_FLAGS) -var-file="$(abspath packer/powervs/$(subst validate-powervs-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) -except=flatcar packer/powervs/packer.json

.PHONY: $(NUTANIX_BUILD_TARGETS)
$(NUTANIX_BUILD_TARGETS): deps-nutanix set-ssh-password
	$(eval NUTANIX_USERDATA:=$(shell cat $(abspath packer/nutanix/linux/cloud-init/$(subst -,/,$(if $(findstring ubuntu,$@),$(call GET_UBUNTU_DOTTED_SEMVER,$(subst build-nutanix-,,$@)),$(subst build-nutanix-,,$@)))/user-data) | base64 -w0))
	$(eval NUTANIX_VAR_FILE:=$(abspath packer/nutanix/$(subst build-nutanix-,,$@).json))
	jq '.user_data = "$(NUTANIX_USERDATA)"' $(NUTANIX_VAR_FILE) > $(NUTANIX_VAR_FILE).templated && mv $(NUTANIX_VAR_FILE).templated $(NUTANIX_VAR_FILE)
	# This uses a packer file builder to input unattend variables into a JSON file to be consumed by the python script before running the nutanix provisioner
	$(if $(findstring windows,$@),hack/windows-unattend.py --unattend-file='./packer/nutanix/windows/$(subst build-nutanix-,,$@)/autounattend.xml',)
	$(PACKER) build $(if $(findstring windows,$@),$(PACKER_WINDOWS_NODE_FLAGS),$(PACKER_NODE_FLAGS)) -var-file="packer/nutanix/nutanix.json" -var-file="$(abspath packer/nutanix/$(subst build-nutanix-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/nutanix/packer$(if $(findstring windows,$@),-windows,).json

.PHONY: $(NUTANIX_VALIDATE_TARGETS)
$(NUTANIX_VALIDATE_TARGETS): deps-nutanix set-ssh-password
	$(PACKER) validate $(if $(findstring windows,$@),$(PACKER_WINDOWS_NODE_FLAGS),$(PACKER_NODE_FLAGS)) -var-file="packer/nutanix/nutanix.json" -var-file="$(abspath packer/nutanix/$(subst validate-nutanix-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/nutanix/packer$(if $(findstring windows,$@),-windows,).json

.PHONY: $(HCLOUD_BUILD_TARGETS)
$(HCLOUD_BUILD_TARGETS): deps-hcloud
	$(PACKER) build $(PACKER_NODE_FLAGS) -var-file="packer/hcloud/hcloud-config.json" -var-file="$(abspath packer/hcloud/$(subst build-hcloud-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/hcloud/packer$(if $(findstring flatcar,$@),-flatcar,).json

.PHONY: $(HCLOUD_VALIDATE_TARGETS)
$(HCLOUD_VALIDATE_TARGETS): deps-hcloud
	$(PACKER) validate $(PACKER_NODE_FLAGS) -var-file="packer/hcloud/hcloud-config.json" -var-file="$(abspath packer/hcloud/$(subst validate-hcloud-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/hcloud/packer$(if $(findstring flatcar,$@),-flatcar,).json

.PHONY: $(PROXMOX_BUILD_TARGETS)
$(PROXMOX_BUILD_TARGETS): deps-proxmox set-ssh-password
	$(PACKER) build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/proxmox/$(subst build-proxmox-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/proxmox/packer.json

.PHONY: $(PROXMOX_VALIDATE_TARGETS)
$(PROXMOX_VALIDATE_TARGETS): deps-proxmox set-ssh-password
	$(PACKER) validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/proxmox/$(subst validate-proxmox-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/proxmox/packer.json

.PHONY: $(VULTR_BUILD_TARGETS)
$(VULTR_BUILD_TARGETS): deps-vultr
	$(PACKER) build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/vultr/$(subst build-vultr-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/vultr/packer.json

.PHONY: $(VULTR_VALIDATE_TARGETS)
$(VULTR_VALIDATE_TARGETS): deps-vultr
	$(PACKER) validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/vultr/$(subst validate-vultr-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/vultr/packer.json

.PHONY: $(MAAS_BUILD_TARGETS)
$(MAAS_BUILD_TARGETS): deps-qemu set-ssh-password
	$(PACKER) build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/maas/$(subst build-,,$@).json)" --var="ansible_user_vars=provider=maas" $(ABSOLUTE_PACKER_VAR_FILES) packer/maas/packer.json

.PHONY: $(MAAS_VALIDATE_TARGETS)
$(MAAS_VALIDATE_TARGETS): deps-qemu set-ssh-password
	$(PACKER) validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/maas/$(subst validate-,,$@).json)" --var="ansible_user_vars=provider=maas" $(ABSOLUTE_PACKER_VAR_FILES) packer/maas/packer.json

.PHONY: $(SCALEWAY_BUILD_TARGETS)
$(SCALEWAY_BUILD_TARGETS): deps-scaleway
	$(PACKER) build $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/scaleway/$(subst build-scaleway-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/scaleway/packer.json

.PHONY: $(SCALEWAY_VALIDATE_TARGETS)
$(SCALEWAY_VALIDATE_TARGETS): deps-scaleway
	$(PACKER) validate $(PACKER_NODE_FLAGS) -var-file="$(abspath packer/scaleway/$(subst validate-scaleway-,,$@).json)" $(ABSOLUTE_PACKER_VAR_FILES) packer/scaleway/packer.json

## --------------------------------------
## Dynamic clean targets
## --------------------------------------
NODE_OVA_LOCAL_CLEAN_TARGETS := $(subst build-,clean-,$(NODE_OVA_LOCAL_BUILD_TARGETS))
.PHONY: $(NODE_OVA_LOCAL_CLEAN_TARGETS)
$(NODE_OVA_LOCAL_CLEAN_TARGETS):
	rm -fr output/$(subst clean-node-ova-local-,,$@)-kube*

QEMU_CLEAN_TARGETS := $(subst build-,clean-,$(QEMU_BUILD_TARGETS))
.PHONY: $(QEMU_CLEAN_TARGETS)
$(QEMU_CLEAN_TARGETS):
	rm -fr output/$(subst clean-qemu-,,$@)-kube*

RAW_CLEAN_TARGETS := $(subst build-,clean-,$(RAW_BUILD_TARGETS))
.PHONY: $(RAW_CLEAN_TARGETS)
$(RAW_CLEAN_TARGETS):
	rm -fr output/$(subst clean-raw-,,$@)-kube*

## --------------------------------------
## Document dynamic build targets
## --------------------------------------
##@ Builds
build-ami-amazon-2: ## Builds Amazon-2 Linux AMI
build-ami-amazon-2023: ## Builds Amazon-2023 Linux AMI
build-ami-ubuntu-2004: ## Builds Ubuntu 20.04 AMI
build-ami-ubuntu-2204: ## Builds Ubuntu 22.04 AMI
build-ami-ubuntu-2404: ## Builds Ubuntu 24.04 AMI
build-ami-rockylinux-8: ## Builds RockyLinux 8 AMI
build-ami-rhel-8: ## Builds RHEL-8 AMI
build-ami-flatcar: ## Builds Flatcar
build-ami-flatcar-arm64: ## Builds Flatcar arm64
build-ami-windows-2019: ## Build Windows Server 2019 AMI Packer config
build-ami-all: $(AMI_BUILD_TARGETS) ## Builds all AMIs

build-azure-sig-ubuntu-2004: ## Builds Ubuntu 20.04 Azure managed image in Shared Image Gallery
build-azure-sig-ubuntu-2204: ## Builds Ubuntu 22.04 Azure managed image in Shared Image Gallery
build-azure-sig-ubuntu-2404: ## Builds Ubuntu 24.04 Azure managed image in Shared Image Gallery
build-azure-sig-azurelinux-3: ## Builds Azure Linux 3 Azure managed image in Shared Image Gallery
build-azure-sig-rhel-8: ## Builds RHEL 8 Azure managed image in Shared Image Gallery
build-azure-sig-windows-2019-containerd: ## Builds Windows Server 2019 with containerd Azure managed image in Shared Image Gallery
build-azure-sig-windows-2022-containerd: ## Builds Windows Server 2022 with containerd Azure managed image in Shared Image Gallery
build-azure-sig-windows-2025-containerd: ## Builds Windows Server 2025 with containerd Azure managed image in Shared Image Gallery
build-azure-sig-windows-2019-containerd-cvm: ## Builds Windows Server 2019 with containerd CVM Azure managed image in Shared Image Gallery
build-azure-sig-windows-2022-containerd-cvm: ## Builds Windows Server 2022 with containerd CVM Azure managed image in Shared Image Gallery
build-azure-vhd-ubuntu-2004: ## Builds Ubuntu 20.04 VHD image for Azure
build-azure-vhd-ubuntu-2204: ## Builds Ubuntu 22.04 VHD image for Azure
build-azure-vhd-ubuntu-2404: ## Builds Ubuntu 24.04 VHD image for Azure
build-azure-vhd-azurelinux-3: ## Builds Azure Linux 3 VHD image for Azure
build-azure-vhd-rhel-8: ## Builds RHEL 8 VHD image for Azure
build-azure-vhd-windows-2019-containerd: ## Builds for Windows Server 2019 with containerd
build-azure-vhd-windows-2022-containerd: ## Builds for Windows Server 2022 with containerd
build-azure-sig-windows-annual-containerd: ## Builds for Windows Server Annual Channel with containerd
build-azure-sig-azurelinux-3-gen2: ## Builds Azure Linux 3 Gen2 managed image in Shared Image Gallery
build-azure-sig-flatcar: ## Builds Flatcar Azure managed image in Shared Image Gallery
build-azure-sig-flatcar-gen2: ## Builds Flatcar Azure Gen2 managed image in Shared Image Gallery
build-azure-sig-ubuntu-2004-gen2: ## Builds Ubuntu 20.04 Gen2 managed image in Shared Image Gallery
build-azure-sig-ubuntu-2204-gen2: ## Builds Ubuntu 22.04 Gen2 managed image in Shared Image Gallery
build-azure-sig-ubuntu-2404-gen2: ## Builds Ubuntu 24.04 Gen2 managed image in Shared Image Gallery
build-azure-sig-ubuntu-2004-cvm: ## Builds Ubuntu 20.04 CVM managed image in Shared Image Gallery
build-azure-sig-ubuntu-2204-cvm: ## Builds Ubuntu 22.04 CVM managed image in Shared Image Gallery
build-azure-sig-ubuntu-2404-cvm: ## Builds Ubuntu 24.04 CVM managed image in Shared Image Gallery
build-azure-vhds: $(AZURE_BUILD_VHD_TARGETS) ## Builds all Azure VHDs
build-azure-sigs: $(AZURE_BUILD_SIG_TARGETS) $(AZURE_BUILD_SIG_GEN2_TARGETS) $(AZURE_BUILD_SIG_CVM_TARGETS) ## Builds all Azure Shared Image Gallery images

build-do-ubuntu-2004: ## Builds Ubuntu 20.04 DigitalOcean Snapshot
build-do-ubuntu-2204: ## Builds Ubuntu 22.04 DigitalOcean Snapshot
build-do-ubuntu-2404: ## Builds Ubuntu 24.04 DigitalOcean Snapshot
build-do-all: $(DO_BUILD_TARGETS) ## Builds all DigitalOcean Snapshot

build-gce-ubuntu-2204: ## Builds the GCE ubuntu-2204 image
build-gce-ubuntu-2404: ## Builds the GCE ubuntu-2404 image
build-gce-rhel-8: ## Builds the GCE rhel-8 image
build-gce-all: $(GCE_BUILD_TARGETS) ## Builds all GCE image

build-huaweicloud-ubuntu-2204: ## Builds Ubuntu 22.04 HuaweiCloud image
build-huaweicloud-all: $(HUAWEICLOUD_BUILD_TARGETS) ## Builds all HuaweiCloud images

build-node-ova-local-flatcar: ## Builds Flatcar stable Node OVA w local hypervisor
build-node-ova-local-photon-4: ## Builds Photon 4 Node OVA w local hypervisor
build-node-ova-local-photon-5: ## Builds Photon 5 Node OVA w local hypervisor
build-node-ova-local-rhel-7: ## Builds RHEL 7 Node OVA w local hypervisor
build-node-ova-local-rhel-8: ## Builds RHEL 8 Node OVA w local hypervisor
build-node-ova-local-rhel-9: ## Builds RHEL 9 Node OVA w local hypervisor
build-node-ova-local-rockylinux-8: ## Builds RockyLinux 8 Node OVA w local hypervisor
build-node-ova-local-rockylinux-9: ## Builds RockyLinux 9 Node OVA w local hypervisor
build-node-ova-local-ubuntu-2004: ## Builds Ubuntu 20.04 Node OVA w local hypervisor
build-node-ova-local-windows-2019: ## Builds for Windows Server 2019 Node OVA w local hypervisor
build-node-ova-local-all: $(NODE_OVA_LOCAL_BUILD_TARGETS) ## Builds all Node OVAs w local hypervisor

build-node-ova-vsphere-flatcar: ## Builds Flatcar stable Node OVA and template on vSphere
build-node-ova-vsphere-photon-4: ## Builds Photon 4 Node OVA and template on vSphere
build-node-ova-vsphere-photon-5: ## Builds Photon 5 Node OVA and template on vSphere
build-node-ova-vsphere-rhel-7: ## Builds RHEL 7 Node OVA and template on vSphere
build-node-ova-vsphere-rhel-8: ## Builds RHEL 8 Node OVA and template on vSphere
build-node-ova-vsphere-rhel-9: ## Builds RHEL 9 Node OVA and template on vSphere
build-node-ova-vsphere-rockylinux-8: ## Builds RockyLinux 8 Node OVA and template on vSphere
build-node-ova-vsphere-rockylinux-9: ## Builds RockyLinux 9 Node OVA and template on vSphere
build-node-ova-vsphere-ubuntu-2004: ## Builds Ubuntu 20.04 Node OVA and template on vSphere
build-node-ova-vsphere-ubuntu-2004-efi: ## Builds Ubuntu 20.04 Node OVA and template on vSphere that EFI boots
build-node-ova-vsphere-ubuntu-2204: ## Builds Ubuntu 22.04 Node OVA and template on vSphere
build-node-ova-vsphere-ubuntu-2204-efi: ## Builds Ubuntu 22.04 Node OVA and template on vSphere that EFI boots
build-node-ova-vsphere-ubuntu-2404: ## Builds Ubuntu 24.04 Node OVA and template on vSphere
build-node-ova-vsphere-ubuntu-2404-efi: ## Builds Ubuntu 24.04 Node OVA and template on vSphere that EFI boots
build-node-ova-vsphere-windows-2019: ## Builds for Windows Server 2019 and template on vSphere
build-node-ova-vsphere-windows-2019-efi: ## Builds for Windows Server 2019 and template on vSphere that EFI boots
build-node-ova-vsphere-windows-2022: ## Builds for Windows Server 2022 template on vSphere
build-node-ova-vsphere-windows-2022-efi: ## Builds for Windows Server 2022 template on vSphere that EFI boots
build-node-ova-vsphere-all: $(NODE_OVA_VSPHERE_BUILD_TARGETS) ## Builds all Node OVAs and templates on vSphere

build-node-ova-vsphere-clone-photon-4: ## Builds Photon 4 Node OVA and template on vSphere
build-node-ova-vsphere-clone-photon-5: ## Builds Photon 5 Node OVA and template on vSphere
build-node-ova-vsphere-clone-rhel-7: ## Builds RHEL 7 Node OVA and template on vSphere
build-node-ova-vsphere-clone-rhel-8: ## Builds RHEL 8 Node OVA and template on vSphere
build-node-ova-vsphere-clone-rhel-9: ## Builds RHEL 9 Node OVA and template on vSphere
build-node-ova-vsphere-clone-rockylinux-8: ## Builds RockyLinux 8 Node OVA and template on vSphere
build-node-ova-vsphere-clone-rockylinux-9: ## Builds RockyLinux 9 Node OVA and template on vSphere
build-node-ova-vsphere-clone-ubuntu-2004: ## Builds Ubuntu 20.04 Node OVA and template on vSphere
build-node-ova-vsphere-clone-ubuntu-2204: ## Builds Ubuntu 22.04 Node OVA and template on vSphere
build-node-ova-vsphere-clone-ubuntu-2204-efi: ## ## Builds Ubuntu 22.04 Node OVA and template on vSphere that EFI boots
build-node-ova-vsphere-clone-ubuntu-2404: ## Builds Ubuntu 24.04 Node OVA and template on vSphere
build-node-ova-vsphere-clone-ubuntu-2404-efi: ## ## Builds Ubuntu 24.04 Node OVA and template on vSphere that EFI boots
build-node-ova-vsphere-clone-all: $(NODE_OVA_VSPHERE_CLONE_BUILD_TARGETS) ## Builds all Node OVAs and templates on vSphere

build-node-ova-vsphere-base-photon-4: ## Builds base Photon 4 Node OVA and template on vSphere
build-node-ova-vsphere-base-photon-5: ## Builds base Photon 5 Node OVA and template on vSphere
build-node-ova-vsphere-base-rhel-7: ## Builds base RHEL 7 Node OVA and template on vSphere
build-node-ova-vsphere-base-rhel-8: ## Builds base RHEL 8 Node OVA and template on vSphere
build-node-ova-vsphere-base-rhel-9: ## Builds base RHEL 9 Node OVA and template on vSphere
build-node-ova-vsphere-base-rockylinux-8: ## Builds base RockyLinux 8 Node OVA and template on vSphere
build-node-ova-vsphere-base-rockylinux-9: ## Builds base RockyLinux 9 Node OVA and template on vSphere
build-node-ova-vsphere-base-ubuntu-2004: ## Builds base Ubuntu 20.04 Node OVA and template on vSphere
build-node-ova-vsphere-base-ubuntu-2204: ## Builds base Ubuntu 22.04 Node OVA and template on vSphere
build-node-ova-vsphere-base-ubuntu-2204-efi: ## Builds Ubuntu 22.04 Node OVA and template on vSphere that EFI boots
build-node-ova-vsphere-base-ubuntu-2404: ## Builds base Ubuntu 24.04 Node OVA and template on vSphere
build-node-ova-vsphere-base-ubuntu-2404-efi: ## Builds Ubuntu 24.04 Node OVA and template on vSphere that EFI boots
build-node-ova-vsphere-base-all: $(NODE_OVA_VSPHERE_BASE_BUILD_TARGETS) ## Builds all base Node OVAs and templates on vSphere

build-node-ova-local-vmx-photon-4: ## Builds Photon 4 Node OVA from VMX file w local hypervisor
build-node-ova-local-vmx-photon-5: ## Builds Photon 5 Node OVA from VMX file w local hypervisor
build-node-ova-local-vmx-rhel-7: ## Builds RHEL 7 Node OVA from VMX file w local hypervisor
build-node-ova-local-vmx-rhel-8: ## Builds RHEL 8 Node OVA from VMX file w local hypervisor
build-node-ova-local-vmx-rhel-9: ## Builds RHEL 9 Node OVA from VMX file w local hypervisor
build-node-ova-local-vmx-rockylinux-8: ## Builds RockyLinux 8 Node OVA from VMX file w local hypervisor
build-node-ova-local-vmx-rockylinux-9: ## Builds RockyLinux 9 Node OVA from VMX file w local hypervisor
build-node-ova-local-vmx-ubuntu-2004: ## Builds Ubuntu 20.04 Node OVA from VMX file w local hypervisor

build-node-ova-local-base-photon-4: ## Builds Photon 4 Base Node OVA w local hypervisor
build-node-ova-local-base-photon-5: ## Builds Photon 5 Base Node OVA w local hypervisor
build-node-ova-local-base-rhel-7: ## Builds RHEL 7 Base Node OVA w local hypervisor
build-node-ova-local-base-rhel-8: ## Builds RHEL 8 Base Node OVA w local hypervisor
build-node-ova-local-base-rhel-9: ## Builds RHEL 9 Base Node OVA w local hypervisor
build-node-ova-local-base-rockylinux-8: ## Builds RockyLinux 8 Base Node OVA w local hypervisor
build-node-ova-local-base-rockylinux-9: ## Builds RockyLinux 9 Base Node OVA w local hypervisor
build-node-ova-local-base-ubuntu-2004: ## Builds Ubuntu 20.04 Base Node OVA w local hypervisor

build-openstack-ubuntu-2004: ## Builds Ubuntu 20.04 OpenStack image
build-openstack-ubuntu-2204: ## Builds Ubuntu 22.04 OpenStack image
build-openstack-ubuntu-2404: ## Builds Ubuntu 24.04 OpenStack image
build-openstack-rockylinux-9: ## Builds RockyLinux 9 OpenStack image
build-openstack-flatcar: ## Builds Flatcar OpenStack image
build-openstack-all: $(OPENSTACK_BUILD_TARGETS)

build-qemu-flatcar: ## Builds Flatcar QEMU image
build-qemu-ubuntu-2004: ## Builds Ubuntu 20.04 QEMU image
build-qemu-ubuntu-2004-efi: ## Builds Ubuntu 20.04 QEMU image that EFI boots
build-qemu-ubuntu-2204: ## Builds Ubuntu 22.04 QEMU image
build-qemu-ubuntu-2204-cloudimg: ## Builds Ubuntu 22.04 QEMU image using cloud image
build-qemu-ubuntu-2204-efi: ## Builds Ubuntu 22.04 QEMU image that EFI boots
build-qemu-ubuntu-2404: ## Builds Ubuntu 24.04 QEMU image
build-qemu-ubuntu-2404-efi: ## Builds Ubuntu 24.04 QEMU image that EFI boots
build-qemu-centos-9: ## Builds CentOS 9 Stream QEMU image
build-qemu-rhel-8: ## Builds RHEL 8 QEMU image
build-qemu-rhel-9: ## Builds RHEL 9 QEMU image
build-qemu-rockylinux-8: ## Builds Rocky 8 QEMU image
build-qemu-rockylinux-8-cloudimg: ## Builds Rocky 8 QEMU image using cloud image
build-qemu-rockylinux-9: ## Builds Rocky 9 QEMU image
build-qemu-rockylinux-9-cloudimg: ## Builds Rocky 9 QEMU image using cloud image
build-qemu-all: $(QEMU_BUILD_TARGETS) ## Builds all Qemu images

build-maas-ubuntu-2204-efi: ## Builds Ubuntu 22.04 MaaS image that EFI boots
build-maas-ubuntu-2404-efi: ## Builds Ubuntu 24.04 MaaS image that EFI boots

build-raw-flatcar: ## Builds Flatcar RAW image
build-raw-ubuntu-2004: ## Builds Ubuntu 20.04 RAW image
build-raw-ubuntu-2004-efi: ## Builds Ubuntu 20.04 RAW image that EFI boots
build-raw-ubuntu-2204: ## Builds Ubuntu 22.04 RAW image
build-raw-ubuntu-2204-efi: ## Builds Ubuntu 22.04 RAW image that EFI boots
build-raw-ubuntu-2404: ## Builds Ubuntu 24.04 RAW image
build-raw-ubuntu-2404-efi: ## Builds Ubuntu 24.04 RAW image that EFI boots
build-raw-rhel-8: ## Builds RHEL 8 RAW image
build-raw-rhel-9: ## Builds RHEL 9 RAW image
build-raw-rhel-9-efi: ## Builds RHEL 9 RAW image that EFI boots
build-raw-all: $(RAW_BUILD_TARGETS) ## Builds all RAW images

build-oci-ubuntu-2004: ## Builds the OCI ubuntu-2004 image
build-oci-ubuntu-2204: ## Builds the OCI ubuntu-2204 image
build-oci-oracle-linux-8: ## Builds the OCI Oracle Linux 8.x image
build-oci-oracle-linux-9: ## Builds the OCI Oracle Linux 9.x image
build-oci-windows-2019: ## Builds the OCI Windows Server 2019 image
build-oci-windows-2022: ## Builds the OCI Windows Server 2022 image
build-oci-all: $(OCI_BUILD_TARGETS) ## Builds all OCI image

build-osc-ubuntu-2004: ## Builds Ubuntu 20.04 Outscale Snapshot
build-osc-ubuntu-2204: ## Builds Ubuntu 22.04 Outscale Snapshot
build-osc-ubuntu-2404: ## Builds Ubuntu 24.04 Outscale Snapshot
build-osc-all: $(OSC_BUILD_TARGETS) ## Builds all Outscale Snapshot

build-nutanix-ubuntu-2004: ## Builds the Nutanix ubuntu-2004 image
build-nutanix-ubuntu-2204: ## Builds the Nutanix ubuntu-2204 image
build-nutanix-ubuntu-2404: ## Builds the Nutanix ubuntu-2404 image
build-nutanix-rhel-8: ## Builds the Nutanix RedHat Enterprise Linux 8 image
build-nutanix-rhel-9: ## Builds the Nutanix edHat Enterprise Linux 9 image
build-nutanix-rockylinux-8: ## Builds the Nutanix Rocky Linux 8 image
build-nutanix-rockylinux-9: ## Builds the Nutanix Rocky Linux 9 image
build-nutanix-flatcar: ## Builds the Nutanix Flatcar image
build-nutanix-windows-2022: ## Builds the Nutanix Windows 2022 image
build-nutanix-all: $(NUTANIX_BUILD_TARGETS) ## Builds all Nutanix image

build-hcloud-ubuntu-2004: ## Builds the Hetzner Cloud ubuntu-2004 image
build-hcloud-ubuntu-2204: ## Builds the Hetzner Cloud ubuntu-2204 image
build-hcloud-ubuntu-2404: ## Builds the Hetzner Cloud ubuntu-2404 image
build-hcloud-rockylinux-8: ## Builds the Hetzner Cloud Rocky Linux 8 image
build-hcloud-rockylinux-9: ## Builds the Hetzner Cloud Rocky Linux 9 image
build-hcloud-flatcar: ## Builds the Hetzner Cloud Flatcar image
build-hcloud-flatcar-arm64: ## Builds the Hetzner Cloud Flatcar arm64 image
build-hcloud-all: $(HCLOUD_BUILD_TARGETS) ## Builds all Hetzner Cloud image

build-proxmox-flatcar: ## Builds Flatcar Proxmox image
build-proxmox-ubuntu-2204: ## Builds the Proxmox ubuntu-2204 image
build-proxmox-ubuntu-2404: ## Builds the Proxmox ubuntu-2404 image
build-proxmox-ubuntu-2404-efi: ## Builds the Proxmox ubuntu-2404-efi image that EFI boots
build-proxmox-rockylinux-9: ## Builds the Proxmox rockylinux-9 image

build-vultr-ubuntu-2204: ## Builds Ubuntu 22.04 Vultr Snapshot

build-scaleway-rockylinux-9: ## Builds the Scaleway rockylinux-9 image
build-scaleway-ubuntu-2204: ## Builds Ubuntu 22.04 Scaleway image
build-scaleway-ubuntu-2404: ## Builds Ubuntu 24.04 Scaleway image
build-scaleway-all: $(SCALEWAY_BUILD_TARGETS) ## Builds all Scaleway Cloud images

## --------------------------------------
## Document dynamic validate targets
## --------------------------------------
##@ Validate packer config
validate-ami-amazon-2: ## Validates Amazon-2 Linux AMI Packer config
validate-ami-amazon-2023: ## Validates Amazon-2023 Linux AMI Packer config
validate-ami-rockylinux-8: ## Validates RockyLinux 8 AMI Packer config
validate-ami-rhel-8: ## Validates RHEL-8 AMI Packer config
validate-ami-flatcar: ## Validates Flatcar AMI Packer config
validate-ami-flatcar-arm64: ## Validates Flatcar arm64 AMI Packer config
validate-ami-ubuntu-2004: ## Validates Ubuntu 20.04 AMI Packer config
validate-ami-ubuntu-2204: ## Validates Ubuntu 22.04 AMI Packer config
validate-ami-ubuntu-2404: ## Validates Ubuntu 22.04 AMI Packer config
validate-ami-windows-2019: ## Validates Windows Server 2019 AMI Packer config
validate-ami-all: $(AMI_VALIDATE_TARGETS) ## Validates all AMIs Packer config

validate-huaweicloud-ubuntu-2004: ## Validates Ubuntu 20.04 HuaweiCloud Snapshot Packer config

validate-azure-sig-azurelinux-3: ## Validates Azure Linux 3 Azure managed image in Shared Image Gallery Packer config
validate-azure-sig-rhel-8: ## Validates RHEL 8 Azure managed image in Shared Image Gallery Packer config
validate-azure-sig-ubuntu-2004: ## Validates Ubuntu 20.04 Azure managed image in Shared Image Gallery Packer config
validate-azure-sig-ubuntu-2204: ## Validates Ubuntu 22.04 Azure managed image in Shared Image Gallery Packer config
validate-azure-sig-ubuntu-2404: ## Validates Ubuntu 24.04 Azure managed image in Shared Image Gallery Packer config
validate-azure-sig-windows-2019-containerd: ## Validate Windows Server 2019 with containerd Azure managed image in Shared Image Gallery Packer config
validate-azure-sig-windows-2022-containerd: ## Validate Windows Server 2022 with containerd Azure managed image in Shared Image Gallery Packer config
validate-azure-sig-windows-2025-containerd: ## Validate Windows Server 2025 with containerd Azure managed image in Shared Image Gallery Packer config
validate-azure-sig-windows-annual-containerd: ## Validate Windows Server Annual Channel with containerd Azure managed image in Shared Image Gallery Packer config
validate-azure-vhd-azurelinux-3: ## Validates Azure Linux 3 VHD image Azure Packer config
validate-azure-vhd-rhel-8: ## Validates RHEL 8 VHD image Azure Packer config
validate-azure-vhd-ubuntu-2004: ## Validates Ubuntu 20.04 VHD image Azure Packer config
validate-azure-vhd-ubuntu-2204: ## Validates Ubuntu 22.04 VHD image Azure Packer config
validate-azure-vhd-ubuntu-2404: ## Validates Ubuntu 24.04 VHD image Azure Packer config
validate-azure-vhd-windows-2019-containerd: ## Validate Windows Server 2019 VHD with containerd image Azure Packer config
validate-azure-vhd-windows-2022-containerd: ## Validate Windows Server 2022 VHD with containerd image Azure Packer config
validate-azure-sig-azurelinux-3-gen2: ## Validates Azure Linux 3 Gen2 Azure managed image in Shared Image Gallery Packer config
validate-azure-sig-ubuntu-2004-gen2: ## Validates Ubuntu 20.04 Azure managed image in Shared Image Gallery Packer config
validate-azure-sig-ubuntu-2004-cvm: ## Validates Ubuntu 20.04 CVM Azure managed image in Shared Image Gallery Packer config
validate-azure-sig-ubuntu-2204-gen2: ## Validates Ubuntu 22.04 Azure managed image in Shared Image Gallery Packer config
validate-azure-sig-ubuntu-2204-cvm: ## Validates Ubuntu 22.04 CVM Azure managed image in Shared Image Gallery Packer config
validate-azure-sig-ubuntu-2404-gen2: ## Validates Ubuntu 24.04 Azure managed image in Shared Image Gallery Packer config
validate-azure-sig-ubuntu-2404-cvm: ## Validates Ubuntu 24.04 CVM Azure managed image in Shared Image Gallery Packer config
validate-azure-all: $(AZURE_VALIDATE_SIG_TARGETS) $(AZURE_VALIDATE_VHD_TARGETS) $(AZURE_VALIDATE_SIG_GEN2_TARGETS) $(AZURE_VALIDATE_SIG_CVM_TARGETS) ## Validates all images for Azure Packer config

validate-do-ubuntu-2004: ## Validates Ubuntu 20.04 DigitalOcean Snapshot Packer config
validate-do-ubuntu-2204: ## Validates Ubuntu 22.04 DigitalOcean Snapshot Packer config
validate-do-ubuntu-2404: ## Validates Ubuntu 24.04 DigitalOcean Snapshot Packer config
validate-do-all: $(DO_VALIDATE_TARGETS) ## Validates all DigitalOcean Snapshot Packer config

validate-openstack-ubuntu-2004: ## Validates Ubuntu 20.04 Openstack Image Packer config
validate-openstack-ubuntu-2204: ## Validates Ubuntu 22.04 Openstack Image Packer config
validate-openstack-ubuntu-2404: ## Validates Ubuntu 22.04 Openstack Image Packer config
validate-openstack-rocky-9: ## Validates Rocky 9 Openstack Image Packer config
validate-openstack-flatcar: ## Validates Flatcar Openstack Image Packer config
validate-openstack-all: $(OPENSTACK_VALIDATE_TARGETS) ## Validates all Openstack Glance Image Packer config

validate-gce-ubuntu-2204: ## Validates Ubuntu 22.04 GCE Snapshot Packer config
validate-gce-ubuntu-2404: ## Validates Ubuntu 24.04 GCE Snapshot Packer config
validate-gce-rhel-8: ## Validates RHEL 8 GCE Snapshot Packer config
validate-gce-all: $(GCE_VALIDATE_TARGETS) ## Validates all GCE Snapshot Packer config

validate-node-ova-local-flatcar: ## Validates Flatcar stable Node OVA Packer config w local hypervisor
validate-node-ova-local-photon-4: ## Validates Photon 4 Node OVA Packer config w local hypervisor
validate-node-ova-local-photon-5: ## Validates Photon 5 Node OVA Packer config w local hypervisor
validate-node-ova-local-rhel-7: ## Validates RHEL 7 Node OVA Packer config w local hypervisor
validate-node-ova-local-rhel-8: ## Validates RHEL 8 Node OVA Packer config w local hypervisor
validate-node-ova-local-rhel-9: ## Validates RHEL 9 Node OVA Packer config w local hypervisor
validate-node-ova-local-rockylinux-8: ## Validates RockyLinux 8 Node OVA Packer config w local hypervisor
validate-node-ova-local-rockylinux-9: ## Validates RockyLinux 9 Node OVA Packer config w local hypervisor
validate-node-ova-local-ubuntu-2004: ## Validates Ubuntu 20.04 Node OVA Packer config w local hypervisor
validate-node-ova-local-ubuntu-2204: ## Validates Ubuntu 22.04 Node OVA Packer config w local hypervisor
validate-node-ova-local-ubuntu-2404: ## Validates Ubuntu 24.04 Node OVA Packer config w local hypervisor
validate-node-ova-local-windows-2019: ## Validates Windows Server 2019 Node OVA Packer config w local hypervisor
validate-node-ova-local-windows-2022: ## Validates Windows Server 2022 Node OVA Packer config w local hypervisor
validate-node-ova-local-all: $(NODE_OVA_LOCAL_VALIDATE_TARGETS) ## Validates all Node OVAs Packer config w local hypervisor

validate-node-ova-local-vmx-photon-4: ## Validates Photon 4 Node OVA from VMX file w local hypervisor
validate-node-ova-local-vmx-photon-5: ## Validates Photon 5 Node OVA from VMX file w local hypervisor
validate-node-ova-local-vmx-rhel-7: ## Validates RHEL 7 Node OVA from VMX file w local hypervisor
validate-node-ova-local-vmx-rhel-8: ## Validates RHEL 8 Node OVA from VMX file w local hypervisor
validate-node-ova-local-vmx-rhel-9: ## Validates RHEL 9 Node OVA from VMX file w local hypervisor
validate-node-ova-local-vmx-rockylinux-8: ## Validates RockyLinux 8 Node OVA from VMX file w local hypervisor
validate-node-ova-local-vmx-rockylinux-9: ## Validates RockyLinux 9 Node OVA from VMX file w local hypervisor
validate-node-ova-local-vmx-ubuntu-2004: ## Validates Ubuntu 20.04 Node OVA from VMX file w local hypervisor
validate-node-ova-local-vmx-ubuntu-2204: ## Validates Ubuntu 22.04 Node OVA from VMX file w local hypervisor
validate-node-ova-local-vmx-ubuntu-2404: ## Validates Ubuntu 24.04 Node OVA from VMX file w local hypervisor

validate-node-ova-local-base-photon-4: ## Validates Photon 4 Base Node OVA w local hypervisor
validate-node-ova-local-base-photon-5: ## Validates Photon 5 Base Node OVA w local hypervisor
validate-node-ova-local-base-rhel-7: ## Validates RHEL 7 Base Node OVA w local hypervisor
validate-node-ova-local-base-rhel-8: ## Validates RHEL 8 Base Node OVA w local hypervisor
validate-node-ova-local-base-rhel-9: ## Validates RHEL 9 Base Node OVA w local hypervisor
validate-node-ova-local-base-rockylinux-8: ## Validates RockyLinux 8 Base Node OVA w local hypervisor
validate-node-ova-local-base-rockylinux-9: ## Validates RockyLinux 9 Base Node OVA w local hypervisor
validate-node-ova-local-base-ubuntu-2004: ## Validates Ubuntu 20.04 Base Node OVA w local hypervisor
validate-node-ova-local-base-ubuntu-2204: ## Validates Ubuntu 22.04 Base Node OVA w local hypervisor
validate-node-ova-local-base-ubuntu-2404: ## Validates Ubuntu 24.04 Base Node OVA w local hypervisor

validate-qemu-flatcar: ## Validates Flatcar QEMU image packer config
validate-qemu-ubuntu-2004: ## Validates Ubuntu 20.04 QEMU image packer config
validate-qemu-ubuntu-2004-efi: ## Validates Ubuntu 20.04 QEMU EFI image packer config
validate-qemu-ubuntu-2204: ## Validates Ubuntu 22.04 QEMU image packer config
validate-qemu-ubuntu-2204-cloudimg: ## Validates Ubuntu 22.04 QEMU image packer config using cloud image
validate-qemu-ubuntu-2204-efi: ## Validates Ubuntu 22.04 QEMU EFI image packer config
validate-qemu-ubuntu-2404: ## Validates Ubuntu 24.04 QEMU image packer config
validate-qemu-ubuntu-2404-efi: ## Validates Ubuntu 24.04 QEMU EFI image packer config
validate-qemu-rhel-8: ## Validates RHEL 8 QEMU image
validate-qemu-rhel-9: ## Validates RHEL 9 QEMU image
validate-qemu-rockylinux-8: ## Validates Rocky Linux 8 QEMU image packer config
validate-qemu-rockylinux-8-cloudimg: ## Validates Rocky Linux 8 QEMU image packer config using cloud image
validate-qemu-rockylinux-9: ## Validates Rocky Linux 9 QEMU image packer config
validate-qemu-rockylinux-9-cloudimg: ## Validates Rocky Linux 9 QEMU image packer config using cloud image
validate-qemu-all: $(QEMU_VALIDATE_TARGETS) ## Validates all Qemu Packer config

validate-raw-flatcar: ## Validates Flatcar RAW image packer config
validate-raw-ubuntu-2004: ## Validates Ubuntu 20.04 RAW image packer config
validate-raw-ubuntu-2004-efi: ## Validates Ubuntu 20.04 RAW EFI image packer config
validate-raw-ubuntu-2204: ## Validates Ubuntu 22.04 RAW image packer config
validate-raw-ubuntu-2204-efi: ## Validates Ubuntu 22.04 RAW EFI image packer config
validate-raw-ubuntu-2404: ## Validates Ubuntu 24.04 RAW image packer config
validate-raw-ubuntu-2404-efi: ## Validates Ubuntu 24.04 RAW EFI image packer config
validate-raw-rhel-8: ## Validates RHEL 8 RAW image packer config
validate-raw-all: $(RAW_VALIDATE_TARGETS) ## Validates all RAW Packer config

validate-oci-ubuntu-2004: ## Validates the OCI ubuntu-2004 image packer config
validate-oci-ubuntu-2204: ## Validates the OCI ubuntu-2204 image packer config
validate-oci-oracle-linux-8: ## Validates the OCI Oracle Linux 8.x image packer config
validate-oci-oracle-linux-9: ## Validates the OCI Oracle Linux 9.x image packer config
validate-oci-windows-2019: ## Validates the OCI Windows 2019 image packer config
validate-oci-windows-2022: ## Validates the OCI Windows 2022 image packer config
validate-oci-all: $(OCI_VALIDATE_TARGETS) ## Validates all OCI image packer config

validate-osc-ubuntu-2004: ## Validates Ubuntu 20.04 Outscale Snapshot Packer config
validate-osc-ubuntu-2204: ## Validates Ubuntu 22.04 Outscale Snapshot Packer config
validate-osc-ubuntu-2404: ## Validates Ubuntu 24.04 Outscale Snapshot Packer config
validate-osc-all: $(OSC_VALIDATE_TARGETS) ## Validates all Outscale Snapshot Packer config

validate-powervs-centos-8: ## Validates the PowerVS CentOS 8 image packer config
validate-powervs-centos-9: ## Validates the PowerVS CentOS 9 image packer config
validate-powervs-all: $(POWERVS_VALIDATE_TARGETS) ## Validates all PowerVS Packer config

validate-nutanix-ubuntu-2004: ## Validates Ubuntu 20.04 Nutanix Packer config
validate-nutanix-ubuntu-2204: ## Validates Ubuntu 22.04 Nutanix Packer config
validate-nutanix-ubuntu-2404: ## Validates Ubuntu 24.04 Nutanix Packer config
validate-nutanix-rhel-8: ## Validates RedHat Enterprise Linux 8 Nutanix Packer config
validate-nutanix-rhel-9: ## Validates RedHat Enterprise Linux 9 Nutanix Packer config
validate-nutanix-rockylinux-8: ## Validates Rocky Linux 8 Nutanix Packer config
validate-nutanix-rockylinux-9: ## Validates Rocky Linux 9 Nutanix Packer config
validate-nutanix-flatcar: ## Validates the Nutanix Flatcar Nutanix Packer config
validate-nutanix-windows-2022: ## Validates Windows Server 2022 Nutanix Packer config
validate-nutanix-all: $(NUTANIX_VALIDATE_TARGETS) ## Validates all Nutanix Packer config

validate-hcloud-ubuntu-2004: ## Validates Ubuntu 20.04 Hetzner Cloud Packer config
validate-hcloud-ubuntu-2204: ## Validates Ubuntu 22.04 Hetzner Cloud Packer config
validate-hcloud-ubuntu-2404: ## Validates Ubuntu 24.04 Hetzner Cloud Packer config
validate-hcloud-rockylinux-8: ## Validates Rocky Linux 8 Hetzner Cloud Packer config
validate-hcloud-rockylinux-9: ## Validates the Hetzner Cloud Rocky Linux 9 Packer config
validate-hcloud-flatcar: ## Validates the Hetzner Cloud Flatcar Packer config
validate-hcloud-flatcar-arm64: ## Validates the Hetzner Cloud Flatcar arm64 Packer config
validate-hcloud-all: $(HCLOUD_VALIDATE_TARGETS) ## Validates all Hetzner Cloud Packer config

validate-proxmox-ubuntu-2204: ## Validates Ubuntu 22.04 Proxmox Packer config
validate-proxmox-flatcar: ## Validates Flatcar Proxmox Packer config

validate-vultr-ubuntu-2204: ## Validates Ubuntu 22.04 Vultr Snapshot Packer config

validate-scaleway-rockylinux-9: ## Validates Rocky Linux 9 Scaleway image Packer config
validate-scaleway-ubuntu-2204: ## Validates Ubuntu 22.04 Scaleway image Packer config
validate-scaleway-ubuntu-2404: ## Validates Ubuntu 24.04 Scaleway image Packer config
validate-scaleway-all: $(SCALEWAY_VALIDATE_TARGETS) ## Validates all Scaleway Cloud Packer config

validate-all: validate-ami-all \
	validate-azure-all \
	validate-do-all \
	validate-gce-all \
	validate-node-ova-local-all \
	validate-qemu-all \
	validate-raw-all \
	validate-oci-all \
	validate-osc-all \
	validate-powervs-all \
	validate-nutanix-all \
	validate-hcloud-all \
	validate-scaleway-all

validate-all: ## Validates the Packer config for all build targets

.PHONY: lint
lint: ## Runs linters on image-builder code
sh_files = $(shell find . -type f -name "*.sh")
lint: deps-lint
	ansible-lint ansible/
# ignore error code since shellcheck exits with Error 1 if problems are found despite running properly
	-@for f in $(sh_files); do (shellcheck -x $$f); done

.PHONY: lint-fix
lint-fix: ## Runs linters on image-builder code and fixes issues
lint-fix: deps-lint
	ansible-lint --fix=all ansible/

.PHONY: lint-ignore
lint-ignore: ## Runs linters on image-builder code and creates an "ignore" file
lint-ignore: deps-lint
	ansible-lint --generate-ignore ansible/

## --------------------------------------
## Clean targets
## --------------------------------------
##@ Cleaning
.PHONY: clean
clean: ## Removes all image output directories and packer image cache
clean: $(NODE_OVA_LOCAL_CLEAN_TARGETS) $(QEMU_CLEAN_TARGETS) clean-packer-cache

.PHONY: clean-ova
clean-ova: ## Removes all ova image output directories (see NOTE at top of help)
clean-ova: $(NODE_OVA_LOCAL_CLEAN_TARGETS)

.PHONY: clean-qemu
clean-qemu: ## Removes all qemu image output directories (see NOTE at top of help)
clean-qemu: $(QEMU_CLEAN_TARGETS)

.PHONY: clean-raw
clean-raw: ## Removes all raw image output directories (see NOTE at top of help)
clean-raw: $(RAW_CLEAN_TARGETS)

.PHONY: clean-packer-cache
clean-packer-cache: ## Removes the packer cache
clean-packer-cache:
	rm -fr packer_cache/*

## --------------------------------------
## Docker targets
## --------------------------------------
##@ Docker

.PHONY: docker-pull-prerequisites
docker-pull-prerequisites:
	# We must pre-pull images https://github.com/moby/buildkit/issues/1271
	docker pull $(BUILDKIT_SYNTAX)
	docker pull $(BASE_IMAGE)

.PHONY: docker-build
docker-build: docker-pull-prerequisites ## Build the Docker image for controller-manager
	DOCKER_BUILDKIT=1 docker build --build-arg BUILDKIT_SYNTAX=$(BUILDKIT_SYNTAX) --build-arg PASSED_IB_VERSION=$(IB_VERSION) --build-arg ARCH=$(ARCH) --build-arg BASE_IMAGE=$(BASE_IMAGE) --build-arg TAG=$(TAG) . -t $(CONTROLLER_IMG)-$(ARCH):$(TAG)

.PHONY: docker-push
docker-push: ## Push the Docker image
	docker push $(CONTROLLER_IMG)-$(ARCH):$(TAG)

## --------------------------------------
## Test targets
## --------------------------------------
##@ Testing
.PHONY: test-azure
test-azure: ## Run the tests for Azure builders
	$(abspath packer/azure/scripts/ci-azure-e2e.sh)

## --------------------------------------
## Release targets
## --------------------------------------
##@ Release

USER_FORK ?= $(shell git config --get remote.origin.url | cut -d/ -f4)
IMAGE_REVIEWERS ?= $(shell ./hack/get-project-maintainers.sh)

.PHONY: release-staging
release-staging: ## Build and push a container image to the staging registry.
	TAG=$(IB_VERSION) REGISTRY=$(STAGING_REGISTRY) $(MAKE) docker-build docker-push

.PHONY: promote-images
promote-image: deps-release ## Create a pull request to promote a staging image to production.
	kpromo pr --project scl-image-builder --tag $(IB_VERSION) --reviewers "$(IMAGE_REVIEWERS)" --fork $(USER_FORK)

## --------------------------------------
## Sort JSON
## --------------------------------------
##@ Sort JSON

.PHONY: json-sort
json_files = $(shell find . -type f -name "*.json" | sort -u)
json-sort: ## Sort all JSON files alphabetically
	@for f in $(json_files); do (cat "$$f" | jq -S '.' >> "$$f".sorted && mv "$$f".sorted "$$f") || exit 1 ; done


## --------------------------------------
## Ignition
## --------------------------------------
##@ Ignition
.PHONY: gen-ignition
ignition_files = bootstrap-pass-auth bootstrap-cloud
gen-ignition: deps-ignition ## Generates Ignition files from CLC
	for f in $(ignition_files); do (ct < packer/files/flatcar/clc/$$f.yaml | jq '.' > packer/files/flatcar/ignition/$$f.json) || exit 1; done

## --------------------------------------
## ISO checksum updates
## --------------------------------------
##@ ISO checksum updates
.PHONY: update-all-iso-checksums
update-all-iso-checksums: update-ubuntu-iso-checksums \
	update-rockylinux-iso-checksums \
	update-centos-9-iso-checksums \
	update-photon-iso-checksums \

update-all-iso-checksums: ## Updates checksums for all ISOs

.PHONY: update-ubuntu-iso-checksums
update-ubuntu-iso-checksums: ## Updates checksums for Ubuntu ISOs
	hack/update-iso-checksums.sh ubuntu false SHA256SUMS "*iso_file_name" 1
	$(MAKE) json-sort

.PHONY: update-rockylinux-iso-checksums
update-rockylinux-iso-checksums: ## Updates checksums for Rocky Linux ISOs
	hack/update-iso-checksums.sh rockylinux false CHECKSUM "SHA256 (iso_file_name)" 4
	$(MAKE) json-sort

.PHONY: update-centos-9-iso-checksums
update-centos-9-iso-checksums: ## Updates checksums for Centos 9 ISOs
	hack/update-iso-checksums.sh centos-9 false SHA256SUM "SHA256 (iso_file_name)" 4
	$(MAKE) json-sort

.PHONY: update-photon-iso-checksums
update-photon-iso-checksums: ## Updates checksums for Photon ISOs
	hack/update-iso-checksums.sh photon true
	$(MAKE) json-sort
