#!/bin/bash

#############################
# Network Connection Script #
#############################

set -e

echo -e "${BLUE}[1/10] Setting Up Network Connection...${NC}"

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
  exit "$i"
fi

echo -e "${GREEN}Network Setup Finished!${NC}"