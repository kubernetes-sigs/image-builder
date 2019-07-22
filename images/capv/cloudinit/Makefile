all: build

CONFIG_DIR ?= .cidata-$(shell date +%s)
CONFIG_DIR ?= $(abspath $(CONFIG_DIR))

ifneq (,$(strip $(KUBERNETES_VERSION)))
ISO ?= cidata-$(KUBERNETES_VERSION).iso
endif
ISO ?= cidata.iso
ISO := $(abspath $(ISO))

$(ISO):
	@rm -f $@
	@mkdir -p $(CONFIG_DIR) && cp user-data meta-data $(CONFIG_DIR)/
ifneq (,$(strip $(KUBERNETES_VERSION)))
	sed 's/kubernetesVersion: v1.13.6/kubernetesVersion: $(KUBERNETES_VERSION)/' >$(CONFIG_DIR)/user-data <user-data
	@rm -f $(CONFIG_DIR)/user-data.bak
endif
ifneq (,$(strip $(shell command -v genisoimage 2>/dev/null)))
	cd $(CONFIG_DIR) && genisoimage -output $@ -volid cidata -joliet -rock user-data meta-data
else
	hdiutil makehybrid -o $@ -hfs -joliet -iso -default-volume-name cidata $(CONFIG_DIR)
endif
	@rm -fr $(CONFIG_DIR)
.PHONY: $(ISO)

build: $(ISO)

clean:
	rm -fr .cidata-* *.iso *.tar.gz
.PHONY: clean
