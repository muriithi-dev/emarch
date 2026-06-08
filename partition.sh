#!/usr/bin/env bash
set -euo pipefail

DISK="/dev/sda"

EFI_SIZE=1024
SWAP_SIZE=4096

part() {
    if [[ "$DISK" =~ nvme|mmcblk ]]; then
        echo "${DISK}p$1"
    else
        echo "${DISK}$1"
    fi
}

echo "[!!!] WIPING ENTIRE DISK: $DISK"

swapoff -a || true
umount -R /mnt || true

########################################
# PARTITION TABLE
########################################

parted -s "$DISK" mklabel gpt

# EFI
parted -s "$DISK" mkpart ESP fat32 1MiB ${EFI_SIZE}MiB
parted -s "$DISK" set 1 esp on

# SWAP
parted -s "$DISK" mkpart swap linux-swap ${EFI_SIZE}MiB $((EFI_SIZE + SWAP_SIZE))MiB

# ROOT
parted -s "$DISK" mkpart root btrfs $((EFI_SIZE + SWAP_SIZE))MiB 100%

partprobe "$DISK"
udevadm settle

EFI=$(part 1)
SWAP=$(part 2)
ROOT=$(part 3)

########################################
# FORMAT
########################################

mkfs.fat -F32 "$EFI"
mkswap "$SWAP"
mkfs.btrfs -f "$ROOT"

swapon "$SWAP"

########################################
# BTRFS SUBVOLUMES
########################################

mount "$ROOT" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots
btrfs subvolume create /mnt/@var_log
btrfs subvolume create /mnt/@var_cache
btrfs subvolume create /mnt/@var_tmp

umount /mnt

########################################
# MOUNT SYSTEM
########################################

mount -o subvol=@,compress=zstd,noatime "$ROOT" /mnt

mkdir -p /mnt/{home,.snapshots,var/log,var/cache,var/tmp,boot/efi}

mount -o subvol=@home "$ROOT" /mnt/home
mount -o subvol=@snapshots "$ROOT" /mnt/.snapshots
mount -o subvol=@var_log "$ROOT" /mnt/var/log
mount -o subvol=@var_cache "$ROOT" /mnt/var/cache
mount -o subvol=@var_tmp "$ROOT" /mnt/var/tmp

########################################
# EFI SYSTEM PARTITION (LIMINE REQUIREMENT)
########################################

mount "$EFI" /mnt/boot/efi

########################################
# BASE INSTALL
########################################

pacstrap -K /mnt \
    base linux linux-firmware \
    neovim \
    limine efibootmgr dhcpcd \
    btrfs-progs snapper

genfstab -U /mnt >> /mnt/etc/fstab

########################################
# FULL AUTOMATED SYSTEM CONFIG
########################################

arch-chroot /mnt /bin/bash <<'EOF'

set -e

########################################
# TIMEZONE
########################################
ln -sf /usr/share/zoneinfo/Africa/Nairobi /etc/localtime
hwclock --systohc

########################################
# LOCALE
########################################
sed -i 's/#en_US.UTF-8 UTF-8/en_US.UTF-8 UTF-8/' /etc/locale.gen
locale-gen

echo "LANG=en_US.UTF-8" > /etc/locale.conf

########################################
# HOSTNAME
########################################
echo "arch" > /etc/hostname

cat > /etc/hosts <<EOT
127.0.0.1   localhost
::1         localhost
127.0.1.1   arch.localdomain arch
EOT

########################################
# SNAPPER SETUP
########################################
snapper -c root create-config /

umount /.snapshots || true
rm -rf /.snapshots
mkdir /.snapshots
mount -a

systemctl enable --now snapper-timeline.timer
systemctl enable --now snapper-cleanup.timer

########################################
# NETWORK
########################################
systemctl enable dhcpcd

EOF

########################################
# LIMINE SETUP (UEFI BOOT)
########################################

ROOT_UUID=$(blkid -s UUID -o value "$ROOT")

cat > /mnt/boot/efi/limine.conf <<EOF
timeout: 3

/Arch Linux
    protocol: linux
    path: boot():/vmlinuz-linux
    module_path: boot():/initramfs-linux.img
    cmdline: root=UUID=${ROOT_UUID} rw rootflags=subvol=@
EOF

mkdir -p /mnt/boot/efi/EFI/BOOT
cp /usr/share/limine/BOOTX64.EFI /mnt/boot/efi/EFI/BOOT/BOOTX64.EFI

########################################
# DONE
########################################

echo ""
echo "====================================="
echo " INSTALL COMPLETE"
echo "====================================="
echo ""
echo "Reboot after chroot if needed."
echo "Limine + Snapper + Btrfs ready."
echo ""



