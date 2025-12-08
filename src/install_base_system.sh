#!/bin/bash

###################################
# Base System Installation Script #
###################################

set -e

echo -e "${BLUE}[6/10] Installing Base System...${NC}"

DRIVERS="mesa mesa-utils intel-ucode vulkan-intel libva-intel-driver vulkan-radeon xf86-video-amdgpu"

pacstrap /mnt base linux linux-headers linux-firmware lvm2 btrfs-progs neovim networkmanager grub efibootmgr git base-devel archlinux-keyring go "$DRIVERS"

genfstab -U /mnt >> /mnt/etc/fstab

echo -e "${GREEN}Base System Installation Finished!${NC}"