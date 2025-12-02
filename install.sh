#!/bin/bash

# ==============================================================================
#  Custom Arch Linux Installer - Encrypted LVM, Btrfs, Hyprland
#  Features: Network Retry, Keymap, Auto-GPU Drivers, Pipewire Audio
# ==============================================================================

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${BLUE}Starting Custom Arch Installer...${NC}"

# ==============================================================================
# 1. Keymap Selection
# ==============================================================================
echo -e "${GREEN}[1/10] Keyboard Layout${NC}"
read -p "Enter keymap code (e.g., 'us', 'de', 'fr', 'uk', 'es') [default: us]: " KEYMAP_INPUT
KEYMAP=${KEYMAP_INPUT:-us}
loadkeys "$KEYMAP" || loadkeys us

# ==============================================================================
# 2. Network Check & Retry Loop
# ==============================================================================
echo -e "${GREEN}[2/10] Network Check${NC}"
while true; do
    if ping -c 1 archlinux.org &> /dev/null; then
        echo "Internet connected."
        break
    else
        echo -e "${RED}No internet connection detected.${NC}"
        echo "1) Open iwctl (WiFi)  2) Retry  3) Abort"
        read -p "Choice [1-3]: " NET_CHOICE
        case $NET_CHOICE in
            1) iwctl ;;
            2) echo "Retrying..." ; sleep 2 ;;
            3) exit 1 ;;
        esac
    fi
done

# ==============================================================================
# 3. Disk & User Configuration
# ==============================================================================
echo -e "${GREEN}[3/10] Configuration${NC}"
lsblk -d -p -n -o NAME,SIZE,MODEL
echo ""
read -p "Enter installation disk (e.g., /dev/nvme0n1): " DISK
if [ ! -b "$DISK" ]; then echo "Invalid disk."; exit 1; fi

echo -e "${RED}WARNING: ALL DATA ON $DISK WILL BE DESTROYED.${NC}"
read -p "Are you sure? (y/N): " CONFIRM
[[ "$CONFIRM" == "y" ]] || exit 1

read -p "Enter EFI size (default 512M): " EFI_SIZE
EFI_SIZE=${EFI_SIZE:-512M}
read -p "Enter Boot size (default 1G): " BOOT_SIZE
BOOT_SIZE=${BOOT_SIZE:-1G}
read -p "Enter Swap size (default 8G): " SWAP_SIZE
SWAP_SIZE=${SWAP_SIZE:-8G}

read -p "Enter Hostname: " NEW_HOSTNAME
read -p "Enter Username: " NEW_USER
echo "Enter Password (Root/User/Luks):"
read -s PASSWORD
echo ""

# ==============================================================================
# 4. Partitioning & Encryption
# ==============================================================================
echo -e "${GREEN}[4/10] Partitioning & Encryption${NC}"
wipefs -a "$DISK"
sgdisk -Z "$DISK"
sgdisk -n 1:0:+$EFI_SIZE -t 1:ef00 "$DISK"
sgdisk -n 2:0:+$BOOT_SIZE -t 2:8300 "$DISK"
sgdisk -n 3:0:0 -t 3:8e00 "$DISK"

if [[ "$DISK" == *"nvme"* ]]; then P1="${DISK}p1"; P2="${DISK}p2"; P3="${DISK}p3"; else P1="${DISK}1"; P2="${DISK}2"; P3="${DISK}3"; fi

echo -n "$PASSWORD" | cryptsetup -q luksFormat "$P3"
echo -n "$PASSWORD" | cryptsetup open "$P3" cryptlvm -

pvcreate /dev/mapper/cryptlvm
vgcreate ArchVG /dev/mapper/cryptlvm
lvcreate -L "$SWAP_SIZE" -n swap ArchVG
lvcreate -l 100%FREE -n root ArchVG

mkfs.fat -F32 "$P1"
mkfs.ext4 "$P2"
mkswap /dev/ArchVG/swap
mkfs.btrfs /dev/ArchVG/root

# ==============================================================================
# 5. Mounting & Subvolumes
# ==============================================================================
echo -e "${GREEN}[5/10] Creating Subvolumes${NC}"
mount /dev/ArchVG/root /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@snapshots
umount /mnt

mount -o noatime,compress=zstd,subvol=@ /dev/ArchVG/root /mnt
mkdir -p /mnt/{boot,efi,home,var,.snapshots}
mount -o noatime,compress=zstd,subvol=@home /dev/ArchVG/root /mnt/home
mount -o noatime,compress=zstd,subvol=@var /dev/ArchVG/root /mnt/var
mount -o noatime,compress=zstd,subvol=@snapshots /dev/ArchVG/root /mnt/.snapshots
mount "$P2" /mnt/boot
mkdir -p /mnt/efi
mount "$P1" /mnt/efi
swapon /dev/ArchVG/swap

# ==============================================================================
# 6. Hardware Detection (CPU & GPU)
# ==============================================================================
echo -e "${GREEN}[6/10] Detecting Hardware...${NC}"

# CPU Microcode
UCODE=""
if grep -q "Intel" /proc/cpuinfo; then UCODE="intel-ucode"; fi
if grep -q "AMD" /proc/cpuinfo; then UCODE="amd-ucode"; fi

# GPU Drivers
GPU_DRIVER=""
IS_NVIDIA=false

if lspci | grep -i "NVIDIA"; then
    echo "  -> NVIDIA GPU detected."
    GPU_DRIVER="nvidia nvidia-utils nvidia-settings"
    IS_NVIDIA=true
fi
if lspci | grep -i "Intel" | grep -i "VGA"; then
    echo "  -> Intel GPU detected."
    GPU_DRIVER="$GPU_DRIVER mesa vulkan-intel intel-media-driver"
fi
if lspci | grep -i "AMD" | grep -i "VGA"; then
    echo "  -> AMD GPU detected."
    GPU_DRIVER="$GPU_DRIVER mesa vulkan-radeon xf86-video-amdgpu"
fi
if lspci | grep -i "VMware" || lspci | grep -i "VirtualBox"; then
    echo "  -> VM detected."
    GPU_DRIVER="$GPU_DRIVER mesa xf86-video-vmware"
fi

echo "  -> Drivers to install: $UCODE $GPU_DRIVER"

# ==============================================================================
# 7. Base Installation
# ==============================================================================
echo -e "${GREEN}[7/10] Installing Base System...${NC}"
pacstrap /mnt base linux linux-firmware lvm2 btrfs-progs neovim networkmanager grub efibootmgr git base-devel $UCODE $GPU_DRIVER

genfstab -U /mnt >> /mnt/etc/fstab

# ==============================================================================
# 8. System Configuration (Chroot)
# ==============================================================================
echo -e "${GREEN}[8/10] Configuring System${NC}"

cat <<EOF > /mnt/setup_internal.sh
#!/bin/bash

# Locale & Time
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$NEW_HOSTNAME" > /etc/hostname
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf

echo "127.0.0.1 localhost" >> /etc/hosts
echo "127.0.1.1 $NEW_HOSTNAME.localdomain $NEW_HOSTNAME" >> /etc/hosts

# Users
echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash "$NEW_USER"
echo "$NEW_USER:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel_auth

# Initramfs Hooks
sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems resume fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# GRUB Config
LUKS_UUID=\$(blkid -s UUID -o value $P3)

# Base kernel params
GRUB_PARAMS="loglevel=3 quiet cryptdevice=UUID=\${LUKS_UUID}:cryptlvm root=/dev/mapper/ArchVG-root resume=/dev/mapper/ArchVG-swap"

# Add Nvidia specific params if needed
if [ "$IS_NVIDIA" = true ]; then
    GRUB_PARAMS="\$GRUB_PARAMS nvidia_drm.modeset=1"
fi

sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"\${GRUB_PARAMS}\"|" /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager
EOF

chmod +x /mnt/setup_internal.sh
arch-chroot /mnt ./setup_internal.sh
rm /mnt/setup_internal.sh

# ==============================================================================
# 9. Hyprland & Pipewire Setup
# ==============================================================================
echo -e "${GREEN}[9/10] Installing Hyprland & Pipewire${NC}"

cat <<EOF > /mnt/setup_gui.sh
#!/bin/bash

# Install GUI + Audio packages
# pipewire: Core audio
# wireplumber: Session manager
# pipewire-pulse: PulseAudio support
# pipewire-alsa: ALSA support
pacman -S --noconfirm hyprland kitty waybar polkit-kde-agent ttf-jetbrains-mono-nerd-font sddm pipewire pipewire-pulse pipewire-alsa wireplumber

systemctl enable sddm
EOF

chmod +x /mnt/setup_gui.sh
arch-chroot /mnt ./setup_gui.sh
rm /mnt/setup_gui.sh

# ==============================================================================
# 10. Cleanup & Reboot
# ==============================================================================
echo -e "${GREEN}[10/10] Installation Complete!${NC}"
echo "Rebooting in 5 seconds..."
sleep 5
reboot
