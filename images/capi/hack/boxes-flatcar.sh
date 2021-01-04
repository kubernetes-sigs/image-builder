#!/bin/sh

[[ -n ${DEBUG:-} ]] && set -o xtrace

export VAGRANT_VAGRANTFILE=${VAGRANT_VAGRANTFILE:-/tmp/Vagrantfile.builder-flatcar}

fetch_vagrantfile() {
    curl -sSL -o ${VAGRANT_VAGRANTFILE} \
        https://raw.githubusercontent.com/flatcar-linux/flatcar-packer-qemu/builder-ignition/Vagrantfile.builder-flatcar
}

list_boxes() {
    vagrant box list \
        | grep -E '^flatcar-(alpha|beta|stable|edge)-[0-9.]+' \
        | sed 's/flatcar-\(alpha\|beta\|stable\|edge\)-\([0-9.]\+\).*/\1 \2/'
}

fetch_vagrantfile

list_boxes | while read -r channel release; do
    export FLATCAR_CHANNEL="$channel"
    export FLATCAR_VERSION="$release"

    echo "##############################################"
    echo "Image:"
    virsh vol-info --pool default "flatcar-${channel}-${release}_vagrant_box_image_0.img"
    echo "Env:"
    echo "  export FLATCAR_CHANNEL='$channel'"
    echo "  export FLATCAR_VERSION='$release'"
    echo "  export VAGRANT_VAGRANTFILE='$VAGRANT_VAGRANTFILE'"

    # shellcheck disable=SC2016
    vagrant status | grep -v 'Run `vagrant up`'

    [ "$1" = "cleanup" ] && {
        echo "#### Cleaning up vagrant VM"

        img_name="flatcar-${channel}-${release}_vagrant_box_image_0.img"
        box_name="packer_flatcar-${channel}-${release}_libvirt.box"
        vagrant_name="flatcar-$channel-$release"

        vagrant halt
        vagrant destroy -f
        vagrant box remove "$vagrant_name"
        virsh vol-delete --pool=default "$img_name"

        rm -f "$box_name"
    }
done
