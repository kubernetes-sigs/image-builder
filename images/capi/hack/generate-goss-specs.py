#!/usr/bin/env python3

# Copyright 2021 The Kubernetes Authors.
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

import argparse
import itertools
import json
import os
import subprocess
import sys

root_path = os.path.abspath(os.path.join(sys.argv[0], '..', '..'))

# Define what OS's are supported on which providers
builds = {'amazon': ['amazon linux', 'centos', 'flatcar', 'ubuntu', 'windows'],
          'azure':  ['centos', 'ubuntu', 'windows'],
          'ova': ['centos', 'photon', 'rhel', 'ubuntu', 'windows']}

def generate_goss(provider, system, versions, runtime, dryrun=False, save=False):
    cmd = ['goss', '-g', 'packer/goss/goss.yaml', '--vars', 'packer/goss/goss-vars.yaml']
    vars = {'OS': system, 'PROVIDER': provider,
            'containerd_version': versions['containerd'],
            'docker_ee_version': versions['docker'],
            'distribution_version': versions['os'],
            'kubernetes_version': versions['k8s'],
            'kubernetes_deb_version': versions['k8s_deb'],
            'kubernetes_rpm_version': versions['k8s_rpm'],
            'kubernetes_source_type': 'pkg',
            'kubernetes_cni_version': versions['cni'],
            'kubernetes_cni_deb_version': versions['cni_deb'],
            'kubernetes_cni_rpm_version': versions['cni_rpm'],
            'kubernetes_cni_source_type': 'pkg',
            'runtime': runtime,
            'pause_image': versions['pause']}


    # Build command
    cmd.extend(['--vars-inline', json.dumps(vars), 'render'])
    print('\nGenerating os: %s, provider: %s, runtime: %s' % (system, provider, runtime))
    print(cmd)

    # Run command with output going to file
    if not dryrun:
        if save:
            out_dir = os.path.join(root_path, 'packer', 'goss')
            out_filename = '%s-%s-%s-goss-spec.yaml' % (provider,
                                                        system.replace(' ', '-'), versions['k8s'])
            out_filename = os.path.join(out_dir, out_filename)
            with open(out_filename, 'w') as f:
                subprocess.run(cmd, cwd=root_path, stdout=f, check=True)
        else:
            subprocess.run(cmd, cwd=root_path, check=True)


def read_json_file(filename):
    j = None
    with open(filename, 'r') as f:
        j = json.load(f)
    return j


def main():
    parser = argparse.ArgumentParser(
        description='Generates GOSS specs. By default, generates all '
                    'possible specs to stdout.',
        usage='%(prog)s [-h] [--provider {amazon,azure,ova}] '
              '[--os {al2,centos,flatcar,photon,rhel,ubuntu,windows}]')
    parser.add_argument('--provider',
                        choices=['amazon', 'azure', 'ova'],
                        action='append',
                        default=None,
                        help='One provider. Can be used multiple times')
    parser.add_argument('--os',
                        choices=['al2', 'centos', 'flatcar', 'photon', 'rhel', 'ubuntu', 'windows'],
                        action='append',
                        default=None,
                        help='One OS. Can be used multiple times')
    parser.add_argument('--dry-run',
                        action='store_true',
                        help='Do not run GOSS, just print GOSS commands')
    parser.add_argument('--write',
                        action='store_true',
                        help='Write GOSS specs to file')
    args = parser.parse_args()

    versions = {}
    # Load JSON files with Version info
    cni = read_json_file(os.path.join(root_path, 'packer', 'config', 'cni.json'))
    versions['cni'] = cni['kubernetes_cni_semver'].lstrip('v')
    versions['cni_deb'] = cni['kubernetes_cni_deb_version']
    versions['cni_rpm'] = cni['kubernetes_cni_rpm_version'].split('-')[0]

    k8s = read_json_file(os.path.join(root_path, 'packer', 'config', 'kubernetes.json'))
    versions['k8s'] = k8s['kubernetes_semver'].lstrip('v')
    versions['k8s_deb'] = k8s['kubernetes_deb_version']
    versions['k8s_rpm'] = k8s['kubernetes_rpm_version'].split('-')[0]

    containerd = read_json_file(os.path.join(root_path, 'packer', 'config', 'containerd.json'))
    versions['containerd'] = containerd['containerd_version']

    docker = read_json_file(os.path.join(root_path, 'packer', 'config', 'windows', 'docker.json'))
    versions['docker'] = docker['docker_ee_version']

    common = read_json_file(os.path.join(root_path, 'packer', 'config', 'common.json'))
    versions['pause'] = common['pause_image']

    providers = builds.keys()
    if args.provider is not None:
        providers = args.provider

    # Generate a unique list of all possible OS's if a choice wasn't made
    oss = args.os
    if args.os is None:
        oss = []
        for x in list(builds.values()):
            for o in x:
                oss.append(o)
        oss = list(set(oss))
    oss = [sub.replace('al2', 'amazon linux') for sub in oss]
    # Generate spec for each valid permutation
    for provider, system in itertools.product(providers, oss):
        if system in builds[provider]:
            if system == 'windows':
                runtimes = ["docker-ee","containerd"]
                os_versions = ["2019", "2004"]
            else: 
                runtimes = ["containerd"]
                os_versions = [""]
            for runtime in runtimes:
                for version in os_versions:
                    versions["os"] = version
                    generate_goss(provider, system, versions, runtime, args.dry_run, args.write)
            

if __name__ == '__main__':
    main()
