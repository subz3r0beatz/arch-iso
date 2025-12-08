#!/bin/bash

#################################################
# Hyprland & Essentials Installation Script #
#################################################

set -e

echo -e "${BLUE}[9/10] Installing Hyprland & Essentials...${NC}"

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