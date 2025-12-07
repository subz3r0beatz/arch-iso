#!/bin/bash

####################################
# Environment Configuration Script #
####################################

# Colors
YELLOW='\033[0;33m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
NC='\033[0m'

# Keymap Setup
echo -e "${BLUE}[1/11] Setting Up Keyboard Layout...${NC}"

read -p "Enter keymap (e.g.: us, de, fr...): " KEYMAP_INPUT
KEYMAP=${KEYMAP_INPUT:-us}
loadkeys "$KEYMAP" || loadkeys us

echo -e "${GREEN}Keyboard Setup Finished!${NC}"

