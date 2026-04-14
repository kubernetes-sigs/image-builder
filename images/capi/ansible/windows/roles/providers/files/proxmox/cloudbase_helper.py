# Copyright 2026 The Kubernetes Authors.
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

"""Apply Proxmox NoCloud network data from a config-drive file."""

import logging
import os
import string
import sys

try:
    from oslo_log import log as oslo_logging

    LOG = oslo_logging.getLogger(__name__)
except Exception:  # pragma: no cover - fallback when oslo logging is unavailable
    logging.basicConfig(level=logging.INFO)
    LOG = logging.getLogger(__name__)


DEFAULT_NETWORK_DATA_FILENAMES = ("NETWORK_CONFIG", "network-config")


def _iter_search_roots():
    search_roots = os.environ.get("PROXMOX_NETWORK_DATA_SEARCH_ROOTS")
    if search_roots:
        for root in search_roots.split(os.pathsep):
            root = root.strip()
            if root:
                yield root
        return

    for drive_letter in string.ascii_uppercase:
        yield "%s:\\" % drive_letter


def _iter_candidate_paths():
    override_path = os.environ.get("PROXMOX_NETWORK_DATA_PATH", "").strip()
    if override_path:
        yield override_path
        return

    for root in _iter_search_roots():
        normalized_root = root.rstrip("\\/")
        for filename in DEFAULT_NETWORK_DATA_FILENAMES:
            yield "%s\\%s" % (normalized_root, filename)


def find_network_data_path(path_exists=os.path.exists):
    for candidate_path in _iter_candidate_paths():
        if path_exists(candidate_path):
            return candidate_path
    return None


def load_network_data(network_data_path, open_file=open, parser=None):
    if parser is None:
        from cloudbaseinit.utils import serialization

        parser = serialization.parse_json_yaml

    with open_file(network_data_path, "r", encoding="utf-8") as network_data_file:
        raw_network_data = network_data_file.read()

    network_data = parser(raw_network_data)
    if not isinstance(network_data, dict):
        raise ValueError(
            "Proxmox network data parsed into %r, expected dict" %
            type(network_data)
        )

    return network_data


def apply_network_data(network_data, network_parser=None, plugin_factory=None):
    if network_parser is None:
        from cloudbaseinit.metadata.services.nocloudservice import (
            NoCloudNetworkConfigParser,
        )

        network_parser = NoCloudNetworkConfigParser.parse

    if plugin_factory is None:
        from cloudbaseinit.plugins.common import networkconfig

        plugin_factory = networkconfig.NetworkConfigPlugin

    network_details = network_parser(network_data)
    if not network_details:
        LOG.warning("NoCloud network parser returned no interfaces")
        return False

    plugin = plugin_factory()
    process_network_details = getattr(plugin, "_process_network_details_v2", None)
    if process_network_details is None:
        raise AttributeError(
            "Cloudbase-Init network plugin is missing _process_network_details_v2"
        )

    process_network_details(network_details)
    return True


def main():
    network_data_path = find_network_data_path()
    if not network_data_path:
        LOG.info(
            "No Proxmox network data found in candidate paths: %s",
            ", ".join(_iter_candidate_paths()),
        )
        return 0

    try:
        network_data = load_network_data(network_data_path)
    except Exception:
        LOG.exception(
            "Failed to load Proxmox network data from %s", network_data_path
        )
        return 0

    try:
        LOG.info("Applying Proxmox network data from %s", network_data_path)
        applied = apply_network_data(network_data)
    except Exception:
        LOG.exception(
            "Failed to apply Proxmox network data from %s", network_data_path
        )
        return 0

    if not applied:
        LOG.warning(
            "No network interfaces were applied from %s", network_data_path
        )

    return 0


if __name__ == "__main__":
    sys.exit(main())
