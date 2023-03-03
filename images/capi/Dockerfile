# syntax=docker/dockerfile:1.1-experimental

# Copyright 2020 The Kubernetes Authors.
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

ARG BASE_IMAGE=docker.io/library/ubuntu:latest
FROM $BASE_IMAGE

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
	apt-transport-https \
	build-essential \
	ca-certificates \
	curl \
	git \
	jq \
	python3-pip \
	rsync \
	unzip \
	vim \
	wget \
	qemu-system-x86 \
	qemu-kvm \
    && useradd -ms /bin/bash imagebuilder \
    && apt-get purge --auto-remove -y \
    && rm -rf /var/lib/apt/lists/*

ARG ARCH
ARG PASSED_IB_VERSION

USER imagebuilder
WORKDIR /home/imagebuilder/

COPY --chown=imagebuilder:imagebuilder ansible ansible/
COPY --chown=imagebuilder:imagebuilder ansible.cfg ansible.cfg
COPY --chown=imagebuilder:imagebuilder cloudinit cloudinit/
COPY --chown=imagebuilder:imagebuilder hack hack/
COPY --chown=imagebuilder:imagebuilder packer packer/
COPY --chown=imagebuilder:imagebuilder Makefile Makefile
COPY --chown=imagebuilder:imagebuilder azure_targets.sh azure_targets.sh

ENV PATH="/home/imagebuilder/.local/bin:${PATH}"
ENV PACKER_ARGS ''
ENV PACKER_VAR_FILES ''
ENV IB_VERSION "${PASSED_IB_VERSION}"

RUN make deps

ENTRYPOINT [ "/usr/bin/make" ]
