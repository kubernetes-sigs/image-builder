.PHONY: all
all: buster-qemu buster-aws

.PHONY: buster-base
buster-base:
	DOCKER_BUILDKIT=1 docker build -t buster-base buster-base/

.PHONY: buster-qemu
buster-qemu: buster-base
	DOCKER_BUILDKIT=1 docker build -t buster-qemu buster-qemu/

.PHONY: buster-aws
buster-aws: buster-base
	DOCKER_BUILDKIT=1 docker build -t buster-aws buster-aws/

.PHONY: buster-gce
buster-gce: buster-base
	DOCKER_BUILDKIT=1 docker build -t buster-gce buster-gce/
