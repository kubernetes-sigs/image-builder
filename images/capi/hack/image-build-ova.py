#!/usr/bin/python

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

################################################################################
# usage: image-build-ova.py [FLAGS] ARGS
#  This program builds an OVA file from a VMDK and manifest file generated as a
#  result of a Packer build.
################################################################################

import argparse
import hashlib
import io
import json
import os
import subprocess
from string import Template
import tarfile


def main():
    parser = argparse.ArgumentParser(
        description="Builds an OVA using the artifacts from a Packer build")
    parser.add_argument('--vmx',
                        dest='vmx_version',
                        default='13',
                        help='The virtual hardware version')
    parser.add_argument('--eula_file',
                        nargs='?',
                        metavar='EULA',
                        default='./ovf_eula.txt',
                        help='Text file containing EULA')
    parser.add_argument(dest='build_dir',
                        nargs='?',
                        metavar='BUILD_DIR',
                        default='.',
                        help='The Packer build directory')
    args = parser.parse_args()

    # Read in the EULA
    eula = ""
    with io.open(args.eula_file, 'r', encoding='utf-8') as f:
        eula = f.read()

    # Change the working directory if one is specified.
    os.chdir(args.build_dir)
    print("image-build-ova: cd %s" % args.build_dir)

    # Load the packer manifest JSON
    data = None
    with open('packer-manifest.json', 'r') as f:
        data = json.load(f)

    # Get the first build.
    build = data['builds'][0]
    build_data = build['custom_data']
    print("image-build-ova: loaded %s-kube-%s" % (build['name'],
                                                  build_data['kubernetes_semver']))

    # Get a list of the VMDK files from the packer manifest.
    vmdk_files = get_vmdk_files(build['files'])

    # Create stream-optimized versions of the VMDK files.
    stream_optimize_vmdk_files(vmdk_files)

    # TODO(akutz) Support multiple VMDK files in the OVF/OVA
    vmdk = vmdk_files[0]

    # Create the OVF file.
    ovf = "%s.ovf" % build['name']
    create_ovf(ovf, {
        'BUILD_DATE': build_data['build_date'],
        'BUILD_NAME': build['name'],
        'ARTIFACT_ID': build['artifact_id'],
        'BUILD_TIMESTAMP': build_data['build_timestamp'],
        'CNI_VERSION': build_data['kubernetes_cni_semver'],
        'EULA': eula,
        'OS_NAME': build_data['os_name'],
        'ISO_CHECKSUM': build_data['iso_checksum'],
        'ISO_CHECKSUM_TYPE': build_data['iso_checksum_type'],
        'ISO_URL': build_data['iso_url'],
        'KUBERNETES_SEMVER': build_data['kubernetes_semver'],
        'KUBERNETES_SOURCE_TYPE': build_data['kubernetes_source_type'],
        'POPULATED_DISK_SIZE': vmdk['size'],
        'STREAM_DISK_SIZE': vmdk['stream_size'],
        'VMX_VERSION': args.vmx_version,
    })

    # Create the OVA manifest.
    ova_manifest = "%s.mf" % build['name']
    create_ova_manifest(ova_manifest, [ovf, vmdk['stream_name']])

    # Create the OVA.
    ova = "%s.ova" % build['name']
    create_ova(ova, [ovf, ova_manifest, vmdk['stream_name']])


def sha256(path):
    m = hashlib.sha256()
    with open(path, 'rb') as f:
        while True:
            data = f.read(65536)
            if not data:
                break
            m.update(data)
    return m.hexdigest()


def create_ova(path, infile_paths):
    print("image-build-ova: create ova %s" % path)
    with open(path, 'wb') as f:
        with tarfile.open(fileobj=f, mode='w|') as tar:
            for infile_path in infile_paths:
                tar.add(infile_path)

    chksum_path = "%s.sha256" % path
    print("image-build-ova: create ova checksum %s" % chksum_path)
    with open(chksum_path, 'w') as f:
        f.write(sha256(path))


def create_ovf(path, data):
    print("image-build-ova: create ovf %s" % path)
    with io.open(path, 'w', encoding='utf-8') as f:
        f.write(Template(_OVF_TEMPLATE).substitute(data))


def create_ova_manifest(path, infile_paths):
    print("image-build-ova: create ova manifest %s" % path)
    with open(path, 'w') as f:
        for i in infile_paths:
            f.write('SHA256(%s)= %s\n' % (i, sha256(i)))


def get_vmdk_files(inlist):
    outlist = []
    for f in inlist:
        if f['name'].endswith('.vmdk'):
            outlist.append(f)
    return outlist


def stream_optimize_vmdk_files(inlist):
    for f in inlist:
        infile = f['name']
        outfile = infile.replace('.vmdk', '.ova.vmdk', 1)
        if os.path.isfile(outfile):
            os.remove(outfile)
        args = [
            'vmware-vdiskmanager',
            '-r', infile,
            '-t', '5',
            outfile
        ]
        print("image-build-ova: stream optimize %s --> %s (1-2 minutes)" %
              (infile, outfile))
        subprocess.check_call(args)
        f['stream_name'] = outfile
        f['stream_size'] = os.path.getsize(outfile)


_OVF_TEMPLATE = '''<?xml version='1.0' encoding='UTF-8'?>
<Envelope xmlns="http://schemas.dmtf.org/ovf/envelope/1" xmlns:ovf="http://schemas.dmtf.org/ovf/envelope/1" xmlns:vmw="http://www.vmware.com/schema/ovf" xmlns:rasd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_ResourceAllocationSettingData" xmlns:vssd="http://schemas.dmtf.org/wbem/wscim/1/cim-schema/2/CIM_VirtualSystemSettingData">
  <References>
    <File ovf:id="file1" ovf:href="${BUILD_NAME}.ova.vmdk" ovf:size="${STREAM_DISK_SIZE}"/>
  </References>
  <DiskSection>
    <Info>List of the virtual disks</Info>
    <Disk ovf:capacity="20" ovf:capacityAllocationUnits="byte * 2^30" ovf:format="http://www.vmware.com/interfaces/specifications/vmdk.html#streamOptimized" ovf:diskId="vmdisk1" ovf:fileRef="file1" ovf:populatedSize="${POPULATED_DISK_SIZE}"/>
  </DiskSection>
  <NetworkSection>
    <Info>The list of logical networks</Info>
    <Network ovf:name="nic0">
      <Description>Please select a network</Description>
    </Network>
  </NetworkSection>
  <vmw:StorageGroupSection ovf:required="false" vmw:id="group1" vmw:name="vSAN Default Storage Policy">
    <Info>Storage policy for group of disks</Info>
    <vmw:Description>The vSAN Default Storage Policy storage policy group</vmw:Description>
  </vmw:StorageGroupSection>
  <VirtualSystem ovf:id="${ARTIFACT_ID}">
    <Info>A Virtual system</Info>
    <Name>${ARTIFACT_ID}</Name>
    <AnnotationSection>
      <Info>A human-readable annotation</Info>
      <Annotation>Cluster API vSphere image - ${OS_NAME} and Kubernetes ${KUBERNETES_SEMVER} - https://github.com/kubernetes-sigs/cluster-api-provider-vsphere/tree/master/build/images</Annotation>
    </AnnotationSection>
    <OperatingSystemSection ovf:id="101" vmw:osType="other3xLinux64Guest">
      <Info>The operating system installed</Info>
      <Description>Other 3.x or later Linux (64-bit)</Description>
    </OperatingSystemSection>
    <VirtualHardwareSection>
      <Info>Virtual hardware requirements</Info>
      <System>
        <vssd:ElementName>Virtual Hardware Family</vssd:ElementName>
        <vssd:InstanceID>0</vssd:InstanceID>
        <vssd:VirtualSystemType>vmx-${VMX_VERSION}</vssd:VirtualSystemType>
      </System>
      <Item>
        <rasd:AllocationUnits>hertz * 10^6</rasd:AllocationUnits>
        <rasd:Description>Number of Virtual CPUs</rasd:Description>
        <rasd:ElementName>2 virtual CPU(s)</rasd:ElementName>
        <rasd:InstanceID>1</rasd:InstanceID>
        <rasd:ResourceType>3</rasd:ResourceType>
        <rasd:VirtualQuantity>2</rasd:VirtualQuantity>
        <vmw:CoresPerSocket ovf:required="false">2</vmw:CoresPerSocket>
      </Item>
      <Item>
        <rasd:AllocationUnits>byte * 2^20</rasd:AllocationUnits>
        <rasd:Description>Memory Size</rasd:Description>
        <rasd:ElementName>2048MB of memory</rasd:ElementName>
        <rasd:InstanceID>2</rasd:InstanceID>
        <rasd:ResourceType>4</rasd:ResourceType>
        <rasd:VirtualQuantity>2048</rasd:VirtualQuantity>
      </Item>
      <Item>
        <rasd:Address>0</rasd:Address>
        <rasd:Description>SCSI Controller</rasd:Description>
        <rasd:ElementName>SCSI Controller 1</rasd:ElementName>
        <rasd:InstanceID>3</rasd:InstanceID>
        <rasd:ResourceSubType>lsilogic</rasd:ResourceSubType>
        <rasd:ResourceType>6</rasd:ResourceType>
        <vmw:Config ovf:required="false" vmw:key="slotInfo.pciSlotNumber" vmw:value="160"/>
      </Item>
      <Item>
        <rasd:Address>1</rasd:Address>
        <rasd:Description>IDE Controller</rasd:Description>
        <rasd:ElementName>IDE Controller 1</rasd:ElementName>
        <rasd:InstanceID>4</rasd:InstanceID>
        <rasd:ResourceType>5</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:ElementName>Hard Disk 1</rasd:ElementName>
        <rasd:HostResource>ovf:/disk/vmdisk1</rasd:HostResource>
        <rasd:InstanceID>5</rasd:InstanceID>
        <rasd:Parent>3</rasd:Parent>
        <rasd:ResourceType>17</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:AutomaticAllocation>false</rasd:AutomaticAllocation>
        <rasd:ElementName>CD/DVD Drive 1</rasd:ElementName>
        <rasd:InstanceID>6</rasd:InstanceID>
        <rasd:Parent>4</rasd:Parent>
        <rasd:ResourceSubType>vmware.cdrom.atapi</rasd:ResourceSubType>
        <rasd:ResourceType>15</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:AutomaticAllocation>false</rasd:AutomaticAllocation>
        <rasd:Description>Floppy Drive</rasd:Description>
        <rasd:ElementName>Floppy Drive 1</rasd:ElementName>
        <rasd:InstanceID>7</rasd:InstanceID>
        <rasd:ResourceSubType>vmware.floppy.device</rasd:ResourceSubType>
        <rasd:ResourceType>14</rasd:ResourceType>
      </Item>
      <Item>
        <rasd:AddressOnParent>0</rasd:AddressOnParent>
        <rasd:AutomaticAllocation>true</rasd:AutomaticAllocation>
        <rasd:Connection>nic0</rasd:Connection>
        <rasd:ElementName>Network adapter 1</rasd:ElementName>
        <rasd:InstanceID>8</rasd:InstanceID>
        <rasd:ResourceSubType>VmxNet3</rasd:ResourceSubType>
        <rasd:ResourceType>10</rasd:ResourceType>
        <vmw:Config ovf:required="false" vmw:key="slotInfo.pciSlotNumber" vmw:value="192"/>
        <vmw:Config ovf:required="false" vmw:key="connectable.allowGuestControl" vmw:value="true"/>
        <vmw:Config ovf:required="false" vmw:key="wakeOnLanEnabled" vmw:value="false"/>
      </Item>
      <Item ovf:required="false">
        <rasd:ElementName>Video card</rasd:ElementName>
        <rasd:InstanceID>9</rasd:InstanceID>
        <rasd:ResourceType>24</rasd:ResourceType>
        <vmw:Config ovf:required="false" vmw:key="enable3DSupport" vmw:value="false"/>
        <vmw:Config ovf:required="false" vmw:key="graphicsMemorySizeInKB" vmw:value="262144"/>
        <vmw:Config ovf:required="false" vmw:key="useAutoDetect" vmw:value="false"/>
        <vmw:Config ovf:required="false" vmw:key="videoRamSizeInKB" vmw:value="4096"/>
        <vmw:Config ovf:required="false" vmw:key="numDisplays" vmw:value="1"/>
        <vmw:Config ovf:required="false" vmw:key="use3dRenderer" vmw:value="automatic"/>
      </Item>
      <vmw:Config ovf:required="false" vmw:key="flags.vbsEnabled" vmw:value="false"/>
      <vmw:Config ovf:required="false" vmw:key="cpuHotAddEnabled" vmw:value="false"/>
      <vmw:Config ovf:required="false" vmw:key="nestedHVEnabled" vmw:value="false"/>
      <vmw:Config ovf:required="false" vmw:key="virtualSMCPresent" vmw:value="false"/>
      <vmw:Config ovf:required="false" vmw:key="flags.vvtdEnabled" vmw:value="false"/>
      <vmw:Config ovf:required="false" vmw:key="cpuHotRemoveEnabled" vmw:value="false"/>
      <vmw:Config ovf:required="false" vmw:key="memoryHotAddEnabled" vmw:value="false"/>
      <vmw:Config ovf:required="false" vmw:key="bootOptions.efiSecureBootEnabled" vmw:value="false"/>
      <vmw:Config ovf:required="false" vmw:key="firmware" vmw:value="bios"/>
      <vmw:Config ovf:required="false" vmw:key="virtualICH7MPresent" vmw:value="false"/>
    </VirtualHardwareSection>
    <vmw:StorageSection ovf:required="false" vmw:group="group1">
      <Info>Storage policy group reference</Info>
    </vmw:StorageSection>
    <EulaSection>
      <Info>An end-user license agreement</Info>
      <License>
${EULA}
      </License>
    </EulaSection>
    <ProductSection>
      <Info>Information about the installed software</Info>
      <Product>${OS_NAME} and Kubernetes ${KUBERNETES_SEMVER}</Product>
      <Vendor>VMware Inc.</Vendor>
      <Version>kube-${KUBERNETES_SEMVER}</Version>
      <FullVersion>kube-${KUBERNETES_SEMVER}</FullVersion>
      <ProductUrl>https://github.com/kubernetes-sigs/cluster-api-provider-vsphere</ProductUrl>
      <VendorUrl>https://vmware.com</VendorUrl>
      <Category>Cluster API Provider (CAPI)</Category>
      <Property ovf:userConfigurable="false" ovf:value="${BUILD_TIMESTAMP}" ovf:type="string" ovf:key="BUILD_TIMESTAMP"></Property>
      <Property ovf:userConfigurable="false" ovf:value="${BUILD_DATE}" ovf:type="string" ovf:key="BUILD_DATE"></Property>
      <Property ovf:userConfigurable="false" ovf:value="${CNI_VERSION}" ovf:type="string" ovf:key="CNI_VERSION"></Property>
      <Property ovf:userConfigurable="false" ovf:value="${ISO_URL}" ovf:type="string" ovf:key="ISO_URL"></Property>
      <Property ovf:userConfigurable="false" ovf:value="${ISO_CHECKSUM}" ovf:type="string" ovf:key="ISO_CHECKSUM"></Property>
      <Property ovf:userConfigurable="false" ovf:value="${ISO_CHECKSUM_TYPE}" ovf:type="string" ovf:key="ISO_CHECKSUM_TYPE"></Property>
      <Property ovf:userConfigurable="false" ovf:value="${KUBERNETES_SEMVER}" ovf:type="string" ovf:key="KUBERNETES_SEMVER"></Property>
      <Property ovf:userConfigurable="false" ovf:value="${KUBERNETES_SOURCE_TYPE}" ovf:type="string" ovf:key="KUBERNETES_SOURCE_TYPE"></Property>
    </ProductSection>
  </VirtualSystem>
</Envelope>
'''

if __name__ == "__main__":
    main()
