#!/bin/bash

#################
# Reboot Script #
#################

set -e

echo -e "${GREEN}[10/10] Installation Finished!${NC}"

umount -R /mnt

echo -e "${RED}Rebooting in 5 seconds...${NC}"
sleep 5
reboot