#!/bin/bash

# NVIDIA Driver Installation Script v1.3
# Automated installation with dual-GPU support and Wayland/X11 session choice

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
NC='\033[0m'

# Global state
DUAL_GPU=false
SESSION_TYPE=""  # "x11", "wayland", or "both"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root${NC}"
    echo "Usage: sudo $0"
    exit 1
fi

echo -e "${BLUE}==================================${NC}"
echo -e "${BLUE}  NVIDIA Driver Installation v1.3${NC}"
echo -e "${BLUE}  Wayland + Dual-GPU Support${NC}"
echo -e "${BLUE}==================================${NC}"
echo ""

# Detect distribution
if [ -f /etc/debian_version ]; then
    DISTRO="debian"
else
    echo -e "${RED}Unsupported distribution — this toolkit supports Debian-based systems only${NC}"
    exit 1
fi

echo -e "${GREEN}Detected distribution: $DISTRO${NC}"
echo ""

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
        echo "primary display device."
    else
        DUAL_GPU=false
        echo -e "${GREEN}Single GPU configuration — no dual-GPU setup needed${NC}"
    fi
    step_done
}

# Function to prompt for session type
detect_session_type() {
    set_step 3 "Selecting display session type"
    echo -e "\n${BLUE}=== Display Session Type ===${NC}"
    echo ""
    echo "Which display session do you want to configure?"
    echo ""
    echo "  1) X11 only     — Traditional X server (maximum compatibility)"
    echo "  2) Wayland only — Modern compositor (requires driver 495+, recommended for KDE Plasma)"
    echo "  3) Both         — Configure both sessions, choose at login"
    echo ""

    while true; do
        read -p "Select session type [1/2/3]: " SESSION_CHOICE
        case "$SESSION_CHOICE" in
            1) SESSION_TYPE="x11"; break ;;
            2) SESSION_TYPE="wayland"; break ;;
            3) SESSION_TYPE="both"; break ;;
            *) echo "Please enter 1, 2, or 3" ;;
        esac
    done

    echo -e "${GREEN}Session type: $SESSION_TYPE${NC}"
    step_done
}

# Function to create backup
create_backup() {
    set_step 4 "Creating configuration backup"
    echo -e "\n${BLUE}=== Creating Backup ===${NC}"
    BACKUP_DIR="/root/nvidia-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    # Backup important configs
    [ -f /etc/X11/xorg.conf ] && cp /etc/X11/xorg.conf "$BACKUP_DIR/"
    [ -d /etc/X11/xorg.conf.d ] && cp -r /etc/X11/xorg.conf.d "$BACKUP_DIR/"
    [ -f /etc/default/grub ] && cp /etc/default/grub "$BACKUP_DIR/"
    [ -d /etc/modprobe.d ] && cp -r /etc/modprobe.d "$BACKUP_DIR/"
    [ -f /etc/environment ] && cp /etc/environment "$BACKUP_DIR/"
    [ -f /etc/sddm.conf ] && cp /etc/sddm.conf "$BACKUP_DIR/"
    [ -d /etc/sddm.conf.d ] && cp -r /etc/sddm.conf.d "$BACKUP_DIR/"

    echo "Backup created at: $BACKUP_DIR"
    echo "$BACKUP_DIR" > /tmp/nvidia-backup-location
    record_change "Created backup at ${BACKUP_DIR}"
    step_done
}

# Function to check prerequisites
check_prerequisites() {
    set_step 5 "Installing prerequisites"
    echo -e "\n${BLUE}=== Checking Prerequisites ===${NC}"

    # Repair broken dpkg state before anything else
    if [ "$DISTRO" = "debian" ]; then
        # Check for packages in broken states: Half-installed, Unpacked, Failed-config, Triggers-awaited/pending
        BROKEN_PKGS=$(dpkg -l 2>/dev/null | awk '/^.[HUFWt]/{print $2}' || true)
        # Also check for packages in "removal" or "purge" desired states that are stuck (ri, rH, etc.)
        STUCK_PKGS=$(dpkg -l 2>/dev/null | awk '/^r[iHUF]/{print $2}' || true)
        # Check for "iU" (installed but Unpacked/half-configured)
        IU_PKGS=$(dpkg -l 2>/dev/null | awk '/^iU/{print $2}' || true)

        ALL_PROBLEM_PKGS="${BROKEN_PKGS} ${STUCK_PKGS} ${IU_PKGS}"
        ALL_PROBLEM_PKGS=$(echo "$ALL_PROBLEM_PKGS" | xargs -n1 2>/dev/null | sort -u | xargs 2>/dev/null || true)

        if [ -n "$ALL_PROBLEM_PKGS" ]; then
            echo -e "${YELLOW}Repairing broken package state...${NC}"
            echo "  Problem packages: $ALL_PROBLEM_PKGS"

            # Step 1: Try to configure pending packages
            dpkg --configure -a 2>/dev/null || true
            apt --fix-broken install -y 2>/dev/null || true

            # Step 2: Force-remove NVIDIA packages that are still broken
            # (These are the primary cause of install failures from prior botched runs)
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
    fi

    # Check kernel headers
    if [ "$DISTRO" = "debian" ]; then
        if ! dpkg -s "linux-headers-$(uname -r)" &>/dev/null; then
            echo -e "${YELLOW}Installing kernel headers...${NC}"
            if apt install -y "linux-headers-$(uname -r)"; then
                record_change "Installed kernel headers for $(uname -r)"
            else
                echo -e "${YELLOW}WARNING: Could not install linux-headers-$(uname -r)${NC}"
                echo -e "${YELLOW}The NVIDIA kernel module may fail to build without headers.${NC}"
                echo -e "${YELLOW}You may need to install them manually before rebooting.${NC}"
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
    fi
    step_done
}

# Function to blacklist nouveau
blacklist_nouveau() {
    set_step 6 "Blacklisting nouveau driver"
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

    # Update initramfs
    echo "Updating initramfs..."
    update-initramfs -u
    record_change "Updated initramfs (nouveau blacklist)"
    step_done
}

# Function to remove old drivers
remove_old_drivers() {
    set_step 7 "Removing old NVIDIA drivers"
    echo -e "\n${BLUE}=== Removing Old Drivers ===${NC}"

    if [ "$DISTRO" = "debian" ]; then
        if dpkg -l 2>/dev/null | grep -q nvidia; then
            echo "Removing existing NVIDIA packages..."
            apt remove --purge -y '^nvidia-.*' '^libnvidia-.*' || true

            # Repair broken state left by purge (same pattern as remove script)
            dpkg --configure -a 2>/dev/null || true
            apt --fix-broken install -y 2>/dev/null || true

            # Clean up any NVIDIA packages stuck in broken states after purge
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
    set_step 8 "Installing NVIDIA driver packages"
    echo -e "\n${BLUE}=== Installing NVIDIA Driver ===${NC}"

    if [ "$DISTRO" = "debian" ]; then
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

        # Install with retry — first attempt may fail due to residual broken state
        if ! apt install -y "$DRIVER_PKG" $DRIVER_EXTRAS; then
            echo -e "${YELLOW}Install failed — repairing package state and retrying...${NC}"

            # Repair: configure pending, fix broken, force-remove broken nvidia pkgs
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

            # Retry install
            echo "Retrying driver installation..."
            apt install -y "$DRIVER_PKG" $DRIVER_EXTRAS
        fi

        # Install EGL/Wayland packages if needed
        if [ "$SESSION_TYPE" = "wayland" ] || [ "$SESSION_TYPE" = "both" ]; then
            echo "Installing Wayland support packages..."
            apt install -y libnvidia-egl-wayland1 egl-wayland 2>/dev/null || true
        fi

    fi

    record_change "Installed NVIDIA driver packages"
    echo -e "${GREEN}NVIDIA driver installed${NC}"
    step_done
}

# Function to configure X server
configure_xserver() {
    set_step 9 "Configuring X server"
    echo -e "\n${BLUE}=== Configuring X Server ===${NC}"

    if [ "$SESSION_TYPE" = "wayland" ]; then
        echo "Wayland-only session selected — skipping X server configuration"
        step_done
        return
    fi

    read -p "Generate xorg.conf? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        if command -v nvidia-xconfig &> /dev/null; then
            nvidia-xconfig
            echo -e "${GREEN}xorg.conf generated${NC}"
            record_change "Generated /etc/X11/xorg.conf via nvidia-xconfig"
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
            record_change "Created /etc/X11/xorg.conf.d/20-nvidia.conf"
        fi
    else
        echo "Skipping xorg.conf generation"
    fi
    step_done
}

# Function to configure Wayland session
configure_wayland() {
    set_step 10 "Configuring Wayland session"
    echo -e "\n${BLUE}=== Configuring Wayland Session ===${NC}"

    if [ "$SESSION_TYPE" = "x11" ]; then
        echo "X11-only session selected — skipping Wayland configuration"
        step_done
        return
    fi

    # Set environment variables for NVIDIA Wayland support
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

    record_change "Set NVIDIA Wayland environment variables in /etc/environment"
    echo -e "${GREEN}Environment variables set in $ENV_FILE:${NC}"
    echo "  GBM_BACKEND=nvidia-drm"
    echo "  __GLX_VENDOR_LIBRARY_NAME=nvidia"

    # Detect which display manager is actually enabled
    ACTIVE_DM=""
    for dm in sddm lightdm gdm gdm3; do
        if systemctl is-enabled "${dm}.service" &>/dev/null; then
            ACTIVE_DM="$dm"
            break
        fi
    done

    if [ -z "$ACTIVE_DM" ]; then
        echo -e "${YELLOW}WARNING: No enabled display manager detected${NC}"
        echo "You may need to enable one manually (e.g., systemctl enable sddm)"
    else
        echo ""
        echo "Active display manager: $ACTIVE_DM"
    fi

    # Configure SDDM for Wayland session
    if [ "$ACTIVE_DM" = "sddm" ] || systemctl list-unit-files 2>/dev/null | grep -q "sddm.service"; then
        if [ "$ACTIVE_DM" != "sddm" ]; then
            echo ""
            echo -e "${YELLOW}NOTE: SDDM is installed but $ACTIVE_DM is the active display manager${NC}"
            echo "Configuring SDDM anyway in case you switch to it later"
        fi
        echo ""
        echo "Configuring SDDM for Wayland session..."
        mkdir -p /etc/sddm.conf.d

        if [ "$SESSION_TYPE" = "wayland" ]; then
            cat > /etc/sddm.conf.d/10-wayland.conf << 'EOF'
# NVIDIA Wayland session configuration
# Generated by nvidia-install.sh v1.3

[General]
DisplayServer=wayland
GreeterEnvironment=QT_WAYLAND_SHELL_INTEGRATION=layer-shell

[Wayland]
CompositorCommand=kwin_wayland --drm --no-lockscreen --no-global-shortcuts --locale1
EOF
            echo -e "${GREEN}SDDM configured for Wayland session${NC}"
            record_change "Created /etc/sddm.conf.d/10-wayland.conf (Wayland-only)"
        else
            cat > /etc/sddm.conf.d/10-wayland.conf << 'EOF'
# NVIDIA dual-session configuration (X11 + Wayland)
# Generated by nvidia-install.sh v1.3
# SDDM greeter runs on X11; Wayland sessions available at login

[General]
DisplayServer=x11
EOF
            echo -e "${GREEN}SDDM configured — Wayland sessions available at login screen${NC}"
            record_change "Created /etc/sddm.conf.d/10-wayland.conf (dual-session)"
        fi
    fi

    # Configure LightDM
    if [ "$ACTIVE_DM" = "lightdm" ] || systemctl list-unit-files 2>/dev/null | grep -q "lightdm.service"; then
        echo ""
        echo "Configuring LightDM for NVIDIA..."
        LIGHTDM_CONF="/etc/lightdm/lightdm.conf"
        LIGHTDM_CONF_DIR="/etc/lightdm/lightdm.conf.d"
        mkdir -p "$LIGHTDM_CONF_DIR"

        # Create NVIDIA display setup script for LightDM
        cat > /usr/local/bin/nvidia-lightdm-setup.sh << 'SCRIPT'
#!/bin/bash
# NVIDIA display setup for LightDM
# Generated by nvidia-install.sh v1.3
xrandr --setprovideroutputsource modesetting NVIDIA-0 2>/dev/null || true
xrandr --auto 2>/dev/null || true
SCRIPT
        chmod +x /usr/local/bin/nvidia-lightdm-setup.sh

        cat > "${LIGHTDM_CONF_DIR}/50-nvidia.conf" << 'EOF'
# NVIDIA configuration for LightDM
# Generated by nvidia-install.sh v1.3

[LightDM]

[Seat:*]
display-setup-script=/usr/local/bin/nvidia-lightdm-setup.sh
EOF
        echo -e "${GREEN}LightDM configured with NVIDIA display setup script${NC}"
        record_change "Created ${LIGHTDM_CONF_DIR}/50-nvidia.conf and /usr/local/bin/nvidia-lightdm-setup.sh"

        if [ "$ACTIVE_DM" = "lightdm" ] && [ "$SESSION_TYPE" != "x11" ]; then
            echo ""
            echo -e "${YELLOW}NOTE: LightDM has limited Wayland support.${NC}"
            echo "For full Wayland sessions, consider switching to SDDM:"
            echo "  sudo systemctl disable lightdm && sudo systemctl enable sddm"
        fi
    fi

    # Configure GDM for Wayland
    if [ "$ACTIVE_DM" = "gdm" ] || [ "$ACTIVE_DM" = "gdm3" ] || systemctl list-unit-files 2>/dev/null | grep -q "gdm.service"; then
        echo ""
        echo "Configuring GDM for Wayland..."
        GDM_CONF="/etc/gdm3/daemon.conf"
        if [ -f "$GDM_CONF" ]; then
            if grep -q "^WaylandEnable=false" "$GDM_CONF"; then
                echo "Re-enabling Wayland in GDM..."
                sed -i 's/^WaylandEnable=false/#WaylandEnable=false/' "$GDM_CONF"
                echo -e "${GREEN}Wayland re-enabled in GDM${NC}"
            else
                echo "Wayland already enabled in GDM"
            fi
        fi
    fi
    step_done
}

# Function to configure dual-GPU setup
configure_dual_gpu() {
    set_step 11 "Configuring dual-GPU routing"
    if [ "$DUAL_GPU" = false ]; then
        step_done
        return
    fi

    echo -e "\n${BLUE}=== Configuring Dual-GPU (NVIDIA as Primary) ===${NC}"

    # Auto-detect NVIDIA PCI BusID
    NVIDIA_BUSID=$(lspci | grep -i "vga.*nvidia\|3d.*nvidia" | head -1 | cut -d' ' -f1 | sed 's/\./:/' || true)
    if [ -z "$NVIDIA_BUSID" ]; then
        echo -e "${RED}Could not detect NVIDIA BusID${NC}"
        step_done
        return
    fi

    # Convert to X format (e.g., 01:00.0 -> PCI:1:0:0)
    BUSID_DEC=$(echo "$NVIDIA_BUSID" | awk -F: '{printf "PCI:%d:%d:%d", strtonum("0x"$1), strtonum("0x"$2), strtonum("0x"$3)}')
    echo "NVIDIA BusID: $NVIDIA_BUSID (X format: $BUSID_DEC)"

    # X11 path: create xorg.conf with explicit BusID
    if [ "$SESSION_TYPE" = "x11" ] || [ "$SESSION_TYPE" = "both" ]; then
        echo ""
        echo "Creating X11 configuration with NVIDIA BusID..."

        # Auto-detect GPU board name
        GPU_NAME=$(lspci | grep -i "vga.*nvidia\|3d.*nvidia" | head -1 | sed 's/.*: //' || true)

        cat > /etc/X11/xorg.conf << EOF
# Dual GPU Configuration — Force NVIDIA as Primary
# Generated by nvidia-install.sh v1.3

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
    Option         "TripleBuffer" "True"
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
        echo -e "${GREEN}Created /etc/X11/xorg.conf with NVIDIA BusID${NC}"
        record_change "Created /etc/X11/xorg.conf with NVIDIA BusID ${BUSID_DEC}"

        # Create xrandr provider setup script and systemd service
        echo "Creating display provider setup service..."
        cat > /usr/local/bin/nvidia-primary.sh << 'SCRIPT'
#!/bin/bash
# Set NVIDIA as primary display provider on startup
sleep 2
xrandr --setprovideroutputsource modesetting NVIDIA-0 2>/dev/null || true
xrandr --auto 2>/dev/null || true
SCRIPT
        chmod +x /usr/local/bin/nvidia-primary.sh

        cat > /etc/systemd/system/nvidia-primary.service << 'EOF'
[Unit]
Description=Set NVIDIA as primary GPU display provider
After=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/local/bin/nvidia-primary.sh
RemainAfterExit=yes

[Install]
WantedBy=graphical.target
EOF
        systemctl daemon-reload
        systemctl enable nvidia-primary.service
        echo -e "${GREEN}Created nvidia-primary startup service${NC}"
        record_change "Created nvidia-primary.service and /usr/local/bin/nvidia-primary.sh"
    fi

    # Wayland path: no xorg.conf needed, DRM/kernel handles GPU selection
    if [ "$SESSION_TYPE" = "wayland" ]; then
        echo ""
        echo "Wayland session: GPU selection is handled by the DRM subsystem."
        echo "No xorg.conf is needed — nvidia-drm.modeset=1 enables NVIDIA as the DRM device."
    fi

    # Optional: blacklist Intel i915
    echo ""
    echo -e "${BLUE}=== Intel Graphics Options ===${NC}"
    echo "You have Intel integrated graphics + NVIDIA discrete GPU."
    echo ""
    echo "Option A (Recommended): Keep Intel active, use NVIDIA for display"
    echo "Option B (Aggressive): Disable Intel completely (NVIDIA only)"
    echo ""
    read -p "Disable Intel graphics? (y/N): " -n 1 -r
    echo

    if [[ $REPLY =~ ^[Yy]$ ]]; then
        cat > /etc/modprobe.d/blacklist-intel.conf << EOF
# Blacklist Intel graphics to force NVIDIA
blacklist i915
blacklist intel_agp
EOF
        echo -e "${YELLOW}Intel graphics will be disabled on next boot${NC}"
        record_change "Created /etc/modprobe.d/blacklist-intel.conf (i915 blacklist)"
        update-initramfs -u
    else
        echo "Keeping Intel graphics active"
    fi
    step_done
}

# Function to add GRUB parameters
configure_grub() {
    set_step 12 "Configuring GRUB parameters"
    echo -e "\n${BLUE}=== Configuring GRUB ===${NC}"

    GRUB_FILE="/etc/default/grub"

    # nvidia-drm.modeset=1 is required for Wayland and beneficial for X11
    if grep -q "nvidia-drm.modeset=1" "$GRUB_FILE"; then
        echo "GRUB already has nvidia-drm.modeset=1"
    else
        echo "Adding nvidia-drm.modeset=1 to GRUB..."
        echo "(Required for Wayland, recommended for X11)"
        sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT="/GRUB_CMDLINE_LINUX_DEFAULT="nvidia-drm.modeset=1 /' "$GRUB_FILE"
        if ! grep -q "nvidia-drm.modeset=1" "$GRUB_FILE"; then
            echo -e "${YELLOW}WARNING: Could not add nvidia-drm.modeset=1 to GRUB automatically${NC}"
            echo "Please add nvidia-drm.modeset=1 to GRUB_CMDLINE_LINUX_DEFAULT in $GRUB_FILE manually"
        else
            update-grub 2>/dev/null || grub-mkconfig -o /boot/grub/grub.cfg
            echo -e "${GREEN}GRUB configured${NC}"
            record_change "Added nvidia-drm.modeset=1 to GRUB and ran update-grub"
        fi
    fi
    step_done
}

# Function to verify installation
verify_installation() {
    set_step 13 "Verifying installation"
    echo -e "\n${BLUE}=== Installation Summary ===${NC}"

    echo "NVIDIA packages installed:"
    dpkg -l 2>/dev/null | grep nvidia | grep ^ii || echo "  (none found — may need reboot)"

    echo ""
    echo "Session type: $SESSION_TYPE"
    echo "Dual-GPU: $DUAL_GPU"
    echo "Backup location: $(cat /tmp/nvidia-backup-location 2>/dev/null || echo 'N/A')"

    echo ""
    echo "Configuration applied:"
    echo "  - nvidia-drm.modeset=1 in GRUB"
    [ -f /etc/modprobe.d/blacklist-nouveau.conf ] && echo "  - Nouveau blacklisted"
    [ -f /etc/modprobe.d/blacklist-intel.conf ] && echo "  - Intel i915 blacklisted"

    if [ "$SESSION_TYPE" = "wayland" ] || [ "$SESSION_TYPE" = "both" ]; then
        echo "  - GBM_BACKEND=nvidia-drm in /etc/environment"
        echo "  - __GLX_VENDOR_LIBRARY_NAME=nvidia in /etc/environment"
        [ -f /etc/sddm.conf.d/10-wayland.conf ] && echo "  - SDDM Wayland config in /etc/sddm.conf.d/"
    fi

    [ -f /etc/lightdm/lightdm.conf.d/50-nvidia.conf ] && echo "  - LightDM NVIDIA config in /etc/lightdm/lightdm.conf.d/"

    if [ "$SESSION_TYPE" = "x11" ] || [ "$SESSION_TYPE" = "both" ]; then
        [ -f /etc/X11/xorg.conf ] && echo "  - xorg.conf configured"
    fi

    if [ "$DUAL_GPU" = true ]; then
        [ -f /etc/systemd/system/nvidia-primary.service ] && echo "  - nvidia-primary.service enabled"
    fi
    step_done
}

# Main installation flow
main() {
    echo "This script will:"
    echo "1. Detect your NVIDIA GPU and check for dual-GPU"
    echo "2. Let you choose display session (X11 / Wayland / Both)"
    echo "3. Create a backup of current configuration"
    echo "4. Install kernel headers and NVIDIA driver"
    echo "5. Blacklist nouveau driver"
    echo "6. Configure display session and GRUB"
    echo "7. Configure dual-GPU routing (if applicable)"
    echo ""
    read -p "Continue with installation? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Installation cancelled"
        exit 0
    fi

    detect_gpu
    detect_dual_gpu
    detect_session_type
    create_backup
    check_prerequisites
    blacklist_nouveau
    remove_old_drivers
    install_nvidia
    configure_xserver
    configure_wayland
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
    echo "After reboot, verify installation with:"
    echo "  nvidia-smi"

    if [ "$SESSION_TYPE" = "x11" ] || [ "$SESSION_TYPE" = "both" ]; then
        echo "  glxinfo | grep NVIDIA        (X11 session)"
        echo "  xrandr --listproviders       (X11 session)"
    fi
    if [ "$SESSION_TYPE" = "wayland" ] || [ "$SESSION_TYPE" = "both" ]; then
        echo "  echo \$XDG_SESSION_TYPE       (should say 'wayland')"
        echo "  eglinfo | head -20           (Wayland session)"
        echo "  wayland-info                 (Wayland session)"
    fi
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
