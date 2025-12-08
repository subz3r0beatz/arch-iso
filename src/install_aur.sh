#!/bin/bash

##############################
# 9. AUR Installation Script #
##############################

set -e

echo -e "${BLUE}[8/10] Installing AUR Helper & Custom Apps...${NC}"

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