#!/bin/bash
set -e

DISK="/dev/sda"

#########################
### Create partitions ###
#########################
echo "Creating Partitions"

# 1MiB → 1025MiB = ~1GiB EFI
# 1025MiB → 3073MiB = +2GiB swap
# 3073MiB → 100% = rest of disk

# wipe + create GPT
parted -s "$DISK" mklabel gpt

# 1) EFI partition (1GiB)
parted -s "$DISK" mkpart ESP fat32 1MiB 1025MiB
parted -s "$DISK" set 1 esp on

# 2) Swap partition (2GiB)
parted -s "$DISK" mkpart swap linux-swap 1025MiB 3073MiB

# 3) Boot partition (2GiB)
parted -s "$DISK" mkpart root btrfs 1025MiB 3073MiB

# 4) Root partition (rest of disk)
parted -s "$DISK" mkpart root btrfs 3073MiB 100%

echo "Partitions created successfully"
fdisk -l

#############################
### Format the partitions ###
#############################

echo "Formating partitions"

mkfs.fat -F 32 "$DISK"1
mkswap "$DISK"2
mkfs.btrfs "$DISK"3
mkfs.btrfs "$DISK"4

echo "Formated successfully"
