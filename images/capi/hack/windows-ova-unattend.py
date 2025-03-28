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


import xml.etree.ElementTree as ET
import os
import argparse
import json

def set_xmlstring(root, location, key, value):
  setting = root.find(location)
  setting.find(key).text = value
  return setting

def main():
    parser = argparse.ArgumentParser(
        description="Updates select variables in autounattend.xml")
    parser.add_argument(dest='build_dir',
                        nargs='?',
                        metavar='BUILD_DIR',
                        default='.',
                        help='The Packer build directory')
    parser.add_argument('--var-file',
                        dest='var_file',
                        nargs='?',
                        metavar='VARIABLES_FILE',
                        required=False,
                        default='./packer_cache/unattend.json',
                        help='The file that containers the unattend variables')
    parser.add_argument('--unattend-file',
                        dest='unattend_file',
                        required=False,
                        nargs='?',
                        metavar='UNATTEND_FILE',
                        help='The Unattend file')
    args = parser.parse_args()

    print("windows-ova-unattend: cd %s" % args.build_dir)

    # Load the packer manifest JSON
    data = None
    with open(args.var_file, 'r') as f:
        data = json.load(f)

    modified=0
    os.chdir(args.build_dir)
    unattend=ET.parse(args.unattend_file)
    ET.register_namespace('', "urn:schemas-microsoft-com:unattend")
    ET.register_namespace('wcm', "http://schemas.microsoft.com/WMIConfig/2002/State")
    ET.register_namespace('xsi', "http://www.w3.org/2001/XMLSchema-instance")
    
    root = unattend.getroot()

    if data.get("unattend_timezone"):
      modified=1
      setting = set_xmlstring(root, ".//*[@pass='oobeSystem']/*[@name='Microsoft-Windows-Shell-Setup']",'{urn:schemas-microsoft-com:unattend}TimeZone', data["unattend_timezone"])
      print("windows-ova-unattend: Setting Timezone to %s" % data["unattend_timezone"])
    
    admin_password = data.get("admin_password")
    if admin_password:
      modified=1
      set_xmlstring(root, ".//*[@pass='oobeSystem']/*[@name='Microsoft-Windows-Shell-Setup']/{*}UserAccounts/{*}AdministratorPassword",'{urn:schemas-microsoft-com:unattend}Value', admin_password)
      set_xmlstring(root, ".//*[@pass='oobeSystem']/*[@name='Microsoft-Windows-Shell-Setup']/{*}AutoLogon/{*}Password",'{urn:schemas-microsoft-com:unattend}Value', admin_password)
      print("windows-ova-unattend: Setting Administrator Password")

    if modified == 1:
      print("windows-ova-unattend: Updating %s ..." % args.unattend_file)
      unattend.write(args.unattend_file)
    else:
      print("windows-ova-unattend: skipping...")

if __name__ == "__main__":
    main()
