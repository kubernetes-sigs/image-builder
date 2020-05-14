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
# usage: image-upload.py [FLAGS] ARGS
#  This program uploads an OVA created from a Packer build
################################################################################

import argparse
import atexit
import hashlib
import json
import os
import re
import requests
import subprocess
import string
import sys


def main():
    parser = argparse.ArgumentParser(
        description="Uploads an OVA created from a Packer build")
    parser.add_argument(dest='build_dir',
                        nargs='?',
                        metavar='BUILD_DIR',
                        default='.',
                        help='The Packer build directory')
    parser.add_argument('--key-file',
                        dest='key_file',
                        required=True,
                        nargs='?',
                        metavar='KEY_FILE',
                        help='The GCS key file')
    args = parser.parse_args()

    # Get the absolute path to the GCS key file.
    key_file = os.path.abspath(args.key_file)

    # Change the working directory if one is specified.
    os.chdir(args.build_dir)
    print("image-upload-ova: cd %s" % args.build_dir)

    # Load the packer manifest JSON
    data = None
    with open('packer-manifest.json', 'r') as f:
        data = json.load(f)

    # Get the first build.
    build = data['builds'][0]
    build_data = build['custom_data']
    build_type = build_data['build_type']

    if build_type == "node":
        version = build_data['kubernetes_semver']
        build_name = "%s-kube-%s" % (build_data['build_name'], version)
    else:
        version = build_data['dataplaneapi_version']
        build_name = "%s-haproxy-%s" % (build_data['build_name'], version)
    print("image-upload-ova: loaded %s" % build_name)

    # Get the OVA and its checksum.
    ova = "%s.ova" % build_name
    ova_sum = "%s.sha256" % ova

    # Determine whether or not this is a release or CI image.
    upload_dir = 'ci'
    if re.match(r'^v?\d+\.\d+\.\d+(-\d+)?$', version):
        upload_dir = 'release'

    # Get the path to the GCS OVA and its checksum.
    if build_type == "node":
        gcs_ova = "gs://capv-images/%s/%s/%s" % (
            upload_dir, version, ova)
    else:
        gcs_ova = "gs://capv-images/extra/haproxy/%s/%s/%s" % (
            upload_dir, version, ova)
    gcs_ova_sum = "%s.sha256" % gcs_ova

    # Get the URL of the OVA and its checksum.
    url_ova = string.replace(gcs_ova, "gs://", "http://storage.googleapis.com/")
    url_ova_sum = "%s.sha256" % url_ova

    # Compare the remote checksum with the local checksum.
    lcl_ova_sum_val = get_local_checksum(ova_sum)
    print("image-upload-ova:  local sha256 %s" % lcl_ova_sum_val)
    rem_ova_sum_val = get_remote_checksum(url_ova_sum)
    print("image-upload-ova: remote sha256 %s" % rem_ova_sum_val)
    if lcl_ova_sum_val == rem_ova_sum_val:
        print("image-upload-ova: skipping upload")
        print("image-upload-ova: download from %s" % url_ova)
        return

    # Activate the GCS service account.
    activate_service_account(key_file)
    atexit.register(deactivate_service_account)

    # Upload the OVA and its checksum.
    print("image-upload-ova: upload %s" % gcs_ova)
    subprocess.check_call(['gsutil', 'cp', ova, gcs_ova])
    print("image-upload-ova: upload %s" % gcs_ova_sum)
    subprocess.check_call(['gsutil', 'cp', ova_sum, gcs_ova_sum])

    print("image-upload-ova: download from %s" % url_ova)


def activate_service_account(path):
    args = [
        "gcloud", "auth",
        "activate-service-account",
        "--key-file", path,
    ]
    subprocess.check_call(args)


def deactivate_service_account():
    subprocess.call(["gcloud", "auth", "revoke"])


def get_remote_checksum(url):
    r = requests.get(url)
    if r.status_code >= 200 and r.status_code <= 299:
        return r.text.strip()
    return None


def get_local_checksum(path):
    with open(path, 'r') as f:
        return f.readline().strip()


if __name__ == "__main__":
    main()
