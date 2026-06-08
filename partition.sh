#!/bin/bash
set -e

DISK="/dev/sda"

#########################
# SIZE VARIABLES (GB)
#########################
EFI_GB=1
SWAP_GB=2

#########################
# CONVERT GB → MiB
#########################
GB_TO_MIB=1024

EFI_MIB=$((EFI_GB * GB_TO_MIB))
SWAP_MIB=$((SWAP_GB * GB_TO_MIB))

#########################
# START POSITION
#########################
START=1

echo "Creating GPT on $DISK"
parted -s "$DISK" mklabel gpt

#########################
# PART 1 - EFI
#########################
END=$((START + EFI_MIB))
parted -s "$DISK" mkpart ESP fat32 ${START}MiB ${END}MiB
parted -s "$DISK" set 1 esp on
EFI_PART=1
START=$END

#########################
# PART 2 - SWAP
#########################
END=$((START + SWAP_MIB))
parted -s "$DISK" mkpart swap linux-swap ${START}MiB ${END}MiB
SWAP_PART=2
START=$END

#########################
# PART 3 - ROOT (REST)
#########################
parted -s "$DISK" mkpart root btrfs ${START}MiB 100%
ROOT_PART=3

echo "Partitioning done"
parted -s "$DISK" print

#########################
# FORMATTING
#########################
echo "Formatting partitions..."

# EFI (FAT32)
mkfs.fat -F32 "${DISK}${EFI_PART}"

# SWAP
mkswap "${DISK}${SWAP_PART}"

# ROOT
mkfs.btrfs -f "${DISK}${ROOT_PART}"

echo "Formatting complete"

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

# mount "${DISK}${ROOT_PART}" -o subvolid=256 /mnt
mount -o subvol=@,compress=zstd:3,noatime \
    "${DISK}${ROOT_PART}" /mnt

mkdir -p /mnt/{home,.snapshots,efi,.btrfsroot,var/log}

mount -o subvol=@home,compress=zstd:3,noatime \
    "${DISK}${ROOT_PART}" /mnt/home

mount -o subvol=@snapshots,compress=zstd:3,noatime \
    "${DISK}${ROOT_PART}" /mnt/.snapshots

mount -o subvol=@var_log,compress=zstd:3,noatime \
    "${DISK}${ROOT_PART}" /mnt/var/log

mount "${DISK}${EFI_PART}" /mnt/boot

swapon "${DISK}${SWAP_PART}"

echo "Ready for pacstrap"







