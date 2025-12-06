#!/bin/bash

###############################
# Custom Arch Linux Installer #
###############################

# Colors
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Stop on errors immediately
set -e

echo -e "${BLUE}Starting Arch Installer...${NC}"

###################
# 1. Keymap Setup #
###################

echo -e "${BLUE}[1/11] Setting Up Keyboard Layout...${NC}"

read -p "Enter keymap (e.g.: us, de, fr...): " KEYMAP_INPUT
KEYMAP=${KEYMAP_INPUT:-us}
loadkeys "$KEYMAP" || loadkeys us

echo -e "${GREEN}Keyboard Setup Finished!${NC}"

####################
# 2. Network Setup #
####################

echo -e "${BLUE}[2/11] Setting Up Network Connection...${NC}"

echo -e "${YELLOW}Checking Network...${NC}"
for i in {1..5}; do
  if ping -c 1 archlinux.org &> /dev/null; then
    echo -e "${GREEN}Internet Connected!${NC}"
    break
  else
    echo -e "${YELLOW}Waiting for internet...${NC}"
    sleep 2
  fi
done

if ! ping -c 1 archlinux.org &> /dev/null; then
  echo -e "${RED}No Internet Connection!${NC}\n${YELLOW}(Run 'iwctl' then restart script)${NC}"
  exit 1
fi

echo -e "${GREEN}Network Setup Finished!${NC}"

#################################
# 3. Environment Configuration  #
#################################

echo -e "${BLUE}[3/11] Configurating Installation...${NC}"
echo -e "${YELLOW}Please Input Choices${NC}\n"

# Disk selection for instalation
echo -e "${BLUE}Installation Disk${NC}"
lsblk -d -p -n -o NAME,SIZE,MODEL
read -p "\nTarget Disk (e.g.: /dev/nvme0n1 or /dev/sda): " DISK
if [ ! -b "$DISK" ]; then
  echo -e "${RED}Invalid Disk${NC}\n${YELLOW}(Restart script and input a valid disk)${NC}"
  exit 1
fi

echo -e "${RED}WARNING: $DISK Will Be Wiped!${NC}"
echo -ne "${YELLOW}Confirm? (WIPE DISK): ${NC}"
read CONF_WIPE
[[ "$CONF_WIPE" == "WIPE DISK" ]] || exit 1

# Size selection for partitions
echo -e "${BLUE}Partition Sizes${NC}"

read -p "EFI Partition Size [Default: 512M]: " EFI_INPUT
EFI_SIZE=${EFI_INPUT:-512M}

read -p "BOOT Partition Size [Default: 2G]: " BOOT_INPUT
BOOT_SIZE=${BOOT_INPUT:-2G}

read -p "SWAP Partition Size [Default: 10G]: " SWAP_INPUT
SWAP_SIZE=${SWAP_INPUT:-10G}

echo -e "${RED}Using: EFI=${EFI_SIZE}, BOOT=${BOOT_SIZE}, SWAP=${SWAP_SIZE}, ROOT=Remaining${NC}"

echo -ne "${YELLOW}Confirm? (YES): ${NC}"
read CONF_SIZE
[[ "$CONF_SIZE" == "YES" ]] || exit 1

# Environment selection (hostname, username, password)
echo -e "${BLUE}System Environment${NC}"

read -p "Hostname: " NEW_HOSTNAME
read -p "Username: " NEW_USER

# Password verification loop
while true; do
  echo -e "${BLUE}Set System Password${NC}\n${YELLOW}(Root / User / Encryption)${NC}"
  read -s -p "Enter Password: " PASSWORD
  echo -e ""
  read -s -p "Confirm Password: " PASSWORD_CONFIRM
  echo -e ""

  if [ -z "$PASSWORD" ]; then
    echo -e "${RED}Password cannot be empty!${NC}"
  elif [ "$PASSWORD" == "$PASSWORD_CONFIRM" ]; then
    echo -e "${GREEN}Passwords Match!${NC}"

	echo -ne "${RED}Show Password? (YES): ${NC}"
    read SHOW_PASS
    if [[ "$SHOW_PASS" == "YES" ]]; then
      echo -e "${BLUE}${PASSWORD}${NC}"
    fi

	echo -ne "${YELLOW}Confirm? (YES): ${NC}"
    read CONF_PASS
    if [[ "$CONF_PASS" == "YES" ]]; then
      break
    fi
  else
    echo -e "${RED}Passwords do not match!${NC}\n${YELLOW}(Please try again)${NC}"
  fi
done

echo -e "${GREEN}Configuration Finished!${NC}"

########################################
# 4. Partition Formatting & Encryption #
########################################

echo -e "${BLUE}[4/] Creating & Encrypting Partitions...${NC}"

echo -e "${YELLOW}Wiping Disk...${NC}"
wipefs -a "$DISK"
sgdisk -Z "$DISK"

# Use variable for sizes
sgdisk -n 1:0:+${EFI_SIZE} -t 1:ef00 "$DISK"
sgdisk -n 2:0:+${BOOT_SIZE} -t 2:8300 "$DISK"
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

# Use variable for swap size
lvcreate -L ${SWAP_SIZE} -n swap ArchVG
lvcreate -l 100%FREE -n root ArchVG

echo -e "${YELLOW}Formatting Partitions...${NC}"
mkfs.fat -F32 "$P1"
mkfs.ext4 "$P2"
mkswap /dev/ArchVG/swap
mkfs.btrfs /dev/ArchVG/root

echo -e "${GREEN}Partition Creation Finished!${NC}"

#######################
# 5. Btrfs Subvolumes #
#######################

echo -e "${BLUE}[5/11] Creating Btrfs Subvolumes...${NC}"

mount /dev/ArchVG/root /mnt
btrfs subvolume create /mnt/@
btrfs subvolume create /mnt/@home
btrfs subvolume create /mnt/@var
btrfs subvolume create /mnt/@snapshots
umount /mnt

echo -e "${GREEN}Subvolumes Creation Finished!${NC}"

###############
# 6. Mounting #
###############

echo -e "${BLUE}[6/11] Mounting Partitions & Subvolumes...${NC}"

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

##########################
# 7. Install Base System #
##########################

echo -e "${BLUE}[7/11] Installing Base System...${NC}"

DRIVERS="mesa mesa-utils intel-ucode vulkan-intel libva-intel-driver vulkan-radeon xf86-video-amdgpu"

pacstrap /mnt base linux linux-headers linux-firmware lvm2 btrfs-progs neovim networkmanager grub efibootmgr git base-devel archlinux-keyring go $DRIVERS

genfstab -U /mnt >> /mnt/etc/fstab

echo -e "${GREEN}Base System Installation Finished!${NC}"

###########################
# 8. System Configuration #
###########################

echo -e "${BLUE}[8/11] Configurating System...${NC}"

cat <<EOF > /mnt/setup_internal.sh
#!/bin/bash
set -e
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
echo -e "en_US.UTF-8" > /etc/locale.gen
locale-gen
echo -e "LANG=en_US.UTF-8" > /etc/locale.conf
echo -e "$NEW_HOSTNAME" > /etc/hostname
echo -e "KEYMAP=$KEYMAP" > /etc/vconsole.conf
echo -e "127.0.0.1 localhost $NEW_HOSTNAME" >> /etc/hosts

echo -e "root:$PASSWORD" | chpasswd
useradd -m -G wheel -s /bin/bash "$NEW_USER"
echo -e "$NEW_USER:$PASSWORD" | chpasswd
echo -e "%wheel ALL=(ALL:ALL) NOPASSWD: ALL" > /etc/sudoers.d/wheel_auth

sed -i 's/^HOOKS=.*/HOOKS=(base udev autodetect modconf kms keyboard keymap consolefont block encrypt lvm2 filesystems resume fsck)/' /etc/mkinitcpio.conf
mkinitcpio -P

# Grub configuration for AMD HD 8730M GPU
LUKS_UUID=\$(blkid -s UUID -o value $P3)

# 1. Encryption & LVM
GRUB_PARAMS="loglevel=3 quiet cryptdevice=UUID=\${LUKS_UUID}:cryptlvm root=/dev/mapper/ArchVG-root resume=/dev/mapper/ArchVG-swap"

# 2. Force GCN 1.0 (Southern Islands) to use 'amdgpu' driver
GRUB_PARAMS="\$GRUB_PARAMS radeon.si_support=0 amdgpu.si_support=1"

# End of GPU specific grub configuration
sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=,*|GRUB_CMDLINE_LINUX_DEFAULT=\"\${GRUB_PARAMS}\"|" /etc/default/grub

grub-install --target=x86_64-efi --efi-directory=/efi --bootloader-id=GRUB
grub-mkconfig -o /boot/grub/grub.cfg

systemctl enable NetworkManager

# Set environment variables
echo -e "XDG_SESSION_TYPE=wayland" >> /etc/environment
echo -e "XDG_CURRENT_DESKTOP=Hyprland" >> /etc/environment
echo -e "XDG_SESSION_DESKTOP=Hyprland" >> /etc/environment
EOF

chmod +x /mnt/setup_internal.sh
arch-chroot /mnt ./setup_internal.sh
rm /mnt/setup_internal.sh

echo -e "${GREEN}Finished Configurating System!${NC}"

#####################################
# 9. AUR & Custom Apps Installation #
#####################################

echo -e "${BLUE}[9/11] Installing AUR Helper & Custom Apps...${NC}"

cat <<EOF > /mnt/setup_aur.sh
#!/bin/bash
set -e

export FAKEROOTDONTTRYSYSV=1

cd /tmp
git clone https://aur.archlinux.org/yay.git
cd yay
makepkg -si --noconfirm

yay -S --noconfirm walker quickshell-git qt6-wayland
EOF

chmod +x /mnt/setup_aur.sh
arch-chroot /mnt su - "$NEW_USER" -c "/setup_aur.sh"
rm /mnt/setup_aur.sh

echo -e "${GREEN}Finished Installing AUR & Custom Apps!${NC}"

#############################
# 10. Hyprland & Essentials #
#############################

echo -e "${BLUE}[10/11] Installing Hyprland & Essentials...${NC}"

cat <<EOF > /mnt/setup_gui.sh
#!/bin/bash
set -e

# Update archlinux-keyring
pacman -Sy --noconfirm archlinux-keyring

# Install sound utilities
pacman -S --noconfirm pipewire pipewire-pulse pipewire-alsa wireplumber pavucontrol

# Install bluetooth utilities
pacman -S --noconfirm bluez bluez-utils

# Install hyprland & essentials
pacman -S --noconfirm hyprland xdg-desktop-portal-hyprland hyprpaper hypridle hyprlock tlp tlp-rdw brightnessctl dunst wl-clipboard polkit-kde-agent kitty thunar gvfs xdg-user-dirs greetd firefox

# Install fonts
pacman -S --noconfirm ttf-jetbrains-mono-nerd noto-fonts noto-fonts-emoji

# Install auto snapshot utilities
pacman -S --noconfirm snapper snap-pac

systemctl enable tlp

umount /.snapshots || true
rm -rf /.snapshots || true
snapper --no-dbus -c root create-config /
btrfs subvolume delete /.snapshots
mkdir /.snapshots
mount -a
chmod 750 /.snapshots
chown :wheel /.snapshots

# Setup hyprland configuration
mkdir -p /home/$NEW_USER/.config/hypr

cat <<CONF > /home/$NEW_USER/.config/hypr/hyprland.conf
monitor=,preferred,auto,1

input {
  kb_layout = $KEYMAP
  follow_mouse = 1
}

general {
  gaps_in = 3
  gaps_out = 5
  border_size = 2
  col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg
  col.inactive_border = rgba(595959aa)
  layout = dwindle
}

decoration {
  rounding = 5
}

animations {
  enabled = yes
}

misc {
  disable_hyprland_logo = true
  disable_splash_rendering = true
  vfr = true
}

\\\$mainMod = SUPER

bindel = ,XF86AudioRaiseVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+
bindel = ,XF86AudioLowerVolume, exec, wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-
bindl = ,XF86AudioMute, exec, wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
bindel = ,XF86MonBrightnessUp, exec, brightnessctl s 5%+
bindel = ,XF86MonBrightnessDown, exec, brightnessctl s 5%-

bind = \\\$mainMod, Return, exec, kitty
bind = \\\$mainMod, W, killactive,
bind = \\\$mainMod, F, exec, thunar
bind = \\\$mainMod, T, togglefloating,
bind = \\\$mainMod, Y, togglesplit,
bind = \\\$mainMod, Space, exec, walker
bind = \\\$mainMod, L, exec, hyprlock

bind = \\\$mainMod, B, exec, firefox
bind = \\\$mainMod, A, exec, firefox --kiosk "https://gemini.google.com" --class gemini-app
windowrulev2 = float, class:^(gemini-app)$

exec-once = quickshell
exec-once = hypridle
exec-once = /usr/lib/polkit-kde-authentication-agent-1

bind = \\\$mainMod, left, movefocus, l
bind = \\\$mainMod, right, movefocus, r
bind = \\\$mainMod, up, movefocus, u
bind = \\\$mainMod, down, movefocus, d
bind = \\\$mainMod, 1, workspace, 1
bind = \\\$mainMod, 2, workspace, 2
bind = \\\$mainMod, 3, workspace, 3
bind = \\\$mainMod, 4, workspace, 4
bind = \\\$mainMod, 5, workspace, 5
bindm = \\\$mainMod, mouse:272, movewindow
bindm = \\\$mainMod, mouse:273, resizewindow
CONF

mkdir -p /home/$NEW_USER/Pictures/Wallpapers
curl -L -o /home/$NEW_USER/Pictures/Wallpapers/wallpaper.jpg https://raw.githubusercontent.com/subz3r0beatz/arch-iso/main/Wallpaper.jpg

cat <<PAPER > /home/$NEW_USER/.config/hypr/hyprpaper.conf
preload = /home/$NEW_USER/Pictures/Wallpapers/wallpaper.jpg
wallpaper = ,/home/$NEW_USER/Pictures/Wallpapers/wallpaper.jpg
splash = false
PAPER

cat <<IDLE > /home/$NEW_USER/.config/hypr/hypridle.conf
general {
  lock_cmd = pidof hyprlock || hyprlock
  before_sleep_cmd = loginctl lock-session
  after_sleep_cmd = hyprctl dispatch dpms on
}
listener {
  timeout = 300
  on-timeout = loginctl lock-session
}
listener {
  timeout = 600
  on-timeout = systemctl suspend
}
IDLE

cat <<LOCK > /home/$NEW_USER/.config/hypr/hyprlock.conf
background {
  monitor =
  color = rgba(25, 20, 20, 1.0)
}
input-field {
  monitor =
  size = 200, 50
  outline_thickness = 3
  dots_size = 0.33
  dots_spacing = 0.15
  dots_center = true
  outer_color = rgb(151515)
  inner_color = rgb(200, 200, 200)
  font_color = rgb(10, 10, 10)
  fade_on_empty = true
  placeholder_text = <i>Input Password...</i>
  hide_input = false
  position = 0, -20
  halign = center
  valign = center
}
label {
  monitor =
  text = \\\$TIME
  color = rgba(200, 200, 200, 1.0)
  font_size = 64
  font_family = Noto Sans
  position = 0, 80
  halign = center
  valign = center
}
LOCK

chown -R $NEW_USER:wheel /home/$NEW_USER/.config

su - "$NEW_USER" -c "xdg-user-dirs-update"

mkdir -p /etc/greetd
cat <<TOML > /etc/greetd/config.toml
[terminal]
vt = 1
[default_session]
command = "agreety --cmd Hyprland"
user = "greeter"
TOML

systemctl enable greetd
systemctl enable bluetooth

echo -e "%wheel ALL=(ALL:ALL) ALL" > /etc/sudoers.d/wheel_auth
EOF

chmod +x /mnt/setup_gui.sh
arch-chroot /mnt ./setup_gui.sh
rm /mnt/setup_gui.sh

echo -e "${GREEN}Finished Installing Hyprland & Essentials!${NC}"

##############
# 11. Reboot #
##############

echo -e "${GREEN}[11/11] Installation Finished!${NC}"

umount -R /mnt

echo -e "${RED}Rebooting in 5 seconds...${NC}"
sleep 5
reboot

