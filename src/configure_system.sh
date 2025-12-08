#!/bin/bash

###############################
# System Configuration Script #
###############################

set -e

echo -e "${BLUE}[7/10] Configurating System...${NC}"

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
{
    echo -e "XDG_SESSION_TYPE=wayland"
    echo -e "XDG_CURRENT_DESKTOP=Hyprland"
    echo -e "XDG_SESSION_DESKTOP=Hyprland" 
} >> /etc/environment
EOF

chmod +x /mnt/setup_internal.sh
arch-chroot /mnt ./setup_internal.sh
rm /mnt/setup_internal.sh

echo -e "${GREEN}Finished Configurating System!${NC}"