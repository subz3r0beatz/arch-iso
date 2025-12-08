#!/bin/bash

#############################
# Partition Mounting Script #
#############################

set -e

echo -e "${BLUE}[5/10] Mounting Partitions & Subvolumes...${NC}"

MOUNT_OPTIONS="noatime,compress=zstd,space_cache=v2"
mount -o $MOUNT_OPTIONS,subvol=@ /dev/ArchVG/root /mnt
mkdir -p /mnt/{boot,efi,home,var,.snapshots}
mount -o $MOUNT_OPTIONS,subvol=@home /dev/ArchVG/root /mnt/home
mount -o $MOUNT_OPTIONS,subvol=@var /dev/ArchVG/root /mnt/var
mount -o $MOUNT_OPTIONS,subvol=@snapshots /dev/ArchVG/root /mnt/.snapshots
mount "$P2" /mnt/boot
mount "$P1" /mnt/efi
swapon /dev/ArchVG/swap

echo -e "${GREEN}Mountpoint Setup Finished!${NC}"