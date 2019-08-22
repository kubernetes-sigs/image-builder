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

all: build

# A list of the supported distribution/version combinations. Each member
# of *_BUILD_NAMES must have a corresponding file "config/*_BUILD_NAME.json".
OVA_BUILD_NAMES ?= ova-centos-7 ova-ubuntu-1804
AMI_BUILD_NAMES ?= ami-default

# The version of Kubernetes to install.
KUBE_JSON ?= packer/config/kubernetes.json packer/config/cni.json packer/config/containerd.json

# The flags to give to Packer.
PACKER_VAR_FILES := $(KUBE_JSON)
OLD_PACKER_FLAGS := $(PACKER_FLAGS)
PACKER_FLAGS := $(foreach f,$(abspath $(PACKER_VAR_FILES)),-var-file="$(f)" )
PACKER_FLAGS += $(OLD_PACKER_FLAGS)

OVA_BUILD_TARGETS := $(addprefix build-,$(OVA_BUILD_NAMES))
AMI_BUILD_TARGETS := $(addprefix build-,$(AMI_BUILD_NAMES))
$(OVA_BUILD_TARGETS):
	packer build $(PACKER_FLAGS) -var-file="$(abspath packer/ova/$(subst build-,,$@).json)" packer/ova/packer.json
.PHONY: $(OVA_BUILD_TARGETS)

$(AMI_BUILD_TARGETS):
	packer build $(PACKER_FLAGS) -var-file="$(abspath packer/ami/$(subst build-,,$@).json)" packer/ami/packer.json
.PHONY: $(AMI_BUILD_TARGETS)

CLEAN_TARGETS := $(addprefix clean-,$(OVA_BUILD_NAMES)) $(addprefix clean-,$(AMI_BUILD_NAMES))
$(CLEAN_TARGETS):
	rm -fr output/$(subst clean-,,$@)*
.PHONY: $(CLEAN_TARGETS)

build: $(OVA_BUILD_TARGETS) $(AMI_BUILD_TARGETS)
clean: $(CLEAN_TARGETS)
.PHONY: build clean
