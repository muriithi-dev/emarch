#!/bin/bash
set -e

DISK="/dev/sda"

#########################
# SIZE VARIABLES (GB)
#########################
EFI_SIZE_GB=1
SWAP_SIZE_GB=2
BOOT_SIZE_GB=2   # optional extra partition
ROOT_SIZE_GB=0   # 0 = rest of disk

#########################
# CONVERT TO MIB
#########################
EFI_SIZE_MIB=$((EFI_SIZE_GB * 1024))
SWAP_SIZE_MIB=$((SWAP_SIZE_GB * 1024))
BOOT_SIZE_MIB=$((BOOT_SIZE_GB * 1024))

#########################
# START/END TRACKING
#########################
START=1   # MiB (leave 1MiB offset for alignment)

echo "Creating partitions on $DISK"

parted -s "$DISK" mklabel gpt

#########################
# 1. EFI
#########################
END=$((START + EFI_SIZE_MIB))
parted -s "$DISK" mkpart ESP fat32 ${START}MiB ${END}MiB
parted -s "$DISK" set 1 esp on
START=$END

#########################
# 2. SWAP
#########################
END=$((START + SWAP_SIZE_MIB))
parted -s "$DISK" mkpart swap linux-swap ${START}MiB ${END}MiB
START=$END

#########################
# 3. BOOT
#########################
END=$((START + BOOT_SIZE_MIB))
parted -s "$DISK" mkpart boot btrfs ${START}MiB ${END}MiB
START=$END

#########################
# 4. ROOT (rest of disk)
#########################
parted -s "$DISK" mkpart root btrfs ${START}MiB 100%

echo "Partitioning complete"
parted -s "$DISK" print
