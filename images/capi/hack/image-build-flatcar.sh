#!/bin/sh -e

set -e
#set -u

export VAGRANT_VAGRANTFILE=${VAGRANT_VAGRANTFILE:-/tmp/Vagrantfile.builder-flatcar}

usage() {
    echo "Usage: $0 [<channel>] [<version>]"
    echo "          <channel> is one of: edge alpha beta stable (defaults to"
    echo "                      stable)"
    echo "          <version> release version to use (defaults to the latest"
    echo "                      release available for <channel>)"
}
# --

list_releases() {
    curl -s \
         "https://www.flatcar-linux.org/releases-json/releases-$1.json" \
        | jq -r 'to_entries[] | "\(.key)"' \
        | grep -v "current" \
        | sort 
}
# --

fetch_vagrantfile() {
    curl -sSL -o ${VAGRANT_VAGRANTFILE} \
        https://raw.githubusercontent.com/flatcar-linux/flatcar-packer-qemu/builder-ignition/Vagrantfile.builder-flatcar
}
# --

channel="$1"
case $channel in
    edge);;
    alpha);;
    beta);;
    stable);;
    "") channel="stable";;
    *)  echo "Unknown channel '$channel'."
        usage
        exit 1;;
esac

release="$2"
if [ -z "$release" ] ; then
    release=$(list_releases "$channel" | tail -n1)
else
    list_releases "$channel" | grep -q "$release" || {
        echo "Unknown release '$release' for channel '$channel'."
        usage
        exit 1; }
fi


echo "#### Building for channel $channel, release $release."

# set packer /vagrant env vars
FLATCAR_CHANNEL="$channel"
FLATCAR_VERSION="$release"
export FLATCAR_CHANNEL FLATCAR_VERSION

rm -rf ./output/flatcar-"${channel}-${release}"-kube-*

# for now the Makefile only supports flatcar-stable.
# TODO: make it support multiple channels and versions
make build-qemu-flatcar-stable

echo "#### Fetching a test Vagrantfile remotely."

fetch_vagrantfile

echo "#### Importing $channel-$release box to vagrant and setting up kubeadm."

vagrant_name="flatcar-$channel-$release"
img_name="flatcar-${channel}-${release}_vagrant_box_image_0.img"
box_name="packer_flatcar-${channel}-${release}_libvirt.box"

export VAGRANT_VAGRANTFILE=${VAGRANT_VAGRANTFILE:-hack/Vagrantfile.flatcar}

echo "#### Cleaning up previous vagrant VMs"
vagrant halt || true
vagrant destroy -f || true
vagrant box remove "$vagrant_name" || true
virsh vol-delete --pool=default "$img_name" || true

echo "#### creating and starting VM."
vagrant box add --name="$vagrant_name" "./$box_name"
vagrant up
vagrant ssh -c 'sudo systemctl stop locksmithd'
vagrant ssh -c 'sudo systemctl restart containerd'

echo "#### Setting up kubeadm"
# shellcheck disable=SC1004
vagrant ssh -c 'sudo kubeadm init --ignore-preflight-errors=NumCPU \
                --config=/etc/kubeadm.yml'
# shellcheck disable=SC2016
vagrant ssh -c 'mkdir -p $HOME/.kube
                sudo cp -i /etc/kubernetes/admin.conf $HOME/.kube/config
                sudo chown $(id -u):$(id -g) $HOME/.kube/config'
echo
vagrant ssh -c 'kubectl cluster-info'
echo

echo "------------------------------------------------------------------"
echo "All done."
echo "You can access kubectl via 'vagrant ssh -c 'kubectl <command>'"
echo "e.g."
echo "  vagrant ssh -c 'kubectl get pods --all-namespaces'"
echo
echo " Please run:"
echo "  export FLATCAR_CHANNEL='$channel'"
echo "  export FLATCAR_VERSION='$release'"
echo "  export VAGRANT_VAGRANTFILE='$VAGRANT_VAGRANTFILE'"
echo "before using vagrant commands."

# vim:set sts=4 sw=4 et:
