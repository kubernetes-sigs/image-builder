#!/usr/bin/env bash

# Copyright 2022 The Kubernetes Authors.
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

function xen_server_export() {
    echo "Creating XenServer Export for $1"
    qemu-img convert -f qcow2 -O raw "$1" "$1".raw
    vhd-util convert -s 0 -t 1 -i "$1".raw -o "$1".vhd
    faketime '2010-01-01' vhd-util convert -s 1 -t 2 -i "$1".vhd -o "$1-xen.vhd"
    rm -f *.bak
    echo "Created .vhd file, now zipping"
    bzip2 "$1-xen.vhd"
    chmod +r "$1-xen.vhd.bz2"
    echo "$1 exported for XenServer: $1-xen.vhd.bz2"
}

function vmware_export() {
    echo "Creating VMware Export for $1"
    qemu-img convert -f qcow2 -O vmdk -o adapter_type=lsilogic,subformat=streamOptimized,compat6 "$1" "$1-vmware.vmdk"
    CDIR=$PWD
    chmod 666 $1-vmware.vmdk
    stage_vmx $1-vmware $1-vmware.vmdk
    ovftool $1-vmware.vmx $1-vmware.ova
    rm -f $1-vmware*.vmx $1-vmware*.vmdk
    cd $CDIR
    chmod +r "$1-vmware.ova"
    echo "$1 exported for VMware: $1-vmware.ova"
}

function stage_vmx() {
  cat << VMXFILE > "${1}.vmx"
.encoding = "UTF-8"
displayname = "${1}"
annotation = "${1}"
guestos = "otherlinux-64"
virtualHW.version = "11"
config.version = "8"
numvcpus = "2"
cpuid.coresPerSocket = "2"
memsize = "2048"
pciBridge0.present = "TRUE"
pciBridge4.present = "TRUE"
pciBridge4.virtualDev = "pcieRootPort"
pciBridge4.functions = "8"
pciBridge5.present = "TRUE"
pciBridge5.virtualDev = "pcieRootPort"
pciBridge5.functions = "8"
pciBridge6.present = "TRUE"
pciBridge6.virtualDev = "pcieRootPort"
pciBridge6.functions = "8"
pciBridge7.present = "TRUE"
pciBridge7.virtualDev = "pcieRootPort"
pciBridge7.functions = "8"
vmci0.present = "TRUE"
floppy0.present = "FALSE"
ide0:0.clientDevice = "FALSE"
ide0:0.present = "TRUE"
ide0:0.deviceType = "atapi-cdrom"
ide0:0.autodetect = "TRUE"
ide0:0.startConnected = "FALSE"
mks.enable3d = "false"
svga.autodetect = "false"
svga.vramSize = "134217728"
scsi0:0.present = "TRUE"
scsi0:0.deviceType = "disk"
scsi0:0.fileName = "$2"
scsi0:0.mode = "persistent"
scsi0:0.writeThrough = "false"
scsi0.virtualDev = "lsilogic"
scsi0.present = "TRUE"
vmci0.unrestricted = "false"
vcpu.hotadd = "false"
vcpu.hotremove = "false"
firmware = "bios"
mem.hotadd = "false"
VMXFILE
}

usage() {
    echo "Converts a qcow2 image to any of the following formats"
    echo "  - x : XenServer [vhd]"
    echo "  - v : VMware [ova]"
    echo "Usage: $0 QCOW2_IMAGE FORMAT" 1>&2
}

if [ "$1" = "-h" ]; then
    usage
    exit
fi

FILE=$1
if [ -z $FILE ]; then
    usage
    echo "File not specified. Exiting"
    exit 1
fi

FORMAT=$2
if [ -z $FILE ]; then
    usage
    echo "Format not specified. Exiting"
    exit 1
fi

if [ ! -f $FILE ]; then
    echo "File '$FILE' not found"
    exit 1
fi

case $FORMAT in
    v)
       vmware_export $FILE
       ;;
    x)
        xen_server_export $FILE
        ;;
    all)
        vmware_export $FILE
        xen_server_export $FILE
        ;;
    *)
        echo "Unknown format. Supported options are [x, v]"
        exit 1
esac
