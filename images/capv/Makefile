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
# of BUILD_NAMES must have a corresponding file "config/BUILD_NAME.json".
BUILD_NAMES ?= centos-7 ubuntu-1804

# The version of Kubernetes to install.
KUBE_JSON ?= config/kubernetes.json

# The flags to give to Packer.
PACKER_VAR_FILES := $(KUBE_JSON)
OLD_PACKER_FLAGS := $(PACKER_FLAGS)
PACKER_FLAGS := -var="capv_version=$(shell git describe --dirty)"
PACKER_FLAGS += $(foreach f,$(abspath $(PACKER_VAR_FILES)),-var-file="$(f)" )
PACKER_FLAGS += $(OLD_PACKER_FLAGS)

BUILD_TARGETS := $(addprefix build-,$(BUILD_NAMES))
$(BUILD_TARGETS):
	cd packer && packer build $(PACKER_FLAGS) -var-file="$(abspath config/$(subst build-,,$@).json)" packer.json
.PHONY: $(BUILD_TARGETS)

CLEAN_TARGETS := $(addprefix clean-,$(BUILD_NAMES))
$(CLEAN_TARGETS):
	rm -fr packer/output/$(subst clean-,,$@)*
.PHONY: $(CLEAN_TARGETS)

build: $(BUILD_TARGETS)
clean: $(CLEAN_TARGETS)
.PHONY: build clean
