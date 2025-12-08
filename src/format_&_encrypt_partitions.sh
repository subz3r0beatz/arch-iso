#!/bin/bash

#################################
# Formatting & Encryption Script #
#################################

set -e

echo -e "${BLUE}[3/10] Formatting & Encrypting Partitions...${NC}"

echo -e "${YELLOW}Wiping Disk...${NC}"
wipefs -a "$DISK"
sgdisk -Z "$DISK"

# Create partitions
sgdisk -n 1:0:+"${EFI_SIZE}" -t 1:ef00 "$DISK"
sgdisk -n 2:0:+"${BOOT_SIZE}" -t 2:8300 "$DISK"
sgdisk -n 3:0:0 -t 3:8e00 "$DISK"

if [[ "$DISK" == *"nvme"* ]]; then
  P1="${DISK}p1"; P2="${DISK}p2"; P3="${DISK}p3"
else
  P1="${DISK}1"; P2="${DISK}2"; P3="${DISK}3"
fi

echo -e "${YELLOW}Encrypting Drive...${NC}"
echo -e -n "$PASSWORD" | cryptsetup -q luksFormat "$P3"
echo -e -n "$PASSWORD" | cryptsetup open "$P3" cryptlvm -

# LVM and formatting
pvcreate /dev/mapper/cryptlvm
vgcreate ArchVG /dev/mapper/cryptlvm

lvcreate -L "${SWAP_SIZE}" -n swap ArchVG
lvcreate -l 100%FREE -n root ArchVG

echo -e "${YELLOW}Formatting Partitions...${NC}"
mkfs.fat -F32 "$P1"
mkfs.ext4 "$P2"
mkswap /dev/ArchVG/swap
mkfs.btrfs /dev/ArchVG/root

echo -e "${GREEN}Partition Creation Finished!${NC}"

export P1
export P2
export P3