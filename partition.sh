#!/usr/bin/env bash
set -Eeuo pipefail

########################################
# CONFIG
########################################

DISK="/dev/sda"

HOSTNAME="arch"

EFI_SIZE_GB=1
SWAP_SIZE_GB=4

########################################
# HELPERS
########################################

part() {
    if [[ "$DISK" =~ nvme|mmcblk ]]; then
        echo "${DISK}p$1"
    else
        echo "${DISK}$1"
    fi
}

########################################
# SAFETY CHECK
########################################

echo
echo "WARNING:"
echo "This will COMPLETELY ERASE:"
echo "  $DISK"
echo

read -rp "Continue? [y/N]: " CONFIRM

[[ "$CONFIRM" =~ ^[Yy]$ ]] || exit 1

########################################
# UNMOUNT ANYTHING
########################################

swapoff -a 2>/dev/null || true
umount -R /mnt 2>/dev/null || true

########################################
# PARTITIONING
########################################

EFI_MIB=$((EFI_SIZE_GB * 1024))
SWAP_MIB=$((SWAP_SIZE_GB * 1024))

START=1

parted -s "$DISK" mklabel gpt

# EFI
END=$((START + EFI_MIB))

parted -s "$DISK" \
    mkpart ESP fat32 "${START}MiB" "${END}MiB"

parted -s "$DISK" set 1 esp on

START=$END

# SWAP
END=$((START + SWAP_MIB))

parted -s "$DISK" \
    mkpart primary linux-swap "${START}MiB" "${END}MiB"

START=$END

# ROOT
parted -s "$DISK" \
    mkpart primary btrfs "${START}MiB" 100%

partprobe "$DISK"
udevadm settle

EFI_PART=$(part 1)
SWAP_PART=$(part 2)
ROOT_PART=$(part 3)

########################################
# FORMAT
########################################

mkfs.fat -F32 "$EFI_PART"

mkswap "$SWAP_PART"

mkfs.btrfs -f "$ROOT_PART"

########################################
# CREATE SUBVOLUMES
########################################

mount "$ROOT_PART" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@var_log
btrfs subvolume create /mnt/@var_cache
btrfs subvolume create /mnt/@var_tmp

umount /mnt

########################################
# MOUNT ROOT
########################################

mount \
-o subvol=@,compress=zstd:3,noatime \
"$ROOT_PART" /mnt

mkdir -p \
/mnt/home \
/mnt/.snapshots \
/mnt/boot \
/mnt/var/log \
/mnt/var/cache \
/mnt/var/tmp

mount \
-o subvol=@home,compress=zstd:3,noatime \
"$ROOT_PART" /mnt/home

mount \
-o subvol=@snapshots,compress=zstd:3,noatime \
"$ROOT_PART" /mnt/.snapshots

mount \
-o subvol=@var_log,compress=zstd:3,noatime \
"$ROOT_PART" /mnt/var/log

mount \
-o subvol=@var_cache,compress=zstd:3,noatime \
"$ROOT_PART" /mnt/var/cache

mount \
-o subvol=@var_tmp,compress=zstd:3,noatime \
"$ROOT_PART" /mnt/var/tmp

mount "$EFI_PART" /mnt/boot

swapon "$SWAP_PART"

########################################
# INSTALL BASE SYSTEM
########################################

pacstrap -K /mnt \
    base \
    linux \
    linux-firmware \
    neovim \
    limine \
    efibootmgr \
    dhcpcd

########################################
# FSTAB
########################################

genfstab -U /mnt >> /mnt/etc/fstab

########################################
# READY
########################################

echo
echo "================================="
echo "Base installation complete"
echo "================================="
echo
echo "Next:"
echo
echo "arch-chroot /mnt"
echo
echo "Then configure:"
echo "  - timezone"
echo "  - locale"
echo "  - hostname"
echo "  - users"
echo "  - limine bootloader"
echo
