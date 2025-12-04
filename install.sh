#!/bin/bash

# ==============================================================================
#  Custom Arch Linux Installer - Hardware Edition
#  Features: No Wrapper Script. Writes Nvidia config to /etc/environment.
# ==============================================================================

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Stop on errors immediately
set -e

echo -e "${BLUE}Starting Arch Installer (Clean Hardware Edition)...${NC}"

# ==============================================================================
# 1. Keymap & Network
# ==============================================================================
echo -e "${GREEN}[1/9] Setup Environment${NC}"

set +e # Temporarily allow errors for user input
read -p "Enter keymap (e.g., us, de, fr): " KEYMAP_INPUT
set -e
KEYMAP=${KEYMAP_INPUT:-us}
loadkeys "$KEYMAP" || loadkeys us

echo "Checking network..."
for i in {1..5}; do
    if ping -c 1 archlinux.org &> /dev/null; then
        echo "Internet connected."
        break
    else
        echo "Waiting for internet..."
        sleep 2
    fi
done

if ! ping -c 1 archlinux.org &> /dev/null; then
    echo -e "${RED}No internet connection. Run 'iwctl' then restart script.${NC}"
    exit 1
fi

# ==============================================================================
# 2. Disk, Partitions & User Config
# ==============================================================================
echo -e "${GREEN}[2/9] Configuration${NC}"
lsblk -d -p -n -o NAME,SIZE,MODEL
echo ""
read -p "Target Disk (e.g., /dev/nvme0n1 or /dev/sda): " DISK
if [ ! -b "$DISK" ]; then 
    echo "Invalid disk" 
    exit 1
fi

echo -e "${RED}WARNING: $DISK will be WIPED.${NC}"
read -p "Confirm (y/N): " C
[[ "$C" == "y" ]] || exit 1

# --- PARTITION SIZE PROMPTS ---
echo -e "${BLUE}Partition Sizing (Press Enter for defaults)${NC}"
read -p "EFI Partition Size [512M]: " EFI_INPUT
EFI_SIZE=${EFI_INPUT:-512M}
read -p "Boot Partition Size [1G]: " BOOT_INPUT
BOOT_SIZE=${BOOT_INPUT:-1G}
read -p "Swap Size [8G]: " SWAP_INPUT
SWAP_SIZE=${SWAP_INPUT:-8G}
echo ""
# ------------------------------

read -p "Hostname: " NEW_HOSTNAME
read -p "Username: " NEW_USER

# Password Verification Loop
while true; do
    echo -e "${BLUE}Set System Password (Root / User / Encryption)${NC}"
    read -s -p "Enter Password: " PASSWORD
    echo ""
    read -s -p "Confirm Password: " PASSWORD_CONFIRM
    echo ""

    if [ -z "$PASSWORD" ]; then
        echo -e "${RED}Password cannot be empty.${NC}"
    elif [ "$PASSWORD" == "$PASSWORD_CONFIRM" ]; then
        echo -e "${GREEN}Passwords match.${NC}"
        break
    else
        echo -e "${RED}Passwords do not match. Please try again.${NC}"
    fi
done

# ==============================================================================
# 3. Partitioning & Encryption
# ==============================================================================
echo -e "${GREEN}[3/9] Wiping & Partitioning${NC}"
wipefs -a "$DISK"
sgdisk -Z "$DISK"

sgdisk -n 1:0:+${EFI_SIZE} -t 1:ef00 "$DISK"
sgdisk -n 2:0:+${BOOT_SIZE} -t 2:8300 "$DISK"
sgdisk -n 3:0:0 -t 3:8e00 "$DISK"

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
lvcreate -L ${SWAP_SIZE} -n swap ArchVG
lvcreate -l 100%FREE -n root ArchVG

mkfs.fat -F32 "$P1"
mkfs.ext4 "$P2"
mkswap /dev/ArchVG/swap
mkfs.btrfs /dev/ArchVG/root

# ==============================================================================
# 4. Mounting (Btrfs Subvolumes)
# ==============================================================================
echo -e "${GREEN}[4/9] Subvolumes & Mounting${NC}"
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
# 5. Hardware Detection (GPU Only)
# ==============================================================================
echo -e "${GREEN}[5/9] Detecting Hardware${NC}"
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
echo -e "${GREEN}[6/9] Installing Packages...${NC}"
# Removed pciutils as we don't need lspci in the final system anymore for wrappers
pacstrap /mnt base linux linux-headers linux-firmware lvm2 btrfs-progs neovim networkmanager grub efibootmgr git base-devel archlinux-keyring $UCODE $GPU_DRIVER

genfstab -U /mnt >> /mnt/etc/fstab

# ==============================================================================
# 7. System Config
# ==============================================================================
echo -e "${GREEN}[7/9] System Configuration${NC}"

cat <<EOF > /mnt/setup_internal.sh
#!/bin/bash
set -e

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

LUKS_UUID=\$(blkid -s UUID -o value $P3)
GRUB_PARAMS="loglevel=3 quiet cryptdevice=UUID=\${LUKS_UUID}:cryptlvm root=/dev/mapper/ArchVG-root resume=/dev/mapper/ArchVG-swap"

# Add Kernel Parameter for Nvidia
if [ "$IS_NVIDIA" = true ]; then
    GRUB_PARAMS="\$GRUB_PARAMS nvidia_drm.modeset=1"
fi

sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"\${GRUB_PARAMS}\"|" /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager

# --- SET VARIABLES GLOBALLY (No Wrapper needed) ---
# If Nvidia is detected, write these to /etc/environment
if [ "$IS_NVIDIA" = true ]; then
    echo "Setting up Nvidia Environment variables..."
    echo "LIBVA_DRIVER_NAME=nvidia" >> /etc/environment
    echo "XDG_SESSION_TYPE=wayland" >> /etc/environment
    echo "GBM_BACKEND=nvidia-drm" >> /etc/environment
    echo "__GLX_VENDOR_LIBRARY_NAME=nvidia" >> /etc/environment
fi
EOF

chmod +x /mnt/setup_internal.sh
arch-chroot /mnt ./setup_internal.sh
rm /mnt/setup_internal.sh

# ==============================================================================
# 8. GUI, Essentials & Config
# ==============================================================================
echo -e "${GREEN}[8/9] Installing Hyprland & Essentials${NC}"

cat <<EOF > /mnt/setup_gui.sh
#!/bin/bash
set -e

pacman -Sy --noconfirm archlinux-keyring
pacman -S --noconfirm pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol bluez bluez-utils
pacman -S --noconfirm hyprland xdg-desktop-portal-hyprland wofi dunst wl-clipboard polkit-kde-agent kitty thunar gvfs greetd mesa mesa-utils qt5-wayland qt6-wayland
pacman -S --noconfirm ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji
pacman -S --noconfirm snapper snap-pac

umount /.snapshots || true
rmdir /.snapshots || true
snapper --no-dbus -c root create-config /
mount -a
chmod a+rx /.snapshots
chown :wheel /.snapshots

# --- Generate Hyprland Config ---
echo "Creating configuration for $NEW_USER..."
mkdir -p /home/$NEW_USER/.config/hypr

cat <<CONF > /home/$NEW_USER/.config/hypr/hyprland.conf
monitor=,preferred,auto,1
input {
    kb_layout = $KEYMAP
    follow_mouse = 1
}
general {
    gaps_in = 5
    gaps_out = 10
    border_size = 2
    col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
    col.inactive_border = rgba(595959aa)
    layout = dwindle
}
decoration {
    rounding = 5
    blur {
        enabled = true
        size = 3
        passes = 1
    }
    drop_shadow = true
}
animations {
    enabled = yes
    bezier = myBezier, 0.05, 0.9, 0.1, 1.05
    animation = windows, 1, 5, myBezier
    animation = windowsOut, 1, 5, default, popin 80%
    animation = border, 1, 10, default
    animation = fade, 1, 5, default
    animation = workspaces, 1, 5, default
}
dwindle {
    pseudotile = yes
    preserve_split = yes
}
misc {
    disable_hyprland_logo = true
}
\$mainMod = SUPER
bind = \$mainMod, Q, exec, kitty
bind = \$mainMod, C, killactive,
bind = \$mainMod, M, exit,
bind = \$mainMod, E, exec, thunar
bind = \$mainMod, V, togglefloating,
bind = \$mainMod, R, exec, wofi --show drun
bind = \$mainMod, P, pseudo,
bind = \$mainMod, J, togglesplit,
bind = \$mainMod, left, movefocus, l
bind = \$mainMod, right, movefocus, r
bind = \$mainMod, up, movefocus, u
bind = \$mainMod, down, movefocus, d
bind = \$mainMod, 1, workspace, 1
bind = \$mainMod, 2, workspace, 2
bind = \$mainMod, 3, workspace, 3
bind = \$mainMod, 4, workspace, 4
bindm = \$mainMod, mouse:272, movewindow
bindm = \$mainMod, mouse:273, resizewindow
CONF

chown -R $NEW_USER:wheel /home/$NEW_USER/.config

mkdir -p /etc/greetd
cat <<TOML > /etc/greetd/config.toml
[terminal]
vt = 1
[default_session]
# No wrapper needed. We just launch Hyprland.
# Environment variables are already loaded from /etc/environment
command = "agreety --cmd Hyprland"
user = "greeter"
TOML

systemctl enable greetd
systemctl enable bluetooth
EOF

chmod +x /mnt/setup_gui.sh
arch-chroot /mnt ./setup_gui.sh
rm /mnt/setup_gui.sh

# ==============================================================================
# 9. Reboot
# ==============================================================================
echo -e "${GREEN}[9/9] Installation Finished!${NC}"
umount -R /mnt

echo -e "${GREEN}Rebooting in 5 seconds...${NC}"
echo -e "Remove the installation media when screen goes black."
sleep 5
reboot
