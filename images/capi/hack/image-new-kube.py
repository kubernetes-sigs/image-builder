#!/usr/bin/env python

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

import re
import requests
import sys
import tarfile
from io import BytesIO

KUBE_CI_SRC = "https://storage.googleapis.com/kubernetes-release-dev"
KUBE_RELEASE_SRC = "https://storage.googleapis.com/kubernetes-release"

KUBE_RESOLVED_SEM = "kubernetes_semver"
KUBE_RESOLVED_SRC = "kubernetes_http_source"
KUBE_RESOLVED_VER = "kubernetes_version"

# KubeVersionResolver is used for resolving Kubernetes version strings to the
# actual version and URL or package string that may be used to deploy
# Kubernetes.


class KubeVersionResolver(object):

    # Resolve accepts a Kubernetes version string and returns a dictionary with
    # information that can be used to deploy the provided version.
    def Resolve(self, version):
        if version == "":
            raise Exception("version is required")

        result = {
            KUBE_RESOLVED_SEM: version,
            KUBE_RESOLVED_SRC: 'pkg',
            KUBE_RESOLVED_VER: version,
        }

        # When version is "latest" then the returned dictionary points
        # to the latest package for Kubernetes.
        if version == "latest":
            return result
        # Otherwise check to see if the provided version matches a
        # managed package format. Technically the else clause could be
        # descoped one level, but by placing the logic in the scope of
        # the else clause, the scope of "match" is isolated from the
        # rest of this function.
        else:
            match = re.match(r'^(\d+\.\d+.\d+)\-\d+$', version)
            if match:
                result[KUBE_RESOLVED_SEM] = 'v%s' % match.groups(1)[0]
                return result

        url = ""
        if re.match(r'(?i)^https?:', version):
            url = version
        elif re.match(r'^v?\d+(?:\.\d+){0,3}(?:[.+-].+)?$', version):
            if not version.startswith('v'):
                version = "v%s" % version
            url = "%s/release/%s" % (KUBE_RELEASE_SRC, version)
        elif version.startswith('ci/'):
            url = self.__resolve_build_url(version, True)
        elif re.match(r'^release/.+$', version):
            url = self.__resolve_build_url(version, False)
        else:
            raise Exception("Invalid Kubernetes version: %s" % version)
        result[KUBE_RESOLVED_SRC] = url

        version = self.__read_version_from_kube_tarball(url)
        result[KUBE_RESOLVED_SEM] = version
        result[KUBE_RESOLVED_VER] = version

        return result

    def __resolve_build_url(self, buildID, ciBuild):
        url = ""
        if ciBuild:
            url = "%s/%s" % (KUBE_CI_SRC, buildID)
        else:
            url = "%s/%s" % (KUBE_RELEASE_SRC, buildID)

        # If the URL doesn't end with ".txt" then see if the URL is already valid.
        if not url.endswith('.txt'):
            # If there is a kubernetes tarball available at the root of the URL
            # then it is already a valid URL.
            try:
                r = requests.head(url, allow_redirects=True)
                if r.status_code >= 200 and r.status_code <= 299:
                    return url
            except:
                pass
            # The URL wasn't valid, so add ".txt" to the end and let's see if the
            # URL points to a valid build.
            url = "%s.txt" % url

        # Do an HTTP GET on the txt file to get the actual Kubernetes version.
        version = requests.get(url).text
        version = version.strip()

        if ciBuild:
            url = "%s/ci/%s" % (KUBE_CI_SRC, version)
        else:
            url = "%s/release/%s" % (KUBE_RELEASE_SRC, version)

        return url

    def __read_version_from_kube_tarball(self, url):
        url = "%s/kubernetes.tar.gz" % url
        r = requests.get(url)
        if not r.status_code == 200:
            raise Exception("HTTP GET %s failed: %d" % (url, r.status_code))
        b = BytesIO(r.content)
        t = tarfile.open(fileobj=b, mode='r')
        v = t.extractfile("kubernetes/version")
        return v.read().strip()


if __name__ == "__main__":
    import argparse
    import textwrap
    parser = argparse.ArgumentParser(
        formatter_class=argparse.RawTextHelpFormatter,
        description='Generates new Kubernetes image config',
        epilog=textwrap.dedent(r'''
            THE VERSION STRING
            ====================================================================
            The version string not only determines what version of Kubernetes 
            will be installed, but also *how* Kubernetes is installed.

            PLACEHOLDERS
            ====================================================================
            The following placeholders are used in the examples below:

            DEV_SRC   storage.googleapis.com/kubernetes-release-dev
            REL_SRC   storage.googleapis.com/kubernetes-release
            K8S_TGZ   kubernetes.tar.gz

            PACKAGE MANAGER INSTALLATION
            ====================================================================
            If the version string matches the pattern "^\d+\.\d+.\d+\-\d+$",
            ex. 1.14.0-0, then Kubernetes is installed using the system's
            package manager, such as yum or apt.

            MANUAL INSTALLATION
            ====================================================================
            If the string does not match the above pattern then the following
            logic is used to resolve the string VALUE to a valid Kubernetes
            version along with the URLs for the Kubernetes artifiacts required
            for installation:

              1. If the VALUE begins with "http:" or "https:" then the value is
              treated as a URL and the Kubernetes version is obtained by reading
              the "kuberentes/version" file from the URL "VALUE/K8S_TGZ".

              2. If the VALUE matches a semantic version then the value is
              treated as a release build and "https://REL_SRC/release/SEMVER"
              is processed like the URL in step one.

              3. If the VALUE begins with "ci/" then:
              
                a. If VALUE does not end with ".txt" then a HEAD request is used
                to check the existence of "https://DEV_SRC/ci/VALUE/K8S_TGZ":
                
                  i. If the HEAD request is successful then the URL is processed
                  like the one in step one.
                  ii. If the HEAD request fails then ".txt" is added to the end
                  of the URL and is processed by step 3b.

                b. If VALUE *does* end with ".txt" then a GET request is used to
                read "https://DEV_SRC/ci/VALUE" in order to get the dereferenced
                version string. Then "https://DEV_SRC/ci/DEREF" is processed
                like the URL in step one.

              4. If the VALUE begins with "release/" then the VALUE is processed
              like step three, with "ci/" replaced by "release/".

            The resolved URL is used to install Kuberentes from the set of
            pre-built container images and binaries.
    '''))
    parser.add_argument('version',
                        nargs=1,
                        help='A Kubernetes version string')

    args = parser.parse_args()
    resolver = KubeVersionResolver()
    result = resolver.Resolve(args.version[0])

    import json
    data = json.dumps(result, indent=2)
    print(data)
