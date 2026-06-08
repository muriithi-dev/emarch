#!/bin/bash
set -Eeuo pipefail

# ===== Colors =====
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# ===== Logging =====
info()    { echo -e "${BLUE}[INFO]${NC} $*"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $*"; }
error()   { echo -e "${RED}[ERROR]${NC} $*" >&2; }
success() { echo -e "${GREEN}[OK]${NC} $*"; }

trap 'error "Script failed at line $LINENO"' ERR

# ===== Root Check =====
if [[ $EUID -ne 0 ]]; then
    error "Run as root."
    exit 1
fi

# ===== Disk Selection =====
info "Available disks:"

mapfile -t DISKS < <(
    lsblk -dno NAME,SIZE,MODEL,TYPE |
    awk '$4=="disk" {print $1 "|" $2 "|" substr($0,index($0,$3))}'
)

if [[ ${#DISKS[@]} -eq 0 ]]; then
    error "No disks found."
    exit 1
fi

echo

for i in "${!DISKS[@]}"; do
    IFS="|" read -r name size model <<< "${DISKS[$i]}"
    printf "${CYAN}%2d)${NC} /dev/%s (%s) %s\n" \
        "$((i+1))" "$name" "$size" "$model"
done

echo
read -rp "Select disk number: " CHOICE

if ! [[ "$CHOICE" =~ ^[0-9]+$ ]] || \
   (( CHOICE < 1 || CHOICE > ${#DISKS[@]} )); then
    error "Invalid selection."
    exit 1
fi

IFS="|" read -r DISK_NAME DISK_SIZE DISK_MODEL <<< \
    "${DISKS[$((CHOICE-1))]}"

DISK="/dev/$DISK_NAME"

echo
warn "Selected disk:"
echo "  Device : $DISK"
echo "  Size   : $DISK_SIZE"
echo "  Model  : $DISK_MODEL"
echo

warn "ALL DATA ON $DISK WILL BE DESTROYED."
read -rp "Type YES to continue: " CONFIRM

if [[ "$CONFIRM" != "YES" ]]; then
    info "Cancelled."
    exit 0
fi

# ===== Partition Plan =====
info "Partition layout:"
echo "  EFI   : 1 GiB"
echo "  BOOT  : 80 GiB"
echo "  ROOT  : Remaining space"
echo

read -rp "Proceed with partitioning? [y/N]: " PROCEED
[[ "$PROCEED" =~ ^[Yy]$ ]] || exit 0

# ===== Partitioning =====
info "Creating GPT partition table..."
parted -s "$DISK" mklabel gpt

info "Creating EFI partition..."
parted -s "$DISK" mkpart ESP fat32 1MiB 1025MiB
parted -s "$DISK" set 1 esp on

info "Creating /boot partition..."
parted -s "$DISK" mkpart primary ext4 1025MiB 81GiB

info "Creating root partition..."
parted -s "$DISK" mkpart primary ext4 81GiB 100%

# NVMe devices use p1, p2, p3
if [[ "$DISK" =~ nvme|mmcblk ]]; then
    EFI="${DISK}p1"
    BOOT="${DISK}p2"
    ROOT="${DISK}p3"
else
    EFI="${DISK}1"
    BOOT="${DISK}2"
    ROOT="${DISK}3"
fi

info "Waiting for kernel to detect partitions..."
partprobe "$DISK"
udevadm settle

# ===== Format =====
info "Formatting EFI..."
mkfs.fat -F32 "$EFI"

info "Formatting BOOT..."
mkfs.ext4 -F "$BOOT"

info "Formatting ROOT..."
mkfs.ext4 -F "$ROOT"

# ===== Mount =====
info "Mounting filesystems..."

mount "$ROOT" /mnt

mkdir -p /mnt/boot
mount "$BOOT" /mnt/boot

mkdir -p /mnt/boot/efi
mount "$EFI" /mnt/boot/efi

success "Partitioning complete."

echo
info "Final layout:"
lsblk "$DISK"

echo
success "Mounted:"
findmnt /mnt
