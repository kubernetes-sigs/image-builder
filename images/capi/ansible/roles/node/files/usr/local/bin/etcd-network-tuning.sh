#!/bin/bash

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

set -o errexit  # exits immediately on any unexpected error (does not bypass traps)
set -o nounset  # will error if variables are used without first being defined
set -o pipefail # any non-zero exit code in a piped command causes the pipeline to fail with that code

trap on_exit ERR
on_exit() {
    echo "Error setting etcd network tuning parameters for interface: ${DEV}" | systemd-cat -p emerg -t etcd-tuning
}

if [ "$#" -ne 1 ]; then
    echo "Error: Usage: $0 <dev>" | systemd-cat -p emerg -t etcd-tuning
    exit 1
fi

DEV=$1
echo "Setting etcd network tuning parameters for interface: ${DEV}" | systemd-cat -p info -t etcd-tuning
tc qdisc add dev ${DEV} root handle 1: prio bands 3
tc filter add dev ${DEV} parent 1: protocol ip prio 1 u32 match ip sport 2380 0xffff flowid 1:1
tc filter add dev ${DEV} parent 1: protocol ip prio 1 u32 match ip dport 2380 0xffff flowid 1:1
tc filter add dev ${DEV} parent 1: protocol ip prio 2 u32 match ip sport 2379 0xffff flowid 1:1
tc filter add dev ${DEV} parent 1: protocol ip prio 2 u32 match ip dport 2379 0xffff flowid 1:1

