#!/bin/bash

# NVIDIA Driver Removal Script v1.2
# Complete removal of NVIDIA drivers, Wayland configs, and dual-GPU setup

set -euo pipefail

# Load error handler
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/error-handler.sh"
init_failure_logging "remove" 9
activate_traps

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
echo -e "${RED}  NVIDIA Driver Removal v1.2${NC}"
echo -e "${RED}==================================${NC}"
echo ""
echo -e "${YELLOW}WARNING: This will remove all NVIDIA drivers and related configuration${NC}"
echo ""

# Warn if running from a graphical session (risk of black screen)
if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ "${XDG_SESSION_TYPE:-}" = "x11" ] || [ -n "${DISPLAY:-}" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
    echo -e "${RED}*** WARNING: You appear to be running this from a graphical session ***${NC}"
    echo "This script will stop the display manager, which will terminate your desktop."
    echo "It is strongly recommended to run this from a TTY (Ctrl+Alt+F2) instead."
    echo ""
    read -p "Continue from graphical session anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Exiting. Switch to a TTY (Ctrl+Alt+F2), log in as root, then re-run this script."
        exit 0
    fi
else
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Removal cancelled"
        exit 0
    fi
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
set_step 1 "Stopping display manager"
echo -e "\n${BLUE}=== Stopping Display Manager ===${NC}"
systemctl stop display-manager 2>/dev/null || echo "Display manager not running"
record_change "Stopped display manager"

# Stop nvidia-persistenced (common GPU consumer that blocks rmmod)
systemctl stop nvidia-persistenced 2>/dev/null || true
record_change "Stopped nvidia-persistenced"
step_done

# Unload NVIDIA modules
set_step 2 "Unloading NVIDIA kernel modules"
echo -e "\n${BLUE}=== Unloading NVIDIA Kernel Modules ===${NC}"

unload_nvidia_modules() {
    rmmod nvidia_drm 2>/dev/null || true
    rmmod nvidia_modeset 2>/dev/null || true
    rmmod nvidia_uvm 2>/dev/null || true
    rmmod nvidia 2>/dev/null || true
}

if lsmod | grep -q nvidia; then
    echo "Unloading NVIDIA modules..."
    unload_nvidia_modules

    # Check if modules are still loaded (processes may be holding them)
    if lsmod | grep -q nvidia; then
        echo -e "${YELLOW}NVIDIA modules still loaded — checking for processes using GPU...${NC}"

        GPU_PROCS=""
        if command -v lsof &> /dev/null; then
            GPU_PROCS=$(lsof /dev/nvidia* 2>/dev/null | tail -n +2 || true)
        fi
        if [ -z "$GPU_PROCS" ] && command -v fuser &> /dev/null; then
            GPU_PROCS=$(fuser -v /dev/nvidia* 2>&1 || true)
        fi

        if [ -n "$GPU_PROCS" ]; then
            echo "Processes using NVIDIA devices:"
            echo "$GPU_PROCS"
            echo ""
            read -p "Kill these processes to unload modules? (y/N): " -n 1 -r
            echo
            if [[ $REPLY =~ ^[Yy]$ ]]; then
                # Extract PIDs and kill them
                if command -v lsof &> /dev/null; then
                    PIDS=$(lsof -t /dev/nvidia* 2>/dev/null || true)
                else
                    PIDS=$(fuser /dev/nvidia* 2>/dev/null || true)
                fi
                for PID in $PIDS; do
                    echo "  Sending SIGTERM to PID $PID..."
                    kill "$PID" 2>/dev/null || true
                done
                sleep 2

                # Force kill any remaining
                if command -v lsof &> /dev/null; then
                    PIDS=$(lsof -t /dev/nvidia* 2>/dev/null || true)
                else
                    PIDS=$(fuser /dev/nvidia* 2>/dev/null || true)
                fi
                for PID in $PIDS; do
                    echo "  Sending SIGKILL to PID $PID..."
                    kill -9 "$PID" 2>/dev/null || true
                done
                sleep 1

                # Retry module unload
                echo "Retrying module unload..."
                unload_nvidia_modules
            fi
        fi

        # Final check
        if lsmod | grep -q nvidia; then
            echo -e "${RED}WARNING: NVIDIA modules could not be unloaded${NC}"
            echo "This usually means a process is still using the GPU, or the module is built-in."
            echo "A reboot will be required to complete removal."
            echo ""
            echo "Creating flag file: /tmp/nvidia-remove-pending"
            touch /tmp/nvidia-remove-pending
            echo "After reboot, re-run this script to finish cleanup."
            echo ""
            read -p "Continue with package removal anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Removal paused. Reboot and re-run this script."
                exit 1
            fi
        else
            echo -e "${GREEN}NVIDIA modules unloaded successfully${NC}"
        fi
    else
        echo -e "${GREEN}NVIDIA modules unloaded${NC}"
    fi
else
    echo "No NVIDIA modules loaded"
fi
record_change "Unloaded NVIDIA kernel modules"
step_done

# Remove packages
set_step 3 "Removing NVIDIA packages"
echo -e "\n${BLUE}=== Removing NVIDIA Packages ===${NC}"
if [ "$DISTRO" = "debian" ]; then
    apt remove --purge -y '^nvidia-.*' '^libnvidia-.*' || true
    apt remove --purge -y egl-wayland libnvidia-egl-wayland1 2>/dev/null || true
    # Fix any broken dependencies left by the purge before autoremove
    apt --fix-broken install -y 2>/dev/null || true
    apt autoremove -y 2>/dev/null || true
    apt clean 2>/dev/null || true
elif [ "$DISTRO" = "arch" ]; then
    pacman -R --noconfirm nvidia nvidia-utils nvidia-settings nvidia-dkms egl-wayland 2>/dev/null || true
    pacman -Sc --noconfirm 2>/dev/null || true
fi
record_change "Purged NVIDIA packages"
step_done

# Remove configuration files
set_step 4 "Removing X server configuration"
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
record_change "Removed X server configuration files"
step_done

# Remove Wayland-specific configs
set_step 5 "Removing Wayland configuration"
echo -e "\n${BLUE}=== Removing Wayland Configuration ===${NC}"

# Clean NVIDIA environment variables from /etc/environment
if [ -f /etc/environment ]; then
    if grep -q "GBM_BACKEND\|__GLX_VENDOR_LIBRARY_NAME" /etc/environment; then
        echo "Removing NVIDIA environment variables from /etc/environment..."
        sed -i '/^GBM_BACKEND=/d' /etc/environment
        sed -i '/^__GLX_VENDOR_LIBRARY_NAME=/d' /etc/environment
        echo "Environment variables removed"
    fi
fi

# Remove SDDM Wayland config
if [ -f /etc/sddm.conf.d/10-wayland.conf ]; then
    echo "Removing SDDM Wayland config..."
    rm -f /etc/sddm.conf.d/10-wayland.conf
    echo "SDDM Wayland config removed"
fi
record_change "Removed Wayland configuration (environment vars, SDDM)"
step_done

# Remove dual-GPU service and script
set_step 6 "Removing dual-GPU configuration"
echo -e "\n${BLUE}=== Removing Dual-GPU Configuration ===${NC}"

if [ -f /etc/systemd/system/nvidia-primary.service ]; then
    echo "Removing nvidia-primary.service..."
    systemctl disable nvidia-primary.service 2>/dev/null || true
    rm -f /etc/systemd/system/nvidia-primary.service
    systemctl daemon-reload
    echo "nvidia-primary.service removed"
fi

if [ -f /usr/local/bin/nvidia-primary.sh ]; then
    rm -f /usr/local/bin/nvidia-primary.sh
    echo "nvidia-primary.sh removed"
fi

# Remove Intel blacklist
if [ -f /etc/modprobe.d/blacklist-intel.conf ]; then
    echo "Removing Intel graphics blacklist..."
    rm -f /etc/modprobe.d/blacklist-intel.conf
    echo "Intel blacklist removed"
fi
record_change "Removed dual-GPU configuration (service, script, Intel blacklist)"
step_done

# Remove modprobe blacklist
set_step 7 "Checking nouveau blacklist"
echo -e "\n${BLUE}=== Checking Nouveau Blacklist ===${NC}"
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
NVIDIA_MODPROBE_FILES=$(find /etc/modprobe.d -name "*nvidia*" -type f 2>/dev/null || true)

if [ -n "$NVIDIA_MODPROBE_FILES" ]; then
    echo "$NVIDIA_MODPROBE_FILES"
    read -p "Remove these files? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        find /etc/modprobe.d -name "*nvidia*" -type f -delete
        echo "NVIDIA modprobe configs removed"
    fi
else
    echo "No NVIDIA modprobe configs found"
fi
step_done

# Update initramfs
set_step 8 "Updating initramfs"
echo -e "\n${BLUE}=== Updating Initramfs ===${NC}"
if [ "$DISTRO" = "debian" ]; then
    update-initramfs -u
elif [ "$DISTRO" = "arch" ]; then
    mkinitcpio -P
fi

# Ensure fallback driver is available
echo -e "\n${BLUE}=== Ensuring Fallback Display Driver ===${NC}"
NOUVEAU_AVAILABLE=false

# If nouveau is still blacklisted, remove the blacklist so it can load
if [ -f /etc/modprobe.d/blacklist-nouveau.conf ]; then
    echo "Nouveau is still blacklisted — it was not removed earlier."
    echo "Removing blacklist to allow nouveau as fallback..."
    rm -f /etc/modprobe.d/blacklist-nouveau.conf
    echo "Rebuilding initramfs to apply blacklist removal..."
    if [ "$DISTRO" = "debian" ]; then
        update-initramfs -u
    elif [ "$DISTRO" = "arch" ]; then
        mkinitcpio -P
    fi
fi

# Try to load nouveau
if modprobe nouveau 2>/dev/null; then
    echo -e "${GREEN}nouveau driver loaded successfully — fallback display available${NC}"
    NOUVEAU_AVAILABLE=true
else
    echo -e "${YELLOW}nouveau could not be loaded (may need reboot)${NC}"
fi

# Try to restart display manager
echo -e "\n${BLUE}=== Restarting Display Manager ===${NC}"
DM_STARTED=false
if [ "$NOUVEAU_AVAILABLE" = true ]; then
    if systemctl start display-manager 2>/dev/null; then
        sleep 3
        if systemctl is-active --quiet display-manager; then
            echo -e "${GREEN}Display manager restarted successfully${NC}"
            DM_STARTED=true
        fi
    fi
fi

if [ "$DM_STARTED" = false ]; then
    echo -e "${YELLOW}Display manager could not be restarted — this is normal${NC}"
    echo "A reboot is required for the fallback driver to initialize properly."
fi
record_change "Updated initramfs and loaded nouveau fallback driver"
step_done

# Remove GRUB parameters
set_step 9 "Cleaning GRUB configuration"
echo -e "\n${BLUE}=== Checking GRUB Configuration ===${NC}"
GRUB_FILE="/etc/default/grub"
if grep -q "nvidia" "$GRUB_FILE"; then
    echo "Found NVIDIA parameters in GRUB"
    grep GRUB_CMDLINE_LINUX "$GRUB_FILE"
    echo ""
    read -p "Remove NVIDIA parameters from GRUB? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sed -i 's/nvidia-drm.modeset=1 //g' "$GRUB_FILE"
        sed -i 's/nvidia-drm.modeset=0 //g' "$GRUB_FILE"
        update-grub 2>/dev/null || grub-mkconfig -o /boot/grub/grub.cfg
        echo -e "${GREEN}GRUB updated${NC}"
        record_change "Removed NVIDIA parameters from GRUB"
    fi
fi
step_done

# Verify removal
echo -e "\n${BLUE}=== Verification ===${NC}"
echo "Checking for remaining NVIDIA packages..."
REMAINING=""
if [ "$DISTRO" = "debian" ]; then
    REMAINING=$(dpkg -l 2>/dev/null | grep nvidia | grep ^ii || true)
elif [ "$DISTRO" = "arch" ]; then
    REMAINING=$(pacman -Q 2>/dev/null | grep nvidia || true)
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
echo "  - Cleaned X server configuration"
echo "  - Cleaned Wayland configuration (environment vars, SDDM)"
echo "  - Removed dual-GPU service (nvidia-primary)"
echo "  - Removed Intel blacklist (if present)"
echo "  - Updated initramfs"
echo ""
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Reboot your system"
echo "2. The system should boot with nouveau or fallback drivers"
echo "3. If you want to reinstall NVIDIA, run ./nvidia-install.sh"
echo ""

# Safe mode instructions in case of black screen
echo -e "${BLUE}=== Safe Mode Recovery (if you get a black screen after reboot) ===${NC}"
echo ""
echo "1. Press Ctrl+Alt+F2 to switch to a TTY"
echo "2. Log in as root"
echo "3. Verify nouveau is not blacklisted:"
echo "     ls /etc/modprobe.d/blacklist-nouveau.conf"
echo "     (if the file exists, delete it: rm /etc/modprobe.d/blacklist-nouveau.conf)"
echo "4. Rebuild initramfs:"
if [ "$DISTRO" = "debian" ]; then
    echo "     update-initramfs -u"
else
    echo "     mkinitcpio -P"
fi
echo "5. Reboot: reboot"
echo "6. If still no display, install a basic X driver:"
if [ "$DISTRO" = "debian" ]; then
    echo "     apt install xserver-xorg-video-nouveau"
else
    echo "     pacman -S xf86-video-nouveau"
fi
echo ""

# Clean up pending flag if it exists
rm -f /tmp/nvidia-remove-pending

read -p "Reboot now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    reboot
else
    echo "Remember to reboot to complete the removal"
fi
