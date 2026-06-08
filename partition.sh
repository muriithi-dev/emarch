#!/bin/bash
set -Eeuo pipefail

############################
# CONFIG
############################

DISK="/dev/sda"

EFI_SIZE="1GiB"
SWAP_SIZE="6GiB"

HOSTNAME="arch"

LUKS_NAME="cryptroot"
MAPPER_ROOT="/dev/mapper/cryptroot"

############################
# SAFETY CHECK
############################

if [[ ! -b "$DISK" ]]; then
  echo "ERROR: $DISK is not a block device"
  exit 1
fi

echo "!!! THIS WILL WIPE $DISK !!!"
read -rp "Are you sure you want to erase the disk? [y/N]: " confirm
confirm="${confirm,,}"   # lowercase

[[ "$confirm" == "y" || "$confirm" == "yes" ]] || exit 1

############################
# PARTITIONING (parted)
############################

echo "Creating partitions..."

parted -s "$DISK" mklabel gpt

parted -s "$DISK" mkpart ESP fat32 1MiB "$EFI_SIZE"
parted -s "$DISK" set 1 esp on

parted -s "$DISK" mkpart swap linux-swap "$EFI_SIZE" "$((6 + 1))GiB"

parted -s "$DISK" mkpart luks ext4 "$((6 + 1))GiB" 100%

############################
# DETECT PARTITION PREFIX
############################

if [[ "$DISK" =~ nvme|mmcblk ]]; then
  P="p"
else
  P=""
fi

EFI_PART="${DISK}${P}1"
SWAP_PART="${DISK}${P}2"
ROOT_PART="${DISK}${P}3"

############################
# EFI FORMAT
############################

mkfs.fat -F32 "$EFI_PART"

############################
# LUKS SETUP (root only)
############################

echo "Setting up LUKS..."
cryptsetup luksFormat "$ROOT_PART"

cryptsetup open "$ROOT_PART" "$LUKS_NAME"

############################
# BTRFS SETUP
############################

mkfs.btrfs -L "arch_root" "$MAPPER_ROOT"

mount "$MAPPER_ROOT" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots

umount /mnt

############################
# MOUNT SUBVOLUMES
############################

mount -o subvol=@,compress=zstd "$MAPPER_ROOT" /mnt

mkdir -p /mnt/{boot,home,.snapshots}

mount -o subvol=@home,compress=zstd "$MAPPER_ROOT" /mnt/home
mount -o subvol=@snapshots,compress=zstd "$MAPPER_ROOT" /mnt/.snapshots

mount "$EFI_PART" /mnt/boot

############################
# SWAP
############################

mkswap "$SWAP_PART"
swapon "$SWAP_PART"

############################
# FSTAB GENERATION
############################

genfstab -U /mnt >> /mnt/etc/fstab

############################
# DONE (BASE SYSTEM READY)
############################

echo "Base system mounted at /mnt"
echo "Continue with pacstrap + arch-chroot"
