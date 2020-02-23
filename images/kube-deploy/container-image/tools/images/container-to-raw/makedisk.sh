#!/bin/bash

set -ex
set -o pipefail

apt-get install --yes uuid-runtime

# Create a (sparse) 8 gig image
dd if=/dev/null bs=1M seek=8192 of=${DISK}


#Create partitions
# Tip: sfdisk -l -d ${DISK} can print the instructions for an existing disk
sfdisk ${DISK} <<EOF
label: gpt
unit: sectors
first-lba: 34

part1 : start=          34, size=        2014, type=21686148-6449-6E6F-744E-656564454649, name="primary"
part2 : start=        2048, size=    16775135, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="root"
EOF

# TODO: Should we make sure that the FS UUID on part2 matches the partition UUID in the GPT table?


LOOPBACK_DEVICE=`losetup --show -f -P ${DISK}`
echo "LOOPBACK_DEVICE=${LOOPBACK_DEVICE}"


function cleanup_mounts {
  umount ${MNT}/dev/pts || true
  umount ${MNT}/proc || true
  umount ${MNT}/sys || true
  umount ${MNT}/dev || true
  umount ${MNT} || true

  umount ${LOOPBACK_DEVICE}p1 || true
  umount ${LOOPBACK_DEVICE}p2 || true
  losetup -l
  losetup -d ${LOOPBACK_DEVICE} || true
}
trap cleanup_mounts EXIT

losetup -l


PARTITION_DEVICE=${LOOPBACK_DEVICE}p2

mkfs.ext4 -i 4096 ${PARTITION_DEVICE}

# Don’t force a fsck check based on dates
tune2fs -i 0 ${PARTITION_DEVICE}

fdisk -l

MNT=/mnt
mkdir -p ${MNT}
mount -t ext4 ${PARTITION_DEVICE} ${MNT}

# Expand the tar file
tar -x -C ${MNT} -f ${SRC}

# Inject the correct UUID for the root device, replacing the UUID_ROOT placeholder
UUID_ROOT=`blkid -s UUID -o value ${PARTITION_DEVICE}`
sed -i -e "s@{{UUID_ROOT}}@${UUID_ROOT}@g" ${MNT}/etc/fstab


# Fix things that can't be done from docker (todo: move to yaml?)
echo "debian" > ${MNT}/etc/hostname
chroot ${MNT} ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf

cat <<EOF | tee ${MNT}/etc/hosts
127.0.0.1       localhost
::1     localhost ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

mount --bind /dev ${MNT}/dev
mount --types proc none ${MNT}/proc
mount --types sysfs none ${MNT}/sys
mount --types devpts none ${MNT}/dev/pts

chroot ${MNT} update-grub

# TODO: We detect some OSes on sda1 in cloudbuild.
# Maybe remove /etc/grub.d/30_os-prober ?
cat ${MNT}/boot/grub/grub.cfg

chroot ${MNT} grub-install ${LOOPBACK_DEVICE}

echo "Created disk image - OK"
