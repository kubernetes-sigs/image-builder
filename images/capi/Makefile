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

## --------------------------------------
## Help
## --------------------------------------
help: ## Display this help
	@echo NOTE
	@echo '  The "build-ova" targets have analogue "clean-ova" targets for'
	@echo '  cleaning artifacts created from building OVAs using a local'
	@echo '  hypervisor.'
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)

## --------------------------------------
## Packer flags
## --------------------------------------

# If FOREGROUND=1 then Packer will set headless to false, causing local builds
# to build in the foreground, with a UI. This is very useful when debugging new
# platforms or issues with existing ones.
ifeq (1,$(strip $(FOREGROUND)))
PACKER_FLAGS += -var="headless=false"
endif

# A list of variable files given to Packer to configure things like the versions
# of Kubernetes, CNI, and ContainerD to install.
PACKER_VAR_FILES +=	packer/config/kubernetes.json \
					packer/config/cni.json \
					packer/config/containerd.json

# Initialize a list of flags to pass to Packer. This includes any existing flags
# specified by PACKER_FLAGS, as well as prefixing the list with the variable
# files from PACKER_VAR_FILES, with each file prefixed by -var-file=.
#
# Any existing values from PACKER_FLAGS take precendence over variable files.
PACKER_FLAGS := $(foreach f,$(abspath $(PACKER_VAR_FILES)),-var-file="$(f)" ) \
				$(PACKER_FLAGS)

## --------------------------------------
## Platform and version combinations
## --------------------------------------
CENTOS_VERSIONS			:=	centos-7
PHOTON_VERSIONS			:=	photon-3
UBUNTU_VERSIONS			:=	ubuntu-1804 ubuntu-2004

PLATFORMS_AND_VERSIONS	:=	$(CENTOS_VERSIONS) \
							$(PHOTON_VERSIONS) \
							$(UBUNTU_VERSIONS)

OVA_BUILD_NAMES			:=	$(addprefix ova-,$(PLATFORMS_AND_VERSIONS))
ESX_BUILD_NAMES			:=	$(addprefix esx-,$(OVA_BUILD_NAMES))

AMI_BUILD_NAMES			?=	ami-default
GCE_BUILD_NAMES			?=	gce-default
AZURE_BUILD_NAMES		?=	azure-sig-ubuntu-1804 azure-vhd-ubuntu-1804

## --------------------------------------
## Dynamic build targets
## --------------------------------------
OVA_BUILD_TARGETS	:= $(addprefix build-,$(OVA_BUILD_NAMES))
ESX_BUILD_TARGETS	:= $(addprefix build-,$(ESX_BUILD_NAMES))
AMI_BUILD_TARGETS	:= $(addprefix build-,$(AMI_BUILD_NAMES))
GCE_BUILD_TARGETS	:= $(addprefix build-,$(GCE_BUILD_NAMES))
AZURE_BUILD_TARGETS	:= $(addprefix build-,$(AZURE_BUILD_NAMES))

.PHONY: $(OVA_BUILD_TARGETS)
$(OVA_BUILD_TARGETS):
	packer build $(PACKER_FLAGS) -var-file="$(abspath packer/ova/$(subst build-,,$@).json)" packer/ova/packer.json

.PHONY: $(ESX_BUILD_TARGETS)
$(ESX_BUILD_TARGETS):
	packer build $(PACKER_FLAGS) -var-file="$(abspath packer/ova/$(subst build-esx-,,$@).json)" -var-file="packer/ova/esx.json" -except=shell-local packer/ova/packer.json

.PHONY: $(AMI_BUILD_TARGETS)
$(AMI_BUILD_TARGETS):
	packer build $(PACKER_FLAGS) -var-file="$(abspath packer/ami/$(subst build-,,$@).json)" packer/ami/packer.json

.PHONY: $(GCE_BUILD_TARGETS)
$(GCE_BUILD_TARGETS):
	packer build $(PACKER_FLAGS) -var-file="$(abspath packer/gce/$(subst build-,,$@).json)" packer/gce/packer.json

.PHONY: $(AZURE_BUILD_TARGETS)
$(AZURE_BUILD_TARGETS):
	. $(abspath packer/azure/scripts/init-$(subst build-azure-,,$@).sh) && packer build $(PACKER_FLAGS) -var-file="$(abspath packer/azure/azure-config.json)" -var-file="$(abspath packer/azure/$(subst build-,,$@).json)" -only="$(subst build-azure-,,$@)" packer/azure/packer.json

## --------------------------------------
## Dynamic clean targets
## --------------------------------------
OVA_CLEAN_TARGETS := $(subst build-,clean-,$(OVA_BUILD_TARGETS))
.PHONY: $(OVA_CLEAN_TARGETS)
$(OVA_CLEAN_TARGETS):
	rm -fr output/$(subst clean-ova-,,$@)*

## --------------------------------------
## Documented targets
## --------------------------------------
build-ova-centos-7: ## Builds CentOS 7 OVA w local hypervisor
build-ova-photon-3: ## Builds Photon 3 OVA w local hypervisor
build-ova-ubuntu-1804: ## Builds Ubuntu 18.04 OVA w local hypervisor
build-ova-ubuntu-2004: ## Builds Ubuntu 20.04 OVA w local hypervisor

build-esx-centos-7: ## Builds CentOS 7 OVA w remote hypervisor
build-esx-photon-3: ## Builds Photon 3 OVA w remote hypervisor
build-esx-ubuntu-1804: ## Builds Ubuntu 18.04 OVA w remote hypervisor
build-esx-ubuntu-2004: ## Builds Ubuntu 20.04 OVA w remote hypervisor

build-ami-default: ## Builds the AMI default image
build-gce-default: ## Builds the GCE default image

build-azure-ubuntu-1804: $(AZURE_BUILD_TARGETS)
build-azure-ubuntu-1804: ## Builds Ubuntu 18.04 for Azure

## --------------------------------------
## Global targets
## --------------------------------------
.PHONY: build
build:	$(OVA_BUILD_TARGETS) \
		$(AMI_BUILD_TARGETS) \
		$(GCE_BUILD_TARGETS) \
		$(AZURE_BUILD_TARGETS)
build: ## Builds all images

.PHONY: clean
clean: $(OVA_CLEAN_TARGETS)
clean: ## Cleans all local image caches
