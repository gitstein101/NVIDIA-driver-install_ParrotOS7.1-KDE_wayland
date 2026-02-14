#!/bin/bash

# NVIDIA Driver Installation Script
# Automated installation with safety checks and rollback capability

set -e

# Colors
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

echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}  NVIDIA Driver Installation${NC}"
echo -e "${BLUE}==================================${NC}"
echo ""

# Detect distribution
if [ -f /etc/debian_version ]; then
    DISTRO="debian"
    PKG_MANAGER="apt"
elif [ -f /etc/arch-release ]; then
    DISTRO="arch"
    PKG_MANAGER="pacman"
else
    echo -e "${RED}Unsupported distribution${NC}"
    exit 1
fi

echo -e "${GREEN}Detected distribution: $DISTRO${NC}"
echo ""

# Function to detect GPU
detect_gpu() {
    echo -e "${BLUE}=== Detecting GPU ===${NC}"
    GPU_INFO=$(lspci | grep -i "vga\|3d")
    echo "$GPU_INFO"
    
    if echo "$GPU_INFO" | grep -qi "nvidia"; then
        echo -e "${GREEN}NVIDIA GPU detected${NC}"
        return 0
    else
        echo -e "${YELLOW}Warning: NVIDIA GPU not clearly detected${NC}"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            exit 1
        fi
    fi
}

# Function to create backup
create_backup() {
    echo -e "\n${BLUE}=== Creating Backup ===${NC}"
    BACKUP_DIR="/root/nvidia-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"
    
    # Backup important configs
    [ -f /etc/X11/xorg.conf ] && cp /etc/X11/xorg.conf "$BACKUP_DIR/"
    [ -d /etc/X11/xorg.conf.d ] && cp -r /etc/X11/xorg.conf.d "$BACKUP_DIR/"
    [ -f /etc/default/grub ] && cp /etc/default/grub "$BACKUP_DIR/"
    [ -d /etc/modprobe.d ] && cp -r /etc/modprobe.d "$BACKUP_DIR/"
    
    echo "Backup created at: $BACKUP_DIR"
    echo "$BACKUP_DIR" > /tmp/nvidia-backup-location
}

# Function to check prerequisites
check_prerequisites() {
    echo -e "\n${BLUE}=== Checking Prerequisites ===${NC}"
    
    # Check kernel headers
    if [ "$DISTRO" = "debian" ]; then
        if ! dpkg -l | grep -q "linux-headers-$(uname -r)"; then
            echo -e "${YELLOW}Installing kernel headers...${NC}"
            apt install -y "linux-headers-$(uname -r)"
        else
            echo -e "${GREEN}Kernel headers installed${NC}"
        fi
    elif [ "$DISTRO" = "arch" ]; then
        if ! pacman -Q linux-headers &> /dev/null; then
            echo -e "${YELLOW}Installing kernel headers...${NC}"
            pacman -S --noconfirm linux-headers
        else
            echo -e "${GREEN}Kernel headers installed${NC}"
        fi
    fi
}

# Function to blacklist nouveau
blacklist_nouveau() {
    echo -e "\n${BLUE}=== Blacklisting Nouveau Driver ===${NC}"
    
    BLACKLIST_FILE="/etc/modprobe.d/blacklist-nouveau.conf"
    
    if [ -f "$BLACKLIST_FILE" ]; then
        echo "Nouveau already blacklisted"
    else
        echo "Creating blacklist configuration..."
        cat > "$BLACKLIST_FILE" << EOF
blacklist nouveau
options nouveau modeset=0
EOF
        echo -e "${GREEN}Nouveau blacklisted${NC}"
    fi
    
    # Update initramfs
    echo "Updating initramfs..."
    if [ "$DISTRO" = "debian" ]; then
        update-initramfs -u
    elif [ "$DISTRO" = "arch" ]; then
        mkinitcpio -P
    fi
}

# Function to remove old drivers
remove_old_drivers() {
    echo -e "\n${BLUE}=== Removing Old Drivers ===${NC}"
    
    if [ "$DISTRO" = "debian" ]; then
        if dpkg -l | grep -q nvidia; then
            echo "Removing existing NVIDIA packages..."
            apt remove --purge -y '^nvidia-.*' '^libnvidia-.*' || true
            apt autoremove -y
        fi
    elif [ "$DISTRO" = "arch" ]; then
        if pacman -Q | grep -q nvidia; then
            echo "Removing existing NVIDIA packages..."
            pacman -R --noconfirm nvidia nvidia-utils nvidia-settings 2>/dev/null || true
        fi
    fi
    
    # Remove nouveau if loaded
    if lsmod | grep -q nouveau; then
        echo -e "${YELLOW}Nouveau is currently loaded${NC}"
        rmmod nouveau 2>/dev/null || echo "Cannot unload nouveau (will be removed on reboot)"
    fi
}

# Function to install NVIDIA driver
install_nvidia() {
    echo -e "\n${BLUE}=== Installing NVIDIA Driver ===${NC}"
    
    if [ "$DISTRO" = "debian" ]; then
        # Update package list
        apt update
        
        # Detect recommended driver
        if command -v ubuntu-drivers &> /dev/null; then
            echo "Detecting recommended driver..."
            ubuntu-drivers devices
            RECOMMENDED=$(ubuntu-drivers devices | grep recommended | awk '{print $3}')
            if [ -n "$RECOMMENDED" ]; then
                echo "Installing recommended driver: $RECOMMENDED"
                apt install -y "$RECOMMENDED" nvidia-settings
            else
                echo "Installing default nvidia-driver package..."
                apt install -y nvidia-driver nvidia-settings
            fi
        else
            echo "Installing nvidia-driver package..."
            apt install -y nvidia-driver nvidia-settings
        fi
        
    elif [ "$DISTRO" = "arch" ]; then
        echo "Installing NVIDIA driver..."
        pacman -S --noconfirm nvidia nvidia-utils nvidia-settings
        
        # Regenerate initramfs
        mkinitcpio -P
    fi
    
    echo -e "${GREEN}NVIDIA driver installed${NC}"
}

# Function to configure X server
configure_xserver() {
    echo -e "\n${BLUE}=== Configuring X Server ===${NC}"
    
    read -p "Generate xorg.conf? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if command -v nvidia-xconfig &> /dev/null; then
            nvidia-xconfig
            echo -e "${GREEN}xorg.conf generated${NC}"
        else
            echo -e "${YELLOW}nvidia-xconfig not found, creating basic config manually...${NC}"
            mkdir -p /etc/X11/xorg.conf.d
            cat > /etc/X11/xorg.conf.d/20-nvidia.conf << 'EOF'
Section "Device"
    Identifier     "NVIDIA Graphics"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
EndSection
EOF
            echo -e "${GREEN}Basic NVIDIA X config created in /etc/X11/xorg.conf.d/20-nvidia.conf${NC}"
        fi
    else
        echo "Skipping xorg.conf generation"
    fi
}

# Function to add GRUB parameters
configure_grub() {
    echo -e "\n${BLUE}=== Configuring GRUB ===${NC}"
    
    read -p "Add nvidia-drm.modeset=1 to GRUB? (Y/n): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        GRUB_FILE="/etc/default/grub"
        if grep -q "nvidia-drm.modeset=1" "$GRUB_FILE"; then
            echo "GRUB already configured"
        else
            sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="nvidia-drm.modeset=1 /' "$GRUB_FILE"
            update-grub 2>/dev/null || grub-mkconfig -o /boot/grub/grub.cfg
            echo -e "${GREEN}GRUB configured${NC}"
        fi
    fi
}

# Function to verify installation
verify_installation() {
    echo -e "\n${BLUE}=== Installation Summary ===${NC}"
    
    echo "NVIDIA packages installed:"
    if [ "$DISTRO" = "debian" ]; then
        dpkg -l | grep nvidia | grep ^ii
    elif [ "$DISTRO" = "arch" ]; then
        pacman -Q | grep nvidia
    fi
    
    echo ""
    echo "Backup location: $(cat /tmp/nvidia-backup-location 2>/dev/null || echo 'N/A')"
}

# Main installation flow
main() {
    echo "This script will:"
    echo "1. Detect your NVIDIA GPU"
    echo "2. Create a backup of current configuration"
    echo "3. Install kernel headers"
    echo "4. Blacklist nouveau driver"
    echo "5. Remove old NVIDIA drivers"
    echo "6. Install NVIDIA driver from repository"
    echo "7. Configure X server (optional)"
    echo "8. Update GRUB configuration (optional)"
    echo ""
    read -p "Continue with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled"
        exit 0
    fi
    
    detect_gpu
    create_backup
    check_prerequisites
    blacklist_nouveau
    remove_old_drivers
    install_nvidia
    configure_xserver
    configure_grub
    verify_installation
    
    echo ""
    echo -e "${GREEN}==================================${NC}"
    echo -e "${GREEN}Installation Complete!${NC}"
    echo -e "${GREEN}==================================${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT: You must reboot for changes to take effect${NC}"
    echo ""
    echo "After reboot, verify installation with:"
    echo "  nvidia-smi"
    echo "  glxinfo | grep NVIDIA"
    echo ""
    echo "If you encounter issues:"
    echo "1. Boot to recovery mode or TTY (Ctrl+Alt+F2)"
    echo "2. Restore backup from: $(cat /tmp/nvidia-backup-location 2>/dev/null)"
    echo "3. Run: ./nvidia-remove.sh"
    echo ""
    
    read -p "Reboot now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        reboot
    else
        echo "Remember to reboot before testing the driver"
    fi
}

# Run main function
main
