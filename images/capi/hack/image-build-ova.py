#!/usr/bin/env python3

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
    parser.add_argument('--stream_vmdk',
                        dest='stream_vmdk',
                        action='store_true',
                        help='Compress vmdk file')
    parser.add_argument('--vmx',
                        dest='vmx_version',
                        default='15',
                        help='The virtual hardware version')
    parser.add_argument('--eula_file',
                        nargs='?',
                        metavar='EULA',
                        default='./ovf_eula.txt',
                        help='Text file containing EULA')
    parser.add_argument('--ovf_template',
                        nargs='?',
                        metavar='OVF_TEMPLATE',
                        default='./ovf_template.xml',
                        help='XML template to build OVF')
    parser.add_argument('--vmdk_file',
                        nargs='?',
                        metavar='FILE',
                        default=None,
                        help='Use FILE as VMDK instead of reading from manifest. '
                             'Must be in BUILD_DIR')
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

    # Read in the OVF template
    ovf_template = ""
    with io.open(args.ovf_template, 'r', encoding='utf-8') as f:
        ovf_template = f.read()

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

    print("image-build-ova: loaded %s-kube-%s" % (build_data['build_name'],
                                                  build_data['kubernetes_semver']))

    if args.vmdk_file is None:
        # Get a list of the VMDK files from the packer manifest.
        vmdk_files = get_vmdk_files(build['files'])
    else:
        vmdk_files = [{"name": args.vmdk_file, "size": os.path.getsize(args.vmdk_file)}]

    # Create stream-optimized versions of the VMDK files.
    if args.stream_vmdk is True:
        stream_optimize_vmdk_files(vmdk_files)
    else:
        for f in vmdk_files:
            f['stream_name'] = f['name']
            f['stream_size'] = os.path.getsize(f['name'])

    # TODO(akutz) Support multiple VMDK files in the OVF/OVA
    vmdk = vmdk_files[0]

    OS_id_map = {"vmware-photon-64": {"id": "36", "version": "", "type": "vmwarePhoton64Guest"},
                 "centos7-64": {"id": "107", "version": "7", "type": "centos7_64Guest"},
                 "centos8-64": {"id": "107", "version": "8", "type": "centos8_64Guest"},
                 "rhel8-64": {"id": "80", "version": "8", "type": "rhel8_64Guest"},
                 "rhel9-64": {"id": "80", "version": "9", "type": "rhel9_64Guest"},
                 "rockylinux-64": {"id": "80", "version": "", "type": "rockylinux_64Guest"},
                 "ubuntu-64": {"id": "94", "version": "", "type": "ubuntu64Guest"},
                 "flatcar-64": {"id": "100", "version": "", "type": "other4xLinux64Guest"},
                 "Windows2019Server-64": {"id": "112", "version": "", "type": "windows2019srv_64Guest"},
                 "Windows2022Server-64": {"id": "112", "version": "", "type": "windows2019srvNext_64Guest"},
                 }

    # Create the OVF file.
    data = {
        'BUILD_DATE': build_data['build_date'],
        'ARTIFACT_ID': build['artifact_id'],
        'BUILD_TIMESTAMP': build_data['build_timestamp'],
        'EULA': eula,
        'OS_NAME': build_data['os_name'],
        'OS_ID': OS_id_map[build_data['guest_os_type']]['id'],
        'OS_TYPE': OS_id_map[build_data['guest_os_type']]['type'],
        'OS_VERSION': OS_id_map[build_data['guest_os_type']]['version'],
        'IB_VERSION': build_data['ib_version'],
        'DISK_NAME': vmdk['stream_name'],
        'DISK_SIZE': build_data['disk_size'],
        'POPULATED_DISK_SIZE': vmdk['size'],
        'STREAM_DISK_SIZE': vmdk['stream_size'],
        'VMX_VERSION': args.vmx_version,
        'DISTRO_NAME': build_data['distro_name'],
        'DISTRO_VERSION': build_data['distro_version'],
        'DISTRO_ARCH': build_data['distro_arch'],
        'NESTEDHV': "false",
        'FIRMWARE': build_data['firmware']
    }

    capv_url = "https://github.com/kubernetes-sigs/cluster-api-provider-vsphere"

    data['CNI_VERSION'] = build_data['kubernetes_cni_semver']
    data['CONTAINERD_VERSION'] = build_data['containerd_version']
    data['KUBERNETES_SEMVER'] = build_data['kubernetes_semver']
    data['KUBERNETES_SOURCE_TYPE'] = build_data['kubernetes_source_type']
    data['PRODUCT'] = "%s and Kubernetes %s" % (
        build_data['os_name'], build_data['kubernetes_semver'])
    data['ANNOTATION'] = "Cluster API vSphere image - %s - %s" % (data['PRODUCT'], capv_url)
    data['WAKEONLANENABLED'] = "false"
    data['TYPED_VERSION'] = build_data['kubernetes_typed_version']

    data['PROPERTIES'] = Template('''
  <Property ovf:userConfigurable="false" ovf:value="${DISTRO_NAME}" ovf:type="string" ovf:key="DISTRO_NAME"/>
  <Property ovf:userConfigurable="false" ovf:value="${DISTRO_VERSION}" ovf:type="string" ovf:key="DISTRO_VERSION"/>
  <Property ovf:userConfigurable="false" ovf:value="${DISTRO_ARCH}" ovf:type="string" ovf:key="DISTRO_ARCH"/>
  <Property ovf:userConfigurable="false" ovf:value="${CNI_VERSION}" ovf:type="string" ovf:key="CNI_VERSION"/>
  <Property ovf:userConfigurable="false" ovf:value="${CONTAINERD_VERSION}" ovf:type="string" ovf:key="CONTAINERD_VERSION"/>
  <Property ovf:userConfigurable="false" ovf:value="${KUBERNETES_SEMVER}" ovf:type="string" ovf:key="KUBERNETES_SEMVER"/>
  <Property ovf:userConfigurable="false" ovf:value="${KUBERNETES_SOURCE_TYPE}" ovf:type="string" ovf:key="KUBERNETES_SOURCE_TYPE"/>\n''').substitute(data)

    # Check if OVF_CUSTOM_PROPERTIES environment Variable is set.
    # If so, load the JSON file & add the properties to the OVF

    if os.environ.get("OVF_CUSTOM_PROPERTIES"):
        with open(os.environ.get("OVF_CUSTOM_PROPERTIES"), 'r') as f:
            custom_properties = json.loads(f.read())
        if custom_properties:
            for k, v in custom_properties.items():
                data['PROPERTIES'] = data['PROPERTIES'] + \
                    f'''      <Property ovf:userConfigurable="false" ovf:value="{v}" ovf:type="string" ovf:key="{k}"/>\n'''

    if "windows" in OS_id_map[build_data['guest_os_type']]['type']:
        if build_data['disable_hypervisor'] != "true":
            data['NESTEDHV'] = "true"

    ovf = "%s-%s.ovf" % (build_data['build_name'], data['TYPED_VERSION'])
    mf = "%s-%s.mf" % (build_data['build_name'], data['TYPED_VERSION'])
    ova = "%s-%s.ova" % (build_data['build_name'], data['TYPED_VERSION'])

    # Create OVF
    create_ovf(ovf, data, ovf_template)

    if os.environ.get("IB_OVFTOOL"):
        # Create the OVA.
        create_ova(ova, ovf, ovftool_args=os.environ.get("IB_OVFTOOL_ARGS", ""))

    else:
        # Create the OVA manifest.
        create_ova_manifest(mf, [ovf, vmdk['stream_name']])

        # Create the OVA
        create_ova(ova, ovf, ova_files=[mf, vmdk['stream_name']])


def sha256(path):
    m = hashlib.sha256()
    with open(path, 'rb') as f:
        while True:
            data = f.read(65536)
            if not data:
                break
            m.update(data)
    return m.hexdigest()


def create_ova(ova_path, ovf_path, ovftool_args=None, ova_files=None):
    if ova_files is None:
        cmd = f"ovftool {ovftool_args} {ovf_path} {ova_path}"

        print("image-build-ova: creating OVA from %s using ovftool" %
              ovf_path)
        subprocess.run(cmd.split(), check=True)
    else:
        infile_paths = [ovf_path]
        infile_paths.extend(ova_files)
        print("image-build-ova: creating OVA using tar")
        with open(ova_path, 'wb') as f:
            with tarfile.open(fileobj=f, mode='w|') as tar:
                for infile_path in infile_paths:
                    tar.add(infile_path)

    chksum_path = "%s.sha256" % ova_path
    print("image-build-ova: create ova checksum %s" % chksum_path)
    with open(chksum_path, 'w') as f:
        f.write(sha256(ova_path))


def create_ovf(path, data, ovf_template):
    print("image-build-ova: create ovf %s" % path)
    with io.open(path, 'w', encoding='utf-8') as f:
      f.write(Template(ovf_template).substitute(data))


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


if __name__ == "__main__":
    main()
