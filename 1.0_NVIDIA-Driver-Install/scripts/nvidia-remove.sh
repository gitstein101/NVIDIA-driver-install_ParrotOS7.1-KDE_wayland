#!/bin/bash

# NVIDIA Driver Removal Script
# Complete removal of NVIDIA drivers for troubleshooting

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

echo -e "${RED}==================================${NC}"
echo -e "${RED}  NVIDIA Driver Removal${NC}"
echo -e "${RED}==================================${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will remove all NVIDIA drivers${NC}"
echo ""

read -p "Continue? (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Removal cancelled"
    exit 0
fi

# Detect distribution
if [ -f /etc/debian_version ]; then
    DISTRO="debian"
elif [ -f /etc/arch-release ]; then
    DISTRO="arch"
else
    echo -e "${RED}Unsupported distribution${NC}"
    exit 1
fi

echo -e "${GREEN}Detected distribution: $DISTRO${NC}"

# Stop display manager
echo -e "\n${BLUE}=== Stopping Display Manager ===${NC}"
systemctl stop display-manager 2>/dev/null || echo "Display manager not running"

# Unload NVIDIA modules
echo -e "\n${BLUE}=== Unloading NVIDIA Kernel Modules ===${NC}"
if lsmod | grep -q nvidia; then
    echo "Unloading NVIDIA modules..."
    rmmod nvidia_drm 2>/dev/null || true
    rmmod nvidia_modeset 2>/dev/null || true
    rmmod nvidia_uvm 2>/dev/null || true
    rmmod nvidia 2>/dev/null || true
    echo "Modules unloaded"
else
    echo "No NVIDIA modules loaded"
fi

# Remove packages
echo -e "\n${BLUE}=== Removing NVIDIA Packages ===${NC}"
if [ "$DISTRO" = "debian" ]; then
    apt remove --purge -y '^nvidia-.*' '^libnvidia-.*' || true
    apt autoremove -y
    apt clean
elif [ "$DISTRO" = "arch" ]; then
    pacman -R --noconfirm nvidia nvidia-utils nvidia-settings nvidia-dkms 2>/dev/null || true
    pacman -Sc --noconfirm
fi

# Remove configuration files
echo -e "\n${BLUE}=== Removing Configuration Files ===${NC}"

# Remove X configuration
if [ -f /etc/X11/xorg.conf ]; then
    echo "Removing /etc/X11/xorg.conf"
    rm -f /etc/X11/xorg.conf
fi

if [ -d /etc/X11/xorg.conf.d ]; then
    echo "Checking /etc/X11/xorg.conf.d for NVIDIA configs..."
    find /etc/X11/xorg.conf.d -name "*nvidia*" -type f -delete
fi

# Remove modprobe blacklist
if [ -f /etc/modprobe.d/blacklist-nouveau.conf ]; then
    read -p "Remove nouveau blacklist? This will allow nouveau to load. (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        rm -f /etc/modprobe.d/blacklist-nouveau.conf
        echo "Nouveau blacklist removed"
    fi
fi

# Find and remove other NVIDIA-related modprobe configs
echo "Checking for other NVIDIA modprobe configs..."
find /etc/modprobe.d -name "*nvidia*" -type f

read -p "Remove these files? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    find /etc/modprobe.d -name "*nvidia*" -type f -delete
    echo "NVIDIA modprobe configs removed"
fi

# Update initramfs
echo -e "\n${BLUE}=== Updating Initramfs ===${NC}"
if [ "$DISTRO" = "debian" ]; then
    update-initramfs -u
elif [ "$DISTRO" = "arch" ]; then
    mkinitcpio -P
fi

# Remove GRUB parameters
echo -e "\n${BLUE}=== Checking GRUB Configuration ===${NC}"
GRUB_FILE="/etc/default/grub"
if grep -q "nvidia" "$GRUB_FILE"; then
    echo "Found NVIDIA parameters in GRUB"
    cat "$GRUB_FILE" | grep GRUB_CMDLINE_LINUX
    echo ""
    read -p "Remove NVIDIA parameters from GRUB? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sed -i 's/nvidia-drm.modeset=1 //g' "$GRUB_FILE"
        sed -i 's/nvidia-drm.modeset=0 //g' "$GRUB_FILE"
        update-grub 2>/dev/null || grub-mkconfig -o /boot/grub/grub.cfg
        echo -e "${GREEN}GRUB updated${NC}"
    fi
fi

# Verify removal
echo -e "\n${BLUE}=== Verification ===${NC}"
echo "Checking for remaining NVIDIA packages..."
if [ "$DISTRO" = "debian" ]; then
    REMAINING=$(dpkg -l | grep nvidia | grep ^ii || true)
elif [ "$DISTRO" = "arch" ]; then
    REMAINING=$(pacman -Q | grep nvidia || true)
fi

if [ -z "$REMAINING" ]; then
    echo -e "${GREEN}All NVIDIA packages removed${NC}"
else
    echo -e "${YELLOW}Some packages remain:${NC}"
    echo "$REMAINING"
fi

# Summary
echo -e "\n${GREEN}==================================${NC}"
echo -e "${GREEN}Removal Complete${NC}"
echo -e "${GREEN}==================================${NC}"
echo ""
echo "What was done:"
echo "  - Stopped display manager"
echo "  - Unloaded NVIDIA kernel modules"
echo "  - Removed NVIDIA packages"
echo "  - Cleaned configuration files"
echo "  - Updated initramfs"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Reboot your system"
echo "2. The system should boot with nouveau or fallback drivers"
echo "3. If you want to reinstall NVIDIA, run ./nvidia-install.sh"
echo ""

read -p "Reboot now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    reboot
else
    echo "Remember to reboot to complete the removal"
fi
