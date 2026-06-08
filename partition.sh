#!/bin/bash
set -Eeuo pipefail

target="/dev/sda"

if [[ ! -b "$target" ]]; then
    echo "Error: $target is not a block device"
    exit 1
fi

cat /sys/firmware/efi/fw_platform_size

fdisk "$target" <<'EOF'
g
n
1

+1G
t
1
n
2

+6G
t
2
19
n
3


w
EOF

mkfs.fat -F32 "${target}1"
mkswap "${target}2"
mkfs.ext4 "${target}3"
