#!/bin/bash
set -e

DISK="/dev/sda"

#########################
# SIZE VARIABLES (GB)
#########################
EFI_GB=1
SWAP_GB=2
BOOT_GB=2

#########################
# CONVERT GB → MiB
#########################
GB_TO_MIB=1024

EFI_MIB=$((EFI_GB * GB_TO_MIB))
SWAP_MIB=$((SWAP_GB * GB_TO_MIB))
BOOT_MIB=$((BOOT_GB * GB_TO_MIB))

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
# PART 3 - BOOT / HOME-BTRFS
#########################
END=$((START + BOOT_MIB))
parted -s "$DISK" mkpart boot btrfs ${START}MiB ${END}MiB
BOOT_PART=3
START=$END

#########################
# PART 4 - HOME (REST)
#########################
parted -s "$DISK" mkpart home btrfs ${START}MiB 100%
HOME_PART=4

echo "Partitioning done"
parted -s "$DISK" print

#########################
# FORMATTING
#########################
echo "Formatting partitions..."

# EFI (FAT32)
mkfs.fat -F 32 "${DISK}${EFI_PART}"

# SWAP
mkswap "${DISK}${SWAP_PART}"

# BOOT (btrfs or ext4 depending on your choice)
mkfs.btrfs -f "${DISK}${BOOT_PART}"

# HOME
mkfs.btrfs -f "${DISK}${HOME_PART}"

echo "Formatting complete"
