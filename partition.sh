############################
# LUKS (correct)
############################

cryptsetup luksFormat -q "$ROOT_PART"
cryptsetup open "$ROOT_PART" "$LUKS_NAME"

# verify mapper exists
if [[ ! -b "$MAPPER_ROOT" ]]; then
  echo "ERROR: $MAPPER_ROOT not created"
  exit 1
fi

############################
# BTRFS (correct)
############################

mkfs.btrfs -f -L "arch_root" "$MAPPER_ROOT"

mount "$MAPPER_ROOT" /mnt

btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@snapshots

umount /mnt
