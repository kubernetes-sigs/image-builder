# Copyright (c) 2019 The Kubernetes authors
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

.DEFAULT_GOAL := help

.PHONY: help
help: ## Display this help and the help for images/capi/Makefile
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z0-9_-]+:.*?##/ { printf "  \033[36m%-35s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) } ' $(MAKEFILE_LIST)
	@echo
	@echo Targets handled by images/capi/Makefile:
	@$(MAKE) -C images/capi help

.PHONY: build-book
build-book: ## Build the image-builder book
	docs/book/build.sh

.PHONY: serve-book
serve-book: ## Build and serve the image-builder book with live-reloading enabled
	$(MAKE) -C docs/book serve

.PHONY: update-release-docs
update-release-docs: ## Updates the docs with reference to the latest release version
	images/capi/scripts/release-update-docs.sh

.DEFAULT:
	$(MAKE) -C images/capi $@
