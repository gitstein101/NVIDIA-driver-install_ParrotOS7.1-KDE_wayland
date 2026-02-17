#!/bin/bash

# NVIDIA Driver Installation Script v1.4
# Target: LightDM + KDE Plasma + Wayland (Debian-based distros)
# Dual-GPU support (Intel iGPU + NVIDIA dGPU)

set -euo pipefail

# Load error handler
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "${SCRIPT_DIR}/error-handler.sh"
init_failure_logging "install" 13
activate_traps

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
BOLD='\033[1m'
NC='\033[0m'

# Global state
DUAL_GPU=false
CONFIG_ONLY=false

# Parse arguments
for arg in "$@"; do
    case "$arg" in
        --config-only)
            CONFIG_ONLY=true
            ;;
        --help|-h)
            echo "Usage: sudo $0 [--config-only]"
            echo ""
            echo "Options:"
            echo "  --config-only   Skip driver install/removal, only reconfigure system"
            echo "                  (modules, GRUB, LightDM, dual-GPU, initramfs)"
            echo "                  Use when drivers are already installed and working."
            exit 0
            ;;
        *)
            echo "Unknown option: $arg"
            echo "Usage: sudo $0 [--config-only]"
            exit 1
            ;;
    esac
done

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}  NVIDIA Driver Installation v1.4${NC}"
echo -e "${BLUE}  LightDM + KDE Plasma + Wayland${NC}"
if [ "$CONFIG_ONLY" = true ]; then
    echo -e "${YELLOW}  Mode: CONFIG-ONLY (no driver install)${NC}"
fi
echo -e "${BLUE}==================================${NC}"
echo ""

# Verify Debian-based distribution
if [ ! -f /etc/debian_version ]; then
    echo -e "${RED}Unsupported distribution — this toolkit supports Debian-based systems only${NC}"
    exit 1
fi

# Function to detect GPU
detect_gpu() {
    set_step 1 "Detecting GPU hardware"
    echo -e "${BLUE}=== Detecting GPU ===${NC}"
    GPU_INFO=$(lspci | grep -i "vga\|3d" || true)
    echo "$GPU_INFO"

    if echo "$GPU_INFO" | grep -qi "nvidia"; then
        echo -e "${GREEN}NVIDIA GPU detected${NC}"
    else
        echo -e "${YELLOW}Warning: NVIDIA GPU not clearly detected${NC}"
        read -p "Continue anyway? (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            echo "Installation cancelled"
            exit 0
        fi
    fi
    step_done
}

# Function to detect dual-GPU setup
detect_dual_gpu() {
    set_step 2 "Checking for dual-GPU configuration"
    echo -e "\n${BLUE}=== Checking for Dual-GPU Configuration ===${NC}"

    VGA_COUNT=$(lspci | grep -ci "vga\|3d" || true)
    echo "Found $VGA_COUNT GPU device(s):"
    lspci | grep -i "vga\|3d" || true
    echo ""

    if [ "${VGA_COUNT:-0}" -gt 1 ]; then
        DUAL_GPU=true
        echo -e "${YELLOW}Dual-GPU system detected${NC}"

        if lspci | grep -i "vga" | grep -qi "intel"; then
            echo "  Intel iGPU + NVIDIA dGPU configuration"
        elif lspci | grep -i "vga" | grep -qi "amd"; then
            echo "  AMD iGPU + NVIDIA dGPU configuration"
        else
            echo "  Multiple GPU configuration"
        fi

        echo ""
        echo "The installer will configure your system to use the NVIDIA GPU as the"
        echo "primary display device via DRM/KMS."
    else
        DUAL_GPU=false
        echo -e "${GREEN}Single GPU configuration — no dual-GPU setup needed${NC}"
    fi
    step_done
}

# Function to create backup
create_backup() {
    set_step 3 "Creating configuration backup"
    echo -e "\n${BLUE}=== Creating Backup ===${NC}"
    BACKUP_DIR="/root/nvidia-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    # Backup important configs
    [ -f /etc/X11/xorg.conf ] && cp /etc/X11/xorg.conf "$BACKUP_DIR/"
    [ -d /etc/X11/xorg.conf.d ] && cp -r /etc/X11/xorg.conf.d "$BACKUP_DIR/"
    [ -f /etc/default/grub ] && cp /etc/default/grub "$BACKUP_DIR/"
    [ -d /etc/modprobe.d ] && cp -r /etc/modprobe.d "$BACKUP_DIR/"
    [ -f /etc/environment ] && cp /etc/environment "$BACKUP_DIR/"
    [ -f /etc/lightdm/lightdm.conf ] && cp /etc/lightdm/lightdm.conf "$BACKUP_DIR/"
    [ -d /etc/lightdm/lightdm.conf.d ] && cp -r /etc/lightdm/lightdm.conf.d "$BACKUP_DIR/"

    echo "Backup created at: $BACKUP_DIR"
    echo "$BACKUP_DIR" > /tmp/nvidia-backup-location
    record_change "Created backup at ${BACKUP_DIR}"
    step_done
}

# Function to check prerequisites
check_prerequisites() {
    set_step 4 "Installing prerequisites"
    echo -e "\n${BLUE}=== Checking Prerequisites ===${NC}"

    # Repair broken dpkg state before anything else
    BROKEN_PKGS=$(dpkg -l 2>/dev/null | awk '/^.[HUFWt]/{print $2}' || true)
    STUCK_PKGS=$(dpkg -l 2>/dev/null | awk '/^r[iHUF]/{print $2}' || true)
    IU_PKGS=$(dpkg -l 2>/dev/null | awk '/^iU/{print $2}' || true)

    ALL_PROBLEM_PKGS="${BROKEN_PKGS} ${STUCK_PKGS} ${IU_PKGS}"
    ALL_PROBLEM_PKGS=$(echo "$ALL_PROBLEM_PKGS" | xargs -n1 2>/dev/null | sort -u | xargs 2>/dev/null || true)

    if [ -n "$ALL_PROBLEM_PKGS" ]; then
        echo -e "${YELLOW}Repairing broken package state...${NC}"
        echo "  Problem packages: $ALL_PROBLEM_PKGS"

        dpkg --configure -a 2>/dev/null || true
        apt --fix-broken install -y 2>/dev/null || true

        STILL_BROKEN=$(dpkg -l 2>/dev/null | awk '/^.[HUFWt]/{print $2}' || true)
        STUCK_REMAINING=$(dpkg -l 2>/dev/null | awk '/^r[iHUF]/{print $2}' || true)
        IU_REMAINING=$(dpkg -l 2>/dev/null | awk '/^iU/{print $2}' || true)
        ALL_REMAINING="${STILL_BROKEN} ${STUCK_REMAINING} ${IU_REMAINING}"
        ALL_REMAINING=$(echo "$ALL_REMAINING" | xargs -n1 2>/dev/null | sort -u | xargs 2>/dev/null || true)

        ESSENTIAL_RE="^(libc-bin|libc6|dpkg|apt|bash|coreutils|debianutils|diffutils|findutils|grep|gzip|hostname|login|ncurses-base|ncurses-bin|perl-base|sed|tar|util-linux|base-files|base-passwd|init-system-helpers|sysvinit-utils)$"
        for pkg in $ALL_REMAINING; do
            if echo "$pkg" | grep -qE "$ESSENTIAL_RE"; then
                echo -e "${YELLOW}  Skipping essential package: $pkg${NC}"
                dpkg --configure "$pkg" 2>/dev/null || true
            elif echo "$pkg" | grep -qi "nvidia\|libnvidia"; then
                echo "  Force-removing broken NVIDIA package: $pkg"
                dpkg --remove --force-remove-reinstreq "$pkg" 2>/dev/null || true
            else
                echo "  Force-removing broken package: $pkg"
                dpkg --remove --force-remove-reinstreq "$pkg" 2>/dev/null || true
            fi
        done

        dpkg --configure -a 2>/dev/null || true
        apt --fix-broken install -y 2>/dev/null || true
        record_change "Repaired broken dpkg packages: ${ALL_PROBLEM_PKGS}"
    fi

    # Check kernel headers
    if ! dpkg -s "linux-headers-$(uname -r)" &>/dev/null; then
        echo -e "${YELLOW}Installing kernel headers...${NC}"
        if apt install -y "linux-headers-$(uname -r)"; then
            record_change "Installed kernel headers for $(uname -r)"
        else
            echo -e "${YELLOW}WARNING: Could not install linux-headers-$(uname -r)${NC}"
            echo -e "${YELLOW}The NVIDIA kernel module may fail to build without headers.${NC}"
            read -p "Continue anyway? (y/N): " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Installation cancelled"
                exit 1
            fi
        fi
    else
        echo -e "${GREEN}Kernel headers installed${NC}"
    fi

    # Verify LightDM is installed
    if ! dpkg -s lightdm &>/dev/null; then
        echo -e "${YELLOW}LightDM not installed — installing...${NC}"
        apt install -y lightdm
        record_change "Installed lightdm"
    else
        echo -e "${GREEN}LightDM installed${NC}"
    fi

    # Check for KDE Plasma Wayland session
    if ! dpkg -l 2>/dev/null | grep -q "plasma-workspace"; then
        echo -e "${YELLOW}WARNING: plasma-workspace not found${NC}"
        echo "KDE Plasma may not be fully installed."
        read -p "Install plasma-workspace? (Y/n): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Nn]$ ]]; then
            apt install -y plasma-workspace
            record_change "Installed plasma-workspace"
        fi
    fi

    # Ensure Wayland session file exists
    if [ ! -f /usr/share/wayland-sessions/plasma.desktop ]; then
        echo -e "${YELLOW}WARNING: /usr/share/wayland-sessions/plasma.desktop not found${NC}"
        echo "KDE Plasma Wayland session may not be available at login screen."
        echo "You may need to install plasma-workspace-wayland or equivalent."
    else
        echo -e "${GREEN}KDE Plasma Wayland session file found${NC}"
    fi

    step_done
}

# Function to blacklist nouveau
blacklist_nouveau() {
    set_step 5 "Blacklisting nouveau driver"
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
        record_change "Created /etc/modprobe.d/blacklist-nouveau.conf"
    fi

    # Note: initramfs rebuild deferred to step 12 (final rebuild catches all modprobe.d changes)
    step_done
}

# Function to remove old drivers
remove_old_drivers() {
    set_step 6 "Removing old NVIDIA drivers"
    echo -e "\n${BLUE}=== Removing Old Drivers ===${NC}"

    if dpkg -l 2>/dev/null | grep -q nvidia; then
        echo "Removing existing NVIDIA packages..."
        apt remove --purge -y '^nvidia-.*' '^libnvidia-.*' || true

        dpkg --configure -a 2>/dev/null || true
        apt --fix-broken install -y 2>/dev/null || true

        BROKEN_NV=$(dpkg -l 2>/dev/null | awk '/^.[HUFWt]/' | awk '{print $2}' | grep -i nvidia || true)
        STUCK_NV=$(dpkg -l 2>/dev/null | awk '/^r[iHUF]/' | awk '{print $2}' | grep -i nvidia || true)
        for pkg in $BROKEN_NV $STUCK_NV; do
            echo "  Force-removing broken package: $pkg"
            dpkg --remove --force-remove-reinstreq "$pkg" 2>/dev/null || true
        done
        dpkg --configure -a 2>/dev/null || true
        apt --fix-broken install -y 2>/dev/null || true

        if ! apt autoremove -y 2>/dev/null; then
            echo -e "${YELLOW}autoremove failed — continuing (non-critical)${NC}"
        fi
        record_change "Purged existing NVIDIA packages"
    fi

    # Remove nouveau if loaded
    if lsmod | grep -q nouveau; then
        echo -e "${YELLOW}Nouveau is currently loaded${NC}"
        rmmod nouveau 2>/dev/null || echo "Cannot unload nouveau (will be removed on reboot)"
    fi
    step_done
}

# Function to install NVIDIA driver
install_nvidia() {
    set_step 7 "Installing NVIDIA driver packages"
    echo -e "\n${BLUE}=== Installing NVIDIA Driver ===${NC}"

    # Update package list
    if ! apt update; then
        echo -e "${RED}Package list update failed — check network connection and /etc/apt/sources.list${NC}"
        exit 1
    fi

    # Determine which driver package to install
    DRIVER_PKG="nvidia-driver"
    DRIVER_EXTRAS="nvidia-settings"
    if command -v ubuntu-drivers &> /dev/null; then
        echo "Detecting recommended driver..."
        ubuntu-drivers devices || true
        RECOMMENDED=$(ubuntu-drivers devices 2>/dev/null | grep recommended | awk '{print $3}' || true)
        if [ -n "${RECOMMENDED:-}" ]; then
            DRIVER_PKG="$RECOMMENDED"
        fi
    fi

    echo "Installing driver package: $DRIVER_PKG"

    # Install with retry
    if ! apt install -y "$DRIVER_PKG" $DRIVER_EXTRAS; then
        echo -e "${YELLOW}Install failed — repairing package state and retrying...${NC}"

        dpkg --configure -a 2>/dev/null || true
        apt --fix-broken install -y 2>/dev/null || true

        BROKEN_NV=$(dpkg -l 2>/dev/null | awk '/^.[HUFWt]/' | awk '{print $2}' | grep -i "nvidia\|libnvidia" || true)
        IU_NV=$(dpkg -l 2>/dev/null | awk '/^iU/' | awk '{print $2}' | grep -i "nvidia\|libnvidia" || true)
        STUCK_NV=$(dpkg -l 2>/dev/null | awk '/^r[iHUF]/' | awk '{print $2}' | grep -i "nvidia\|libnvidia" || true)
        for pkg in $BROKEN_NV $IU_NV $STUCK_NV; do
            echo "  Force-removing broken package: $pkg"
            dpkg --remove --force-remove-reinstreq "$pkg" 2>/dev/null || true
        done

        dpkg --configure -a 2>/dev/null || true
        apt --fix-broken install -y 2>/dev/null || true

        echo "Retrying driver installation..."
        apt install -y "$DRIVER_PKG" $DRIVER_EXTRAS
    fi

    # Install Wayland support packages
    echo "Installing Wayland support packages..."
    if ! apt install -y libnvidia-egl-wayland1 egl-wayland 2>/dev/null; then
        echo -e "${YELLOW}WARNING: Wayland EGL packages failed to install${NC}"
        echo -e "${YELLOW}Wayland sessions may not work correctly without libnvidia-egl-wayland1${NC}"
        echo -e "${YELLOW}Try manually: apt install libnvidia-egl-wayland1 egl-wayland${NC}"
    fi

    record_change "Installed NVIDIA driver packages"
    echo -e "${GREEN}NVIDIA driver installed${NC}"
    step_done
}

# Function to configure NVIDIA kernel module options
configure_nvidia_modules() {
    set_step 8 "Configuring NVIDIA kernel module options"
    echo -e "\n${BLUE}=== Configuring NVIDIA Kernel Module Options ===${NC}"

    # Create modprobe config for NVIDIA Wayland requirements
    MODPROBE_CONF="/etc/modprobe.d/nvidia-wayland.conf"
    cat > "$MODPROBE_CONF" << 'EOF'
# NVIDIA kernel module options for Wayland
# Generated by nvidia-install.sh v1.4

# Required: enable DRM kernel mode setting
options nvidia_drm modeset=1 fbdev=1

# Required for suspend/resume on Wayland
options nvidia NVreg_PreserveVideoMemoryAllocations=1
EOF

    echo -e "${GREEN}Created $MODPROBE_CONF:${NC}"
    echo "  nvidia_drm modeset=1 fbdev=1"
    echo "  nvidia NVreg_PreserveVideoMemoryAllocations=1"
    record_change "Created /etc/modprobe.d/nvidia-wayland.conf"

    # Ensure nvidia-suspend/resume/hibernate services are enabled
    for svc in nvidia-suspend nvidia-resume nvidia-hibernate; do
        if systemctl list-unit-files 2>/dev/null | grep -q "${svc}.service"; then
            systemctl enable "${svc}.service" 2>/dev/null || true
            echo "  Enabled ${svc}.service"
        fi
    done
    record_change "Enabled NVIDIA power management services"

    # Ensure NVIDIA modules load early via modules-load.d
    MODULES_LOAD="/etc/modules-load.d/nvidia.conf"
    cat > "$MODULES_LOAD" << 'EOF'
# Load NVIDIA modules at boot for Wayland/DRM
# Generated by nvidia-install.sh v1.4
nvidia
nvidia_modeset
nvidia_uvm
nvidia_drm
EOF
    echo -e "${GREEN}Created $MODULES_LOAD for early module loading${NC}"
    record_change "Created /etc/modules-load.d/nvidia.conf"

    step_done
}

# Function to configure X server (minimal — for LightDM greeter only)
configure_xserver() {
    set_step 9 "Configuring X server for LightDM greeter"
    echo -e "\n${BLUE}=== Configuring X Server (LightDM greeter) ===${NC}"

    if [ "$DUAL_GPU" = true ]; then
        # Dual-GPU: need xorg.conf with NVIDIA BusID for the greeter
        NVIDIA_BUSID=$(lspci | grep -i "vga.*nvidia\|3d.*nvidia" | head -1 | cut -d' ' -f1 | sed 's/\./:/' || true)
        if [ -n "$NVIDIA_BUSID" ]; then
            IFS=':' read -r _BUS _DEV _FUNC <<< "$NVIDIA_BUSID"
            BUSID_DEC="PCI:$((16#$_BUS)):$((16#$_DEV)):$((16#$_FUNC))"
            GPU_NAME=$(lspci | grep -i "vga.*nvidia\|3d.*nvidia" | head -1 | sed 's/.*: //' || true)

            cat > /etc/X11/xorg.conf << EOF
# Dual GPU Configuration — NVIDIA as primary (for LightDM X11 greeter)
# Generated by nvidia-install.sh v1.4
# Note: User session runs under Wayland (KDE Plasma), not X11

Section "ServerLayout"
    Identifier     "Layout0"
    Screen      0  "Screen0" 0 0
    Option         "Xinerama" "0"
EndSection

Section "Monitor"
    Identifier     "Monitor0"
    VendorName     "Unknown"
    ModelName      "Unknown"
    Option         "DPMS"
EndSection

Section "Device"
    Identifier     "Device0"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
    BoardName      "$GPU_NAME"
    BusID          "$BUSID_DEC"
    Option         "AllowEmptyInitialConfiguration"
EndSection

Section "Screen"
    Identifier     "Screen0"
    Device         "Device0"
    Monitor        "Monitor0"
    DefaultDepth    24
    SubSection     "Display"
        Depth       24
    EndSubSection
EndSection
EOF
            echo -e "${GREEN}Created /etc/X11/xorg.conf with NVIDIA BusID ($BUSID_DEC)${NC}"
            record_change "Created /etc/X11/xorg.conf with NVIDIA BusID ${BUSID_DEC}"
        else
            echo -e "${YELLOW}Could not detect NVIDIA BusID — skipping xorg.conf${NC}"
        fi
    else
        # Single GPU: minimal xorg.conf.d snippet
        mkdir -p /etc/X11/xorg.conf.d
        cat > /etc/X11/xorg.conf.d/20-nvidia.conf << 'EOF'
Section "Device"
    Identifier     "NVIDIA Graphics"
    Driver         "nvidia"
    VendorName     "NVIDIA Corporation"
    Option         "AllowEmptyInitialConfiguration"
EndSection
EOF
        echo -e "${GREEN}Created /etc/X11/xorg.conf.d/20-nvidia.conf${NC}"
        record_change "Created /etc/X11/xorg.conf.d/20-nvidia.conf"
    fi

    step_done
}

# Function to configure LightDM for Wayland session
configure_lightdm_wayland() {
    set_step 10 "Configuring LightDM for KDE Plasma Wayland"
    echo -e "\n${BLUE}=== Configuring LightDM for KDE Plasma Wayland ===${NC}"

    # Set NVIDIA Wayland environment variables
    echo "Setting NVIDIA Wayland environment variables..."
    ENV_FILE="/etc/environment"
    VARS_TO_SET=(
        "GBM_BACKEND=nvidia-drm"
        "__GLX_VENDOR_LIBRARY_NAME=nvidia"
    )

    for VAR in "${VARS_TO_SET[@]}"; do
        VAR_NAME="${VAR%%=*}"
        if grep -q "^${VAR_NAME}=" "$ENV_FILE" 2>/dev/null; then
            sed -i "s|^${VAR_NAME}=.*|${VAR}|" "$ENV_FILE"
        else
            echo "$VAR" >> "$ENV_FILE"
        fi
    done

    echo -e "${GREEN}Environment variables set in $ENV_FILE:${NC}"
    echo "  GBM_BACKEND=nvidia-drm"
    echo "  __GLX_VENDOR_LIBRARY_NAME=nvidia"
    record_change "Set NVIDIA Wayland environment variables in /etc/environment"

    # Ensure LightDM is enabled as the display manager
    if ! systemctl is-enabled lightdm.service &>/dev/null; then
        echo "Enabling LightDM as display manager..."
        systemctl enable lightdm.service
        record_change "Enabled lightdm.service"
    fi

    # Disable other display managers that might conflict
    for dm in sddm gdm gdm3; do
        if systemctl is-enabled "${dm}.service" &>/dev/null; then
            echo "Disabling ${dm}.service (LightDM is the target DM)..."
            systemctl disable "${dm}.service" 2>/dev/null || true
            record_change "Disabled ${dm}.service"
        fi
    done

    # Configure LightDM
    LIGHTDM_CONF_DIR="/etc/lightdm/lightdm.conf.d"
    mkdir -p "$LIGHTDM_CONF_DIR"

    # Create NVIDIA display setup script for LightDM greeter (X11)
    cat > /usr/local/bin/nvidia-lightdm-setup.sh << 'SCRIPT'
#!/bin/bash
# NVIDIA display setup for LightDM greeter (X11)
# Generated by nvidia-install.sh v1.4
# This runs before the greeter to set up the X11 display
xrandr --setprovideroutputsource modesetting NVIDIA-0 2>/dev/null || true
xrandr --auto 2>/dev/null || true
SCRIPT
    chmod +x /usr/local/bin/nvidia-lightdm-setup.sh

    # Create LightDM NVIDIA config with Wayland session default
    cat > "${LIGHTDM_CONF_DIR}/50-nvidia-wayland.conf" << 'EOF'
# NVIDIA + KDE Plasma Wayland configuration for LightDM
# Generated by nvidia-install.sh v1.4

[Seat:*]
# X11 display setup for the LightDM greeter (runs under X)
display-setup-script=/usr/local/bin/nvidia-lightdm-setup.sh

# Default to KDE Plasma Wayland session
# The session type (wayland) is determined by plasma.desktop
# in /usr/share/wayland-sessions/ — KDE sets XDG_SESSION_TYPE=wayland
user-session=plasma
EOF

    echo -e "${GREEN}LightDM configured:${NC}"
    echo "  - Display setup script for greeter (X11)"
    echo "  - Default session: plasma (Wayland)"
    record_change "Created ${LIGHTDM_CONF_DIR}/50-nvidia-wayland.conf and /usr/local/bin/nvidia-lightdm-setup.sh"

    # Remove old 50-nvidia.conf if it exists (replaced by 50-nvidia-wayland.conf)
    if [ -f "${LIGHTDM_CONF_DIR}/50-nvidia.conf" ]; then
        rm -f "${LIGHTDM_CONF_DIR}/50-nvidia.conf"
        echo "  Removed old 50-nvidia.conf (replaced by 50-nvidia-wayland.conf)"
        record_change "Removed old ${LIGHTDM_CONF_DIR}/50-nvidia.conf"
    fi

    # Verify the Wayland session desktop file
    if [ -f /usr/share/wayland-sessions/plasma.desktop ]; then
        echo -e "${GREEN}Verified: /usr/share/wayland-sessions/plasma.desktop exists${NC}"
    else
        echo -e "${YELLOW}WARNING: /usr/share/wayland-sessions/plasma.desktop not found${NC}"
        echo "Available Wayland sessions:"
        ls /usr/share/wayland-sessions/ 2>/dev/null || echo "  (none)"
        echo ""
        echo "Available X11 sessions:"
        ls /usr/share/xsessions/ 2>/dev/null || echo "  (none)"
    fi

    step_done
}

# Function to configure dual-GPU setup (Wayland path)
configure_dual_gpu() {
    set_step 11 "Configuring dual-GPU for Wayland"
    if [ "$DUAL_GPU" = false ]; then
        step_done
        return
    fi

    echo -e "\n${BLUE}=== Configuring Dual-GPU (Wayland DRM) ===${NC}"
    echo ""
    echo "On Wayland, GPU selection is handled by the DRM/KMS subsystem."
    echo "nvidia-drm.modeset=1 (set in step 8) enables NVIDIA as a DRM device."
    echo "No xrandr provider setup or systemd service is needed for the Wayland session."
    echo ""

    # Clean up nvidia-primary.service if it exists from a previous install
    # (It uses xrandr which is X11-only and hangs on Wayland)
    if [ -f /etc/systemd/system/nvidia-primary.service ]; then
        echo "Removing nvidia-primary.service (X11-only, not needed for Wayland)..."
        systemctl disable nvidia-primary.service 2>/dev/null || true
        systemctl stop nvidia-primary.service 2>/dev/null || true
        rm -f /etc/systemd/system/nvidia-primary.service
        systemctl daemon-reload
        echo -e "${GREEN}Removed nvidia-primary.service${NC}"
        record_change "Removed nvidia-primary.service (not needed for Wayland)"
    fi
    if [ -f /usr/local/bin/nvidia-primary.sh ]; then
        rm -f /usr/local/bin/nvidia-primary.sh
        record_change "Removed /usr/local/bin/nvidia-primary.sh"
    fi

    # Intel iGPU handling
    echo ""
    echo -e "${BLUE}=== Intel iGPU Options ===${NC}"
    echo "You have Intel integrated graphics + NVIDIA discrete GPU."
    echo ""
    echo "  Option A (Recommended): Blacklist Intel — all rendering on NVIDIA"
    echo "    Best for: desktop systems where NVIDIA is the only connected display"
    echo ""
    echo "  Option B: Keep Intel active — let DRM choose primary device"
    echo "    Best for: laptops or systems that need Intel QuickSync"
    echo ""
    read -p "Blacklist Intel graphics? (Y/n): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Nn]$ ]]; then
        cat > /etc/modprobe.d/blacklist-intel.conf << EOF
# Blacklist Intel graphics to force NVIDIA as sole GPU
# Generated by nvidia-install.sh v1.4
blacklist i915
blacklist intel_agp
EOF
        echo -e "${GREEN}Intel graphics will be disabled on next boot${NC}"
        record_change "Created /etc/modprobe.d/blacklist-intel.conf (i915 blacklist)"
    else
        # Remove blacklist if it existed from a prior install
        if [ -f /etc/modprobe.d/blacklist-intel.conf ]; then
            rm -f /etc/modprobe.d/blacklist-intel.conf
            echo "Removed Intel blacklist"
            record_change "Removed /etc/modprobe.d/blacklist-intel.conf"
        fi
        echo "Keeping Intel graphics active"
    fi

    step_done
}

# Function to add GRUB parameters
configure_grub() {
    set_step 12 "Configuring GRUB parameters"
    echo -e "\n${BLUE}=== Configuring GRUB ===${NC}"

    GRUB_FILE="/etc/default/grub"

    # Read current GRUB_CMDLINE_LINUX_DEFAULT
    CURRENT_GRUB=$(grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_FILE" || true)
    echo "Current GRUB line: $CURRENT_GRUB"

    GRUB_CHANGED=false

    # Helper: add a param to GRUB_CMDLINE_LINUX_DEFAULT (handles both single and double quotes)
    _grub_add_param() {
        local param="$1"
        if ! grep -q "$param" "$GRUB_FILE"; then
            # Match GRUB_CMDLINE_LINUX_DEFAULT= followed by either ' or "
            sed -i -E "s/(GRUB_CMDLINE_LINUX_DEFAULT=['\"])/\1${param} /" "$GRUB_FILE"
            if grep -q "$param" "$GRUB_FILE"; then
                echo "  Added: $param"
                GRUB_CHANGED=true
            else
                echo -e "${RED}  FAILED to add: $param — check /etc/default/grub format${NC}"
            fi
        else
            echo "  Already present: $param"
        fi
    }

    # Add nvidia-drm.modeset=1 (required for Wayland DRM)
    _grub_add_param "nvidia-drm.modeset=1"

    # Add nvidia-drm.fbdev=1 (recommended for kernel 6.x+ framebuffer console)
    _grub_add_param "nvidia-drm.fbdev=1"

    # Add NVreg_PreserveVideoMemoryAllocations=1 (suspend/resume on Wayland)
    _grub_add_param "nvidia.NVreg_PreserveVideoMemoryAllocations=1"

    if [ "$GRUB_CHANGED" = true ]; then
        echo ""
        echo "Updated GRUB line:"
        grep "^GRUB_CMDLINE_LINUX_DEFAULT=" "$GRUB_FILE"
        record_change "Added NVIDIA boot params to GRUB"
    fi

    # Always run update-grub to regenerate grub.cfg
    # (Even if params were already in /etc/default/grub, grub.cfg may be stale)
    echo ""
    echo "Running update-grub to regenerate /boot/grub/grub.cfg..."
    if update-grub 2>&1; then
        echo -e "${GREEN}GRUB updated successfully${NC}"
    elif grub-mkconfig -o /boot/grub/grub.cfg 2>&1; then
        echo -e "${GREEN}GRUB config regenerated via grub-mkconfig${NC}"
    else
        echo -e "${RED}WARNING: GRUB update failed!${NC}"
        echo "You MUST manually run 'update-grub' before rebooting."
        echo "Without this, nvidia-drm.modeset=1 will NOT be in boot params."
    fi
    record_change "Ran update-grub to regenerate grub.cfg"

    # Add NVIDIA modules to initramfs for early KMS
    INITRAMFS_MODULES="/etc/initramfs-tools/modules"
    if [ -f "$INITRAMFS_MODULES" ]; then
        for mod in nvidia nvidia_modeset nvidia_uvm nvidia_drm; do
            if ! grep -q "^${mod}$" "$INITRAMFS_MODULES" 2>/dev/null; then
                echo "$mod" >> "$INITRAMFS_MODULES"
            fi
        done
        record_change "Ensured nvidia modules in /etc/initramfs-tools/modules"
    fi

    # Single initramfs rebuild for the entire install — bakes in ALL modprobe.d changes:
    #   blacklist-nouveau.conf (step 5/config-only step 4)
    #   nvidia-wayland.conf (step 8) — modeset, fbdev, PreserveVideoMemory
    #   blacklist-intel.conf (step 11, if created)
    #   NVIDIA modules in /etc/initramfs-tools/modules (above)
    echo ""
    echo "Rebuilding initramfs (final — includes all modprobe.d changes)..."
    update-initramfs -u
    echo -e "${GREEN}Initramfs rebuilt${NC}"
    record_change "Final initramfs rebuild with all module/blacklist changes"

    step_done
}

# Function to verify installation
verify_installation() {
    set_step 13 "Verifying installation"
    echo -e "\n${BLUE}=== Installation Summary ===${NC}"

    echo ""
    echo -e "${BOLD}Target configuration:${NC}"
    echo "  Display manager:  LightDM"
    echo "  Desktop session:  KDE Plasma (Wayland)"
    echo "  Dual-GPU:         $DUAL_GPU"
    echo ""

    echo -e "${BOLD}NVIDIA packages installed:${NC}"
    dpkg -l 2>/dev/null | grep nvidia | grep ^ii | awk '{print "  " $2 " " $3}' || echo "  (none found — may need reboot)"

    echo ""
    echo -e "${BOLD}Configuration applied:${NC}"
    [ -f /etc/modprobe.d/blacklist-nouveau.conf ] && echo "  [OK] Nouveau blacklisted"
    [ -f /etc/modprobe.d/blacklist-intel.conf ] && echo "  [OK] Intel i915 blacklisted"
    [ -f /etc/modprobe.d/nvidia-wayland.conf ] && echo "  [OK] NVIDIA module options (modeset, fbdev, PreserveVideoMemory)"
    [ -f /etc/modules-load.d/nvidia.conf ] && echo "  [OK] NVIDIA modules loaded at boot"

    echo ""
    echo "  GRUB parameters:"
    grep "^GRUB_CMDLINE_LINUX_DEFAULT=" /etc/default/grub 2>/dev/null | sed 's/^/    /'

    echo ""
    echo "  Environment (/etc/environment):"
    grep -E "GBM_BACKEND|__GLX_VENDOR_LIBRARY_NAME" /etc/environment 2>/dev/null | sed 's/^/    /' || echo "    (not set)"

    echo ""
    echo "  LightDM:"
    [ -f /etc/lightdm/lightdm.conf.d/50-nvidia-wayland.conf ] && echo "    [OK] 50-nvidia-wayland.conf (default session: plasma)"
    [ -f /usr/local/bin/nvidia-lightdm-setup.sh ] && echo "    [OK] Greeter display setup script"

    if [ "$DUAL_GPU" = true ]; then
        echo ""
        echo "  Dual-GPU:"
        [ -f /etc/X11/xorg.conf ] && echo "    [OK] xorg.conf with NVIDIA BusID (for greeter)"
        [ ! -f /etc/systemd/system/nvidia-primary.service ] && echo "    [OK] nvidia-primary.service removed (Wayland uses DRM)"
    fi

    echo ""
    echo "  Backup: $(cat /tmp/nvidia-backup-location 2>/dev/null || echo 'N/A')"

    step_done
}

# Main installation flow
main() {
    echo "This script will install and configure NVIDIA for:"
    echo "  Display manager:  LightDM"
    echo "  Desktop session:  KDE Plasma (Wayland)"
    echo ""

    if [ "$CONFIG_ONLY" = true ]; then
        echo -e "${BOLD}Config-only mode — skipping driver install/removal${NC}"
        echo ""
        echo "Steps:"
        echo "   1. Detect GPU hardware"
        echo "   2. Check for dual-GPU"
        echo "   3. Create configuration backup"
        echo "   4. Verify existing NVIDIA driver + nouveau blacklist"
        echo "      (steps 5-7 skipped — driver already installed)"
        echo "   8. Configure NVIDIA kernel module options"
        echo "   9. Configure X server for LightDM greeter"
        echo "  10. Configure LightDM for KDE Plasma Wayland"
        echo "  11. Configure dual-GPU for Wayland (if applicable)"
        echo "  12. Configure GRUB parameters + rebuild initramfs"
        echo "  13. Verify installation"
    else
        echo "Steps:"
        echo "   1. Detect GPU hardware"
        echo "   2. Check for dual-GPU"
        echo "   3. Create configuration backup"
        echo "   4. Install prerequisites (kernel headers, LightDM, Plasma)"
        echo "   5. Blacklist nouveau driver"
        echo "   6. Remove old NVIDIA drivers"
        echo "   7. Install NVIDIA driver packages"
        echo "   8. Configure NVIDIA kernel module options"
        echo "   9. Configure X server for LightDM greeter"
        echo "  10. Configure LightDM for KDE Plasma Wayland"
        echo "  11. Configure dual-GPU for Wayland (if applicable)"
        echo "  12. Configure GRUB parameters + rebuild initramfs"
        echo "  13. Verify installation"
    fi

    echo ""
    read -p "Continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled"
        exit 0
    fi

    detect_gpu
    detect_dual_gpu
    create_backup

    if [ "$CONFIG_ONLY" = true ]; then
        # Config-only: verify driver is present, skip install steps
        set_step 4 "Verifying existing NVIDIA driver"
        echo -e "\n${BLUE}=== Verifying Existing NVIDIA Driver ===${NC}"
        if ! dpkg -l 2>/dev/null | grep -q "^ii.*nvidia-driver"; then
            echo -e "${RED}ERROR: nvidia-driver package not installed${NC}"
            echo "Cannot use --config-only without an installed driver."
            echo "Run without --config-only for full installation."
            exit 1
        fi
        DRIVER_VER=$(dpkg -l 2>/dev/null | grep "^ii.*nvidia-driver " | awk '{print $3}')
        echo -e "${GREEN}NVIDIA driver installed: $DRIVER_VER${NC}"

        if ! command -v nvidia-smi &>/dev/null; then
            echo -e "${YELLOW}WARNING: nvidia-smi not found in PATH${NC}"
        elif nvidia-smi &>/dev/null; then
            echo -e "${GREEN}nvidia-smi: working${NC}"
        else
            echo -e "${YELLOW}WARNING: nvidia-smi failed (modules may not be loaded — will be fixed by config)${NC}"
        fi

        # Verify nouveau is blacklisted (normally done in step 5)
        if [ ! -f /etc/modprobe.d/blacklist-nouveau.conf ]; then
            echo ""
            echo -e "${YELLOW}Nouveau not blacklisted — creating blacklist...${NC}"
            cat > /etc/modprobe.d/blacklist-nouveau.conf << EOF
blacklist nouveau
options nouveau modeset=0
EOF
            echo -e "${GREEN}Nouveau blacklisted${NC}"
            record_change "Created /etc/modprobe.d/blacklist-nouveau.conf"
        else
            echo -e "${GREEN}Nouveau blacklist: present${NC}"
        fi

        # Check Wayland EGL packages
        if ! dpkg -l 2>/dev/null | grep -q "libnvidia-egl-wayland1"; then
            echo -e "${YELLOW}WARNING: libnvidia-egl-wayland1 not installed${NC}"
            echo "  Install with: apt install libnvidia-egl-wayland1 egl-wayland"
        fi

        step_done
    else
        check_prerequisites
        blacklist_nouveau
        remove_old_drivers
        install_nvidia
    fi

    configure_nvidia_modules
    configure_xserver
    configure_lightdm_wayland
    configure_dual_gpu
    configure_grub
    verify_installation

    echo ""
    echo -e "${GREEN}==================================${NC}"
    echo -e "${GREEN}Installation Complete!${NC}"
    echo -e "${GREEN}==================================${NC}"
    echo ""
    echo -e "${YELLOW}IMPORTANT: You must reboot for changes to take effect${NC}"
    echo ""
    echo "After reboot, verify with:"
    echo "  sudo ${SCRIPT_DIR}/nvidia-verify.sh"
    echo ""
    echo "Or verify manually:"
    echo "  echo \$XDG_SESSION_TYPE       (should say 'wayland')"
    echo "  nvidia-smi                    (driver loaded)"
    echo "  cat /sys/module/nvidia_drm/parameters/modeset  (should say 'Y')"
    echo "  cat /sys/module/nvidia_drm/parameters/fbdev    (should say 'Y')"
    echo "  eglinfo | head -20            (EGL info)"
    echo "  wayland-info                  (Wayland compositor info)"
    echo ""
    echo "If you encounter issues:"
    echo "  1. Boot to TTY (Ctrl+Alt+F2)"
    echo "  2. Restore backup from: $(cat /tmp/nvidia-backup-location 2>/dev/null)"
    echo "  3. Run: sudo ./nvidia-remove.sh"
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
