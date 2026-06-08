#!/bin/bash
set -Eeuo pipefail

############################
# CONFIG
############################

DISK="/dev/sda"

EFI_SIZE="1GiB"
SWAP_SIZE="2GiB"

LUKS_NAME="cryptroot"
MAPPER_ROOT="/dev/mapper/cryptroot"

############################
# PARTITIONING (parted)
############################

echo "Creating GPT partitions on $DISK..."

parted -s "$DISK" mklabel gpt

# EFI partition
parted -s "$DISK" mkpart ESP fat32 1MiB "$EFI_SIZE"
parted -s "$DISK" set 1 esp on

# Swap partition
parted -s "$DISK" mkpart swap linux-swap "$EFI_SIZE" "$SWAP_SIZE"

# Root partition (rest of disk)
parted -s "$DISK" mkpart luks ext4 "$SWAP_SIZE" 100%

############################
# PARTITION PREFIX HANDLING
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
# FORMAT EFI
############################

echo "Formatting EFI..."
mkfs.fat -F32 "$EFI_PART"

############################
# LUKS SETUP
############################

echo "Setting up LUKS..."
cryptsetup luksFormat -q "$ROOT_PART"
cryptsetup open "$ROOT_PART" "$LUKS_NAME"

# Ensure device is ready
udevadm settle

if [[ ! -b "$MAPPER_ROOT" ]]; then
  echo "ERROR: LUKS mapping failed"
  exit 1
fi

############################
# BTRFS SETUP
############################

echo "Creating Btrfs filesystem..."
mkfs.btrfs -f -L "arch_root" "$MAPPER_ROOT"

mount "$MAPPER_ROOT" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots

umount /mnt

############################
# MOUNT SUBVOLUMES
############################

echo "Mounting Btrfs subvolumes..."

mount -o subvol=@,compress=zstd "$MAPPER_ROOT" /mnt

mkdir -p /mnt/{boot,home,.snapshots}

mount -o subvol=@home,compress=zstd "$MAPPER_ROOT" /mnt/home
mount -o subvol=@snapshots,compress=zstd "$MAPPER_ROOT" /mnt/.snapshots

mount "$EFI_PART" /mnt/boot

############################
# SWAP
############################

echo "Setting up swap..."
mkswap "$SWAP_PART"
swapon "$SWAP_PART"

############################
# FSTAB
############################

echo "Generating fstab..."
genfstab -U /mnt >> /mnt/etc/fstab

echo "DONE: Base system mounted at /mnt"
