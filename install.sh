#!/bin/bash

# ==============================================================================
#  Custom Arch Linux Installer - Pure Wayland (VM Loop Fix)
#  Fixes: Uses LIBGL_ALWAYS_SOFTWARE, sets XDG vars, and uses dbus-launch
# ==============================================================================

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Stop on errors immediately
set -e

echo -e "${BLUE}Starting Arch Installer (VM Loop Fix)...${NC}"

# ==============================================================================
# 1. Keymap & Network
# ==============================================================================
echo -e "${GREEN}[1/10] Setup Environment${NC}"

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
# 2. Disk & User Config
# ==============================================================================
echo -e "${GREEN}[2/10] Configuration${NC}"
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
echo -e "${GREEN}[3/10] Wiping & Partitioning${NC}"
wipefs -a "$DISK"
sgdisk -Z "$DISK"
# 1: EFI (512M), 2: Boot (1G), 3: LUKS (Rest)
sgdisk -n 1:0:+512M -t 1:ef00 "$DISK"
sgdisk -n 2:0:+1G -t 2:8300 "$DISK"
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
# 5. Hardware Detection (Standard Drivers)
# ==============================================================================
echo -e "${GREEN}[5/10] Detecting Hardware${NC}"
UCODE=""
grep -q "Intel" /proc/cpuinfo && UCODE="intel-ucode"
grep -q "AMD" /proc/cpuinfo && UCODE="amd-ucode"

GPU_DRIVER="mesa"
if lspci | grep -i "NVIDIA"; then
    echo "  -> Nvidia detected"
    GPU_DRIVER="$GPU_DRIVER nvidia nvidia-utils nvidia-settings"
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
# pciutils is needed for the wrapper script to detect VM/Nvidia
pacstrap /mnt base linux linux-headers linux-firmware lvm2 btrfs-progs neovim networkmanager grub efibootmgr git base-devel archlinux-keyring pciutils $UCODE $GPU_DRIVER

genfstab -U /mnt >> /mnt/etc/fstab

# ==============================================================================
# 7. Generate Wrapper Script (Full Session Setup)
# ==============================================================================
echo -e "${GREEN}[7/10] Creating Startup Wrapper${NC}"

# We write this DIRECTLY to /mnt so it definitely exists
mkdir -p /mnt/usr/local/bin

cat <<'WRAPPER' > /mnt/usr/local/bin/hypr-run
#!/bin/bash
# Log file unique to the user running it
LOG="/tmp/hypr-run-${USER}.log"
echo "--- Starting Wrapper at $(date) ---" > "$LOG"

# Set standard Wayland session variables (Prevents immediate exit)
export XDG_SESSION_TYPE=wayland
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_DESKTOP=Hyprland

# 1. VirtualBox / VM Detection
if lspci | grep -i "VirtualBox" >> "$LOG" 2>&1 || lspci | grep -i "VMware" >> "$LOG" 2>&1; then
    echo "  -> VM Detected. Forcing software rendering." >> "$LOG"
    
    # Fix invisible cursor
    export WLR_NO_HARDWARE_CURSORS=1
    
    # Force Software Rendering (The heavy hammer for VirtualBox)
    export LIBGL_ALWAYS_SOFTWARE=1
    export WLR_RENDERER_ALLOW_SOFTWARE=1
    
    # NOTE: We removed 'pixman' as it causes issues on newer Hyprland
fi

# 2. Nvidia Detection
if lspci | grep -i "NVIDIA" >> "$LOG" 2>&1; then
    echo "  -> Nvidia Detected. Exporting variables." >> "$LOG"
    export LIBVA_DRIVER_NAME=nvidia
    export GBM_BACKEND=nvidia-drm
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
fi

# 3. Launch Hyprland
# Using dbus-launch prevents session crashes
echo "  -> Launching Hyprland with dbus-launch..." >> "$LOG"
exec dbus-launch --exit-with-session Hyprland >> "$LOG" 2>&1
WRAPPER

# Make it executable immediately
chmod +x /mnt/usr/local/bin/hypr-run

# ==============================================================================
# 8. System Config (Chroot)
# ==============================================================================
echo -e "${GREEN}[8/10] System Configuration${NC}"

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

# GRUB Setup
LUKS_UUID=\$(blkid -s UUID -o value $P3)
GRUB_PARAMS="loglevel=3 quiet cryptdevice=UUID=\${LUKS_UUID}:cryptlvm root=/dev/mapper/ArchVG-root resume=/dev/mapper/ArchVG-swap"
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"\${GRUB_PARAMS}\"|" /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager
EOF

chmod +x /mnt/setup_internal.sh
arch-chroot /mnt ./setup_internal.sh
rm /mnt/setup_internal.sh

# ==============================================================================
# 9. GUI & Essentials
# ==============================================================================
echo -e "${GREEN}[9/10] Installing Hyprland & Essentials${NC}"

cat <<EOF > /mnt/setup_gui.sh
#!/bin/bash
set -e

echo "Refreshing keys..."
pacman -Sy --noconfirm archlinux-keyring

echo "Installing Audio..."
pacman -S --noconfirm pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol bluez bluez-utils

echo "Installing Desktop..."
# ADDED: qt5-wayland/qt6-wayland (Helps prevent random app crashes on start)
pacman -S --noconfirm hyprland xdg-desktop-portal-hyprland wofi dunst wl-clipboard polkit-kde-agent kitty thunar gvfs greetd vulkan-swrast mesa mesa-utils qt5-wayland qt6-wayland

echo "Installing Fonts..."
pacman -S --noconfirm ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji

echo "Installing Snapper..."
pacman -S --noconfirm snapper snap-pac

# Snapper Config
umount /.snapshots || true
rmdir /.snapshots || true
snapper --no-dbus -c root create-config /
mount -a
chmod a+rx /.snapshots
chown :wheel /.snapshots

echo "Configuring Greetd..."
mkdir -p /etc/greetd
cat <<TOML > /etc/greetd/config.toml
[terminal]
vt = 1

[default_session]
# Pointing to the wrapper we created in Step 7
command = "agreety --cmd /usr/local/bin/hypr-run"
user = "greeter"
TOML

echo "Enabling Services..."
systemctl enable greetd
systemctl enable bluetooth
EOF

chmod +x /mnt/setup_gui.sh
arch-chroot /mnt ./setup_gui.sh
rm /mnt/setup_gui.sh

# ==============================================================================
# 10. Reboot
# ==============================================================================
echo -e "${GREEN}[10/10] Installation Finished!${NC}"
umount -R /mnt

echo -e "${GREEN}Rebooting in 5 seconds...${NC}"
echo -e "Remove the installation media when screen goes black."
sleep 5
reboot
