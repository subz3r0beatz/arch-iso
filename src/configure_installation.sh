#!/bin/bash

#####################################
# Installation Configuration Script #
#####################################

set -e

echo -e "${BLUE}[2/10] Configurating Installation...${NC}"
echo -e "${YELLOW}Please Input Choices${NC}\n"

# Keymap layout selection
echo -e "${BLUE}Keyboard Layout${NC}"

read -r -p "Enter keymap (e.g.: us, de, fr...): " KEYMAP_INPUT
KEYMAP=${KEYMAP_INPUT:-us}
loadkeys "$KEYMAP" || loadkeys us

echo -e "${GREEN}Keyboard Setup Finished!${NC}"

# Disk selection for instalation
echo -e "${BLUE}Installation Disk${NC}"
lsblk -d -p -n -o NAME,SIZE,MODEL
read -r -p "Target Disk (e.g.: /dev/nvme0n1 or /dev/sda): " DISK
if [ ! -b "$DISK" ]; then
  echo -e "${RED}Invalid Disk${NC}\n${YELLOW}(Restart script and input a valid disk)${NC}"
  exit 1
fi

echo -e "${RED}WARNING: $DISK Will Be Wiped!${NC}"
echo -ne "${YELLOW}Confirm? (WIPE DISK): ${NC}"
read -r CONF_WIPE
[[ "$CONF_WIPE" == "WIPE DISK" ]] || exit 1

# Size selection for partitions
echo -e "${BLUE}Partition Sizes${NC}"

read -r -p "EFI Partition Size [Default: 512M]: " EFI_INPUT
EFI_SIZE=${EFI_INPUT:-512M}

read -r -p "BOOT Partition Size [Default: 2G]: " BOOT_INPUT
BOOT_SIZE=${BOOT_INPUT:-2G}

read -r -p "SWAP Partition Size [Default: 10G]: " SWAP_INPUT
SWAP_SIZE=${SWAP_INPUT:-10G}

echo -e "${RED}Using: EFI=${EFI_SIZE}, BOOT=${BOOT_SIZE}, SWAP=${SWAP_SIZE}, ROOT=Remaining${NC}"

echo -ne "${YELLOW}Confirm? (YES): ${NC}"
read -r CONF_SIZE
[[ "$CONF_SIZE" == "YES" ]] || exit 1

# Account selection
echo -e "${BLUE}System Environment${NC}"

read -r -p "Hostname: " NEW_HOSTNAME
read -r -p "Username: " NEW_USER

# Password selection
while true; do
  echo -e "${BLUE}Set System Password${NC}\n${YELLOW}(Root / User / Encryption)${NC}"
  read -s -r -p "Enter Password: " PASSWORD
  echo -e ""
  read -s -r -p "Confirm Password: " PASSWORD_CONFIRM
  echo -e ""

  if [ -z "$PASSWORD" ]; then
    echo -e "${RED}Password cannot be empty!${NC}"
  elif [ "$PASSWORD" == "$PASSWORD_CONFIRM" ]; then
    echo -e "${GREEN}Passwords Match!${NC}"

	echo -ne "${RED}Show Password? (YES): ${NC}"
    read -r SHOW_PASS
    if [[ "$SHOW_PASS" == "YES" ]]; then
      echo -e "${BLUE}${PASSWORD}${NC}"
    fi

	echo -ne "${YELLOW}Confirm? (YES): ${NC}"
    read -r CONF_PASS
    if [[ "$CONF_PASS" == "YES" ]]; then
      break
    fi
  else
    echo -e "${RED}Passwords do not match!${NC}\n${YELLOW}(Please try again)${NC}"
  fi
done

echo -e "${GREEN}Configuration Finished!${NC}"

export KEYMAP
export DISK
export EFI_SIZE
export BOOT_SIZE
export SWAP_SIZE
export NEW_HOSTNAME
export NEW_USER
export PASSWORD