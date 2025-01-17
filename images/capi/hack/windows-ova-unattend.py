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


import io
import xml.etree.ElementTree as ET
import os
import argparse
import json

ADDRESSES_TEMPLATE = """        <IpAddress wcm:action="add" wcm:keyValue="%(order)d">%(cidr)s</IpAddress>
"""
INTERFACE_COMPONENT_TEMPLATE = """
<component name="Microsoft-Windows-TCPIP" processorArchitecture="amd64"
  publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
  xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
  <Interfaces>
    <Interface wcm:action="add">
      <Ipv4Settings>
        <DhcpEnabled>false</DhcpEnabled>
      </Ipv4Settings>
      <Ipv6Settings>
        <DhcpEnabled>false</DhcpEnabled>
      </Ipv6Settings>
      <Identifier>%(iface_id)s</Identifier>
      <UnicastIpAddresses>
%(addresses)s      </UnicastIpAddresses>
    <Routes>%(routes)s
    </Routes>
    </Interface>
  </Interfaces>
</component>
"""
ROUTE_TEMPLATE = """
      <Route wcm:action="add">
        <Identifier>%(id)s</Identifier>
        <Prefix>%(prefix)s</Prefix>
        <NextHopAddress>%(gateway)s</NextHopAddress>
      </Route>"""
DNS_TEMPLATE = """
<component name="Microsoft-Windows-DNS-Client" processorArchitecture="amd64"
  publicKeyToken="31bf3856ad364e35" language="neutral" versionScope="nonSxS"
  xmlns:wcm="http://schemas.microsoft.com/WMIConfig/2002/State"
  xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance">
   <Interfaces>%(interfaces)s
   </Interfaces>
</component>
"""
DNS_INTERFACE_TEMPLATE = """
      <Interface wcm:action="add">
         <Identifier>%(iface_id)s</Identifier>
         <DNSServerSearchOrder>%(dns_search_orders)s
         </DNSServerSearchOrder>
      </Interface>
"""
DNS_SEARCH_ORDER_TEMPLATE = """
            <IpAddress wcm:action="add" wcm:keyValue="%(key)s">%(server)s</IpAddress>"""
INTERFACE_ID = "Ethernet0"


def set_xmlstring(root, location, key, value):
    setting = root.find(location)
    setting.find(key).text = value
    return setting


def ensure_interfaces(root, interfaces_content):
    setting = root.find("*[@pass='specialize']")
    old_element = setting.find(".//*[@name='Microsoft-Windows-TCPIP']")
    modified = False
    if old_element:
        setting.remove(old_element)
        modified = not interfaces_content

    if interfaces_content:
        interface_component_tree = ET.parse(io.StringIO(interfaces_content))
        new_element = interface_component_tree.getroot()
        setting.append(new_element)
        modified = True

    return setting, modified


def ensure_dns_settings(root, dns_content):
    setting = root.find("*[@pass='specialize']")
    old_element = setting.find(".//*[@name='Microsoft-Windows-DNS-Client']")
    modified = False
    if old_element:
        setting.remove(old_element)
        modified = not dns_content

    if dns_content:
        dns_component_tree = ET.parse(io.StringIO(dns_content))
        new_element = dns_component_tree.getroot()
        setting.append(new_element)
        modified = True

    return setting, modified


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

    modified = False
    os.chdir(args.build_dir)
    unattend = ET.parse(args.unattend_file)
    ET.register_namespace('', "urn:schemas-microsoft-com:unattend")
    ET.register_namespace('wcm', "http://schemas.microsoft.com/WMIConfig/2002/State")
    ET.register_namespace('xsi', "http://www.w3.org/2001/XMLSchema-instance")

    root = unattend.getroot()

    if data.get("unattend_timezone"):
        modified = True
        setting = set_xmlstring(root, ".//*[@pass='oobeSystem']/*[@name='Microsoft-Windows-Shell-Setup']",
                                '{urn:schemas-microsoft-com:unattend}TimeZone', data["unattend_timezone"])
        print("windows-ova-unattend: Setting Timezone to %s" % data["unattend_timezone"])

    admin_password = data.get("admin_password")
    if admin_password:
        modified = True
        set_xmlstring(root,
                      ".//*[@pass='oobeSystem']/*[@name='Microsoft-Windows-Shell-Setup']/{*}UserAccounts/{*}AdministratorPassword",
                      '{urn:schemas-microsoft-com:unattend}Value', admin_password)
        set_xmlstring(root,
                      ".//*[@pass='oobeSystem']/*[@name='Microsoft-Windows-Shell-Setup']/{*}AutoLogon/{*}Password",
                      '{urn:schemas-microsoft-com:unattend}Value', admin_password)
        print("windows-ova-unattend: Setting Administrator Password")

    addr_elements = []
    ip_addr_cidr = data.get("ipv4_address_cidr")
    gateway4 = data.get("gateway4")
    if ip_addr_cidr:
        modified = True
        route_configs = []
        if gateway4:
            route_configs.append(("0.0.0.0/0", gateway4))

        routes = []
        for i in range(len(route_configs)):
            route_config = route_configs[i]
            routes.append(ROUTE_TEMPLATE % {"id": i + 1, "prefix": route_config[0], "gateway": route_config[1]})
            print("windows-ova-unattend: Setting Gateway to %s" % route_config[1])

        addrs = [ip_addr_cidr]
        for i in range(len(addrs)):
            addr_elements.append(ADDRESSES_TEMPLATE % {"order": i + 1,
                                                       "cidr": addrs[i]})
            print("windows-ova-unattend: Setting IP Address to %s" % ip_addr_cidr)

    interfaces_content = None
    if addr_elements:
        interfaces_content = INTERFACE_COMPONENT_TEMPLATE % {"iface_id": INTERFACE_ID,
                                                             "addresses": ''.join(addr_elements),
                                                             "routes": ''.join(routes)}

    setting, xml_modified = ensure_interfaces(root, interfaces_content)
    if xml_modified:
        modified = True

    dns_servers = data.get("dns_servers")
    dns_servers_content = ''
    if dns_servers:
        dns_servers = dns_servers.split()
        search_order_content = []
        for i in range(len(dns_servers)):
            search_order_content.append(DNS_SEARCH_ORDER_TEMPLATE % {"key": i + 1,
                                                                     "server": dns_servers[i]})
        dns_interface_content = [DNS_INTERFACE_TEMPLATE % {"iface_id": INTERFACE_ID,
                                                           "dns_search_orders": ''.join(search_order_content)}]
        dns_servers_content = DNS_TEMPLATE % {"interfaces": ''.join(dns_interface_content)}
        print("windows-ova-unattend: Setting DNS Addresses to %s" % dns_servers)

    setting, xml_modified = ensure_dns_settings(root, dns_servers_content)
    if xml_modified:
        modified = True

    if modified:
        print("windows-ova-unattend: Updating %s ..." % args.unattend_file)
        unattend.write(args.unattend_file)
    else:
        print("windows-ova-unattend: skipping...")


if __name__ == "__main__":
    main()
