#!/bin/bash

###############################
# Custom Arch Linux Installer #
###############################

set -e

# Colors
export YELLOW='\033[0;33m'
export GREEN='\033[0;32m'
export BLUE='\033[0;34m'
export RED='\033[0;31m'
export NC='\033[0m'

echo -e "${BLUE}Starting Arch Installer...${NC}"

# 1. Check network connection
chmod +x ./src/check_network.sh
./src/check_network.sh

# 2. Prompt for installation variables
chmod +x ./src/configure_installation.sh
source ./src/configure_installation.sh

# 3. Format & encrypt partitions
chmod +x ./src/format_\&_encrypt_partitions.sh
source ./src/format_\&_encrypt_partitions.sh

# 4. Create btrfs subvolumes
chmod +x ./src/create_btrfs_subvolumes.sh
./src/create_btrfs_subvolumes.sh

# 5. Mount partitions
chmod +x ./src/mount_partitions.sh
./src/mount_partitions.sh

# 6. Install base system
chmod +x ./src/install_base_system.sh
./src/install_base_system.sh

# 7. Configure system
chmod +x ./src/configure_system.sh
./src/configure_system.sh

# 8. Install AUR
chmod +x ./src/install_aur.sh
./src/install_aur.sh

# 9. Install hyprland & essentials
chmod +x ./src/install_hyprland_\&_essentials.sh
./src/install_hyprland_\&_essentials.sh

# 10. Reboot
chmod +x ./src/reboot.sh
./src/reboot.sh