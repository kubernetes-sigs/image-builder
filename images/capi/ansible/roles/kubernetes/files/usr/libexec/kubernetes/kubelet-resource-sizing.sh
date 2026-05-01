#!/bin/bash

# This script is used to calculate the resource sizing for the kubelet based on values used by GKE and repeated
# in https://github.com/awslabs/amazon-eks-ami/pull/367/files

#RPM and DEB systems kubelet sysconfig PATH
KUBELET_SYSCONFIG_FILES=( "/etc/sysconfig/kubelet" "/etc/default/kubelet" )
KUBELET_CONFIG="/var/lib/kubelet/kubelet.conf.d/kubelet-resource-sizing.json"

for KUBELET_SYSCONFIG in "${KUBELET_SYSCONFIG_FILES[@]}"
do
  # Check if the file exists
  if [ -f "${KUBELET_SYSCONFIG}" ]; then
    # shellcheck source=/dev/null
    . "${KUBELET_SYSCONFIG}"
    # If system-reserved is already set by user, ignore
    if grep -q 'systemReserved' "${KUBELET_SYSCONFIG}"; then
      exit 0
    fi
  fi
done

total_memory_mebibytes=$(free -m | grep Mem | awk '{print $2}')
schedulable_cores_no=$(nproc)

memory_reservation_mebibytes() {
  local memory_reserved_mebibytes=0
  local memory_remaining_mebibytes=$total_memory_mebibytes

  # Minimally reserve 255MiB
  if [[ $memory_remaining_mebibytes -lt 1024 ]]; then
    memory_reserved_mebibytes=255
    echo "$memory_reserved_mebibytes"
    return
  fi

  # Reserve 25% of the first 4 gigabytes of memory
  if [[ memory_remaining_mebibytes -lt 4096 ]]; then
    segment_memory_reservation_mebibytes=$(echo $memory_remaining_mebibytes | awk '{result = $1 * 0.25; if (result != int(result)) result++; printf "%d\n", result}')
    memory_reserved_mebibytes=$((memory_reserved_mebibytes + segment_memory_reservation_mebibytes))
    echo "$memory_reserved_mebibytes"
    return
  fi

  memory_reserved_mebibytes=$((memory_reserved_mebibytes + 1024))
  memory_remaining_mebibytes=$((memory_remaining_mebibytes - 4096))

  # Reserve 20% of the next 4 gigabytes of memory up to 8GB
  if [[ memory_remaining_mebibytes -lt 4096 ]]; then
    segment_memory_reservation_mebibytes=$(echo $memory_remaining_mebibytes | awk '{result = $1 * 0.2; if (result != int(result)) result++; printf "%d\n", result}')
    memory_reserved_mebibytes=$((memory_reserved_mebibytes + segment_memory_reservation_mebibytes))
    echo "$memory_reserved_mebibytes"
    return
  fi

  memory_reserved_mebibytes=$((memory_reserved_mebibytes + 820))
  memory_remaining_mebibytes=$((memory_remaining_mebibytes - 4096))

  # Reserve 10% of the next 8 gigabytes of memory up to 16GB
  if [[ memory_remaining_mebibytes -lt 8192 ]]; then
    segment_memory_reservation_mebibytes=$(echo $memory_remaining_mebibytes | awk '{result = $1 * 0.1; if (result != int(result)) result++; printf "%d\n", result}')
    memory_reserved_mebibytes=$((memory_reserved_mebibytes + segment_memory_reservation_mebibytes))
    echo "$memory_reserved_mebibytes"
    return
  fi

  memory_reserved_mebibytes=$((memory_reserved_mebibytes + 820))
  memory_remaining_mebibytes=$((memory_remaining_mebibytes - 8192))

  # Reserve 6% of the next 16 gigabytes of memory up to 114GB
  if [[ memory_remaining_mebibytes -lt 116736 ]]; then
    segment_memory_reservation_mebibytes=$(echo $memory_remaining_mebibytes | awk '{result = $1 * 0.06; if (result != int(result)) result++; printf "%d\n", result}')
    memory_reserved_mebibytes=$((memory_reserved_mebibytes + segment_memory_reservation_mebibytes))
    echo "$memory_reserved_mebibytes"
    return
  fi

  # Reserve 2% of any remaining memory
  memory_reserved_mebibytes=$((memory_reserved_mebibytes + 7004))
  memory_remaining_mebibytes=$((memory_remaining_mebibytes - 116736))
  segment_memory_reservation_mebibytes=$(echo $memory_remaining_mebibytes | awk '{result = $1 * 0.02; if (result != int(result)) result++; printf "%d\n", result}')
  memory_reserved_mebibytes=$((memory_reserved_mebibytes + segment_memory_reservation_mebibytes))
  echo "$memory_reserved_mebibytes"
}

declare -A CPU_CORE_RESERVATION_MICROCORES

CPU_CORE_RESERVATION_MICROCORES=(
  # Reserve 6% of the first core
  ["0"]=600
  # Reserve 1% of the second core
  ["1"]=100
  # Reserve 0.5% of the third core
  ["2"]=50
  # Reserve 0.5% of the fourth core
  ["3"]=50
  # Reserve 0.25% of any remaining cores
  ["4+"]=25
)

# Calculate the CPU reservation
cpu_millicores_to_reserve() {
  local cpu_microcores_reserved=0

  for ((i = 0; i < schedulable_cores_no; i++)); do
    if [[ $i -gt 3 ]]; then
      cpu_microcores_reserved=$((cpu_microcores_reserved + ${CPU_CORE_RESERVATION_MICROCORES["4+"]}))
    else
      cpu_microcores_reserved=$((cpu_microcores_reserved + ${CPU_CORE_RESERVATION_MICROCORES[$i]}))
    fi
  done

  # Round up just in case
  echo "$cpu_microcores_reserved" | awk '{result = $1 / 10; if (result != int(result)) result++; printf "%d\n", result}'
}

mkdir -p /var/lib/kubelet/kubelet.conf.d

# Initialize config file if it doesn't exist
if [ ! -f "$KUBELET_CONFIG" ]; then
  echo "{}" > "$KUBELET_CONFIG"
fi

# Get the computed values from the functions
memory_reservation_mebibytes=$(memory_reservation_mebibytes)
cpu_millicores_to_reserve=$(cpu_millicores_to_reserve)

echo "$(jq --arg memory_reservation_mebibytes "${memory_reservation_mebibytes}Mi" --arg cpu_millicores_to_reserve "${cpu_millicores_to_reserve}m" \
    '. += {"apiVersion": "kubelet.config.k8s.io/v1beta1","kind": "KubeletConfiguration", "systemReserved": {"cpu": $cpu_millicores_to_reserve, "ephemeral-storage": "1Gi", "memory": $memory_reservation_mebibytes}}' "$KUBELET_CONFIG")" > "$KUBELET_CONFIG"
