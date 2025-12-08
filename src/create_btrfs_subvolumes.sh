#!/bin/bash

####################################
# Btrfs Subvolumes Creation Script #
####################################

set -e

echo -e "${BLUE}[4/10] Creating Btrfs Subvolumes...${NC}"

mount /dev/ArchVG/root /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@snapshots
umount /mnt

echo -e "${GREEN}Subvolumes Creation Finished!${NC}"