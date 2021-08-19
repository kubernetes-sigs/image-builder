#!/bin/sh -e

[[ -n ${DEBUG:-} ]] && set -o xtrace

export VAGRANT_VAGRANTFILE=${VAGRANT_VAGRANTFILE:-/tmp/Vagrantfile.builder-flatcar}
export VAGRANT_SSH_PRIVATE_KEY=${VAGRANT_SSH_PRIVATE_KEY:-/tmp/vagrant-insecure-key}
export VAGRANT_SSH_PUBLIC_KEY=${VAGRANT_SSH_PUBLIC_KEY:-/tmp/vagrant-insecure-key.pub}

CONTAINERD_TMPDIR="$(mktemp -d)"
CONTAINERD_CHECKSUM_FILE="${CONTAINERD_TMPDIR}/containerd-sha256sum"
PACKER_VAR_FILES_CONTAINERD="${CONTAINERD_TMPDIR}/containerd.json"

usage() {
    echo "Usage: $0 [<channel>] [<version>]"
    echo "          <channel> is one of: edge alpha beta stable (defaults to"
    echo "                      stable)"
    echo "          <version> release version to use (defaults to the latest"
    echo "                      release available for <channel>)"
    echo ""
    echo "To specify Flatcar-specific containerd version and/or its sha256:"
    echo ""
    echo "  FLATCAR_CONTAINERD_VERSION=1.5.4 FLATCAR_CONTAINERD_SHA256=abcd... ./hack/image-build-flatcar.sh"
}
# --

check_for_release() {
    channel="$1"
    release="$2"
    curl -L -s \
         "https://kinvolk.io/flatcar-container-linux/releases-json/releases-$channel.json" \
        | jq -r 'to_entries[] | "\(.key)"' \
        | grep -q "$release"
}
# --

fetch_vagrant_ssh_keys() {
    curl -sSL -o ${VAGRANT_SSH_PRIVATE_KEY} \
        https://raw.githubusercontent.com/hashicorp/vagrant/master/keys/vagrant
    curl -sSL -o ${VAGRANT_SSH_PUBLIC_KEY} \
        https://raw.githubusercontent.com/hashicorp/vagrant/master/keys/vagrant.pub
}
# --

fetch_vagrantfile() {
    curl -sSL -o ${VAGRANT_VAGRANTFILE} \
        https://raw.githubusercontent.com/flatcar-linux/flatcar-packer-qemu/builder-ignition/Vagrantfile.builder-flatcar
}
# --

run_vagrant() {
    echo "#### Fetching a test Vagrantfile remotely."

    fetch_vagrantfile

    echo "#### Importing $channel box to vagrant and setting up kubeadm."

    vagrant_name="flatcar-${channel}-${release}"
    img_name="flatcar-${channel}-${release}_vagrant_box_image_0.img"
    box_name="packer_flatcar_libvirt.box"

    export VAGRANT_VAGRANTFILE="${VAGRANT_VAGRANTFILE:-hack/Vagrantfile.flatcar}"
    export VAGRANT_DEFAULT_PROVIDER="libvirt"

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
}

function create_containerd_config() {
    [ -z "${FLATCAR_CONTAINERD_VERSION}" ] && return

    if [ -z "${FLATCAR_CONTAINERD_SHA256}" ]; then
        curl -Ls -o ${CONTAINERD_CHECKSUM_FILE} \
            "https://github.com/containerd/containerd/releases/download/v${FLATCAR_CONTAINERD_VERSION}/cri-containerd-cni-${FLATCAR_CONTAINERD_VERSION}-linux-amd64.tar.gz.sha256sum"
        FLATCAR_CONTAINERD_SHA256="$(cat ${CONTAINERD_CHECKSUM_FILE} | cut -f1 -d \  )"
    fi

    echo "{\"containerd_sha256\": \"${FLATCAR_CONTAINERD_SHA256}\", \"containerd_version\": \"${FLATCAR_CONTAINERD_VERSION}\"}" \
        > ${PACKER_VAR_FILES_CONTAINERD}
}

function cleanup_containerd_config() {
    rm -rf ${CONTAINERD_TMPDIR}
}

trap cleanup_containerd_config INT KILL EXIT

CAPI_PROVIDER=${CAPI_PROVIDER:-qemu}

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
if [ -n "$release" ] ; then
    check_for_release "$channel" "$release" || {
        echo "Unknown release '$release' for channel '$channel'."
        usage
        exit 1; }
else
    release="$(\
       "$(dirname "$0")"/image-grok-latest-flatcar-version.sh "$channel")"
fi


echo "#### Building for channel $channel, release $release."

# set packer /vagrant env vars
FLATCAR_CHANNEL="$channel"
FLATCAR_VERSION="$release"
export FLATCAR_CHANNEL FLATCAR_VERSION

rm -rf ./output/flatcar-"${channel}-${release}"-kube-*

create_containerd_config

if [ -f "${PACKER_VAR_FILES_CONTAINERD}" ]; then
    FLATCAR_MAKE_OPTS+="PACKER_VAR_FILES=${PACKER_VAR_FILES_CONTAINERD} "
fi

if [[ ${CAPI_PROVIDER} = "qemu" ]]; then
    FLATCAR_MAKE_OPTS+="FLATCAR_CHANNEL=$channel FLATCAR_VERSION=$release "
    FLATCAR_MAKE_OPTS+="SSH_PRIVATE_KEY_FILE=${VAGRANT_SSH_PRIVATE_KEY} "
    FLATCAR_MAKE_OPTS+="SSH_PUBLIC_KEY_FILE=${VAGRANT_SSH_PUBLIC_KEY} "

    fetch_vagrant_ssh_keys
    make ${FLATCAR_MAKE_OPTS} build-qemu-flatcar
    run_vagrant
elif [[ ${CAPI_PROVIDER} = "aws" ]] || [[ ${CAPI_PROVIDER} = "ami" ]]; then
    make ${FLATCAR_MAKE_OPTS} build-ami-flatcar
else
    echo "Unknown CAPI_PROVIDER=${CAPI_PROVIDER}. exit."
    exit 1
fi

exit 0

# vim:set sts=4 sw=4 et:
