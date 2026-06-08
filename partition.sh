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

parted -s "$DISK" mklabel gpt

parted -s "$DISK" mkpart ESP fat32 1MiB "$EFI_SIZE"
parted -s "$DISK" set 1 esp on

parted -s "$DISK" mkpart swap linux-swap "$EFI_SIZE" "$((6 + 1))GiB"

parted -s "$DISK" mkpart luks ext4 "$((6 + 1))GiB" 100%

############################
# PARTITION NAMES
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
# EFI
############################

mkfs.fat -F32 "$EFI_PART"

############################
# LUKS (NO PROMPT MODE)
############################

# WARNING: wipes without asking
cryptsetup luksFormat -q "$ROOT_PART"
cryptsetup open "$ROOT_PART" "$LUKS_NAME"

############################
# BTRFS
############################

mkdir "$MAPPER_ROOT"
mkfs.btrfs -f -L "arch_root" "$MAPPER_ROOT"

mount "$MAPPER_ROOT" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots

umount /mnt

############################
# MOUNTS
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
# FSTAB
############################

genfstab -U /mnt >> /mnt/etc/fstab
