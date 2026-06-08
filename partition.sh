#!/usr/bin/env bash
set -euo pipefail

DISK="/dev/sda"

EFI_SIZE=1024   # 1GB EFI (good for kernels + snapshots)
SWAP_SIZE=4096  # adjust if needed

part() {
    if [[ "$DISK" =~ nvme|mmcblk ]]; then
        echo "${DISK}p$1"
    else
        echo "${DISK}$1"
    fi
}

echo "[!] DESTROYING ALL DATA ON $DISK"
# (intentionally no prompt as requested)

swapoff -a || true
umount -R /mnt || true

parted -s "$DISK" mklabel gpt

parted -s "$DISK" mkpart ESP fat32 1MiB ${EFI_SIZE}MiB
parted -s "$DISK" set 1 esp on

parted -s "$DISK" mkpart swap linux-swap ${EFI_SIZE}MiB $((EFI_SIZE + SWAP_SIZE))MiB

parted -s "$DISK" mkpart root btrfs $((EFI_SIZE + SWAP_SIZE))MiB 100%

partprobe "$DISK"
udevadm settle

EFI=$(part 1)
SWAP=$(part 2)
ROOT=$(part 3)

mkfs.fat -F32 "$EFI"
mkswap "$SWAP"
mkfs.btrfs -f "$ROOT"

mount "$ROOT" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@var_log

umount /mnt

# ROOT mount (Snapper-friendly)
mount -o subvol=@,compress=zstd,noatime "$ROOT" /mnt

mkdir -p /mnt/{home,.snapshots,var/log,boot/efi}

mount -o subvol=@home "$ROOT" /mnt/home
mount -o subvol=@snapshots "$ROOT" /mnt/.snapshots
mount -o subvol=@var_log "$ROOT" /mnt/var/log

# EFI MOUNT (IMPORTANT FOR LIMINE)
mount "$EFI" /mnt/boot/efi

swapon "$SWAP"

pacstrap -K /mnt \
    base linux linux-firmware \
    neovim limine efibootmgr dhcpcd \
    btrfs-progs snapper

genfstab -U /mnt >> /mnt/etc/fstab

echo "DONE. Now chroot and install Limine config."
