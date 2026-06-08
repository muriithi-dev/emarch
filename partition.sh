#!/bin/bash
set -Eeuo pipefail

############################
# CONFIG
############################

DISK="/dev/sda"

EFI_SIZE=1024      # MiB
SWAP_SIZE=2048     # MiB
ROOT_START=$((EFI_SIZE + SWAP_SIZE))

LUKS_NAME="cryptroot"
MAPPER_ROOT="/dev/mapper/cryptroot"

############################
# PARTITIONING (SAFE + EXACT)
############################

echo "Wiping and creating GPT..."

parted -s "$DISK" mklabel gpt

# EFI (1 MiB → 1024 MiB)
parted -s "$DISK" mkpart ESP fat32 1MiB ${EFI_SIZE}MiB
parted -s "$DISK" set 1 esp on

# SWAP (1024 → 3072 MiB)
parted -s "$DISK" mkpart swap linux-swap ${EFI_SIZE}MiB ${ROOT_START}MiB

# ROOT (rest)
parted -s "$DISK" mkpart luks ${ROOT_START}MiB 100%

############################
# DETECT PARTITIONS
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

mkfs.fat -F32 "$EFI_PART"

############################
# LUKS
############################

echo "Creating LUKS..."

cryptsetup luksFormat "$ROOT_PART"

echo "Opening LUKS..."

cryptsetup open "$ROOT_PART" "$LUKS_NAME"

udevadm settle

# HARD CHECK
if [[ ! -b "$MAPPER_ROOT" ]]; then
  echo "❌ LUKS mapping failed"
  echo "Debug:"
  lsblk
  cryptsetup status "$LUKS_NAME" || true
  ls -l /dev/mapper
  exit 1
fi

############################
# BTRFS
############################

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

echo "DONE"
