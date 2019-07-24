K8S_VERSION=1.15
KONFIGADM_VERSION=0.4.0
CMD=konfigadm images build --resize +2G --output-dir images -vv "k8s-$(K8S_VERSION).yml"
$(shell mkdir -p images)

.PHONY: setup
setup:
  # TODO(moshloop) remove dependency on privately owned repository - See GH Issue #9
	$(shell which konfigadm > /dev/null || \
		wget https://github.com/moshloop/konfigadm/releases/download/$(KONFIGADM_VERSION)/konfigadm.deb && \
		dpkg -i konfigadm.deb)

.PHONY: ubuntu1804
ubuntu1804:
	$(CMD) --image ubuntu1804 --output-filename ubuntu-1804.img

.PHONY: debian
debian:
	$(CMD) --image debian --output-filename debian.img

.PHONY: centos7
centos7:
	$(CMD) --image centos7 --output-filename centos7.img

.PHONY: fedora
fedora:
	$(CMD) --image fedora --output-filename fedora.img

