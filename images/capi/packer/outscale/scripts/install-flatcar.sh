#!/bin/bash
set -euo pipefail

# Re-execute from tmpfs so bash can keep reading after /dev/vda is overwritten
if [[ "${BASH_SOURCE[0]}" != /dev/shm/* ]]; then
  cp "${BASH_SOURCE[0]}" /dev/shm/install-flatcar.sh
  exec bash /dev/shm/install-flatcar.sh
fi

# Wait for cloud-init to finish so boot-time apt operations complete first
sudo cloud-init status --wait

# Install prerequisites
sudo apt-get update
sudo apt-get install -y bzip2

# Format and mount the scratch volume (attached via Packer launch_block_device_mappings).
# All image work happens here — not in RAM and not on /dev/vda which gets overwritten.
SCRATCH_DEV=$(lsblk -dpno NAME,TYPE | awk '$2=="disk" && $1!="/dev/vda" {print $1; exit}')
if [ -z "$SCRATCH_DEV" ]; then
  echo "ERROR: No scratch volume found"
  exit 1
fi
sudo mkfs.ext4 -q "$SCRATCH_DEV"
sudo mount "$SCRATCH_DEV" /mnt

# Capture the SSH public key injected by Packer
SSH_KEY=$(cat ~/.ssh/authorized_keys | head -1)

# Build the SSH keys JSON array
SSH_KEYS_JSON="\"${SSH_KEY}\""
if [ -n "${DEBUG_SSH_PUBLIC_KEY:-}" ]; then
  SSH_KEYS_JSON="\"${SSH_KEY}\", \"${DEBUG_SSH_PUBLIC_KEY}\""
fi

# Create Ignition config
cat <<EOF | sudo tee /mnt/ignition.json > /dev/null
{
  "ignition": { "version": "3.0.0" },
  "passwd": {
    "users": [
      {
        "name": "outscale",
        "groups": ["wheel", "sudo", "docker"],
        "sshAuthorizedKeys": [
          ${SSH_KEYS_JSON}
        ]
      }
    ]
  },
  "systemd": {
    "units": [
      {
        "enabled": true,
        "name": "docker.service"
      },
      {
        "mask": true,
        "name": "update-engine.service"
      },
      {
        "mask": true,
        "name": "locksmithd.service"
      }
    ]
  }
}
EOF

# Download and decompress the Flatcar image to the scratch volume
BASE_URL="https://${FLATCAR_CHANNEL}.release.flatcar-linux.net/amd64-usr/${FLATCAR_VERSION}"
sudo wget --tries 10 --timeout=20 --retry-connrefused \
  -O /mnt/flatcar_image.bin.bz2 "${BASE_URL}/flatcar_production_image.bin.bz2"
sudo bunzip2 /mnt/flatcar_image.bin.bz2

# Embed the Ignition config into the image's OEM partition via loopback.
# All tools (losetup, blkid, mount, cp) work because Ubuntu is still intact.
LOOP=$(sudo losetup --find --show --partscan /mnt/flatcar_image.bin)
sleep 1

OEM_PART=""
for part in ${LOOP}p*; do
  LABEL=$(sudo blkid -s LABEL -o value "$part" 2>/dev/null || true)
  if [ "$LABEL" = "OEM" ]; then
    OEM_PART="$part"
    break
  fi
done

if [ -z "$OEM_PART" ]; then
  echo "ERROR: Could not find OEM partition in Flatcar image"
  sudo losetup --detach "$LOOP"
  exit 1
fi

sudo mkdir -p /mnt/oem
sudo mount "$OEM_PART" /mnt/oem
sudo cp /mnt/ignition.json /mnt/oem/config.ign
sudo umount /mnt/oem
sudo losetup --detach "$LOOP"

# Write the Flatcar image (with embedded Ignition config) to the root disk
# and immediately reboot via sysrq (bash builtin echo + kernel VFS, no
# userspace binaries needed from the now-destroyed root filesystem).
sudo bash -c '
  dd bs=1M if=/mnt/flatcar_image.bin of=/dev/vda conv=fdatasync status=none
  echo 1 > /proc/sys/kernel/sysrq
  echo b > /proc/sysrq-trigger
'
