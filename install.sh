#!/bin/bash

# ==============================================================================
#  Custom Arch Linux Installer - Encrypted LVM, Btrfs, Hyprland
#  Features: Network Retry, Keymap Selection, Minimal Bloat
# ==============================================================================

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting Custom Arch Installer...${NC}"

# ==============================================================================
# 1. Keymap Selection (Crucial for typing passwords correctly)
# ==============================================================================
echo -e "${GREEN}[1/9] Keyboard Layout${NC}"
read -p "Enter keymap code (e.g., 'us', 'de', 'fr', 'uk', 'es') [default: us]: " KEYMAP_INPUT
KEYMAP=${KEYMAP_INPUT:-us}

echo "Loading keymap: $KEYMAP"
loadkeys "$KEYMAP"

if [ $? -ne 0 ]; then
    echo -e "${RED}Error loading keymap. Defaulting to 'us'.${NC}"
    KEYMAP="us"
    loadkeys us
fi

# ==============================================================================
# 2. Network Check & Retry Loop
# ==============================================================================
echo -e "${GREEN}[2/9] Network Check${NC}"

while true; do
    if ping -c 1 archlinux.org &> /dev/null; then
        echo "Internet connected."
        break
    else
        echo -e "${RED}No internet connection detected.${NC}"
        echo "Select an option:"
        echo "1) Open iwctl (Connect to WiFi)"
        echo "2) Retry connection check"
        echo "3) Abort"
        read -p "Choice [1-3]: " NET_CHOICE

        case $NET_CHOICE in
            1)
                echo "Launching iwctl. Type 'station wlan0 connect YOUR_SSID', then 'exit'."
                iwctl
                ;;
            2)
                echo "Retrying..."
                sleep 2
                ;;
            3)
                echo "Aborting installation."
                exit 1
                ;;
            *)
                echo "Invalid option."
                ;;
        esac
    fi
done

# ==============================================================================
# 3. User Prompts & Configuration
# ==============================================================================
echo -e "${GREEN}[3/9] Disk & User Configuration${NC}"

# List disks
lsblk -d -p -n -o NAME,SIZE,MODEL
echo ""
read -p "Enter installation disk (e.g., /dev/nvme0n1 or /dev/sda): " DISK

if [ ! -b "$DISK" ]; then
    echo "Invalid disk. Aborting."
    exit 1
fi

echo -e "${RED}WARNING: ALL DATA ON $DISK WILL BE DESTROYED.${NC}"
read -p "Are you sure? (y/N): " CONFIRM
if [[ "$CONFIRM" != "y" ]]; then exit 1; fi

# Partition Sizes
read -p "Enter EFI partition size (default 512M): " EFI_SIZE
EFI_SIZE=${EFI_SIZE:-512M}

read -p "Enter Boot partition size (default 1G): " BOOT_SIZE
BOOT_SIZE=${BOOT_SIZE:-1G}

read -p "Enter Swap partition size (default 8G): " SWAP_SIZE
SWAP_SIZE=${SWAP_SIZE:-8G}

# User Config
read -p "Enter Hostname: " NEW_HOSTNAME
read -p "Enter Username: " NEW_USER
echo "Enter Password (will be used for Root, User, and Encryption):"
read -s PASSWORD
echo ""

# ==============================================================================
# 4. Partitioning & Encryption
# ==============================================================================
echo -e "${GREEN}[4/9] Partitioning & Encryption${NC}"

# Wipe disk signatures
wipefs -a "$DISK"
sgdisk -Z "$DISK"

# Create Partitions
# 1: EFI, 2: Boot, 3: LVM (Encrypted)
sgdisk -n 1:0:+$EFI_SIZE -t 1:ef00 "$DISK"
sgdisk -n 2:0:+$BOOT_SIZE -t 2:8300 "$DISK"
sgdisk -n 3:0:0 -t 3:8e00 "$DISK"

# Detect partition names (nvme0n1p1 vs sda1)
if [[ "$DISK" == *"nvme"* ]]; then
    P1="${DISK}p1"
    P2="${DISK}p2"
    P3="${DISK}p3"
else
    P1="${DISK}1"
    P2="${DISK}2"
    P3="${DISK}3"
fi

# Encrypt Partition 3
echo -n "$PASSWORD" | cryptsetup -q luksFormat "$P3"
echo -n "$PASSWORD" | cryptsetup open "$P3" cryptlvm -

# LVM Setup
pvcreate /dev/mapper/cryptlvm
vgcreate ArchVG /dev/mapper/cryptlvm
lvcreate -L "$SWAP_SIZE" -n swap ArchVG
lvcreate -l 100%FREE -n root ArchVG

# Formatting
mkfs.fat -F32 "$P1"
mkfs.ext4 "$P2"
mkswap /dev/ArchVG/swap
mkfs.btrfs /dev/ArchVG/root

# ==============================================================================
# 5. Mounting & Subvolumes
# ==============================================================================
echo -e "${GREEN}[5/9] Creating Subvolumes${NC}"

mount /dev/ArchVG/root /mnt

# Create Btrfs Subvolumes
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@snapshots

umount /mnt

# Mount Real Structure
mount -o noatime,compress=zstd,space_cache=v2,subvol=@ /dev/ArchVG/root /mnt

mkdir -p /mnt/{boot,efi,home,var,.snapshots}
mount -o noatime,compress=zstd,space_cache=v2,subvol=@home /dev/ArchVG/root /mnt/home
mount -o noatime,compress=zstd,space_cache=v2,subvol=@var /dev/ArchVG/root /mnt/var
mount -o noatime,compress=zstd,space_cache=v2,subvol=@snapshots /dev/ArchVG/root /mnt/.snapshots

# Mount Boot and EFI
mount "$P2" /mnt/boot
mkdir -p /mnt/efi
mount "$P1" /mnt/efi

# Activate Swap
swapon /dev/ArchVG/swap

# ==============================================================================
# 6. Base Installation
# ==============================================================================
echo -e "${GREEN}[6/9] Installing Base System...${NC}"

# Detect CPU for microcode
CPU_UCODE=""
if grep -q "Intel" /proc/cpuinfo; then
    CPU_UCODE="intel-ucode"
elif grep -q "AMD" /proc/cpuinfo; then
    CPU_UCODE="amd-ucode"
fi

pacstrap /mnt base linux linux-firmware lvm2 btrfs-progs neovim networkmanager grub efibootmgr git base-devel $CPU_UCODE

# Generate Fstab
genfstab -U /mnt >> /mnt/etc/fstab

# ==============================================================================
# 7. System Configuration (Chroot)
# ==============================================================================
echo -e "${GREEN}[7/9] Configuring System${NC}"

# Create a setup script to run inside chroot
cat <<EOF > /mnt/setup_internal.sh
#!/bin/bash

# Timezone & Locale
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$NEW_HOSTNAME" > /etc/hostname

# Set Console Keymap (Persist the selection made earlier)
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

# Hosts
echo "127.0.0.1 localhost" >> /etc/hosts
echo "127.0.1.1 $NEW_HOSTNAME.localdomain $NEW_HOSTNAME" >> /etc/hosts

# Users & Passwords
echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash "$NEW_USER"
echo "$NEW_USER:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel_auth

# MKINITCPIO Config (Hooks for Encrypt, LVM, Resume)
# We need 'encrypt' before 'lvm2', and 'resume' after 'lvm2'
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems resume fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# GRUB Bootloader
# We need to find the UUID of the raw encrypted partition (P3)
LUKS_UUID=\$(blkid -s UUID -o value $P3)

# Configure GRUB for LUKS + LVM + Hibernation
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"loglevel=3 quiet cryptdevice=UUID=\${LUKS_UUID}:cryptlvm root=/dev/mapper/ArchVG-root resume=/dev/mapper/ArchVG-swap\"|" /etc/default/grub

# Install GRUB
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

# Enable Networking
systemctl enable NetworkManager

EOF

# Execute the setup script inside /mnt
chmod +x /mnt/setup_internal.sh
arch-chroot /mnt ./setup_internal.sh
rm /mnt/setup_internal.sh

# ==============================================================================
# 8. Hyprland & Minimal GUI Setup
# ==============================================================================
echo -e "${GREEN}[8/9] Installing Hyprland (Minimal)${NC}"

# Running this in chroot as well
cat <<EOF > /mnt/setup_gui.sh
#!/bin/bash

# Install minimal Hyprland packages
# kitty: Terminal (needed)
# polkit-kde-agent: Authentication agent (needed for GUI sudo prompts)
# ttf-jetbrains-mono-nerd: Font (so icons/text aren't broken)
pacman -S --noconfirm hyprland kitty waybar polkit-kde-agent ttf-jetbrains-mono-nerd-font sddm

# Enable Display Manager
systemctl enable sddm

EOF

chmod +x /mnt/setup_gui.sh
arch-chroot /mnt ./setup_gui.sh
rm /mnt/setup_gui.sh

# ==============================================================================
# 9. Cleanup & Reboot
# ==============================================================================
echo -e "${GREEN}[9/9] Installation Complete!${NC}"
echo "You can now reboot. Remove the installation media."
echo "Login with your user: $NEW_USER"
