#!/bin/bash

# ==============================================================================
#  Custom Arch Linux Installer - Clean Standard Boot
#  Includes: LVM-on-LUKS, Btrfs, Hyprland, Audio, Auto-GPU Drivers
# ==============================================================================

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}Starting Arch Installer...${NC}"

# ==============================================================================
# 1. Keymap & Network
# ==============================================================================
echo -e "${GREEN}[1/10] Setup Environment${NC}"
read -p "Enter keymap (e.g., us, de, fr): " KEYMAP_INPUT
KEYMAP=${KEYMAP_INPUT:-us}
loadkeys "$KEYMAP" || loadkeys us

while true; do
    if ping -c 1 archlinux.org &> /dev/null; then
        echo "Internet connected."
        break
    else
        echo -e "${RED}No internet.${NC} 1) iwctl  2) Retry  3) Abort"
        read -p "Choice: " N
        case $N in 1) iwctl ;; 2) sleep 2 ;; 3) exit 1 ;; esac
    fi
done

# ==============================================================================
# 2. Disk & User Config
# ==============================================================================
echo -e "${GREEN}[2/10] Configuration${NC}"
lsblk -d -p -n -o NAME,SIZE,MODEL
echo ""
read -p "Target Disk (e.g., /dev/nvme0n1 or /dev/sda): " DISK
[ ! -b "$DISK" ] && echo "Invalid disk" && exit 1

echo -e "${RED}WARNING: $DISK will be WIPED.${NC}"
read -p "Confirm (y/N): " C
[[ "$C" == "y" ]] || exit 1

read -p "Hostname: " NEW_HOSTNAME
read -p "Username: " NEW_USER
echo "Password (Root/User/Encryption):"
read -s PASSWORD
echo ""

# ==============================================================================
# 3. Partitioning & Encryption
# ==============================================================================
echo -e "${GREEN}[3/10] Wiping & Partitioning${NC}"
wipefs -a "$DISK"
sgdisk -Z "$DISK"
# 1: EFI (512M), 2: Boot (1G), 3: LUKS (Rest)
sgdisk -n 1:0:+512M -t 1:ef00 "$DISK"
sgdisk -n 2:0:+1G -t 2:8300 "$DISK"
sgdisk -n 3:0:0 -t 3:8e00 "$DISK"

# Handle NVMe vs SATA naming
if [[ "$DISK" == *"nvme"* ]]; then 
    P1="${DISK}p1"; P2="${DISK}p2"; P3="${DISK}p3"
else 
    P1="${DISK}1"; P2="${DISK}2"; P3="${DISK}3"
fi

echo "Encrypting drive..."
echo -n "$PASSWORD" | cryptsetup -q luksFormat "$P3"
echo -n "$PASSWORD" | cryptsetup open "$P3" cryptlvm -

# LVM & Formatting
pvcreate /dev/mapper/cryptlvm
vgcreate ArchVG /dev/mapper/cryptlvm
lvcreate -L 8G -n swap ArchVG
lvcreate -l 100%FREE -n root ArchVG

mkfs.fat -F32 "$P1"
mkfs.ext4 "$P2"
mkswap /dev/ArchVG/swap
mkfs.btrfs /dev/ArchVG/root

# ==============================================================================
# 4. Mounting (Btrfs Subvolumes)
# ==============================================================================
echo -e "${GREEN}[4/10] Subvolumes & Mounting${NC}"
mount /dev/ArchVG/root /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@snapshots
umount /mnt

MOUNT_OPTS="noatime,compress=zstd,space_cache=v2"
mount -o $MOUNT_OPTS,subvol=@ /dev/ArchVG/root /mnt
mkdir -p /mnt/{boot,efi,home,var,.snapshots}
mount -o $MOUNT_OPTS,subvol=@home /dev/ArchVG/root /mnt/home
mount -o $MOUNT_OPTS,subvol=@var /dev/ArchVG/root /mnt/var
mount -o $MOUNT_OPTS,subvol=@snapshots /dev/ArchVG/root /mnt/.snapshots
mount "$P2" /mnt/boot
mount "$P1" /mnt/efi
swapon /dev/ArchVG/swap

# ==============================================================================
# 5. Hardware Detection
# ==============================================================================
echo -e "${GREEN}[5/10] Detecting Hardware${NC}"
UCODE=""
grep -q "Intel" /proc/cpuinfo && UCODE="intel-ucode"
grep -q "AMD" /proc/cpuinfo && UCODE="amd-ucode"

GPU_DRIVER="mesa"
IS_NVIDIA=false

if lspci | grep -i "NVIDIA"; then
    echo "  -> Nvidia detected"
    GPU_DRIVER="$GPU_DRIVER nvidia nvidia-utils nvidia-settings"
    IS_NVIDIA=true
elif lspci | grep -i "AMD" | grep -i "VGA"; then
    echo "  -> AMD detected"
    GPU_DRIVER="$GPU_DRIVER vulkan-radeon xf86-video-amdgpu"
elif lspci | grep -i "Intel" | grep -i "VGA"; then
    echo "  -> Intel detected"
    GPU_DRIVER="$GPU_DRIVER vulkan-intel intel-media-driver"
fi

# ==============================================================================
# 6. Install Base System
# ==============================================================================
echo -e "${GREEN}[6/10] Installing Packages...${NC}"
pacstrap /mnt base linux linux-headers linux-firmware lvm2 btrfs-progs neovim networkmanager grub efibootmgr git base-devel $UCODE $GPU_DRIVER

genfstab -U /mnt >> /mnt/etc/fstab

# ==============================================================================
# 7. System Config (Chroot)
# ==============================================================================
echo -e "${GREEN}[7/10] System Configuration${NC}"

cat <<EOF > /mnt/setup_internal.sh
#!/bin/bash

ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
echo "$NEW_HOSTNAME" > /etc/hostname
echo "KEYMAP=$KEYMAP" > /etc/vconsole.conf
echo "127.0.0.1 localhost $NEW_HOSTNAME" >> /etc/hosts

echo "root:$PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash "$NEW_USER"
echo "$NEW_USER:$PASSWORD" | chpasswd
echo "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel_auth

sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems resume fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# GRUB Setup
LUKS_UUID=\$(blkid -s UUID -o value $P3)
GRUB_PARAMS="loglevel=3 quiet cryptdevice=UUID=\${LUKS_UUID}:cryptlvm root=/dev/mapper/ArchVG-root resume=/dev/mapper/ArchVG-swap"
[ "$IS_NVIDIA" = true ] && GRUB_PARAMS="\$GRUB_PARAMS nvidia_drm.modeset=1"

sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"\${GRUB_PARAMS}\"|" /etc/default/grub

echo "Installing Bootloader..."
# Standard installation to NVRAM
# This relies on efibootmgr working correctly (requires booted in UEFI mode)
grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB

grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager
EOF

chmod +x /mnt/setup_internal.sh
arch-chroot /mnt ./setup_internal.sh
rm /mnt/setup_internal.sh

# ==============================================================================
# 8. GUI & Essentials
# ==============================================================================
echo -e "${GREEN}[8/10] Installing Hyprland & Essentials${NC}"

cat <<EOF > /mnt/setup_gui.sh
#!/bin/bash
pacman -S --noconfirm pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol bluez bluez-utils
pacman -S --noconfirm hyprland xdg-desktop-portal-hyprland wofi dunst wl-clipboard polkit-kde-agent kitty thunar gvfs
pacman -S --noconfirm ttf-jetbrains-mono-nerd-font noto-fonts noto-fonts-emoji
pacman -S --noconfirm snapper snap-pac

umount /.snapshots
rmdir /.snapshots
snapper -c root create-config /
mount -a
chmod a+rx /.snapshots
chown :wheel /.snapshots

systemctl enable sddm
systemctl enable bluetooth
EOF

chmod +x /mnt/setup_gui.sh
arch-chroot /mnt ./setup_gui.sh
rm /mnt/setup_gui.sh

# ==============================================================================
# 9. Reboot
# ==============================================================================
echo -e "${GREEN}[9/10] Installation Finished!${NC}"
umount -R /mnt

echo -e "${GREEN}Rebooting in 5 seconds...${NC}"
echo -e "Be ready to remove the USB stick when the screen goes black."
sleep 5
reboot
