#!/bin/bash
set -e

DISK="/dev/sda"

EFI_GB=1
SWAP_GB=2

GB_TO_MIB=1024

EFI_MIB=$((EFI_GB * GB_TO_MIB))
SWAP_MIB=$((SWAP_GB * GB_TO_MIB))

START=1

#########################
# PARTITIONING
#########################

parted -s "$DISK" mklabel gpt

# EFI
END=$((START + EFI_MIB))
parted -s "$DISK" mkpart ESP fat32 ${START}MiB ${END}MiB
parted -s "$DISK" set 1 esp on
EFI_PART=1
START=$END

# SWAP
END=$((START + SWAP_MIB))
parted -s "$DISK" mkpart swap linux-swap ${START}MiB ${END}MiB
SWAP_PART=2
START=$END

# ROOT (rest of disk)
parted -s "$DISK" mkpart root btrfs ${START}MiB 100%
ROOT_PART=3

#########################
# FORMAT
#########################

mkfs.fat -F32 "${DISK}${EFI_PART}"
mkswap "${DISK}${SWAP_PART}"
mkfs.btrfs -f "${DISK}${ROOT_PART}"

#########################
# CREATE SUBVOLUMES
#########################

mount "${DISK}${ROOT_PART}" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@var_log

umount /mnt

#########################
# MOUNT
#########################

mount -o subvol=@,compress=zstd:3,noatime \
    "${DISK}${ROOT_PART}" /mnt

mkdir -p /mnt/{boot,home,.snapshots,var/log}

mount -o subvol=@home,compress=zstd:3,noatime \
    "${DISK}${ROOT_PART}" /mnt/home

mount -o subvol=@snapshots,compress=zstd:3,noatime \
    "${DISK}${ROOT_PART}" /mnt/.snapshots

mount -o subvol=@var_log,compress=zstd:3,noatime \
    "${DISK}${ROOT_PART}" /mnt/var/log

mount "${DISK}${EFI_PART}" /mnt/boot

swapon "${DISK}${SWAP_PART}"

echo "Ready for pacstrap"
